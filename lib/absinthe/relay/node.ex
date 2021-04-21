defmodule Absinthe.Relay.Node do
  @moduledoc """
  Support for global object identification.

  The `node` macro can be used by schema designers to add required
  "object identification" support for object types, and to provide a unified
  interface for querying them.

  More information can be found at:
  - https://facebook.github.io/relay/docs/graphql-object-identification.html#content
  - https://facebook.github.io/relay/graphql/objectidentification.htm

  ## Interface

  Define a node interface for your schema, providing a type resolver that,
  given a resolved object can determine which node object type it belongs to.

  ```
  node interface do
    resolve_type fn
      %{age: _}, _ ->
        :person
      %{employee_count: _}, _ ->
        :business
      _, _ ->
        nil
    end
  end
  ```

  This will create an interface, `:node` that expects one field, `:id`, be
  defined -- and that the ID will be a global identifier.

  If you use the `node` macro to create your `object` types (see "Object" below),
  this can be easily done, layered on top of the standard object type definition
  style.

  ## Field

  The node field provides a unified interface to query for an object in the
  system using a global ID. The node field should be defined within your schema
  `query` and should provide a resolver that, given a map containing the object
  type identifier and internal, non-global ID (the incoming global ID will be
  parsed into these values for you automatically) can resolve the correct value.

  ```
  query do

    # ...

    node field do
      resolve fn
        %{type: :person, id: id}, _ ->
          {:ok, Map.get(@people, id)}
        %{type: :business, id: id}, _ ->
          {:ok, Map.get(@businesses, id)}
      end
    end

  end
  ```

  This creates a field, `:node`, with one argument: `:id`. This is expected to
  be a global ID and, once resolved, will result in a value whose type
  implements the `:node` interface.

  Here's how you easily create object types that can be looked up using this
  field:

  ## Object

  To play nicely with the `:node` interface and field, explained above, any
  object types need to implement the `:node` interface and generate a global
  ID as the value of its `:id` field. Using the `node` macro, you can easily do
  this while retaining the usual object type definition style.

  ```
  node object :person do
    field :name, :string
    field :age, :string
  end
  ```

  This will create an object type, `:person`, as you might expect. An `:id`
  field is created for you automatically, and this field generates a global ID;
  an opaque string that's built using a global ID translator (by default a
  Base64 implementation). All of this is handled for you automatically by
  prefixing your object type definition with `"node "`.

  By default, type of `:id` field is `ID`. But you can pass custom type in `:id_type` attribute:

  ```
  node interface id_type: :uuid do
      resolve_type fn
        ...
      end
  end

  node field id_type: :uuid do
      resolve fn
        ...
      end
  end

  node object :thing, id_type: :uuid do
    field :name, :string
  end
  ```

  Or you can set it up globally via application config:
  ```
  config Absinthe.Relay,
    node_id_type: :uuid
  ```

  The raw, internal value is retrieved using `default_id_fetcher/2` which just
  pattern matches an `:id` field from the resolved object. If you need to
  extract/build an internal ID via another method, just provide a function as
  an `:id_fetcher` option.

  For instance, assuming your raw internal IDs were stored as `:_id`, you could
  configure your object like this:

  ```
  node object :thing, id_fetcher: &my_custom_id_fetcher/2 do
    field :name, :string
  end
  ```

  For instructions on how to change the underlying method of decoding/encoding
  a global ID, see `Absinthe.Relay.Node.IDTranslator`.

  ## Macros

  For more details on node-related macros, see
  `Absinthe.Relay.Node.Notation`.

  """

  require Logger

  @type global_id :: binary

  # Middleware to handle a global id
  # parses the global ID before invoking it
  @doc false
  def resolve_with_global_id(%{state: :unresolved, arguments: %{id: global_id}} = res, _) do
    case Absinthe.Relay.Node.from_global_id(global_id, res.schema) do
      {:ok, result} ->
        %{res | arguments: result}

      error ->
        Absinthe.Resolution.put_result(res, error)
    end
  end

  def resolve_with_global_id(res, _) do
    res
  end

  @doc """
  Parse a global ID, given a schema.

  To change the underlying method of decoding a global ID,
  see `Absinthe.Relay.Node.IDTranslator`.

  ## Examples

  For `nil`, pass-through:

  ```
  iex> from_global_id(nil, Schema)
  {:ok, nil}
  ```

  For a valid, existing type in `Schema`:

  ```
  iex> from_global_id("UGVyc29uOjE=", Schema)
  {:ok, %{type: :person, id: "1"}}
  ```

  For an invalid global ID value:

  ```
  iex> from_global_id("GHNF", Schema)
  {:error, "Could not decode ID value `GHNF'"}
  ```

  For a type that isn't in the schema:

  ```
  iex> from_global_id("Tm9wZToxMjM=", Schema)
  {:error, "Unknown type `Nope'"}
  ```

  For a type that is in the schema but isn't a node:

  ```
  iex> from_global_id("Tm9wZToxMjM=", Schema)
  {:error, "Type `Item' is not a valid node type"}
  ```
  """
  @spec from_global_id(nil, Absinthe.Schema.t()) :: {:ok, nil}
  @spec from_global_id(global_id, Absinthe.Schema.t()) ::
          {:ok, %{type: atom, id: binary}} | {:error, binary}
  def from_global_id(nil, _schema) do
    {:ok, nil}
  end

  def from_global_id(global_id, schema) do
    case translate_global_id(schema, :from_global_id, [global_id]) do
      {:ok, type_name, id} ->
        do_from_global_id({type_name, id}, schema)

      {:error, err} ->
        {:error, err}
    end
  end

  defp do_from_global_id({type_name, id}, schema) do
    case schema.__absinthe_type__(type_name) do
      nil ->
        {:error, "Unknown type `#{type_name}`"}

      %{identifier: ident, interfaces: interfaces} ->
        if Enum.member?(List.wrap(interfaces), :node) do
          {:ok, %{type: ident, id: id}}
        else
          {:error, "Type `#{type_name}` is not a valid node type"}
        end
    end
  end

  @doc """
  Generate a global ID given a node type name and an internal (non-global) ID given a schema.

  To change the underlying method of encoding a global ID,
  see `Absinthe.Relay.Node.IDTranslator`.

  ## Examples

  ```
  iex> to_global_id("Person", "123")
  "UGVyc29uOjEyMw=="
  iex> to_global_id(:person, "123", SchemaWithPersonType)
  "UGVyc29uOjEyMw=="
  iex> to_global_id(:person, nil, SchemaWithPersonType)
  nil
  ```
  """
  # TODO: Return tuples in v1.5
  @spec to_global_id(atom | binary, integer | binary | nil, Absinthe.Schema.t() | nil) ::
          global_id | nil
  def to_global_id(node_type, source_id, schema \\ nil)

  def to_global_id(_node_type, nil, _schema) do
    nil
  end

  def to_global_id(node_type, source_id, schema) when is_binary(node_type) do
    case translate_global_id(schema, :to_global_id, [node_type, source_id]) do
      {:ok, global_id} ->
        global_id

      {:error, err} ->
        Logger.warn(
          "Failed to translate (#{inspect(node_type)}, #{inspect(source_id)}) to global ID with error: #{
            err
          }"
        )

        nil
    end
  end

  def to_global_id(node_type, source_id, schema) when is_atom(node_type) and not is_nil(schema) do
    case Absinthe.Schema.lookup_type(schema, node_type) do
      nil ->
        nil

      type ->
        to_global_id(type.name, source_id, schema)
    end
  end

  defp translate_global_id(schema, direction, args) do
    schema
    |> global_id_translator
    |> apply(direction, args ++ [schema])
  end

  @non_relay_schema_error "Non Relay schema provided"
  @doc false
  # Returns an ID Translator from either the schema config, env config.
  # or a default Base64 implementation.
  def global_id_translator(nil) do
    Absinthe.Relay.Node.IDTranslator.Base64
  end

  def global_id_translator(schema) do
    from_schema =
      case Keyword.get(schema.__info__(:functions), :__absinthe_relay_global_id_translator__) do
        0 ->
          apply(schema, :__absinthe_relay_global_id_translator__, [])

        nil ->
          raise ArgumentError, message: @non_relay_schema_error
      end

    from_env =
      Absinthe.Relay
      |> Application.get_env(schema, [])
      |> Keyword.get(:global_id_translator, nil)

    from_schema || from_env || Absinthe.Relay.Node.IDTranslator.Base64
  end

  @missing_internal_id_error "No source non-global ID value could be fetched from the source object"
  @doc false

  # The resolver for a global ID. If a type identifier instead of a type name
  # is used during field configuration, the type name needs to be looked up
  # during resolution.

  def global_id_resolver(%Absinthe.Resolution{state: :unresolved} = res, id_fetcher) do
    type = res.parent_type

    id_fetcher = id_fetcher || (&default_id_fetcher/2)

    result =
      case id_fetcher.(res.source, res) do
        nil ->
          report_fetch_id_error(type.name, res.source)

        internal_id ->
          {:ok, to_global_id(type.name, internal_id, res.schema)}
      end

    Absinthe.Resolution.put_result(res, result)
  end

  def global_id_resolver(identifier, nil) do
    global_id_resolver(identifier, &default_id_fetcher/2)
  end

  def global_id_resolver(identifier, id_fetcher) when is_atom(identifier) do
    fn _obj, info ->
      type = Absinthe.Schema.lookup_type(info.schema, identifier)

      case id_fetcher.(info.source, info) do
        nil ->
          report_fetch_id_error(type.name, info.source)

        internal_id ->
          {:ok, to_global_id(type.name, internal_id, info.schema)}
      end
    end
  end

  def global_id_resolver(type_name, id_fetcher) when is_binary(type_name) do
    fn _, info ->
      case id_fetcher.(info.source, info) do
        nil ->
          report_fetch_id_error(type_name, info.source)

        internal_id ->
          {:ok, to_global_id(type_name, internal_id, info.schema)}
      end
    end
  end

  # Reports a failure to fetch an ID
  @spec report_fetch_id_error(type_name :: String.t(), source :: any) :: {:error, String.t()}
  defp report_fetch_id_error(type_name, source) do
    Logger.warn(@missing_internal_id_error <> " (type #{type_name})")
    Logger.debug(inspect(source))
    {:error, @missing_internal_id_error}
  end

  @doc """
  The default ID fetcher used to retrieve raw, non-global IDs from values.

  * Matches `:id` out of the value.
    * If it's `nil`, it returns `nil`
    * If it's not nil, it coerces it to a binary using `Kernel.to_string/1`

  ## Examples

  ```
  iex> default_id_fetcher(%{id: "foo"})
  "foo"
  iex> default_id_fetcher(%{id: 123})
  "123"
  iex> default_id_fetcher(%{id: nil})
  nil
  iex> default_id_fetcher(%{nope: "no_id"})
  nil
  ```
  """
  @spec default_id_fetcher(any, Absinthe.Resolution.t()) :: nil | binary
  def default_id_fetcher(%{id: id}, _info) when is_nil(id), do: nil
  def default_id_fetcher(%{id: id}, _info), do: id |> to_string
  def default_id_fetcher(_, _), do: nil
end

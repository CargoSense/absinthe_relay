defmodule Absinthe.Relay.Node.ParseIDsTest do
  use Absinthe.Relay.Case, async: true

  defmodule Foo do
    defstruct [:id, :name]
  end

  defmodule Parent do
    defstruct [:id, :name, :children]
  end

  defmodule Child do
    defstruct [:id, :name]
  end

  defmodule CustomIDTranslator do
    @behaviour Absinthe.Relay.Node.IDTranslator

    @impl true
    def to_global_id(type_name, source_id, _schema) do
      {:ok, "#{type_name}:#{source_id}"}
    end

    @impl true
    def from_global_id(global_id, _schema) do
      case String.split(global_id, ":", parts: 2) do
        [type_name, source_id] ->
          {:ok, type_name, source_id}

        _ ->
          {:error, "Could not extract value from ID `#{inspect(global_id)}`"}
      end
    end
  end

  defmodule SchemaClassic do
    use Absinthe.Schema

    use Absinthe.Relay.Schema,
      flavor: :classic,
      global_id_translator: CustomIDTranslator

    alias Absinthe.Relay.Node.ParseIDsTest.Foo
    alias Absinthe.Relay.Node.ParseIDsTest.Parent
    alias Absinthe.Relay.Node.ParseIDsTest.Child

    @foos %{
      "1" => %Foo{id: "1", name: "Foo 1"},
      "2" => %Foo{id: "2", name: "Foo 2"}
    }

    node interface do
      resolve_type fn
        %Foo{}, _ ->
          :foo

        %Parent{}, _ ->
          :parent

        %Child{}, _ ->
          :child

        _, _ ->
          nil
      end
    end

    node object(:foo) do
      field :name, :string
    end

    node object(:other_foo, name: "FancyFoo") do
      field :name, :string
    end

    node object(:parent) do
      field :name, :string
      field :children, list_of(:child)
      field :child, :child

      field :child_by_id, :child do
        arg :id, :id
        middleware Absinthe.Relay.Node.ParseIDs, id: :child
        resolve &resolve_child_by_id/3
      end
    end

    node object(:child) do
      field :name, :string
    end

    input_object :parent_input do
      field :id, non_null(:id)
      field :children, list_of(:child_input)
      field :child, non_null(:child_input)
    end

    input_object :child_input do
      field :id, :id
    end

    query do
      node field do
        resolve fn args, _ ->
          {:ok, args}
        end
      end

      field :unauthorized, :foo do
        arg :foo_id, :id

        resolve fn _, _, _ ->
          {:error, "unauthorized"}
        end

        middleware Absinthe.Relay.Node.ParseIDs, foo_id: :foo
      end

      field :foo, :foo do
        arg :foo_id, :id
        arg :foobar_id, :id
        middleware Absinthe.Relay.Node.ParseIDs, foo_id: :foo
        middleware Absinthe.Relay.Node.ParseIDs, foobar_id: [:foo, :bar]
        resolve &resolve_foo/2
      end

      field :foos, list_of(:foo) do
        arg :foo_ids, list_of(:id)
        middleware Absinthe.Relay.Node.ParseIDs, foo_ids: :foo
        resolve &resolve_foos/2
      end
    end

    mutation do
      payload field(:update_parent) do
        input do
          field :parent, :parent_input
        end

        output do
          field :parent, :parent
        end

        resolve &resolve_parent/2
      end

      payload field(:update_parent_local_middleware) do
        input do
          field :parent, :parent_input
        end

        output do
          field :parent, :parent
        end

        middleware Absinthe.Relay.Node.ParseIDs,
          parent: [
            id: :parent,
            children: [id: :child],
            child: [id: :child]
          ]

        resolve &resolve_parent/2
      end
    end

    defp resolve_foo(%{foo_id: id}, _) do
      {:ok, Map.get(@foos, id)}
    end

    defp resolve_foo(%{foobar_id: nil}, _) do
      {:ok, nil}
    end

    defp resolve_foo(%{foobar_id: %{id: id, type: :foo}}, _) do
      {:ok, Map.get(@foos, id)}
    end

    defp resolve_foos(%{foo_ids: ids}, _) do
      values = Enum.map(ids, &Map.get(@foos, &1))
      {:ok, values}
    end

    defp resolve_child_by_id(%{children: children}, %{id: id}, _) do
      child = Enum.find(children, &(&1.id === id))
      {:ok, child}
    end

    defp resolve_parent(args, _) do
      {:ok, args |> to_parent_output}
    end

    defp resolve_child_by_id(%{children: children}, %{id: id}, _) do
      child = Enum.find(children, &(&1.id === id))
      {:ok, child}
    end

    # This is just a utility that converts the input value into the
    # expected output value (which has non-null constraints).
    #
    # It doesn't have any value outside these tests!
    #
    defp to_parent_output(%{id: nil}) do
      nil
    end

    defp to_parent_output(values) when is_list(values) do
      for value <- values do
        value
        |> to_parent_output
      end
    end

    defp to_parent_output(%{} = args) do
      for {key, value} <- args, into: %{} do
        {key, value |> to_parent_output}
      end
    end

    defp to_parent_output(value) do
      value
    end

    @update_parent_ids {
      Absinthe.Relay.Node.ParseIDs,
      [
        # Needs `input` because this is being inserted
        # before the mutation middleware.
        input: [
          parent: [
            id: :parent,
            children: [id: :child],
            child: [id: :child]
          ]
        ]
      ]
    }
    def middleware(middleware, %{identifier: :update_parent}, _) do
      [@update_parent_ids | middleware]
    end

    def middleware(middleware, _, _) do
      middleware
    end
  end

  defmodule SchemaModern do
    use Absinthe.Schema
    use Absinthe.Relay.Schema, :modern

    alias Absinthe.Relay.Node.ParseIDsTest.Parent

    node interface do
      resolve_type fn
        %Parent{}, _ ->
          :parent

        %Child{}, _ ->
          :child

        _, _ ->
          nil
      end
    end

    input_object :parent_input do
      field :id, non_null(:id)
      field :children, list_of(:child_input)
      field :child, :child_input
    end

    input_object :child_input do
      field :id, :id
    end

    node object(:child) do
      field :name, :string
    end

    node object(:parent) do
      field :name, :string
      field :children, list_of(:child)
      field :child, :child

      field :child_by_id, :child do
        arg :id, :id
        middleware Absinthe.Relay.Node.ParseIDs, id: :child
        resolve &resolve_child_by_id/3
      end
    end

    query do
    end

    mutation do
      payload field(:update_parent_local_middleware) do
        input do
          field :parent, :parent_input
        end

        output do
          field :parent, :parent
        end

        middleware Absinthe.Relay.Node.ParseIDs,
          parent: [
            id: :parent,
            children: [id: :child],
            child: [id: :child]
          ]

        resolve &resolve_parent/2
      end
    end

    defp resolve_parent(args, _) do
      {:ok, args}
    end

    defp resolve_child_by_id(%{children: children}, %{id: id}, _) do
      child = Enum.find(children, &(&1.id === id))
      {:ok, child}
    end
  end

  @foo1_id "Foo:1"
  @foo2_id "Foo:2"
  @parent1_id "Parent:1"
  @child1_id "Child:1"
  @child2_id "Child:2"
  @otherfoo1_id "FancyFoo:1"
  @modern_parent1_id Base.encode64(@parent1_id)
  @modern_child1_id Base.encode64(@child1_id)
  @modern_child2_id Base.encode64(@child2_id)

  describe "parses one id" do
    test "succeeds with a non-null value" do
      result =
        """
        {
          foo(fooId: "#{@foo1_id}") {
            id
            name
          }
        }
        """
        |> Absinthe.run(SchemaClassic)

      assert {:ok, %{data: %{"foo" => %{"name" => "Foo 1", "id" => @foo1_id}}}} == result
    end

    test "succeeds with a null value" do
      result =
        """
        {
          foo(fooId: null) {
            id
            name
          }
        }
        """
        |> Absinthe.run(SchemaClassic)

      assert {:ok, %{data: %{"foo" => nil}}} == result
    end
  end

  describe "parses a list of ids" do
    test "succeeds with a non-null value" do
      result =
        """
        {
          foos(fooIds: ["#{@foo1_id}", "#{@foo2_id}"]) { id name }
        }
        """
        |> Absinthe.run(SchemaClassic)

      assert {:ok,
              %{
                data: %{
                  "foos" => [
                    %{"name" => "Foo 1", "id" => @foo1_id},
                    %{"name" => "Foo 2", "id" => @foo2_id}
                  ]
                }
              }} == result
    end

    test "succeeds with a null value" do
      result =
        """
        {
          foos(fooIds: [null, "#{@foo2_id}"]) { id name }
        }
        """
        |> Absinthe.run(SchemaClassic)

      assert {:ok,
              %{
                data: %{
                  "foos" => [
                    nil,
                    %{"name" => "Foo 2", "id" => @foo2_id}
                  ]
                }
              }} == result
    end
  end

  describe "parsing an id into one of multiple node types" do
    test "parses an non-null id into one of multiple node types" do
      result =
        """
        {
          foo(foobarId: "#{@foo1_id}") { id name }
        }
        """
        |> Absinthe.run(SchemaClassic)

      assert {:ok, %{data: %{"foo" => %{"name" => "Foo 1", "id" => @foo1_id}}}} == result
    end

    test "parses null" do
      result =
        """
        {
          foo(foobarId: null) { id name }
        }
        """
        |> Absinthe.run(SchemaClassic)

      assert {:ok, %{data: %{"foo" => nil}}} == result
    end
  end

  describe "parsing nested ids" do
    test "works with non-null values" do
      result =
        """
        mutation Foobar {
          updateParent(input: {
            clientMutationId: "abc",
            parent: {
              id: "#{@parent1_id}",
              children: [{ id: "#{@child1_id}"}, {id: "#{@child2_id}"}],
              child: { id: "#{@child2_id}"}
            }
          }) {
            parent {
              id
              children { id }
              child { id }
              }
            }
        }
        """
        |> Absinthe.run(SchemaClassic)

      expected_parent_data = %{
        "parent" => %{
          # The output re-converts everything to global_ids.
          "id" => @parent1_id,
          "children" => [%{"id" => @child1_id}, %{"id" => @child2_id}],
          "child" => %{
            "id" => @child2_id
          }
        }
      }

      assert {:ok, %{data: %{"updateParent" => expected_parent_data}}} == result
    end

    test "works with null branch values" do
      result =
        """
        mutation Foobar {
          updateParent(input: {
            clientMutationId: "abc",
            parent: null
          }) {
            parent {
              id
              children { id }
              child { id }
            }
          }
        }
        """
        |> Absinthe.run(SchemaClassic)

      expected_parent_data = %{
        "parent" => nil
      }

      assert {:ok, %{data: %{"updateParent" => expected_parent_data}}} == result
    end

    test "works with null leaf values" do
      result =
        """
        mutation Foobar {
          updateParent(input: {
            clientMutationId: "abc",
            parent: {
              id: "#{@parent1_id}",
              children: [{ id: "#{@child1_id}" }, { id: null }],
              child: { id: null }
            }
          }) {
            parent {
              id
              children { id }
              child { id }
              }
            }
        }
        """
        |> Absinthe.run(SchemaClassic)

      expected_parent_data = %{
        "parent" => %{
          # The output re-converts everything to global_ids.
          "id" => @parent1_id,
          "children" => [%{"id" => @child1_id}, nil],
          "child" => nil
        }
      }

      assert {:ok, %{data: %{"updateParent" => expected_parent_data}}} == result
    end

    test "works with nested id args" do
      result =
        """
        mutation Foobar {
          updateParent(input: {
            clientMutationId: "abc",
            parent: {
              id: "#{@parent1_id}",
              children: [{ id: "#{@child1_id}"}, {id: "#{@child2_id}"}],
              child: { id: "#{@child2_id}"}
            }
          }) {
            parent {
              id
              childById(id: "#{@child2_id}") { id }
            }
          }
        }
        """
        |> Absinthe.run(SchemaClassic)

      expected_parent_data = %{
        "parent" => %{
          # The output re-converts everything to global_ids.
          "id" => @parent1_id,
          "childById" => %{
            "id" => @child2_id
          }
        }
      }

      assert {:ok, %{data: %{"updateParent" => expected_parent_data}}} == result
    end
  end

  test "parses incorrect nested ids" do
    incorrect_id = @otherfoo1_id

    mutation = """
      mutation Foobar {
        updateParent(input: {
          clientMutationId: "abc",
          parent: {
            id: "#{@parent1_id}",
            child: {id: "#{incorrect_id}"}
          }
        }) {
          parent {
          id
          child { id }
        }
      }
    }
    """

    assert {:ok, result} = Absinthe.run(mutation, SchemaClassic)

    assert %{
             data: %{"updateParent" => nil},
             errors: [
               %{
                 locations: [%{column: 5, line: 2}],
                 message:
                   ~s<In argument "input": In field "parent": In field "child": In field "id": Expected node type in ["Child"], found "FancyFoo".>
               }
             ]
           } = result
  end

  test "doesn't run if already resolved" do
    result =
      """
      {
        unauthorized(fooId: "unknown") {
          id
        }
      }
      """
      |> Absinthe.run(SchemaClassic)

    assert {:ok,
            %{
              data: %{"unauthorized" => nil},
              errors: [
                %{
                  locations: [%{column: 3, line: 2}],
                  message: "unauthorized",
                  path: ["unauthorized"]
                }
              ]
            }} = result
  end

  test "handles one incorrect id correctly on node field" do
    result =
      """
      {
        node(id: "unknown") {
          id
        }
      }
      """
      |> Absinthe.run(SchemaClassic)

    assert {:ok,
            %{
              data: %{"node" => nil},
              errors: [
                %{
                  locations: [%{column: 3, line: 2}],
                  message: "Could not extract value from ID `\"unknown\"`",
                  path: ["node"]
                }
              ]
            }} = result
  end

  test "handles one incorrect id correctly" do
    incorrect_id = @otherfoo1_id

    result =
      """
      {
        foo(fooId: "#{incorrect_id}") {
          id
          name
        }
      }
      """
      |> Absinthe.run(SchemaClassic)

    assert {
             :ok,
             %{
               data: %{},
               errors: [
                 %{
                   message:
                     ~s<In argument "fooId": Expected node type in ["Foo"], found "FancyFoo".>
                 }
               ]
             }
           } = result
  end

  describe "parses nested ids with local middleware" do
    test "for classic schema" do
      result =
        """
        mutation FoobarLocal {
          updateParentLocalMiddleware(input: {
            clientMutationId: "abc",
            parent: {
              id: "#{@parent1_id}",
              children: [{ id: "#{@child1_id}"}, {id: "#{@child2_id}"}, {id: null}],
              child: { id: "#{@child2_id}"}
            }
          }) {
            parent {
              id
              children { id }
              child { id }
              }
            }
        }
        """
        |> Absinthe.run(SchemaClassic)

      expected_parent_data = %{
        "parent" => %{
          # The output re-converts everything to global_ids.
          "id" => @parent1_id,
          "children" => [%{"id" => @child1_id}, %{"id" => @child2_id}, nil],
          "child" => %{
            "id" => @child2_id
          }
        }
      }

      assert {:ok, %{data: %{"updateParentLocalMiddleware" => expected_parent_data}}} == result
    end

    test "for modern schema" do
      result =
        """
        mutation FoobarLocal {
          updateParentLocalMiddleware(input: {
            parent: {
              id: "#{@modern_parent1_id}",
            }
          }) {
            parent {
              id
            }
          }
        }
        """
        |> Absinthe.run(SchemaModern)

      expected_parent_data = %{
        "parent" => %{
          "id" => @modern_parent1_id
        }
      }

      assert {:ok, %{data: %{"updateParentLocalMiddleware" => expected_parent_data}}} == result
    end
  end

  describe "ParseIDs middlware in both mutation and child field" do
    test "classic schema" do
      result =
        """
        mutation Foobar {
          updateParent(input: {
            clientMutationId: "abc",
            parent: {
              id: "#{@parent1_id}",
              children: [{ id: "#{@child1_id}"}, {id: "#{@child2_id}"}],
              child: { id: "#{@child2_id}"}
            }
          }) {
            parent {
              id
              childById(id: "#{@child2_id}") { id }
            }
          }
        }
        """
        |> Absinthe.run(SchemaClassic)

      expected_parent_data = %{
        "parent" => %{
          # The output re-converts everything to global_ids.
          "id" => @parent1_id,
          "childById" => %{
            "id" => @child2_id
          }
        }
      }

      assert {:ok, %{data: %{"updateParent" => expected_parent_data}}} == result
    end

    test "modern schema" do
      result =
        """
        mutation FoobarLocal {
          updateParentLocalMiddleware(input: {
            parent: {
              id: "#{@modern_parent1_id}",
              children: [{ id: "#{@modern_child1_id}"}, {id: "#{@modern_child2_id}"}],
              child: { id: "#{@modern_child1_id}"}
            }})
            {
              parent {
                id
                childById(id: "#{@modern_child1_id}") {
                  id
                }
            }
          }
        }
        """
        |> Absinthe.run(SchemaModern)

      expected_parent_data =
        {:ok,
         %{
           data: %{
             "updateParentLocalMiddleware" => %{
               "parent" => %{
                 # The output re-converts everything to global_ids.
                 "id" => @modern_parent1_id,
                 "childById" => %{
                   "id" => @modern_child1_id
                 }
               }
             }
           }
         }}

      assert expected_parent_data == result
    end
  end
end

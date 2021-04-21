defmodule Absinthe.Relay.Node.IDTranslator.Base64 do
  @behaviour Absinthe.Relay.Node.IDTranslator

  @moduledoc """
  A basic implementation of `Absinthe.Relay.Node.IDTranslator` using Base64 encoding.
  """

  @impl true
  def to_global_id(type_name, source_id, _schema) do
    {:ok, Base.encode64("#{type_name}:#{source_id}")}
  end

  @impl true
  def from_global_id(global_id, _schema) do
    case Base.decode64(global_id) do
      {:ok, decoded} ->
        case String.split(decoded, ":", parts: 2) do
          [type_name, source_id] when byte_size(type_name) > 0 and byte_size(source_id) > 0 ->
            {:ok, type_name, source_id}

          _ ->
            {:error, "Could not extract value from decoded ID `#{inspect(decoded)}`"}
        end

      :error ->
        {:error, "Could not decode ID value `#{global_id}`"}
    end
  end
end

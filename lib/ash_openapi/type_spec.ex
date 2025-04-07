defmodule AshOpenapi.TypeSpec do
  @moduledoc """
  Converts Ash Resource schemas to Elixir type specifications.
  """

  @doc """
  Converts an Ash type to an Elixir type specification string.
  """
  def to_type_spec({:union, types}) when is_list(types) do
    types_string =
      types
      |> Enum.map(&to_type_spec/1)
      |> Enum.join(" | ")

    "(#{types_string})"
  end

  def to_type_spec({:array, type}) do
    "[#{to_type_spec(type)}]"
  end

  def to_type_spec({:embedded, [type: module]}) do
    "#{inspect(module)}.t()"
  end

  def to_type_spec(type) do
    case type do
      :string -> "String.t()"
      :integer -> "integer()"
      :decimal -> "Decimal.t()"
      :boolean -> "boolean()"
      :date -> "Date.t()"
      :utc_datetime -> "DateTime.t()"
      :atom -> "atom()"
      other -> inspect(other)
    end
  end

  @doc """
  Converts a schema to a complete type specification, including all constraints.
  """
  def schema_to_type_spec(type, constraints \\ []) do
    base_type = to_type_spec(type)

    case constraints do
      [] ->
        base_type

      [constraints: [one_of: values]] when is_list(values) ->
        values_string = values |> Enum.map(&inspect/1) |> Enum.join(" | ")
        "(#{values_string})"

      _ ->
        base_type
    end
  end
end

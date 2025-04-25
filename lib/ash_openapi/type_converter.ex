defmodule AshOpenApi.TypeConverter do
  @moduledoc """
  Converts OpenAPI schema types to Ash types.
  """

  @doc """
  Converts an OpenApiSpex.Schema to an Ash type.

  ## Examples

      iex> schema = %OpenApiSpex.Schema{type: :string, format: :"date-time"}
      iex> AshOpenApi.TypeConverter.to_ash_type(schema)
      :utc_datetime

      iex> schema = %OpenApiSpex.Schema{type: :string, enum: ["pending", "active"]}
      iex> AshOpenApi.TypeConverter.to_ash_type(schema)
      :atom

      iex> schema = %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :string}}
      iex> AshOpenApi.TypeConverter.to_ash_type(schema)
      {:array, :string}
  """
  def to_ash_type(%OpenApiSpex.Schema{} = schema) do
    cond do
      # Handle arrays first
      schema.type == :array and schema.items ->
        {:array, to_ash_type(schema.items)}

      # Handle enums
      schema.enum != nil ->
        :atom

      # Handle specific string formats
      schema.type == :string and schema.format != nil ->
        convert_string_format(schema.format)

      # Handle basic types
      true ->
        convert_basic_type(schema.type)
    end
  end

  def to_ash_type(%OpenApiSpex.Reference{} = ref) do
    # Extract component type and name from the ref
    # Format: "#/components/{type}/{name}"
    [_, "components", component_type, schema_name] = String.split(ref."$ref", "/")

    # For parameters, use just the base name without any operation prefix
    schema_name =
      if component_type == "parameters" do
        schema_name |> String.split(".") |> List.last()
      else
        schema_name
      end

    # Build the full module name and return it as a module reference
    module_name =
      "#{AshOpenApi.Context.app_name()}.#{AshOpenApi.Context.namespace()}.#{Macro.camelize(component_type)}.#{Macro.camelize(schema_name)}"
      |> String.split(".")
      |> Enum.map(&Macro.camelize/1)
      |> Module.concat()

    module_name
  end

  # String format conversions
  defp convert_string_format(format) do
    case format do
      :"date-time" -> :utc_datetime
      :date -> :date
      :time -> :time
      # Using case-insensitive string for emails
      :email -> :ci_string
      :uuid -> :uuid
      :uri -> :string
      :binary -> :binary
      :text -> :string
      _ -> :string
    end
  end

  # Basic type conversions
  defp convert_basic_type(type) do
    case type do
      :string -> :string
      :integer -> :integer
      # Using decimal for better precision
      :number -> :decimal
      :boolean -> :boolean
      :object -> :map
      # Default to string if type is not specified
      nil -> :string
      # Default to string for unknown types
      _ -> :string
    end
  end
end

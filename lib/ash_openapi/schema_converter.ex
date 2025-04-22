defmodule AshOpenApi.SchemaConverter do
  @moduledoc """
  Converts OpenAPI document schemas into OpenApiSpex.Schema structs.
  """

  alias OpenApiSpex.Schema

  @doc """
  Takes an OpenAPI document and converts all its schemas into OpenApiSpex.Schema structs,
  storing them in the AshOpenApi.Context.
  """
  def convert_and_store_schemas(openapi_doc) do
    schemas = openapi_doc.components.schemas || %{}

    Enum.each(schemas, fn {name, schema} ->
      converted_schema = convert_schema(schema)
      AshOpenApi.Context.put_schema(name, converted_schema)
    end)
  end

  @doc """
  Converts a single OpenAPI schema into an OpenApiSpex.Schema struct.
  """
  def convert_schema(schema) when is_map(schema) do
    # Convert the schema map to an OpenApiSpex.Schema struct
    # This is a basic implementation - you'll need to handle all schema types
    %Schema{
      type: schema["type"],
      title: schema["title"],
      description: schema["description"],
      properties: convert_properties(schema["properties"] || %{}),
      required: schema["required"] || [],
      example: schema["example"]
    }
  end

  @doc """
  Converts a map of OpenAPI schema properties into a map of OpenApiSpex.Schema structs.
  Each property in the input map is converted using convert_schema/1.
  """
  def convert_properties(properties) do
    properties
    |> Enum.map(fn {name, property} ->
      {name, convert_schema(property)}
    end)
    |> Map.new()
  end
end

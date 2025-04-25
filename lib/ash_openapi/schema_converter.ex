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
    %Schema{
      type: schema["type"],
      title: schema["title"],
      description: schema["description"],
      properties: convert_properties(schema["properties"] || %{}),
      required: schema["required"] || [],
      example: schema["example"],
      allOf: schema["allOf"]
    }
  end

  def convert_schema(%{"allOf" => schemas} = schema) when is_list(schemas) do
    # Convert the base schema
    base_schema = Map.drop(schema, ["allOf"])
    base = convert_schema(base_schema)

    # Convert and merge all schemas in allOf
    merged =
      Enum.reduce(schemas, base, fn schema, acc ->
        converted = convert_schema(schema)
        Map.merge(acc, converted)
      end)

    %Schema{merged | allOf: schemas}
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

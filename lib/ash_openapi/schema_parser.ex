defmodule AshOpenApi.SchemaParser do
  @moduledoc """
  Parses OpenAPI documents and stores their schemas in the AshOpenApi.Context.
  """

  alias AshOpenApi.Context

  @doc """
  Takes an OpenAPI document (either as JSON or YAML string, or as decoded map)
  and stores all its schemas in the Context.
  """
  def parse_and_store(openapi_doc) when is_binary(openapi_doc) do
    doc =
      case Jason.decode(openapi_doc) do
        {:ok, decoded} ->
          decoded

        {:error, _} ->
          # Try YAML if JSON fails
          openapi_doc
          |> YamlElixir.read_from_string!()
      end

    parse_and_store(doc)
  end

  def parse_and_store(openapi_doc) when is_map(openapi_doc) do
    # Convert the OpenAPI document into an OpenApiSpex struct
    spec = OpenApiSpex.OpenApi.Decode.decode(openapi_doc)

    # Reset the context to ensure clean state
    Context.reset()

    # Store all schemas from the components section
    schemas = get_in(spec, [Access.key(:components), Access.key(:schemas)]) || %{}

    # Convert schemas to a map with prefixed keys and store them
    schemas_map =
      Map.new(schemas, fn {name, schema} ->
        {"schemas/#{name}", schema}
      end)

    # Store the map of schemas in the context
    Context.setup(schemas_map, nil)

    {:ok, spec}
  end
end

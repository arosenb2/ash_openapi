defmodule AshOpenApi.SchemaExtractor do
  @moduledoc """
  Extracts schemas from OpenAPI operations, including inline schemas.
  """

  alias OpenApiSpex.{OpenApi, Operation, RequestBody, Response, Schema, Reference, MediaType}

  @doc """
  Extracts all schemas from an OpenAPI spec, including:
  - Component schemas
  - Inline operation schemas
  - Request body schemas
  - Response schemas
  """
  def extract_all_schemas(%OpenApi{} = spec) do
    # Start with component schemas
    component_schemas = extract_component_schemas(spec)

    # Extract operation schemas
    operation_schemas = extract_operation_schemas(spec)

    # Merge all schemas
    Map.merge(component_schemas, operation_schemas)
  end

  defp extract_component_schemas(%OpenApi{components: nil}), do: %{}

  defp extract_component_schemas(%OpenApi{components: components}) do
    components
    |> Map.from_struct()
    |> Enum.flat_map(fn
      {component_type, schemas} when is_map(schemas) ->
        Enum.map(schemas, fn {name, schema} ->
          {"#{component_type}/#{name}", normalize_schema(schema)}
        end)

      _ ->
        []
    end)
    |> Map.new()
  end

  defp extract_operation_schemas(%OpenApi{paths: paths}) do
    paths
    |> Enum.flat_map(fn {path, path_item} ->
      path_item
      |> Map.from_struct()
      |> Enum.flat_map(fn
        {_method, %Operation{} = operation} ->
          [
            extract_request_body_schemas(operation.requestBody, path),
            extract_response_schemas(operation.responses, path),
            extract_parameter_schemas(operation.parameters, operation)
          ]

        _ ->
          []
      end)
    end)
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp extract_request_body_schemas(nil, _path), do: []
  defp extract_request_body_schemas(%Reference{}, _path), do: []

  defp extract_request_body_schemas(%RequestBody{content: content}, path) when is_map(content) do
    content
    |> Enum.flat_map(fn {media_type, %MediaType{schema: schema}} ->
      case normalize_schema(schema) do
        nil -> []
        schema -> [{"requestBodies/#{path}_#{media_type}", schema}]
      end
    end)
  end

  defp extract_response_schemas(nil, _path), do: []

  defp extract_response_schemas(responses, path) when is_map(responses) do
    responses
    |> Enum.flat_map(fn {status, response} ->
      case response do
        %Reference{} ->
          []

        %Response{content: content} when is_map(content) ->
          content
          |> Enum.flat_map(fn {media_type, %MediaType{schema: schema}} ->
            case normalize_schema(schema) do
              nil -> []
              schema -> [{"responses/#{path}_#{status}_#{media_type}", schema}]
            end
          end)

        _ ->
          []
      end
    end)
  end

  defp extract_parameter_schemas(nil, _path), do: []

  defp extract_parameter_schemas(parameters, %Operation{operationId: operation_id})
       when is_list(parameters) do
    parameters
    |> Enum.flat_map(fn
      %Reference{"$ref": ref_path} = ref ->
        # Extract the parameter name from the reference path
        # Format: "#/components/parameters/{name}"
        param_name = ref_path |> String.split("/") |> List.last()
        [{"parameters/#{operation_id}.Parameters.#{param_name}", ref}]

      parameter ->
        case normalize_schema(parameter.schema) do
          nil -> []
          schema -> [{"parameters/#{operation_id}.Parameters.#{parameter.name}", schema}]
        end
    end)
  end

  defp normalize_schema(%Reference{} = ref), do: ref
  defp normalize_schema(%Schema{} = schema), do: schema
  defp normalize_schema(_), do: nil
end

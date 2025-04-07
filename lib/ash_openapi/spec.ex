defmodule AshOpenapi.Spec do
  @moduledoc """
  Common functionality for parsing and validating OpenAPI specifications.
  """

  @doc """
  Parses an OpenAPI specification file (JSON or YAML).
  """
  def parse_spec_file(file_path) do
    case Path.extname(file_path) do
      ext when ext in [".yml", ".yaml"] ->
        YamlElixir.read_from_file(file_path)

      ".json" ->
        with {:ok, content} <- File.read(file_path),
             {:ok, json} <- Jason.decode(content) do
          {:ok, json}
        end

      _ ->
        {:error, "Unsupported file format. Please use .json, .yml, or .yaml"}
    end
  end

  @doc """
  Validates that the OpenAPI specification version is 3.x.x.
  """
  def validate_openapi_version(%{"openapi" => version}) do
    if String.starts_with?(version, "3.") do
      :ok
    else
      {:error, "Only OpenAPI 3.0 and higher are supported (found version #{version})"}
    end
  end

  @doc """
  Gets the default module prefix based on the application name.
  """
  def app_module_prefix do
    Mix.Project.config()[:app]
    |> to_string()
    |> Macro.camelize()
  end

  @doc """
  Resolves a reference within an OpenAPI specification.
  """
  def resolve_ref(_spec, nil), do: nil

  def resolve_ref(spec, "#" <> path) do
    path
    |> String.trim_leading("/")
    |> String.split("/")
    |> Enum.reduce(spec, fn segment, acc ->
      Map.get(acc, segment)
    end)
  end

  def resolve_ref(spec, ref) when is_binary(ref) do
    ref
    |> String.trim_leading("#/")
    |> String.split("/")
    |> Enum.reduce(spec, fn segment, acc ->
      Map.get(acc, segment)
    end)
  end

  def resolve_ref(_spec, _ref), do: nil

  @doc """
  Resolves all references in a schema recursively.
  """
  def resolve_refs_in_schema(%{"$ref" => ref}, spec), do: resolve_ref(spec, ref)

  def resolve_refs_in_schema(%{"properties" => props} = schema, spec) do
    resolved_props =
      props
      |> Enum.map(fn {key, value} -> {key, resolve_refs_in_schema(value, spec)} end)
      |> Map.new()

    %{schema | "properties" => resolved_props}
  end

  def resolve_refs_in_schema(%{"items" => %{"$ref" => _} = items} = schema, spec) do
    %{schema | "items" => resolve_refs_in_schema(items, spec)}
  end

  def resolve_refs_in_schema(schema, _spec), do: schema

  @doc """
  Resolves and merges all allOf references in a schema.
  """
  def maybe_merge_all_of(%{"allOf" => schemas} = parent_schema, spec) do
    parent_schema = Map.delete(parent_schema, "allOf")

    merged_schema =
      schemas
      |> Enum.map(fn schema ->
        case schema do
          %{"$ref" => ref} ->
            case resolve_ref(spec, ref) do
              # Return empty map instead of nil
              nil -> %{}
              resolved -> maybe_merge_all_of(resolved, spec)
            end

          %{"allOf" => _} = nested ->
            maybe_merge_all_of(nested, spec)

          schema ->
            schema
        end
      end)
      # Filter out empty maps
      |> Enum.reject(&Enum.empty?/1)
      |> Enum.reduce(parent_schema, &deep_merge_schemas/2)

    # Resolve any remaining refs in the merged schema
    merged_schema = resolve_refs_in_schema(merged_schema, spec)

    # Check if there are any new allOf to merge after resolution
    case merged_schema do
      %{"allOf" => _} -> maybe_merge_all_of(merged_schema, spec)
      _ -> merged_schema
    end
  end

  def maybe_merge_all_of(schema, spec) do
    case schema do
      # Return empty map instead of nil
      nil -> %{}
      _ -> resolve_refs_in_schema(schema, spec)
    end
  end

  @doc """
  Deep merges two schemas, handling special cases for properties and required fields.
  """
  def deep_merge_schemas(schema1, schema2) do
    Map.merge(schema1, schema2, fn
      "properties", props1, props2 when is_map(props1) and is_map(props2) ->
        Map.merge(props1, props2, fn
          _k, v1, v2 when is_map(v1) and is_map(v2) -> deep_merge_schemas(v1, v2)
          _k, _v1, v2 -> v2
        end)

      "required", req1, req2 when is_list(req1) and is_list(req2) ->
        Enum.uniq(req1 ++ req2)

      "type", _v1, v2 ->
        v2

      _key, _v1, v2 ->
        v2
    end)
  end
end

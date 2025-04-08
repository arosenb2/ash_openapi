defmodule Mix.Tasks.AshOpenapi.GenerateSchemas do
  use Igniter.Mix.Task

  @example "mix ash_openapi.generate_schemas path/to/openapi.yaml --output-dir lib/my_app/schemas"

  @shortdoc "Generate Ash resources from OpenAPI schemas"
  @moduledoc """
  #{@shortdoc}

  Generates Ash embedded resources from OpenAPI 3.1 request and response schemas.

  ## Example

  ```bash
  #{@example}
  ```

  ## Options

  * `--output-dir` or `-o` - Directory where generated resources will be saved
  * `--prefix` or `-p` - Module prefix for generated resources (defaults to app name)
  """

  @doc """
  Provides information about the mix task, including dependencies, options, and aliases.

  This callback is required by `Igniter.Mix.Task` and configures:
  - Task group: :ash_openapi
  - Dependencies: jason, yaml_elixir, open_api_spex
  - Required options: output_dir
  - Optional options: prefix (defaults to app name)
  """
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :ash_openapi,
      adds_deps: [
        {:jason, "~> 1.4"},
        {:yaml_elixir, "~> 2.9"},
        {:open_api_spex, "~> 3.18"}
      ],
      example: @example,
      positional: [:openapi_file],
      schema: [
        output_dir: :string,
        prefix: :string
      ],
      defaults: [
        prefix: app_module_prefix()
      ],
      aliases: [
        o: :output_dir,
        p: :prefix
      ],
      required: [:output_dir]
    }
  end

  @doc """
  Executes the mix task to generate Ash resources from OpenAPI schemas.

  This callback is required by `Igniter.Mix.Task` and:
  - Parses and validates the OpenAPI specification file
  - Creates the output directory
  - Extracts schemas from the specification
  - Generates Ash resources for each schema
  """
  def igniter(igniter, argv) do
    {[openapi_file], argv} = positional_args!(argv)
    options = options!(argv)

    with {:ok, spec} <- AshOpenapi.Spec.parse_spec_file(openapi_file),
         :ok <- AshOpenapi.Spec.validate_openapi_version(spec) do
      output_dir = options.output_dir
      File.mkdir_p!(output_dir)

      schemas = extract_schemas(spec)

      Enum.reduce(schemas, igniter, fn {name, schema}, acc_igniter ->
        schema_path = Path.join(output_dir, "#{Macro.underscore(name)}.ex")
        resource_content = generate_ash_resource(name, schema, options.prefix)

        Igniter.Project.Config.configure(
          acc_igniter,
          schema_path,
          String.to_atom(name),
          [:module],
          resource_content
        )
      end)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Extracts all schemas from an OpenAPI specification.
  """
  def extract_schemas(%{"components" => %{"schemas" => schemas}} = spec) do
    schemas
    |> Enum.map(fn {name, schema} ->
      schema = AshOpenapi.Spec.maybe_merge_all_of(schema, spec)
      nested = extract_nested_schemas(schema, spec)
      Map.put(nested, name, schema)
    end)
    |> Enum.reduce(%{}, &Map.merge/2)
  end

  @doc """
  Extracts nested object schemas from a parent schema's properties.
  """
  def extract_nested_schemas(%{"properties" => properties}, spec) do
    properties
    |> Enum.flat_map(fn {field_name, schema} ->
      schema = AshOpenapi.Spec.maybe_merge_all_of(schema, spec)

      case schema do
        %{"type" => "object", "properties" => _} = nested_schema ->
          nested_name = derive_embedded_name(nil, field_name)
          [{nested_name, nested_schema}]

        %{"type" => "array", "items" => %{"type" => "object"} = items} ->
          extract_nested_schemas(items, spec)

        %{"type" => "array", "items" => %{"allOf" => _} = items} ->
          items = AshOpenapi.Spec.maybe_merge_all_of(items, spec)
          extract_nested_schemas(items, spec)

        _ ->
          []
      end
    end)
    |> Map.new()
  end

  @doc """
  Generates an Ash resource module from an OpenAPI schema definition.
  """
  def generate_ash_resource(name, schema, app_prefix) do
    title = schema["title"] || name
    description = schema["description"] || "Schema for #{name}"
    properties = schema["properties"] || %{}
    required = schema["required"] || []

    # Generate any enum types and embedded schemas first
    {attributes, extra_types} =
      properties
      |> Enum.map(fn {prop_name, prop} ->
        is_required = prop_name in required
        {attr, types} = generate_attribute({prop_name, prop}, name, is_required, app_prefix)
        {attr, types}
      end)
      |> Enum.unzip()

    content = """
    defmodule #{app_prefix}.Resources.#{name} do
      @moduledoc \"\"\"
      #{title}

      #{description}
      \"\"\"

      use Ash.Resource,
        data_layer: :embedded

      #{Enum.join(extra_types, "\n\n")}

      attributes do
        #{Enum.join(attributes, "\n    ")}
      end

      #{if has_relationships?(properties), do: generate_relationships(properties, app_prefix), else: ""}
    end
    """

    content
    |> Code.format_string!(
      locals_without_parens: [
        attribute: 2,
        attribute: 3,
        belongs_to: 2,
        belongs_to: 3,
        has_many: 2,
        has_many: 3,
        embeds_one: 2,
        embeds_many: 2
      ]
    )
    |> IO.iodata_to_binary()
  end

  @doc """
  Generates an attribute definition for an Ash resource.
  """
  def generate_attribute({name, schema}, parent_name, required?, app_prefix) do
    case schema do
      %{"type" => "object"} = object_schema ->
        {type_name, resource_defs} = map_type(object_schema, parent_name, name, app_prefix)

        attr_def =
          "attribute :#{name}, #{type_name}" <>
            case Map.get(schema, "description") do
              nil -> ""
              desc -> ", description: #{inspect(desc)}"
            end <>
            ", allow_nil?: #{!required?}, public?: true"

        {attr_def, resource_defs}

      %{"type" => "string", "enum" => _values} = enum_schema ->
        {enum_module, enum_defs} = map_type(enum_schema, parent_name, name, app_prefix)

        attr_def =
          "attribute :#{name}, #{enum_module}" <>
            case Map.get(schema, "description") do
              nil -> ""
              desc -> ", description: #{inspect(desc)}"
            end <>
            ", allow_nil?: #{!required?}, public?: true"

        {attr_def, enum_defs}

      %{"type" => "array", "items" => _items} = array_schema ->
        {type_name, type_defs} = map_type(array_schema, parent_name, name, app_prefix)

        attr_def =
          "attribute :#{name}, #{inspect(type_name)}" <>
            case Map.get(schema, "description") do
              nil -> ""
              desc -> ", description: #{inspect(desc)}"
            end <>
            ", allow_nil?: #{!required?}, public?: true"

        {attr_def, type_defs}

      %{"oneOf" => _types} = union_schema ->
        {type_name, type_defs} = map_type(union_schema, parent_name, name, app_prefix)

        attr_def =
          "attribute :#{name}, #{inspect(type_name)}" <>
            case Map.get(schema, "description") do
              nil -> ""
              desc -> ", description: #{inspect(desc)}"
            end <>
            ", allow_nil?: #{!required?}, public?: true"

        {attr_def, type_defs}

      _ ->
        {type, type_defs} = map_type(schema, parent_name, name)
        type_str = inspect(type)

        attr_def =
          "attribute :#{name}, #{type_str}" <>
            case Map.get(schema, "description") do
              nil -> ""
              desc -> ", description: #{inspect(desc)}"
            end <>
            ", allow_nil?: #{!required?}, public?: true"

        {attr_def, type_defs}
    end
  end

  @doc """
  Generates an attribute definition for an Ash resource without a module prefix.
  """
  def generate_attribute(property, parent_name, is_required) do
    generate_attribute(property, parent_name, is_required, nil)
  end

  @doc """
  Determines if a schema has any relationships based on its properties.
  """
  def has_relationships?(properties) do
    Enum.any?(properties, fn {_name, prop} ->
      Map.has_key?(prop, "$ref") ||
        (prop["type"] == "array" && Map.has_key?(prop["items"], "$ref"))
    end)
  end

  @doc """
  Generates the relationships block for an Ash resource.
  """
  def generate_relationships(properties, app_prefix) do
    relationships =
      properties
      |> Enum.filter(fn {_name, prop} ->
        Map.has_key?(prop, "$ref") ||
          (prop["type"] == "array" && Map.has_key?(prop["items"], "$ref"))
      end)
      |> Enum.map(fn {name, prop} ->
        if prop["type"] == "array" do
          ref_type = derive_type_from_ref(prop["items"]["$ref"])
          "has_many :#{name}, #{app_prefix}.Resources.#{ref_type}"
        else
          ref_type = derive_type_from_ref(prop["$ref"])
          "belongs_to :#{name}, #{app_prefix}.Resources.#{ref_type}"
        end
      end)
      |> Enum.join("\n    ")

    """
    relationships do
      #{relationships}
    end
    """
  end

  @doc """
  Maps an OpenAPI type to its corresponding Ash type.
  """
  def map_type(%{"type" => "string", "format" => "date-time"}, _parent_name, _name),
    do: {:utc_datetime, []}

  def map_type(%{"type" => "string", "format" => "date"}, _parent_name, _name), do: {:date, []}
  def map_type(%{"type" => "string", "format" => "time"}, _parent_name, _name), do: {:time, []}
  def map_type(%{"type" => "string"}, _parent_name, _name), do: {:string, []}
  def map_type(%{"type" => "integer"}, _parent_name, _name), do: {:integer, []}
  def map_type(%{"type" => "number"}, _parent_name, _name), do: {:float, []}
  def map_type(%{"type" => "boolean"}, _parent_name, _name), do: {:boolean, []}

  def map_type(%{"$ref" => ref}, _parent_name, _name) do
    {derive_type_from_ref(ref), []}
  end

  def map_type(%{"type" => "string", "enum" => values} = schema, parent_name, name, app_prefix) do
    # Create enum name as Parent.Name to be more specific and prevent collisions
    enum_name =
      if parent_name do
        "#{parent_name}.#{Macro.camelize(name)}"
      else
        Macro.camelize(name)
      end

    qualified_name = if app_prefix, do: "#{app_prefix}.Enums.#{enum_name}", else: enum_name

    enum_def = """
    defmodule #{qualified_name} do
      @moduledoc \"\"\"
      #{schema["description"] || "Enum type for #{name}"}
      \"\"\"

      use Ash.Type.Enum,
        constraints: [
          values: #{inspect(values)}
        ]
    end
    """

    {qualified_name, [enum_def]}
  end

  def map_type(%{"oneOf" => types}, parent_name, name, app_prefix) do
    # Map each type using either map_type/4 for objects or map_type/3 for basic types
    mapped_types =
      Enum.map(types, fn type ->
        case type do
          %{"type" => "object"} = object_schema ->
            {type_name, _defs} = map_type(object_schema, parent_name, name, app_prefix)
            type_name

          basic_schema ->
            {type_name, _defs} = map_type(basic_schema, parent_name, name)
            type_name
        end
      end)

    {{:union, mapped_types}, []}
  end

  def map_type(
        %{"type" => "array", "items" => %{"type" => "object"} = items},
        parent_name,
        name,
        app_prefix
      ) do
    {item_type, item_defs} = map_type(items, parent_name, name, app_prefix)
    {{:array, item_type}, item_defs}
  end

  def map_type(%{"type" => "array", "items" => items}, parent_name, name, _app_prefix) do
    # For arrays of basic types, get the type from items using map_type/3
    {base_type, defs} = map_type(items, parent_name, name)
    {{:array, base_type}, defs}
  end

  def map_type(%{"type" => "object"} = schema, parent_name, name, app_prefix) do
    resource_name = derive_embedded_name(parent_name, name)

    qualified_name =
      if app_prefix, do: "#{app_prefix}.Resources.#{resource_name}", else: resource_name

    resource_def = generate_ash_resource(resource_name, schema, app_prefix)
    {qualified_name, [resource_def]}
  end

  @doc """
  Generates enum modules for all enum properties in a schema.
  """
  def generate_enums(%{"properties" => properties}, prefix) do
    properties
    |> Enum.filter(fn {_, schema} ->
      schema["type"] == "string" && Map.has_key?(schema, "enum")
    end)
    |> Enum.map(fn {name, schema} ->
      generate_enum_type(name, schema, prefix)
    end)
    |> Enum.join("\n\n")
  end

  def generate_enums(_, _), do: ""

  @doc """
  Generates a single enum type module.
  """
  def generate_enum_type(name, schema, _prefix) do
    enum_name = "#{Macro.camelize(name)}Type"
    values = schema["enum"]
    description = schema["description"] || "Enum type for #{name}"

    """
    defmodule #{enum_name} do
      use Ash.Type.Enum,
        values: #{inspect(values)},
        description: #{inspect(description)}
    end
    """
  end

  @doc """
  Generates attribute definitions for all properties in a schema.
  """
  def generate_attributes(properties, parent_name, required \\ []) do
    properties
    |> Enum.map(fn {name, schema} ->
      is_required = name in required
      generate_attribute({name, schema}, parent_name, is_required)
    end)
  end

  @doc """
  Formats constraint options for an attribute.
  """
  def generate_constraints([]), do: ""

  def generate_constraints(constraints) do
    constraints_string =
      constraints
      |> Enum.map(fn {key, value} -> "#{key}: #{inspect(value)}" end)
      |> Enum.join(", ")

    ", #{constraints_string}"
  end

  @doc """
  Creates an embedded type module for a nested object schema.
  """
  def generate_embedded_type(schema, parent_name, property_name) do
    name = derive_embedded_name(parent_name, property_name)
    content = generate_ash_resource(name, schema, "")
    {mod, _} = Code.eval_string(content)
    mod
  end

  @doc """
  Derives a module name for an embedded type.
  """
  def derive_embedded_name(parent_name, field_name) do
    # Convert field name to PascalCase
    field_part =
      field_name
      |> Macro.camelize()
      # Remove trailing 's' for plurals
      |> String.replace(~r/s$/, "")

    if parent_name do
      "#{parent_name}#{field_part}"
    else
      field_part
    end
  end

  @doc """
  Gets the application module prefix from the Mix project configuration.
  """
  def app_module_prefix, do: AshOpenapi.Spec.app_module_prefix()

  @doc """
  Extracts the type name from a JSON Schema reference.
  """
  def derive_type_from_ref(ref) when is_binary(ref) do
    ref
    |> String.split("/")
    |> List.last()
  end

  @doc """
  Derives an enum module name based on parent context.
  """
  def derive_enum_name(parent_name, field_name) do
    field_part = Macro.camelize(field_name)

    if parent_name do
      "#{parent_name}#{field_part}"
    else
      field_part
    end
  end
end

defmodule AshOpenApi.ResourceConverter do
  @moduledoc """
  Converts OpenAPI schemas into Ash Embedded Resources.
  """

  alias AshOpenApi.Debug
  alias OpenApiSpex.{Reference, Schema}
  alias AshOpenApi.{TypeConverter, Context, SchemaConverter}

  @supported_component_types ~w(schemas responses headers parameters)
  @known_ash_types [
    :string,
    :integer,
    :boolean,
    :float,
    :decimal,
    :date,
    :time,
    :utc_datetime,
    :naive_datetime,
    :uuid,
    :ci_string
  ]

  @doc """
  Converts OpenAPI schemas into Ash Resource modules.
  Returns a map of module names to their content as strings.

  ## Examples

      iex> schemas = %{"User" => user_schema, "Post" => post_schema}
      iex> AshOpenApi.ResourceConverter.to_ash_resources(schemas, "Api")
      %{
        "MyApp.Api.Schemas.User" => "defmodule MyApp.Api.Schemas.User do\\n...",
        "MyApp.Api.Schemas.Post" => "defmodule MyApp.Api.Schemas.Post do\\n..."
      }
  """
  def to_ash_resources(nil, _namespace, _component_type) do
    %{}
  end

  def to_ash_resources(schemas, namespace, "headers" = component_type) do
    Context.setup(schemas, namespace)

    result =
      schemas
      |> Enum.map(fn {name, schema} ->
        module_name = generate_module_name(name, component_type)
        content = generate_module(name, schema, component_type)

        # Add debug output
        if content do
          Mix.shell().info([:green, "* Generated #{module_name}:\n", :reset])
        end

        {module_name, content}
      end)
      |> Enum.reject(fn {_, content} -> is_nil(content) end)
      |> Map.new()

    Mix.shell().info([:yellow, "* Generated #{map_size(result)} resources for #{component_type}"])

    result
  end

  def to_ash_resources(schemas, namespace, component_type)
      when component_type in @supported_component_types do
    # Convert the list of tuples to a map before setting up the context
    schemas_map = Map.new(schemas)
    Context.setup(schemas_map, namespace)

    result =
      schemas
      |> Enum.map(fn {name, schema} ->
        module_name = generate_module_name(name, component_type)
        content = generate_module(name, schema, component_type)

        # Add debug output
        if content do
          Mix.shell().info([:green, "* Generated #{module_name}:\n", :reset])
        end

        {module_name, content}
      end)
      |> Enum.reject(fn {_, content} -> is_nil(content) end)
      |> Map.new()

    # Add summary debug output
    Mix.shell().info([:yellow, "* Generated #{map_size(result)} resources for #{component_type}"])

    result
  end

  def to_ash_resources(schemas, namespace, "parameters" = component_type) do
    # Convert the list of tuples to a map before setting up the context
    schemas_map = Map.new(schemas)
    Context.setup(schemas_map, namespace)

    result =
      schemas
      |> Enum.map(fn {name, schema} ->
        # Just use the name directly with the Parameters namespace
        module_name = generate_module_name(name, component_type)
        content = generate_module(name, schema, component_type)

        # Add debug output
        if content do
          Mix.shell().info([:green, "* Generated #{module_name}:\n", :reset])
        end

        {module_name, content}
      end)
      |> Enum.reject(fn {_, content} -> is_nil(content) end)
      |> Map.new()

    # Add summary debug output
    Mix.shell().info([:yellow, "* Generated #{map_size(result)} resources for #{component_type}"])

    result
  end

  def to_ash_resources(_schemas, _namespace, component_type) do
    Mix.shell().info([:yellow, "* Skipping unsupported component type: #{component_type}"])
    %{}
  end

  def generate_module(_name, nil, _component_type) do
    nil
  end

  def generate_module(name, %Schema{type: :string, enum: values} = schema, _component_type)
      when not is_nil(values) do
    # Convert string values to atoms
    atom_values = Enum.map(values, &String.to_atom/1)

    """
    @moduledoc \"\"\"
    #{name}
    #{schema.description || ""}
    \"\"\"
    use Ash.Type.Enum, values: #{inspect(atom_values)}

    def match(value) when is_binary(value), do: {:ok, String.to_atom(value)}
    def match(value), do: super(value)
    """
  end

  def generate_module(name, %Schema{allOf: schemas} = base_schema, component_type)
      when is_list(schemas) do
    # Drop the allOf field from the base schema but keep other fields
    base_schema = Map.drop(base_schema, [:allOf])

    # Convert each schema in allOf, preserving references
    merged_schema =
      schemas
      |> Enum.reduce(base_schema, fn
        %Reference{} = ref, acc_schema ->
          # For references in allOf, we want to merge their non-reference properties
          # but preserve any property references
          case resolve_reference(ref) do
            nil ->
              acc_schema

            referenced_schema ->
              # Merge properties, preserving references
              merged_properties =
                Map.merge(
                  acc_schema.properties || %{},
                  referenced_schema.properties || %{},
                  fn _k, v1, v2 ->
                    case {v1, v2} do
                      {%Reference{}, _} -> v1
                      {_, %Reference{}} -> v2
                      _ -> v2
                    end
                  end
                )

              %Schema{
                acc_schema
                | properties: merged_properties,
                  required:
                    Enum.uniq((acc_schema.required || []) ++ (referenced_schema.required || [])),
                  type: referenced_schema.type || acc_schema.type,
                  description: referenced_schema.description || acc_schema.description
              }
          end

        %Schema{} = schema, acc_schema ->
          # For direct schemas, merge properties preserving references
          merged_properties =
            Map.merge(
              acc_schema.properties || %{},
              schema.properties || %{},
              fn _k, v1, v2 ->
                case {v1, v2} do
                  {%Reference{}, _} -> v1
                  {_, %Reference{}} -> v2
                  _ -> v2
                end
              end
            )

          %Schema{
            acc_schema
            | properties: merged_properties,
              required: Enum.uniq((acc_schema.required || []) ++ (schema.required || [])),
              type: schema.type || acc_schema.type,
              description: schema.description || acc_schema.description
          }

        schema, acc_schema when is_map(schema) ->
          # For raw maps, convert to Schema first then merge
          schema_struct = %Schema{
            type: schema["type"] && String.to_atom(schema["type"]),
            properties: schema["properties"],
            required: schema["required"] || [],
            description: schema["description"]
          }

          merged_properties =
            Map.merge(
              acc_schema.properties || %{},
              schema_struct.properties || %{},
              fn _k, v1, v2 ->
                case {v1, v2} do
                  {%Reference{}, _} -> v1
                  {_, %Reference{}} -> v2
                  _ -> v2
                end
              end
            )

          %Schema{
            acc_schema
            | properties: merged_properties,
              required: Enum.uniq((acc_schema.required || []) ++ (schema_struct.required || [])),
              type: schema_struct.type || acc_schema.type,
              description: schema_struct.description || acc_schema.description
          }
      end)

    # Now generate the module with the merged schema
    generate_module(name, merged_schema, component_type)
  end

  def generate_module(name, %Schema{type: type} = schema, _component_type)
      when type in @known_ash_types do
    # For scalar types, create a custom type module instead of a resource
    description = if schema.description, do: schema.description, else: name
    storage_type = determine_storage_type(schema)

    """
    @moduledoc \"\"\"
    #{name}
    #{description}
    \"\"\"
    use Ash.Type

    @impl true
    def storage_type(_), do: #{inspect(storage_type)}

    @impl true
    def cast_input(nil, _), do: {:ok, nil}
    def cast_input(value, constraints) do
      #{generate_cast_input(storage_type)}
    end

    @impl true
    def cast_stored(nil, _), do: {:ok, nil}
    def cast_stored(value, constraints) do
      #{generate_cast_stored(storage_type)}
    end

    @impl true
    def dump_to_native(nil, _), do: {:ok, nil}
    def dump_to_native(value, constraints) do
      #{generate_dump_to_native(storage_type)}
    end

    @impl true
    def constraints do
      #{inspect(build_constraints(schema), pretty: true)}
    end
    """
  end

  def generate_module(name, %Schema{allOf: allOf} = schema, component_type) when is_list(allOf) do
    base_schema = Map.drop(schema, [:allOf, "allOf"])
    merged_schema = merge_all_of_schemas(allOf, base_schema)
    generate_module(name, merged_schema, component_type)
  end

  def generate_module(name, %Schema{type: :object} = schema, component_type) do
    generate_resource_module(name, schema, component_type)
  end

  def generate_module(name, %Schema{} = schema, _component_type) do
    description = if schema.description, do: schema.description, else: name
    type = TypeConverter.to_ash_type(schema)

    """
    @moduledoc \"\"\"
    #{name}
    #{description}
    \"\"\"
    use Ash.Type

    @impl true
    def storage_type, do: #{inspect(type)}

    @impl true
    def constraints do
      #{inspect(build_constraints(schema), pretty: true)}
    end
    """
  end

  def generate_module(
        name,
        %{"type" => "object", "properties" => props} = raw_schema,
        component_type
      ) do
    # Convert the raw properties to Schema structs
    properties =
      Map.new(props, fn {key, value} ->
        # Convert the raw property schema to a Schema struct directly
        schema = %Schema{
          type: String.to_atom(value["type"]),
          description: value["description"],
          format: value["format"] && String.to_atom(value["format"]),
          maxLength: value["maxLength"],
          minLength: value["minLength"],
          pattern: value["pattern"],
          enum: value["enum"],
          nullable: value["nullable"],
          default: value["default"]
        }

        {key, schema}
      end)

    # Create a Schema struct for the object
    schema = %Schema{
      type: :object,
      properties: properties,
      required: Map.get(raw_schema, "required", [])
    }

    generate_resource_module(name, schema, component_type)
  end

  def generate_module(_name, %Reference{}, _component_type) do
    # For references, we don't need to generate a new resource
    nil
  end

  defp generate_resource_module(
         name,
         %Schema{properties: props, required: required} = schema,
         _component_type
       ) do
    required = required || []

    attributes = extract_attributes(schema, props, required)
    Debug.log("Generated attributes: #{inspect(attributes)}", verbose: true)

    if Enum.empty?(attributes) do
      Debug.log("Warning: No attributes generated for #{name}", verbose: true)
    end

    """
    @moduledoc \"\"\"
    #{name}
    #{schema.description || ""}
    \"\"\"
    use Ash.Resource,
      data_layer: :embedded

    attributes do
    #{indent_lines(attributes, 2)}
    end
    """
  end

  defp extract_attributes(_schema, nil, _required), do: []

  defp extract_attributes(schema, props, required) when is_map(props) do
    Debug.log("schema: #{inspect(schema)}, props: #{inspect(props)}", verbose: true)

    props
    |> Enum.map(fn {name, property} ->
      generate_attribute(name, property, to_string(name) in required)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp generate_attribute(name, %Reference{} = ref, required) do
    [_, "components", component_type, schema_name] = String.split(ref."$ref", "/")

    if component_type == "schemas" do
      module_name =
        "#{Context.app_name()}.#{Context.namespace()}.Schemas.#{Macro.camelize(schema_name)}"

      allow_nil = get_allow_nil(required, false)

      """
      attribute #{inspect(name)}, #{module_name}, public?: true#{allow_nil}
      """
    else
      case resolve_reference(ref) do
        nil ->
          type = TypeConverter.to_ash_type(ref)
          allow_nil = get_allow_nil(required, false)
          type_str = type |> Module.split() |> Enum.join(".")

          """
          attribute #{inspect(name)}, #{type_str}, public?: true#{allow_nil}
          """

        referenced_schema ->
          generate_attribute(name, referenced_schema, required)
      end
    end
  end

  defp generate_attribute(name, %Schema{type: :array, items: items} = schema, required) do
    type = TypeConverter.to_ash_type(items)
    # For arrays, check if type includes "null" for nullable
    nullable = is_list(schema.type) && Enum.member?(schema.type, :null)
    allow_nil = get_allow_nil(required, nullable)

    type_str =
      case type do
        type when type in @known_ash_types ->
          ":#{type}"

        {:array, inner_type} ->
          "{:array, #{inner_type}}"

        type when is_atom(type) ->
          if to_string(type) |> String.starts_with?("Elixir.") do
            # For full module names, just use the module path
            type |> Module.split() |> Enum.join(".")
          else
            # For simple atoms, add the colon prefix
            ":#{type}"
          end
      end

    constraints = array_constraints(schema)

    constraints_str =
      if constraints != [],
        do: ", constraints: [\n      #{Enum.join(constraints, ",\n      ")}\n    ]",
        else: ""

    """
    attribute #{inspect(name)}, {:array, #{type_str}}, public?: true#{allow_nil}#{constraints_str}
    """
  end

  defp generate_attribute(name, %Schema{} = schema, required) do
    type = TypeConverter.to_ash_type(schema)

    description =
      if schema.description, do: ", description: #{inspect(schema.description)}", else: ""

    default = if schema.default, do: ", default: #{inspect(schema.default)}", else: ""

    # Check if type includes "null" for nullable
    nullable = is_list(schema.type) && Enum.member?(schema.type, :null)
    allow_nil = get_allow_nil(required, nullable)

    constraints = build_constraints(schema)

    constraints_str =
      if constraints != [],
        do: ", constraints: [\n      #{Enum.join(constraints, ",\n      ")}\n    ]",
        else: ""

    attribute_name = if is_binary(name), do: String.to_atom(name), else: name

    """
    attribute #{inspect(attribute_name)}, #{inspect(type)}#{description}#{default}#{allow_nil}, public?: true#{constraints_str}
    """
  end

  defp generate_attribute(
         name,
         %Schema{allOf: schemas, required: base_required} = base_schema,
         required
       )
       when is_list(schemas) do
    # Drop the allOf field from the base schema but keep other fields
    base_schema = Map.drop(base_schema, [:allOf])

    # Convert each schema in allOf, preserving references
    merged_schema =
      schemas
      |> Enum.reduce({base_schema, base_required || []}, fn
        %Reference{} = ref, {acc_schema, acc_required} ->
          referenced_schema = resolve_reference(ref)

          {
            Map.merge(acc_schema, referenced_schema),
            (referenced_schema.required || []) ++ acc_required
          }

        schema, {acc_schema, acc_required} ->
          {
            Map.merge(acc_schema, schema),
            (schema.required || []) ++ acc_required
          }
      end)
      |> then(fn {schema, all_required} ->
        %{schema | required: Enum.uniq(all_required)}
      end)

    # Now process as a normal schema
    generate_attribute(name, merged_schema, required)
  end

  defp generate_attribute(name, %{"allOf" => schemas} = schema, required) do
    # For allOf, we need to merge all the schemas together
    base_schema = Map.drop(schema, ["allOf"])
    base_required = schema["required"] || []

    # Convert each schema in allOf and merge them with the base schema
    {merged_schema, all_required} =
      schemas
      |> Enum.reduce({base_schema, base_required}, fn
        %{"$ref" => ref}, {acc_schema, acc_required} ->
          # Convert reference to Reference struct and resolve it
          referenced_schema = resolve_reference(%Reference{:"$ref" => ref})

          {
            Map.merge(acc_schema, referenced_schema),
            (referenced_schema.required || []) ++ acc_required
          }

        %Reference{} = ref, {acc_schema, acc_required} ->
          referenced_schema = resolve_reference(ref)

          {
            Map.merge(acc_schema, referenced_schema),
            (referenced_schema.required || []) ++ acc_required
          }

        %Schema{} = schema, {acc_schema, acc_required} ->
          {
            Map.merge(acc_schema, schema),
            (schema.required || []) ++ acc_required
          }

        schema, {acc_schema, acc_required} when is_map(schema) ->
          # Handle inline schema
          {
            Map.merge(acc_schema, schema),
            (schema["required"] || []) ++ acc_required
          }
      end)

    # Ensure unique required fields and add them to the merged schema
    merged_schema = Map.put(merged_schema, "required", Enum.uniq(all_required))

    # Now process as a normal schema
    case merged_schema do
      %Schema{} ->
        generate_attribute(name, merged_schema, required)

      schema when is_map(schema) ->
        # If it's still a raw map, convert type and process
        if Map.has_key?(schema, "type") do
          generate_attribute(name, %{"type" => schema["type"]} |> Map.merge(schema), required)
        else
          # If no type specified, default to object
          generate_attribute(name, Map.put(schema, "type", "object"), required)
        end
    end
  end

  defp generate_attribute(name, %{"$ref" => ref}, required) do
    # Convert to Reference struct and process
    generate_attribute(name, %Reference{:"$ref" => ref}, required)
  end

  defp generate_attribute(name, %{"type" => type} = schema, required) do
    # Manually map the known OpenAPI schema properties to Schema struct fields
    decoded_schema = %Schema{
      type: String.to_atom(type),
      description: schema["description"],
      format: schema["format"] && String.to_atom(schema["format"]),
      maxLength: schema["maxLength"],
      minLength: schema["minLength"],
      pattern: schema["pattern"],
      enum: schema["enum"],
      nullable: schema["nullable"],
      default: schema["default"],
      properties: schema["properties"]
    }

    Debug.log("name: #{inspect(name)}, schema: #{inspect(decoded_schema)}", verbose: true)
    generate_attribute(name, decoded_schema, required)
  end

  defp resolve_reference(%Reference{"$ref": ref}) do
    # Extract component type and name from the ref
    # Format: "#/components/{type}/{name}"
    [_, "components", component_type, schema_name] = String.split(ref, "/")

    # Get the schema from context
    Context.get_schema("#{component_type}/#{schema_name}")
  end

  defp build_constraints(%Schema{} = schema) do
    [
      enum_constraint(schema),
      pattern_constraint(schema),
      length_constraints(schema),
      number_constraints(schema)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp enum_constraint(%Schema{enum: nil}), do: nil

  defp enum_constraint(%Schema{enum: values}) when is_list(values) do
    "one_of: #{inspect(values)}"
  end

  defp pattern_constraint(%Schema{pattern: nil}), do: nil

  defp pattern_constraint(%Schema{pattern: pattern}) do
    "match: Regex.compile!(#{inspect(pattern)})"
  end

  defp length_constraints(schema) do
    [
      min_length_constraint(schema),
      max_length_constraint(schema)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp min_length_constraint(%Schema{minLength: nil}), do: nil

  defp min_length_constraint(%Schema{minLength: min}) do
    "min_length: #{min}"
  end

  defp max_length_constraint(%Schema{maxLength: nil}), do: nil

  defp max_length_constraint(%Schema{maxLength: max}) do
    "max_length: #{max}"
  end

  defp number_constraints(schema) do
    [
      minimum_constraint(schema),
      maximum_constraint(schema),
      multiple_of_constraint(schema)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp minimum_constraint(%Schema{minimum: nil}), do: nil

  defp minimum_constraint(%Schema{minimum: min, exclusiveMinimum: true}) do
    "min: #{min}, exclusive_min?: true"
  end

  defp minimum_constraint(%Schema{minimum: min}) do
    "min: #{min}"
  end

  defp maximum_constraint(%Schema{maximum: nil}), do: nil

  defp maximum_constraint(%Schema{maximum: max, exclusiveMaximum: true}) do
    "max: #{max}, exclusive_max?: true"
  end

  defp maximum_constraint(%Schema{maximum: max}) do
    "max: #{max}"
  end

  defp multiple_of_constraint(%Schema{multipleOf: nil}), do: nil

  defp multiple_of_constraint(%Schema{multipleOf: multiple}) do
    "multiple_of: #{multiple}"
  end

  defp indent_lines(string_or_lines, spaces) do
    lines =
      if is_binary(string_or_lines),
        do: String.split(string_or_lines, "\n"),
        else: string_or_lines

    lines
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map_join("\n", fn line -> String.duplicate(" ", spaces) <> line end)
  end

  defp generate_module_name(name, component_type) do
    cond do
      component_type == "schemas" ->
        generate_schema_module_name(name)

      component_type == "headers" ->
        generate_header_module_name(name)

      component_type == "responses" and String.contains?(name, ".") ->
        generate_response_module_name(name)

      component_type == "parameters" and String.contains?(name, ".") ->
        # For operation parameters, if they're references, we'll use the component parameter module
        case String.split(name, ".", parts: 3) do
          [operation_id, "Parameters", param_name] ->
            # Check if this is a reference to a component parameter
            if is_reference?(param_name) do
              generate_component_parameter_module_name(param_name)
            else
              "#{Context.app_name()}.#{Context.namespace()}.#{operation_id}.Parameters.#{param_name}"
            end

          _ ->
            generate_component_parameter_module_name(name)
        end

      component_type == "parameters" ->
        generate_component_parameter_module_name(name)

      true ->
        generate_default_module_name(name, component_type)
    end
  end

  defp generate_schema_module_name(name) do
    "#{Context.app_name()}.#{Context.namespace()}.Schemas.#{Macro.camelize(name)}"
  end

  defp generate_header_module_name(name) do
    "#{Context.app_name()}.#{Context.namespace()}.Headers.#{Macro.camelize(name)}"
  end

  defp generate_response_module_name(name) do
    # First, split by underscore to separate path_status from content_type
    case String.split(name, "_", parts: 3) do
      [path, status, content_type] ->
        # Clean up the path (remove leading slash)
        operation_id = String.trim_leading(path, "/")

        sanitized_content_type = sanitize_content_type(content_type)

        "#{Context.app_name()}.#{Context.namespace()}.#{operation_id}.Responses#{status}.#{sanitized_content_type}"

      _ ->
        raise "Invalid response name format: #{name}"
    end
  end

  defp sanitize_content_type(content_type) do
    [base, subtype] = String.split(content_type, "/", parts: 2)

    [base, subtype]
    |> Enum.map(&sanitize_type_part/1)
    |> Enum.join("")
  end

  defp sanitize_type_part(part) do
    part
    |> String.replace(~r/[^a-zA-Z0-9]/, "")
    |> Macro.camelize()
  end

  defp generate_component_parameter_module_name(name) do
    "#{Context.app_name()}.#{Context.namespace()}.Parameters.#{Macro.camelize(name)}"
  end

  defp generate_default_module_name(name, component_type) do
    "#{Context.app_name()}.#{Context.namespace()}.#{Macro.camelize(component_type)}.#{Macro.camelize(name)}"
  end

  # Helper function to check if a parameter name is a reference
  defp is_reference?(param_name) do
    schemas = Context.get_all_schemas()
    key = "parameters/#{param_name}"

    case Map.get(schemas, key) do
      %OpenApiSpex.Reference{} -> true
      _ -> false
    end
  end

  defp array_constraints(%Schema{type: :array} = schema) do
    [
      min_items_constraint(schema),
      max_items_constraint(schema),
      unique_items_constraint(schema)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp min_items_constraint(%Schema{minItems: nil}), do: nil
  defp min_items_constraint(%Schema{minItems: min}), do: "min_length: #{min}"

  defp max_items_constraint(%Schema{maxItems: nil}), do: nil
  defp max_items_constraint(%Schema{maxItems: max}), do: "max_length: #{max}"

  defp unique_items_constraint(%Schema{uniqueItems: true}), do: "unique?: true"
  defp unique_items_constraint(_), do: nil

  defp get_allow_nil(true, false), do: ", allow_nil?: false"
  defp get_allow_nil(_required, _nullable), do: ", allow_nil?: true"

  defp determine_storage_type(%Schema{type: :string, format: format}) when not is_nil(format) do
    case format do
      :date -> :date
      :date_time -> :utc_datetime
      :email -> :string
      :uuid -> :uuid
      :uri -> :string
      :binary -> :binary
      _ -> :string
    end
  end

  defp determine_storage_type(%Schema{type: type}) when type in @known_ash_types, do: type

  defp generate_cast_input(storage_type) do
    case storage_type do
      :string -> "Ash.Type.String.cast_input(value, constraints)"
      :integer -> "Ash.Type.Integer.cast_input(value, constraints)"
      :boolean -> "Ash.Type.Boolean.cast_input(value, constraints)"
      :float -> "Ash.Type.Float.cast_input(value, constraints)"
      :decimal -> "Ash.Type.Decimal.cast_input(value, constraints)"
      :date -> "Ash.Type.Date.cast_input(value, constraints)"
      :time -> "Ash.Type.Time.cast_input(value, constraints)"
      :utc_datetime -> "Ash.Type.UtcDatetime.cast_input(value, constraints)"
      :naive_datetime -> "Ash.Type.NaiveDatetime.cast_input(value, constraints)"
      :uuid -> "Ash.Type.UUID.cast_input(value, constraints)"
      :ci_string -> "Ash.Type.CiString.cast_input(value, constraints)"
      _ -> "Ash.Type.String.cast_input(value, constraints)"
    end
  end

  defp generate_cast_stored(storage_type) do
    case storage_type do
      :string -> "Ash.Type.String.cast_stored(value, constraints)"
      :integer -> "Ash.Type.Integer.cast_stored(value, constraints)"
      :boolean -> "Ash.Type.Boolean.cast_stored(value, constraints)"
      :float -> "Ash.Type.Float.cast_stored(value, constraints)"
      :decimal -> "Ash.Type.Decimal.cast_stored(value, constraints)"
      :date -> "Ash.Type.Date.cast_stored(value, constraints)"
      :time -> "Ash.Type.Time.cast_stored(value, constraints)"
      :utc_datetime -> "Ash.Type.UtcDatetime.cast_stored(value, constraints)"
      :naive_datetime -> "Ash.Type.NaiveDatetime.cast_stored(value, constraints)"
      :uuid -> "Ash.Type.UUID.cast_stored(value, constraints)"
      :ci_string -> "Ash.Type.CiString.cast_stored(value, constraints)"
      _ -> "Ash.Type.String.cast_stored(value, constraints)"
    end
  end

  defp generate_dump_to_native(storage_type) do
    case storage_type do
      :string -> "Ash.Type.String.dump_to_native(value, constraints)"
      :integer -> "Ash.Type.Integer.dump_to_native(value, constraints)"
      :boolean -> "Ash.Type.Boolean.dump_to_native(value, constraints)"
      :float -> "Ash.Type.Float.dump_to_native(value, constraints)"
      :decimal -> "Ash.Type.Decimal.dump_to_native(value, constraints)"
      :date -> "Ash.Type.Date.dump_to_native(value, constraints)"
      :time -> "Ash.Type.Time.dump_to_native(value, constraints)"
      :utc_datetime -> "Ash.Type.UtcDatetime.dump_to_native(value, constraints)"
      :naive_datetime -> "Ash.Type.NaiveDatetime.dump_to_native(value, constraints)"
      :uuid -> "Ash.Type.UUID.dump_to_native(value, constraints)"
      :ci_string -> "Ash.Type.CiString.dump_to_native(value, constraints)"
      _ -> "Ash.Type.String.dump_to_native(value, constraints)"
    end
  end

  defp merge_all_of_schemas(schemas, base_schema) do
    Enum.reduce(schemas, base_schema, fn
      %Reference{} = ref, acc_schema ->
        case resolve_reference(ref) do
          nil -> acc_schema
          referenced_schema -> merge_schemas(acc_schema, referenced_schema)
        end

      %Schema{} = schema, acc_schema ->
        merge_schemas(acc_schema, schema)

      schema, acc_schema when is_map(schema) ->
        schema_struct = SchemaConverter.convert_schema(schema)
        merge_schemas(acc_schema, schema_struct)
    end)
  end

  defp merge_schemas(schema1, schema2) do
    merged_properties =
      Map.merge(
        schema1.properties || %{},
        schema2.properties || %{},
        fn _k, v1, v2 ->
          case {v1, v2} do
            {%Reference{}, _} -> v1
            {_, %Reference{}} -> v2
            _ -> v2
          end
        end
      )

    %Schema{
      schema1
      | properties: merged_properties,
        required: Enum.uniq((schema1.required || []) ++ (schema2.required || [])),
        type: schema2.type || schema1.type,
        description: schema2.description || schema1.description
    }
  end
end

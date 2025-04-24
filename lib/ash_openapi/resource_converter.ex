defmodule AshOpenApi.ResourceConverter do
  @moduledoc """
  Converts OpenAPI schemas into Ash Embedded Resources.
  """

  alias AshOpenApi.Debug
  alias OpenApiSpex.{Reference, Schema}
  alias AshOpenApi.{TypeConverter, Context}

  @supported_component_types ~w(schemas responses headers parameters)

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

    # Add summary debug output
    Mix.shell().info([:yellow, "* Generated #{map_size(result)} resources for #{component_type}"])

    result
  end

  def to_ash_resources(schemas, namespace, "parameters" = component_type) do
    Context.setup(schemas, namespace)

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

  defp generate_module(_name, nil, _component_type) do
    nil
  end

  defp generate_module(name, %Schema{type: :string, enum: values} = schema, component_type)
       when not is_nil(values) do
    # Convert string values to atoms
    atom_values = Enum.map(values, &String.to_atom/1)

    """
    defmodule #{Context.app_name()}.#{Context.namespace()}.#{Macro.camelize(component_type)}.#{name} do
      @moduledoc \"\"\"
      #{name}
      #{schema.description || ""}
      \"\"\"
      use Ash.Type.Enum, values: #{inspect(atom_values)}

      def match(value) when is_binary(value), do: {:ok, String.to_atom(value)}
      def match(value), do: super(value)
    end
    """
  end

  defp generate_module(name, %Schema{} = schema, component_type) do
    generate_resource_module(name, schema, component_type)
  end

  defp generate_module(
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

  defp generate_module(_name, %Reference{}, _component_type) do
    # For references, we don't need to generate a new resource
    nil
  end

  defp generate_resource_module(
         name,
         %Schema{properties: props, required: required} = schema,
         component_type
       ) do
    required = required || []

    attributes = extract_attributes(schema, props, required)
    Debug.log("Generated attributes: #{inspect(attributes)}", verbose: true)

    namespace = Context.namespace()
    app_name = Context.app_name()

    if Enum.empty?(attributes) do
      Debug.log("Warning: No attributes generated for #{name}", verbose: true)
    end

    """
    defmodule #{app_name}.#{namespace}.#{Macro.camelize(component_type)}.#{name} do
      use Ash.Resource,
        data_layer: :embedded

      attributes do
    #{indent_lines(attributes, 4)}
      end
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

  defp generate_attribute(name, %Schema{type: :array, items: items}, required) do
    type = TypeConverter.to_ash_type(items)
    allow_nil = if required, do: ", allow_nil?: false", else: ""

    """
    attribute #{inspect(name)}, {:array, #{type}}, public?: true#{allow_nil}
    """
  end

  defp generate_attribute(name, %Reference{} = ref, required) do
    type = TypeConverter.to_ash_type(ref)
    allow_nil = if required, do: ", allow_nil?: false", else: ""

    """
    attribute #{inspect(name)}, #{type}, public?: true#{allow_nil}
    """
  end

  defp generate_attribute(name, %Schema{} = schema, required) do
    type = TypeConverter.to_ash_type(schema)

    description =
      if schema.description, do: ", description: #{inspect(schema.description)}", else: ""

    default = if schema.default, do: ", default: #{inspect(schema.default)}", else: ""

    allow_nil =
      cond do
        required -> ", allow_nil?: false"
        schema.nullable -> ", allow_nil?: true"
        true -> ""
      end

    constraints = build_constraints(schema)

    constraints_str =
      if constraints != [],
        do: ", constraints: [\n      #{Enum.join(constraints, ",\n      ")}\n    ]",
        else: ""

    # Convert string name to atom
    attribute_name = if is_binary(name), do: String.to_atom(name), else: name

    """
    attribute #{inspect(attribute_name)}, #{inspect(type)}#{description}#{default}#{allow_nil}, public?: true#{constraints_str}
    """
  end

  defp generate_attribute(name, %{"type" => _type, "allOf" => schemas} = schema, required) do
    # For allOf, we need to merge all the schemas together
    base_schema = Map.drop(schema, ["allOf"])

    # Convert each schema in allOf and merge them with the base schema
    merged_schema =
      schemas
      |> Enum.reduce(base_schema, fn schema, acc ->
        Map.merge(acc, schema)
      end)

    # Now process as a normal schema
    generate_attribute(name, merged_schema, required)
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
      default: schema["default"]
    }

    Debug.log("name: #{inspect(name)}, schema: #{inspect(decoded_schema)}", verbose: true)
    generate_attribute(name, decoded_schema, required)
  end

  defp generate_attribute(name, schema, _required) do
    Debug.log("skipping - name: #{inspect(name)}, schema: #{inspect(schema)}", verbose: true)
    # schema = OpenApiSpex.OpenApi.Decode.decode(%{"schema" => schema})[:schema]
    # generate_attribute(name, schema, required)
    nil
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
      # For component schemas (e.g., "User")
      component_type == "schemas" ->
        "#{Context.app_name()}.#{Context.namespace()}.Schemas.#{name}"

      # For headers (e.g., "ETag")
      component_type == "headers" ->
        "#{Context.app_name()}.#{Context.namespace()}.Headers.#{name}"

      # For operation responses (e.g., "GetUser.Responses200.ApplicationJson")
      component_type == "responses" and String.contains?(name, ".") ->
        [operation_id, status, content_type] = String.split(name, ".", parts: 3)

        "#{Context.app_name()}.#{Context.namespace()}.#{operation_id}.Responses#{status}.#{content_type}"

      # For operation request bodies (e.g., "CreateUser.RequestBodies.ApplicationJson")
      component_type == "requestBodies" and String.contains?(name, ".") ->
        [operation_id, _request_bodies, content_type] = String.split(name, ".", parts: 3)

        "#{Context.app_name()}.#{Context.namespace()}.#{operation_id}.RequestBodies.#{content_type}"

      # For operation parameters (e.g., "GetUserById.Parameters.Id")
      component_type == "parameters" and String.contains?(name, ".") ->
        [operation_id, _parameters, param_name] = String.split(name, ".", parts: 3)
        "#{Context.app_name()}.#{Context.namespace()}.#{operation_id}.Parameters.#{param_name}"

      # For component parameters (e.g., "limitQueryParam")
      component_type == "parameters" ->
        "#{Context.app_name()}.#{Context.namespace()}.Parameters.#{name}"

      # Default case for other component types
      true ->
        "#{Context.app_name()}.#{Context.namespace()}.#{Macro.camelize(component_type)}.#{name}"
    end
  end
end

defmodule AshOpenApi.ResourceConverter do
  @moduledoc """
  Converts OpenAPI schemas into Ash Embedded Resources.
  """

  alias OpenApiSpex.{Reference, Schema}
  alias AshOpenApi.{TypeConverter, Context}

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
  def to_ash_resources(schemas, namespace, component_type) do
    Context.setup(schemas, namespace)

    schemas
    |> Enum.map(fn {name, schema} ->
      module_name = "#{Context.app_name()}.#{namespace}.#{Macro.camelize(component_type)}.#{name}"
      content = generate_resource_module(name, schema, component_type)
      {module_name, content}
    end)
    |> Map.new()
  end

  defp generate_resource_module(
         name,
         %Schema{properties: props, required: required},
         component_type
       ) do
    required = required || []
    attributes = extract_attributes(props, required)

    """
    defmodule #{Context.app_name()}.#{Context.namespace()}.#{Macro.camelize(component_type)}.#{name} do
      use Ash.Resource,
        data_layer: :embedded

      attributes do
    #{indent_lines(attributes, 4)}
      end
    end
    """
  end

  defp extract_attributes(nil, _required), do: []

  defp extract_attributes(props, required) when is_map(props) do
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

    """
    attribute #{inspect(name)}, #{inspect(type)}#{description}#{default}#{allow_nil}, public?: true#{constraints_str}
    """
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
    "match: ~r/#{pattern}/"
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
end

defmodule Mix.Tasks.AshOpenapi.Generate do
  @shortdoc """
  Generates Ash resources from an OpenAPI definition.

  This task will:
  * Parse the OpenAPI definition file
  * Extract all component schemas and inline schemas from operations
  * Generate corresponding Ash resources
  * Create or update the resource modules in your project
  """
  @example "mix ash_openapi.generate --definition path/to/openapi.yaml --namespace Api"

  @moduledoc """
  #{@shortdoc}

  ## Example
  ```sh
  #{@example}
  ```

  ## Reference

  ### Options

    * `--definition` - Path to the OpenAPI definition file. This can be either a JSON or YAML file
      that follows the OpenAPI 3.X.X specification.

    * `--namespace` - The namespace under which to generate the resources. This will be used to
      organize the generated modules. For example, if namespace is "Api", resources will be generated
      under `YourApp.Api.Schemas`, `YourApp.Api.Responses`, etc.

    * `--verbose` - Enable debug output during generation. Defaults to false.
  """

  use Igniter.Mix.Task
  alias AshOpenApi.{SchemaParser, SchemaExtractor, ResourceConverter, Debug}
  alias Igniter.Project.Module
  alias Igniter.Mix.Task.Info

  @impl Igniter.Mix.Task
  def info(_args, _opts) do
    %Info{
      schema: [
        definition: :string,
        namespace: :string,
        verbose: :boolean
      ],
      defaults: [
        verbose: false
      ],
      required: [:definition, :namespace],
      example: "mix ash_openapi.generate --definition path/to/openapi.yaml --namespace Api"
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    app_name = Mix.Project.config()[:app]
    opts = igniter.args.options

    # Parse the OpenAPI definition
    Debug.log("Reading OpenAPI definition from #{Keyword.get(opts, :definition)}", opts)
    definition_content = File.read!(Keyword.get(opts, :definition))
    {:ok, definition} = SchemaParser.parse_and_store(definition_content)
    Debug.log("Successfully parsed OpenAPI definition", opts)

    # Extract all schemas (including inline ones)
    Debug.log("Extracting schemas from definition", opts)
    schemas = SchemaExtractor.extract_all_schemas(definition)
    Debug.log("Found #{map_size(schemas)} schemas", opts)

    # Group schemas by component type
    schemas_by_type =
      schemas
      |> Enum.group_by(
        fn {path, _schema} ->
          [component_type, _] = String.split(path, "/", parts: 2)
          component_type
        end,
        fn {path, schema} ->
          [_, name] = String.split(path, "/", parts: 2)
          {name, schema}
        end
      )

    Debug.log("Grouped schemas by type: #{inspect(Map.keys(schemas_by_type))}", opts)

    # Generate resources for each component type
    for {component_type, type_schemas} <- schemas_by_type do
      Debug.log("Processing component type: #{component_type}", opts)

      # Convert schemas to resources
      resources =
        ResourceConverter.to_ash_resources(
          type_schemas,
          Keyword.get(opts, :namespace),
          component_type
        )

      if map_size(resources) > 0 do
        Debug.log("Generated #{map_size(resources)} resources for #{component_type}", opts)

        # Create or update each resource module
        for {module_name, content} <- resources do
          file_name = module_name |> String.split(".") |> List.last() |> Macro.underscore()

          file_path =
            Path.join([
              "lib",
              to_string(app_name),
              Keyword.get(opts, :namespace),
              Macro.camelize(component_type),
              "#{file_name}.ex"
            ])

          Debug.log("Writing resource to #{file_path}", opts)

          Module.find_and_update_or_create_module(
            igniter,
            String.to_atom(module_name),
            content,
            fn zipper ->
              ast = Code.string_to_quoted!(content)
              {:ok, Sourceror.Zipper.replace(zipper, ast)}
            end,
            path: file_path
          )
        end
      end
    end

    Mix.shell().info([:green, "* Generated Ash resources from OpenAPI definition"])
  end
end

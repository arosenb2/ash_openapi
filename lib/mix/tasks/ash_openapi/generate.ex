defmodule Mix.Tasks.AshOpenapi.Generate do
  use Igniter.Mix.Task

  @example "mix ash_openapi.generate path/to/openapi.yaml --output-dir lib/my_app"

  @shortdoc "Generate Ash resources and operation stubs from OpenAPI spec"
  @moduledoc """
  #{@shortdoc}

  Generates Ash embedded resources and operation stubs from an OpenAPI 3.1 specification.
  First generates the schemas, then creates operation stubs that use those schemas.

  ## Example

  ```bash
  #{@example}
  ```

  ## Options

  * `--output-dir` or `-o` - Base directory for generated files
  * `--prefix` or `-p` - Module prefix for generated modules (defaults to app name)
  """

  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :ash_openapi,
      adds_deps: [
        {:jason, "~> 1.4"},
        {:yaml_elixir, "~> 2.9"},
        {:xml_builder, "~> 2.2"}
      ],
      example: @example,
      positional: [:openapi_file],
      schema: [
        output_dir: :string,
        prefix: :string
      ],
      defaults: [
        prefix: AshOpenapi.Spec.app_module_prefix()
      ],
      aliases: [
        o: :output_dir,
        p: :prefix
      ],
      required: [:output_dir]
    }
  end

  def igniter(igniter, argv) do
    {[openapi_file], argv} = positional_args!(argv)
    options = options!(argv)

    # Set up options for both tasks
    schema_options = Map.put(options, :output_dir, Path.join(options.output_dir, "schemas"))
    operation_options = Map.put(options, :output_dir, Path.join(options.output_dir, "operations"))

    # Create new argument lists for sub-tasks
    schema_args = [
      openapi_file,
      "--output-dir",
      schema_options.output_dir,
      "--prefix",
      options.prefix
    ]

    operation_args = [
      openapi_file,
      "--output-dir",
      operation_options.output_dir,
      "--prefix",
      options.prefix
    ]

    with {:ok, igniter} <- Mix.Tasks.AshOpenapi.GenerateSchemas.igniter(igniter, schema_args),
         {:ok, igniter} <- Mix.Tasks.AshOpenapi.GenerateStubs.igniter(igniter, operation_args) do
      {:ok, igniter}
    else
      error -> error
    end
  end
end

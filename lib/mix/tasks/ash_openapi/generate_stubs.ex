defmodule Mix.Tasks.AshOpenapi.GenerateStubs do
  use Igniter.Mix.Task

  @example "mix ash_openapi.generate_stubs path/to/openapi.yaml --output-dir lib/my_app/api"

  @shortdoc "Generate API operation stubs from OpenAPI spec"
  @moduledoc """
  #{@shortdoc}

  Generates behaviour modules for API operations defined in an OpenAPI 3.1 specification.
  Uses generated schemas from Mix.Tasks.AshOpenapi.GenerateSchemas.

  ## Example

  ```bash
  #{@example}
  ```

  ## Options

  * `--output-dir` or `-o` - Directory where generated stubs will be saved
  * `--prefix` or `-p` - Module prefix for generated stubs (defaults to app name)
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
        prefix: app_module_prefix()
      ],
      aliases: [
        o: :output_dir,
        p: :prefix
      ],
      required: [:output_dir]
    }
  end

  def igniter(igniter, argv) do
    # Parse arguments according to Igniter.Mix.Task documentation
    {arguments, argv} = positional_args!(argv)
    options = options!(argv)

    [openapi_file] = arguments

    case AshOpenapi.Spec.parse_spec_file(openapi_file) do
      {:ok, spec} ->
        case AshOpenapi.Spec.validate_openapi_version(spec) do
          :ok ->
            operations = extract_operations(spec)

            # Don't wrap the result in a tuple
            igniter
            |> configure_router(operations, options.prefix)
            |> configure_controllers(operations, options.prefix, spec)

          error ->
            error
        end

      error ->
        error
    end
  end

  @doc """
  Configures the router with routes from the OpenAPI spec.
  """
  def configure_router(igniter, operations, prefix) do
    routes = format_routes(operations)
    router_path = Path.join(["lib", "#{Macro.underscore(prefix)}_web", "router.ex"])
    router_module = Module.concat([:"#{prefix}Web", "Router"])

    content = Code.format_string!("""
    defmodule #{router_module} do
      use #{prefix}Web, :router

      pipeline :api do
        plug :accepts, ["json"]
      end

      scope "/api", #{prefix}Web do
        pipe_through :api

        #{routes}
      end
    end
    """)

    Igniter.Project.Module.find_and_update_or_create_module(
      igniter,
      router_module,
      content,
      fn zipper ->
        ast = Code.string_to_quoted!(content)
        {:ok, Sourceror.Zipper.replace(zipper, ast)}
      end,
      path: router_path
    )
  end

  def configure_controllers(igniter, operations, prefix, spec) do
    operations
    |> group_operations_by_controller()
    |> Enum.reduce(igniter, fn {controller_name, controller_operations}, acc ->
      create_or_update_controller(acc, controller_name, controller_operations, prefix, spec)
    end)
  end

  @doc """
  Groups operations by their controller name.
  """
  def group_operations_by_controller(operations) do
    Enum.group_by(operations, fn {_path, _method, operation} ->
      get_controller_name(operation)
    end)
  end

  @doc """
  Creates or updates a single controller module.
  """
  def create_or_update_controller(igniter, controller_name, operations, prefix, spec) do
    content = generate_controller_module(controller_name, operations, prefix, spec)
    formatted_content = IO.iodata_to_binary(Code.format_string!(content))
    file_path = controller_file_path(prefix, controller_name)
    module_name = controller_module_name(prefix, controller_name)

    IO.puts("Creating or updating controller module: #{module_name}")
    IO.puts("File path: #{file_path}")

    Igniter.Project.Module.find_and_update_or_create_module(
      igniter,
      module_name,
      formatted_content,
      fn zipper ->
        ast = Code.string_to_quoted!(formatted_content)
        {:ok, Sourceror.Zipper.replace(zipper, ast)}
      end,
      path: file_path
    )
  end

  @doc """
  Generates the file path for a controller.
  """
  def controller_file_path(prefix, controller_name) do
    Path.join([
      "lib",
      "#{Macro.underscore(prefix)}_web",
      "controllers",
      "#{Macro.underscore(controller_name)}.ex"
    ])
  end

  @doc """
  Generates the module name for a controller.
  """
  def controller_module_name(prefix, controller_name) do
    Module.concat([:"#{prefix}Web", "Controllers", controller_name])
  end

  def generate_controller_module(controller_name, operations, prefix, _spec) do
    actions =
      operations
      |> Enum.map(fn {path, method, operation} ->
        action_name = get_action_name(method, operation)
        tag = get_operation_tag(operation)

        operation_module =
          "#{prefix}.Operations.#{Macro.camelize(tag)}.#{operation_module_name(operation)}"

        responses = extract_responses(operation)
        content_types = extract_content_types(operation)

        """
        @doc \"\"\"
        #{operation["description"] || ""}

        Path: #{path}
        Method: #{String.upcase(method)}
        \"\"\"
        def #{action_name}(conn, params) do
          content_type = get_accepted_content_type(conn, #{inspect(content_types)})

          case #{operation_module}.call(params) do
            #{generate_response_matches(responses)}
          end
        end
        """
      end)
      |> Enum.join("\n\n")

    """
    defmodule #{prefix}Web.Controllers.#{controller_name} do
      use #{prefix}Web, :controller

      #{actions}

      defp get_accepted_content_type(conn, supported_types) do
        conn
        |> get_req_header("accept")
        |> List.first()
        |> case do
          nil -> hd(supported_types)
          accept ->
            Enum.find(supported_types, hd(supported_types), &String.contains?(accept, &1))
        end
      end

      #{generate_format_response_functions(extract_content_types_from_operations(operations))}
    end
    """
  end

  def configure_operations(igniter, operations, prefix, output_dir, spec) do
    # Group operations by their primary tag
    operations_by_tag =
      Enum.group_by(operations, fn {_path, _method, operation} ->
        get_operation_tag(operation)
      end)

    Enum.reduce(operations_by_tag, igniter, fn {tag, tag_operations}, acc ->
      # Create a subdirectory for each tag
      tag_dir = Path.join(output_dir, Macro.underscore(tag))

      # Process operations within this tag group
      Enum.reduce(tag_operations, acc, fn {path, method, operation}, tag_acc ->
        operation_path = Path.join(tag_dir, "#{operation_filename(operation)}.ex")

        module_name =
          String.to_atom(
            "#{prefix}.Operations.#{Macro.camelize(tag)}.#{operation_module_name(operation)}"
          )

        stub = generate_operation_stub(path, method, operation, prefix, spec)

        Igniter.Project.Module.find_and_update_or_create_module(
          # igniter as first argument
          tag_acc,
          # module name
          module_name,
          # initial content
          stub,
          # update function
          fn zipper ->
            IO.puts("Updating operation stub for #{operation_path}")

            {:ok,
             Sourceror.Zipper.update(zipper, fn _node ->
               Code.string_to_quoted!(stub)
             end)}
          end,
          # options as keyword list
          path: operation_path
        )
      end)
    end)
  end

  def generate_routes_from_spec(%{"paths" => paths}) do
    paths
    |> Enum.flat_map(fn {path, methods} ->
      methods
      |> Enum.map(fn {method, operation} ->
        {path, method, operation}
      end)
    end)
  end

  def format_routes(routes) do
    routes
    |> Enum.map(fn {path, method, operation} ->
      controller = get_controller_name(operation)
      action = get_action_name(method, operation)
      phoenix_path = openapi_path_to_phoenix(path)
      "#{method} \"#{phoenix_path}\", #{controller}, :#{action}"
    end)
    |> Enum.join("\n      ")
  end

  def get_controller_name(%{"tags" => [primary_tag | _]}) do
    "#{Macro.camelize(primary_tag)}Controller"
  end

  def get_controller_name(_operation), do: "DefaultController"

  def get_action_name(_method, %{"operationId" => operation_id}) do
    operation_id
    |> Macro.underscore()
  end

  def get_action_name(method, _) do
    case method do
      "get" -> "index"
      "post" -> "create"
      "put" -> "update"
      "patch" -> "update"
      "delete" -> "delete"
      _ -> "index"
    end
  end

  def openapi_path_to_phoenix(path) do
    path
    |> String.replace(~r/{([^}]+)}/, ":\\1")
    |> String.replace_prefix("/", "")
  end

  # New functions for operation extraction and stub generation
  def extract_operations(%{"paths" => paths}) do
    paths
    |> Enum.flat_map(fn {path, methods} ->
      methods
      |> Enum.map(fn {method, operation} ->
        {path, method, operation}
      end)
    end)
  end

  def generate_operation_stub(path, method, operation, prefix, spec) do
    module_name = operation_module_name(operation)
    request_schema = extract_request_schema(operation)
    response_schema = extract_response_schema(operation)

    """
    defmodule #{prefix}.Operations.#{module_name} do
      @moduledoc \"\"\"
      #{operation["description"] || "Operation #{module_name}"}
      \"\"\"

      @callback call(#{request_params(request_schema, spec)}) :: #{response_type(response_schema, spec)}

      def call(params) do
        # TODO: Implement operation logic
        {:ok, %{}}
      end

      def path, do: "#{path}"
      def method, do: "#{method}"
    end
    """
  end

  def operation_module_name(%{"operationId" => operation_id}) do
    operation_id
    |> Macro.camelize()
  end

  def operation_module_name(%{"summary" => summary}) when is_binary(summary) do
    summary
    |> String.replace(~r/[^a-zA-Z0-9]+/, "_")
    |> Macro.camelize()
  end

  def operation_module_name(_) do
    "Operation#{:erlang.unique_integer([:positive])}"
  end

  def operation_filename(operation) do
    operation
    |> operation_module_name()
    |> Macro.underscore()
  end

  def extract_request_schema(operation) do
    case operation do
      %{"requestBody" => %{"content" => %{"application/json" => %{"schema" => schema}}}} ->
        schema

      _ ->
        nil
    end
  end

  def extract_response_schema(schema)

  def extract_response_schema(%{"$ref" => ref}) do
    ref
    |> String.split("/")
    |> List.last()
  end

  def extract_response_schema(%{"type" => type, "items" => items}) when type == "array" do
    item_type = extract_response_schema(items)
    "[#{item_type}]"
  end

  def extract_response_schema(%{"type" => type}) do
    type
  end

  def extract_response_schema(_) do
    "any"
  end

  def request_params(nil), do: "any()"

  def request_params(schema, spec) do
    {type, constraints} = map_type(schema, spec, nil, nil)
    AshOpenapi.TypeSpec.schema_to_type_spec(type, constraints)
  end

  def response_type(nil), do: "any()"

  def response_type(schema, spec) do
    {type, constraints} = map_type(schema, spec, nil, nil)
    type_spec = AshOpenapi.TypeSpec.schema_to_type_spec(type, constraints)
    "{:ok, #{type_spec}} | {:error, term()}"
  end

  def app_module_prefix, do: AshOpenapi.Spec.app_module_prefix()

  # Add map_type from generate_schemas but modified for type specs
  def map_type(%{"oneOf" => schemas}, spec, parent_name, property_name) do
    types =
      schemas
      |> Enum.map(fn schema ->
        case schema do
          %{"$ref" => ref} ->
            ref
            |> AshOpenapi.Spec.resolve_ref(spec)
            |> map_type(spec, parent_name, property_name)
            |> elem(0)

          schema ->
            schema
            |> map_type(spec, parent_name, property_name)
            |> elem(0)
        end
      end)
      |> Enum.uniq()

    {{:union, types}, []}
  end

  def map_type(
        %{"type" => "object", "properties" => _} = schema,
        _spec,
        parent_name,
        property_name
      ) do
    module_name = derive_type_module(schema, parent_name, property_name)
    {:embedded, [type: module_name]}
  end

  def map_type(schema, spec, parent_name, property_name) do
    case schema do
      %{"type" => "string", "format" => "date-time"} ->
        {:utc_datetime, []}

      %{"type" => "string", "format" => "date"} ->
        {:date, []}

      %{"type" => "string", "enum" => values} ->
        {:atom, [constraints: [one_of: values]]}

      %{"type" => "string"} ->
        {:string, []}

      %{"type" => "integer"} ->
        {:integer, []}

      %{"type" => "number"} ->
        {:decimal, []}

      %{"type" => "boolean"} ->
        {:boolean, []}

      %{"type" => "array", "items" => items} ->
        {item_type, item_constraints} = map_type(items, spec, parent_name, property_name)
        {{:array, item_type}, item_constraints}

      _ ->
        {:string, []}
    end
  end

  # Helper to derive the module name for a type
  def derive_type_module(%{"$ref" => ref}, _parent_name, _property_name) do
    name =
      ref
      |> String.split("/")
      |> List.last()
      |> Macro.camelize()

    Module.concat(["#{app_module_prefix()}.Schemas", name])
  end

  def derive_type_module(schema, parent_name, nil),
    do: derive_type_module(schema, parent_name, "")

  def derive_type_module(_schema, parent_name, property_name)
      when is_binary(property_name) and byte_size(property_name) > 0 do
    name =
      if parent_name do
        "#{parent_name}#{Macro.camelize(property_name)}"
      else
        Macro.camelize(property_name)
      end

    Module.concat(["#{app_module_prefix()}.Schemas", name])
  end

  def derive_type_module(_schema, _parent_name, _property_name) do
    name = "UnknownType#{:erlang.unique_integer([:positive])}"
    Module.concat(["#{app_module_prefix()}.Schemas", name])
  end

  def extract_responses(operation) do
    operation
    |> Map.get("responses", %{})
    |> Enum.map(fn {status, response} ->
      {status, response["content"] || %{}, response["description"]}
    end)
  end

  def extract_content_types(operation) do
    operation
    |> Map.get("responses", %{})
    |> Enum.flat_map(fn {_, response} ->
      response
      |> Map.get("content", %{})
      |> Map.keys()
    end)
    |> Enum.uniq()
    |> case do
      [] -> ["application/json"]
      types -> types
    end
  end

  def generate_response_matches(responses) do
    error_responses =
      Enum.filter(responses, fn {status, _, _} ->
        String.first(status) in ["4", "5"]
      end)

    success_responses =
      Enum.filter(responses, fn {status, _, _} ->
        String.first(status) in ["2", "3"]
      end)

    [
      # Success responses
      success_responses
      |> Enum.map(fn {status, content, description} ->
        """
              {:ok, response} ->
                # #{description}
                case content_type do
                  #{generate_content_type_matches(content, status)}
                end
        """
      end),

      # Error responses with defined schemas
      error_responses
      |> Enum.map(fn {status, content, description} ->
        """
              {:error, error} when response_status == #{status} ->
                # #{description}
                case content_type do
                  #{generate_content_type_matches(content, status)}
                end
        """
      end),

      # Content type negotiation failure (no schema defined)
      """
            {:error, :unsupported_content_type} ->
              problem = %{
                type: #{inspect(url_helpers())}.error_url(conn, :not_acceptable),
                title: gettext("not_acceptable"),
                status: 406,
                detail: gettext("requested_content_type_not_available")
              }

              case get_accepted_content_type(conn, ["application/problem+json", "application/problem+xml"]) do
                "application/problem+xml" ->
                  conn
                  |> put_status(406)
                  |> put_resp_content_type("application/problem+xml")
                  |> send_resp(406, XmlBuilder.generate(problem))
                _ ->
                  conn
                  |> put_status(406)
                  |> put_resp_content_type("application/problem+json")
                  |> json(problem)
              end
      """,

      # Fallback error handler (no schema defined)
      """
            {:error, error} ->
              problem = %{
                type: #{inspect(url_helpers())}.error_url(conn, :internal_server_error),
                status: 500,
                title: gettext("internal_server_error"),
                detail: error
              }

              case get_accepted_content_type(conn, ["application/problem+json", "application/problem+xml"]) do
                "application/problem+xml" ->
                  conn
                  |> put_status(500)
                  |> put_resp_content_type("application/problem+xml")
                  |> send_resp(500, XmlBuilder.generate(problem))
                _ ->
                  conn
                  |> put_status(500)
                  |> put_resp_content_type("application/problem+json")
                  |> json(problem)
              end
      """
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  def generate_content_type_matches(content, status) do
    content
    |> Enum.map(fn {content_type, %{"schema" => schema}} ->
      response_type = extract_response_schema(schema)

      """
                "#{content_type}" ->
                  # Expected response type: #{response_type}
                  conn
                  |> put_status(#{status})
                  |> format_response(response, "#{content_type}")
      """
    end)
    |> Enum.join("\n")
  end

  def generate_format_response_functions(content_types) do
    content_types
    |> Enum.map(fn content_type ->
      case content_type do
        "application/json" ->
          """
          defp format_response(conn, response, "application/json") do
            json(conn, response)
          end
          """

        "application/xml" ->
          """
          defp format_response(conn, response, "application/xml") do
            conn
            |> put_resp_content_type("application/xml")
            |> send_resp(conn.status, XmlBuilder.generate(response))
          end
          """

        _ ->
          """
          defp format_response(conn, response, "#{content_type}") do
            conn
            |> put_resp_content_type("#{content_type}")
            |> send_resp(conn.status, to_string(response))
          end
          """
      end
    end)
    |> Enum.join("\n\n")
  end

  def url_helpers do
    app_name = Mix.Project.config()[:app]
    Module.concat(["#{app_name}_web", "Router", "Helpers"])
  end

  def get_operation_tag(%{"tags" => [primary_tag | _]}), do: primary_tag
  def get_operation_tag(_), do: "default"

  def extract_content_types_from_operations(operations) do
    operations
    |> Enum.flat_map(fn {_, _, operation} -> extract_content_types(operation) end)
    |> Enum.uniq()
  end
end

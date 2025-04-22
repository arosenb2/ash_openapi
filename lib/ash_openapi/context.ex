defmodule AshOpenApi.Context do
  @moduledoc """
  Stores OpenApiSpex.Schema structs and configuration for schema conversion.
  Uses an Agent to maintain state across the application.
  """

  use Agent

  @type t :: %{
          schemas: %{String.t() => OpenApiSpex.Schema.t()},
          namespace: String.t()
        }

  @doc """
  Starts the context agent.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    # Stop any existing process with this name
    if Process.whereis(name), do: Process.exit(Process.whereis(name), :normal)

    Agent.start_link(
      fn -> %{schemas: %{}, namespace: nil} end,
      name: name
    )
  end

  @doc """
  Resets the context to its initial state.
  """
  def reset do
    case Process.whereis(__MODULE__) do
      nil -> start_link()
      _ -> Agent.update(__MODULE__, fn _ -> %{schemas: %{}, namespace: nil} end)
    end
  end

  @doc """
  Stops the context agent.
  """
  def stop do
    case Process.whereis(__MODULE__) do
      nil ->
        :ok

      pid ->
        ref = Process.monitor(pid)
        Process.exit(pid, :normal)

        receive do
          {:DOWN, ^ref, :process, ^pid, _} -> :ok
        after
          1000 -> :ok
        end
    end
  end

  @doc """
  Sets up the context with schemas and namespace.
  """
  def setup(schemas, namespace) do
    case Process.whereis(__MODULE__) do
      nil ->
        {:ok, _} = start_link()

        Agent.update(__MODULE__, fn _ ->
          %{schemas: schemas, namespace: namespace}
        end)

      _ ->
        Agent.update(__MODULE__, fn _ ->
          %{schemas: schemas, namespace: namespace}
        end)
    end
  end

  @doc """
  Gets the current namespace.
  """
  def namespace do
    Agent.get(__MODULE__, & &1.namespace)
  end

  @doc """
  Gets all schemas.
  """
  def get_all_schemas do
    Agent.get(__MODULE__, & &1.schemas)
  end

  @doc """
  Gets a specific schema by name.
  """
  def get_schema(name) do
    Agent.get(__MODULE__, &get_in(&1, [:schemas, name]))
  end

  @doc """
  Puts a schema into the context.
  """
  def put_schema(name, schema) do
    Agent.update(__MODULE__, fn %{schemas: schemas} = state ->
      %{schemas: Map.put(schemas, name, schema), namespace: state.namespace}
    end)
  end

  @doc """
  Gets the application name in module format (e.g., "my_app" -> "MyApp").
  """
  def app_name do
    Mix.Project.config()[:app]
    |> to_string()
    |> Macro.camelize()
  end
end

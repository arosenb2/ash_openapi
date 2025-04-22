defmodule AshOpenApi do
  @moduledoc """
  Documentation for `AshOpenApi`.
  """

  @doc """
  Parse an OpenAPI document and store its schemas in the Context.
  The document can be provided as:
  - A JSON string
  - A YAML string
  - A decoded map/struct

  ## Examples

      iex> json = File.read!("openapi.json")
      iex> AshOpenApi.parse_document(json)
      {:ok, %OpenApiSpex.OpenApi{...}}

      iex> yaml = File.read!("openapi.yaml")
      iex> AshOpenApi.parse_document(yaml)
      {:ok, %OpenApiSpex.OpenApi{...}}

  """
  defdelegate parse_document(openapi_doc), to: AshOpenApi.SchemaParser, as: :parse_and_store

  @doc """
  Get a schema by name from the Context.
  Returns nil if schema not found.

  ## Examples

      iex> AshOpenApi.get_schema("Pet")
      %OpenApiSpex.Schema{...}

  """
  defdelegate get_schema(name), to: AshOpenApi.Context

  @doc """
  Get all stored schemas from the Context.

  ## Examples

      iex> AshOpenApi.get_all_schemas()
      %{"Pet" => %OpenApiSpex.Schema{...}, "User" => %OpenApiSpex.Schema{...}}

  """
  defdelegate get_all_schemas(), to: AshOpenApi.Context

  @doc """
  Initializes the AshOpenApi context and converts an OpenAPI document's schemas.

  ## Examples

      iex> openapi_doc = %{components: %{schemas: %{...}}}
      iex> AshOpenApi.init(openapi_doc)
      :ok

  """
  def init(openapi_doc) do
    # Ensure the context is started
    case AshOpenApi.Context.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Convert and store schemas
    AshOpenApi.SchemaConverter.convert_and_store_schemas(openapi_doc)
  end
end

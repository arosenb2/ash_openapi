defmodule AshOpenApi.SchemaParserTest do
  use ExUnit.Case, async: false

  alias AshOpenApi.{SchemaParser, Context}

  setup do
    # Stop any existing context
    Context.stop()
    # Start a fresh context
    {:ok, _} = Context.start_link()
    on_exit(fn -> Context.stop() end)
    :ok
  end

  describe "parse_and_store/1" do
    test "successfully parses and stores schemas from YAML" do
      yaml = File.read!("test/fixtures/openapi.yaml")
      assert {:ok, spec} = SchemaParser.parse_and_store(yaml)

      # Verify it's a valid OpenApiSpex struct
      assert %OpenApiSpex.OpenApi{} = spec
      assert spec.info.title == "Train Travel API"
      assert spec.info.version == "1.2.1"

      # Check that schemas were stored in the Context
      all_schemas = Context.get_all_schemas()
      refute Enum.empty?(all_schemas)

      # Verify some expected schemas exist and are valid OpenApiSpex.Schema structs
      station_schema = Context.get_schema("Station")
      assert %OpenApiSpex.Schema{} = station_schema
      assert station_schema.type == :object
      assert Map.has_key?(station_schema.properties, :name)
      assert Map.has_key?(station_schema.properties, :country_code)
    end

    test "successfully parses and stores schemas from JSON" do
      # First convert our YAML to JSON for testing
      yaml = File.read!("test/fixtures/openapi.yaml")

      {:ok, json} =
        yaml
        |> YamlElixir.read_from_string!()
        |> Jason.encode()

      assert {:ok, spec} = SchemaParser.parse_and_store(json)
      assert %OpenApiSpex.OpenApi{} = spec

      # Verify schemas were stored
      all_schemas = Context.get_all_schemas()
      refute Enum.empty?(all_schemas)

      assert Enum.count(all_schemas) == 11
    end

    test "successfully parses and stores schemas from decoded map" do
      yaml = File.read!("test/fixtures/openapi.yaml")
      decoded = YamlElixir.read_from_string!(yaml)

      assert {:ok, spec} = SchemaParser.parse_and_store(decoded)
      assert %OpenApiSpex.OpenApi{} = spec

      # Verify schemas were stored
      all_schemas = Context.get_all_schemas()
      refute Enum.empty?(all_schemas)
    end

    test "handles missing components/schemas gracefully" do
      minimal_spec = %{
        "openapi" => "3.0.0",
        "info" => %{
          "title" => "Minimal API",
          "version" => "1.0.0"
        },
        "paths" => %{}
      }

      assert {:ok, spec} = SchemaParser.parse_and_store(minimal_spec)
      assert %OpenApiSpex.OpenApi{} = spec

      # Should have no schemas stored
      assert Context.get_all_schemas() == %{}
    end
  end

  describe "integration with AshOpenApi module" do
    test "parse_document/1 delegates to SchemaParser.parse_and_store/1" do
      yaml = File.read!("test/fixtures/openapi.yaml")
      assert {:ok, spec} = AshOpenApi.parse_document(yaml)
      assert %OpenApiSpex.OpenApi{} = spec

      # Verify we can retrieve schemas through the main API
      assert %OpenApiSpex.Schema{} = AshOpenApi.get_schema("Station")
      refute Enum.empty?(AshOpenApi.get_all_schemas())
    end
  end
end

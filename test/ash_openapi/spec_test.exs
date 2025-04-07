defmodule AshOpenapi.SpecTest do
  use ExUnit.Case, async: true
  alias AshOpenapi.Spec

  @fixtures_path "test/fixtures"

  describe "parse_spec_file/1" do
    test "successfully parses YAML OpenAPI spec" do
      yaml_path = Path.join(@fixtures_path, "openapi.yaml")
      assert {:ok, spec} = Spec.parse_spec_file(yaml_path)
      assert spec["openapi"] == "3.0.0"
      assert spec["info"]["title"] == "Train Travel API"
    end

    test "successfully parses JSON OpenAPI spec" do
      json_path = Path.join(@fixtures_path, "openapi.json")
      File.write!(json_path, Jason.encode!(sample_json_spec()))

      assert {:ok, spec} = Spec.parse_spec_file(json_path)
      assert spec["openapi"] == "3.0.0"

      File.rm!(json_path)
    end

    test "returns error for unsupported file format" do
      assert {:error, message} = Spec.parse_spec_file("invalid.txt")
      assert message =~ "Unsupported file format"
    end

    test "returns error for non-existent file" do
      assert {:error, _} = Spec.parse_spec_file("nonexistent.yaml")
    end
  end

  describe "validate_openapi_version/1" do
    test "accepts valid 3.x.x versions" do
      assert :ok = Spec.validate_openapi_version(%{"openapi" => "3.0.0"})
      assert :ok = Spec.validate_openapi_version(%{"openapi" => "3.1.0"})
      assert :ok = Spec.validate_openapi_version(%{"openapi" => "3.2.1"})
    end

    test "rejects non-3.x versions" do
      assert {:error, message} = Spec.validate_openapi_version(%{"openapi" => "2.0.0"})
      assert message =~ "Only OpenAPI 3.0 and higher"
    end
  end

  describe "resolve_ref/2" do
    test "resolves simple references" do
      spec = %{
        "components" => %{
          "schemas" => %{
            "Station" => %{"type" => "object"}
          }
        }
      }

      result = Spec.resolve_ref(spec, "#/components/schemas/Station")
      assert result == %{"type" => "object"}
    end

    test "returns nil for non-existent references" do
      spec = %{"components" => %{"schemas" => %{}}}
      result = Spec.resolve_ref(spec, "#/components/schemas/NonExistent")
      assert is_nil(result)
    end
  end

  describe "resolve_refs_in_schema/2" do
    test "resolves direct references" do
      spec = %{
        "components" => %{
          "schemas" => %{
            "Location" => %{
              "type" => "object",
              "properties" => %{
                "latitude" => %{"type" => "number"},
                "longitude" => %{"type" => "number"}
              }
            }
          }
        }
      }

      schema = %{"$ref" => "#/components/schemas/Location"}
      resolved = Spec.resolve_refs_in_schema(schema, spec)

      assert resolved["type"] == "object"
      assert resolved["properties"]["latitude"]["type"] == "number"
    end

    test "resolves nested property references" do
      spec = %{
        "components" => %{
          "schemas" => %{
            "Location" => %{
              "type" => "object",
              "properties" => %{
                "latitude" => %{"type" => "number"}
              }
            }
          }
        }
      }

      schema = %{
        "type" => "object",
        "properties" => %{
          "location" => %{"$ref" => "#/components/schemas/Location"}
        }
      }

      resolved = Spec.resolve_refs_in_schema(schema, spec)

      assert get_in(resolved, ["properties", "location", "properties", "latitude", "type"]) ==
               "number"
    end

    test "resolves array item references" do
      spec = %{
        "components" => %{
          "schemas" => %{
            "Station" => %{
              "type" => "object",
              "properties" => %{
                "name" => %{"type" => "string"}
              }
            }
          }
        }
      }

      schema = %{
        "type" => "array",
        "items" => %{"$ref" => "#/components/schemas/Station"}
      }

      resolved = Spec.resolve_refs_in_schema(schema, spec)
      assert get_in(resolved, ["items", "properties", "name", "type"]) == "string"
    end
  end

  describe "maybe_merge_all_of/2" do
    test "merges allOf schemas" do
      spec = %{
        "components" => %{
          "schemas" => %{
            "BaseStation" => %{
              "type" => "object",
              "properties" => %{
                "id" => %{"type" => "string"}
              }
            },
            "StationExtension" => %{
              "type" => "object",
              "properties" => %{
                "name" => %{"type" => "string"}
              }
            }
          }
        }
      }

      schema = %{
        "type" => "object",
        "allOf" => [
          %{"$ref" => "#/components/schemas/BaseStation"},
          %{"$ref" => "#/components/schemas/StationExtension"}
        ]
      }

      merged = Spec.maybe_merge_all_of(schema, spec)

      assert merged["type"] == "object"
      assert get_in(merged, ["properties", "id", "type"]) == "string"
      assert get_in(merged, ["properties", "name", "type"]) == "string"
    end

    test "handles nested allOf references" do
      spec = %{
        "components" => %{
          "schemas" => %{
            "Base" => %{
              "type" => "object",
              "properties" => %{
                "id" => %{"type" => "string"}
              }
            },
            "Extension1" => %{
              "type" => "object",
              "allOf" => [
                %{"$ref" => "#/components/schemas/Base"},
                %{"properties" => %{"ext1" => %{"type" => "string"}}}
              ]
            }
          }
        }
      }

      schema = %{
        "allOf" => [
          %{"$ref" => "#/components/schemas/Extension1"},
          %{"properties" => %{"ext2" => %{"type" => "string"}}}
        ]
      }

      merged = Spec.maybe_merge_all_of(schema, spec)

      assert merged["properties"]["id"]["type"] == "string"
      assert merged["properties"]["ext1"]["type"] == "string"
      assert merged["properties"]["ext2"]["type"] == "string"
    end
  end

  defp sample_json_spec do
    %{
      "openapi" => "3.0.0",
      "info" => %{
        "title" => "Sample API",
        "version" => "1.0.0"
      },
      "paths" => %{}
    }
  end
end

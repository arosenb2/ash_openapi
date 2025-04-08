defmodule Mix.Tasks.AshOpenapi.GenerateSchemasTest do
  use ExUnit.Case, async: true
  alias Mix.Tasks.AshOpenapi.GenerateSchemas

  describe "extract_schemas/1" do
    test "extracts basic schemas" do
      spec = %{
        "components" => %{
          "schemas" => %{
            "Station" => %{
              "type" => "object",
              "properties" => %{
                "name" => %{"type" => "string"},
                "code" => %{"type" => "string"}
              }
            }
          }
        }
      }

      assert %{"Station" => %{"type" => "object"}} = GenerateSchemas.extract_schemas(spec)
    end

    test "extracts nested schemas" do
      spec = %{
        "components" => %{
          "schemas" => %{
            "Station" => %{
              "type" => "object",
              "properties" => %{
                "location" => %{
                  "type" => "object",
                  "properties" => %{
                    "latitude" => %{"type" => "number"},
                    "longitude" => %{"type" => "number"}
                  }
                }
              }
            }
          }
        }
      }

      schemas = GenerateSchemas.extract_schemas(spec)

      # Verify we have both the main schema and the nested schema
      assert Map.has_key?(schemas, "Station")
      assert Map.has_key?(schemas, "Location")

      # Verify the nested schema structure
      location_schema = schemas["Location"]
      assert location_schema["type"] == "object"
      assert Map.has_key?(location_schema["properties"], "latitude")
      assert Map.has_key?(location_schema["properties"], "longitude")

      # Verify the main schema still has the location reference
      station_schema = schemas["Station"]
      assert station_schema["type"] == "object"
      assert Map.has_key?(station_schema["properties"], "location")
    end

    test "extracts schemas with allOf" do
      spec = %{
        "components" => %{
          "schemas" => %{
            "Stop" => %{
              "type" => "object",
              "properties" => %{
                "name" => %{"type" => "string"}
              }
            },
            "Station" => %{
              "allOf" => [
                %{"$ref" => "#/components/schemas/Stop"},
                %{
                  "type" => "object",
                  "properties" => %{
                    "code" => %{"type" => "string"}
                  }
                }
              ]
            }
          }
        }
      }

      schemas = GenerateSchemas.extract_schemas(spec)
      assert Map.has_key?(schemas, "Station")
      station_schema = schemas["Station"]
      assert get_in(station_schema, ["properties", "name", "type"]) == "string"
      assert get_in(station_schema, ["properties", "code", "type"]) == "string"
    end
  end

  describe "map_type/3" do
    test "maps basic types" do
      assert {:string, []} = GenerateSchemas.map_type(%{"type" => "string"}, nil, nil)
      assert {:integer, []} = GenerateSchemas.map_type(%{"type" => "integer"}, nil, nil)
      assert {:float, []} = GenerateSchemas.map_type(%{"type" => "number"}, nil, nil)
      assert {:boolean, []} = GenerateSchemas.map_type(%{"type" => "boolean"}, nil, nil)
    end

    test "maps date and time formats" do
      assert {:utc_datetime, []} =
               GenerateSchemas.map_type(%{"type" => "string", "format" => "date-time"}, nil, nil)

      assert {:date, []} =
               GenerateSchemas.map_type(%{"type" => "string", "format" => "date"}, nil, nil)

      assert {:time, []} =
               GenerateSchemas.map_type(%{"type" => "string", "format" => "time"}, nil, nil)
    end

    test "maps references" do
      assert {"Location", []} =
               GenerateSchemas.map_type(%{"$ref" => "#/components/schemas/Location"}, nil, nil)
    end
  end

  describe "map_type/4" do
    test "maps array of basic types" do
      assert {{:array, :string}, []} =
               GenerateSchemas.map_type(
                 %{"type" => "array", "items" => %{"type" => "string"}},
                 nil,
                 "strings",
                 "TestApp"
               )

      assert {{:array, :integer}, []} =
               GenerateSchemas.map_type(
                 %{"type" => "array", "items" => %{"type" => "integer"}},
                 nil,
                 "numbers",
                 "TestApp"
               )

      assert {{:array, :float}, []} =
               GenerateSchemas.map_type(
                 %{"type" => "array", "items" => %{"type" => "number"}},
                 nil,
                 "floats",
                 "TestApp"
               )
    end

    test "maps array of objects" do
      schema = %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => "string"}
          }
        }
      }

      {type_name, [resource_def]} =
        GenerateSchemas.map_type(schema, "Station", "platforms", "TestApp")

      assert type_name == {:array, "TestApp.Resources.StationPlatform"}
      assert resource_def =~ ~r/defmodule TestApp.Resources.StationPlatform do/
      assert resource_def =~ ~r/attribute :name, :string/
    end

    test "maps enum type" do
      schema = %{
        "type" => "string",
        "enum" => ["scheduled", "delayed"],
        "description" => "Train status"
      }

      {type_name, [enum_def]} = GenerateSchemas.map_type(schema, "Station", "status", "TestApp")

      assert type_name == "TestApp.Enums.Station.Status"
      assert enum_def =~ ~r/defmodule TestApp.Enums.Station.Status do/
      assert enum_def =~ ~r/@moduledoc/
      assert enum_def =~ ~r/Train status/
      assert enum_def =~ ~r/use Ash.Type.Enum/
      assert enum_def =~ ~r/constraints: \[\s*values: \["scheduled", "delayed"\]\s*\]/
    end

    test "maps oneOf type" do
      schema = %{
        "oneOf" => [
          %{"type" => "string"},
          %{"type" => "integer"}
        ]
      }

      assert {{:union, [:string, :integer]}, []} =
               GenerateSchemas.map_type(schema, "Station", "value", "TestApp")
    end

    test "maps object type" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "latitude" => %{"type" => "number"},
          "longitude" => %{"type" => "number"},
          "name" => %{"type" => "string"}
        },
        "required" => ["latitude", "longitude"]
      }

      {type_name, [resource_def]} =
        GenerateSchemas.map_type(schema, "Station", "location", "TestApp")

      assert type_name == "TestApp.Resources.StationLocation"
      assert resource_def =~ ~r/defmodule TestApp.Resources.StationLocation do/
      assert resource_def =~ ~r/use Ash.Resource/
      assert resource_def =~ ~r/data_layer: :embedded/
      assert resource_def =~ ~r/attribute :latitude, :float, allow_nil\?: false, public\?: true/
      assert resource_def =~ ~r/attribute :longitude, :float, allow_nil\?: false, public\?: true/
      assert resource_def =~ ~r/attribute :name, :string, allow_nil\?: true, public\?: true/
    end
  end

  describe "generate_enum_type/3" do
    test "generates enum module definition" do
      schema = %{
        "type" => "string",
        "enum" => ["scheduled", "delayed"],
        "description" => "Train status"
      }

      expected = """
      defmodule StatusType do
        use Ash.Type.Enum,
          values: ["scheduled", "delayed"],
          description: "Train status"
      end
      """

      assert String.trim(GenerateSchemas.generate_enum_type("status", schema, "")) ==
               String.trim(expected)
    end
  end

  describe "generate_attribute/3" do
    test "generates basic attribute" do
      property = {"code", %{"type" => "string"}}
      {attr, types} = GenerateSchemas.generate_attribute(property, "Station", false)

      assert attr == "attribute :code, :string, allow_nil?: true, public?: true"
      assert types == []
    end

    test "generates array attribute" do
      property = {"platforms", %{"type" => "array", "items" => %{"type" => "string"}}}
      {attr, types} = GenerateSchemas.generate_attribute(property, "Station", false)

      assert attr == "attribute :platforms, {:array, :string}, allow_nil?: true, public?: true"
      assert types == []
    end

    test "generates required attribute" do
      property = {"name", %{"type" => "string"}}
      {attr, types} = GenerateSchemas.generate_attribute(property, "Station", true)

      assert attr == "attribute :name, :string, allow_nil?: false, public?: true"
      assert types == []
    end

    test "generates enum attribute" do
      property = {
        "status",
        %{
          "type" => "string",
          "enum" => ["active", "inactive"],
          "description" => "Station status"
        }
      }

      {attr, [enum_def]} =
        GenerateSchemas.generate_attribute(property, "Station", false, "TestApp")

      assert attr ==
               "attribute :status, TestApp.Enums.Station.Status, description: \"Station status\", allow_nil?: true, public?: true"

      assert enum_def =~ ~r/defmodule TestApp.Enums.Station.Status do/
      assert enum_def =~ ~r/use Ash.Type.Enum/
      assert enum_def =~ ~r/constraints: \[\s*values: \["active", "inactive"\]\s*\]/
    end

    test "generates attribute with description" do
      property =
        {"name",
         %{
           "type" => "string",
           "description" => "The station's display name"
         }}

      {attr, types} = GenerateSchemas.generate_attribute(property, "Station", false)

      assert attr ==
               "attribute :name, :string, description: \"The station's display name\", allow_nil?: true, public?: true"

      assert types == []
    end
  end

  describe "derive_embedded_name/2" do
    test "derives name from field name" do
      assert "Platform" = GenerateSchemas.derive_embedded_name(nil, "platforms")
      assert "Location" = GenerateSchemas.derive_embedded_name(nil, "location")
    end

    test "derives name with parent prefix" do
      assert "StationPlatform" = GenerateSchemas.derive_embedded_name("Station", "platforms")
      assert "StationLocation" = GenerateSchemas.derive_embedded_name("Station", "location")
    end
  end

  describe "derive_type_from_ref/1" do
    test "derives name from ref" do
      assert "Location" = GenerateSchemas.derive_type_from_ref("#/components/schemas/Location")

      assert "GpsLocation" =
               GenerateSchemas.derive_type_from_ref("#/components/schemas/GpsLocation")
    end
  end

  describe "generate_ash_resource/2" do
    test "generates a basic resource" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "code" => %{"type" => "string"}
        }
      }

      result = GenerateSchemas.generate_ash_resource("Station", schema, "MyApp")

      assert result =~ ~r/defmodule MyApp.Resources.Station do/
      assert result =~ ~r/use Ash.Resource/
      assert result =~ ~r/data_layer: :embedded/
      assert result =~ ~r/attribute :name, :string/
      assert result =~ ~r/attribute :code, :string/
    end

    test "handles nullable fields" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "nullable" => true}
        }
      }

      result = GenerateSchemas.generate_ash_resource("Station", schema, "MyApp")
      assert result =~ ~r/attribute :name, :string, allow_nil\?: true, public\?: true/
    end

    test "handles descriptions and examples" do
      schema = %{
        "type" => "object",
        "title" => "Station",
        "description" => "A train station in the network",
        "properties" => %{
          "name" => %{
            "type" => "string",
            "description" => "The station's display name"
          },
          "code" => %{
            "type" => "string",
            "description" => "The station's unique code"
          }
        }
      }

      result = GenerateSchemas.generate_ash_resource("Station", schema, "MyApp")

      # Verify moduledoc content
      assert result =~ ~r/@moduledoc """\n  Station\n\n  A train station in the network\n  """/

      # Extract attributes section
      attributes_section = Regex.run(~r/attributes do\n(.*?)\n  end/s, result)
      assert attributes_section, "Attributes section not found"
      [_, attributes_content] = attributes_section

      # Extract complete attribute definitions (handling multi-line attributes)
      attribute_defs =
        attributes_content
        |> String.split(~r/(?=attribute :)/)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      assert length(attribute_defs) == 2

      # Find each attribute definition
      name_attr = Enum.find(attribute_defs, &(&1 =~ ~r/^attribute :name,/))
      code_attr = Enum.find(attribute_defs, &(&1 =~ ~r/^attribute :code,/))

      assert name_attr =~ ~r/^attribute :name, :string/
      assert name_attr =~ ~r/description: "The station's display name"/
      assert name_attr =~ ~r/allow_nil\?: true/
      assert name_attr =~ ~r/public\?: true/

      assert code_attr =~ ~r/^attribute :code, :string/
      assert code_attr =~ ~r/description: "The station's unique code"/
      assert code_attr =~ ~r/allow_nil\?: true/
      assert code_attr =~ ~r/public\?: true/
    end

    test "handles descriptions without title" do
      schema = %{
        "type" => "object",
        "description" => "A train station in the network",
        "properties" => %{
          "name" => %{
            "type" => "string",
            "description" => "The station's display name"
          }
        }
      }

      result = GenerateSchemas.generate_ash_resource("Station", schema, "MyApp")

      # Verify moduledoc content is present
      assert result =~ ~r/@moduledoc/
      assert result =~ ~r/Station/
      assert result =~ ~r/A train station in the network/

      # Extract attributes section using regex
      attributes_section = Regex.run(~r/attributes do\n(.*?)\n  end/s, result)
      assert attributes_section, "Attributes section not found"
      [_, attributes_content] = attributes_section

      # Verify the attribute definition
      assert attributes_content =~ ~r/attribute :name, :string/
      assert attributes_content =~ ~r/description: "The station's display name"/
      assert attributes_content =~ ~r/allow_nil\?: true/
      assert attributes_content =~ ~r/public\?: true/
    end
  end

  describe "generate_ash_resource/3" do
    test "handles required properties" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "code" => %{"type" => "string"},
          "description" => %{"type" => "string"},
          "status" => %{
            "type" => "string",
            "enum" => ["active", "inactive"],
            "description" => "Station status"
          }
        },
        "required" => ["name", "code"]
      }

      result = GenerateSchemas.generate_ash_resource("Station", schema, "MyApp")

      # Extract attributes section
      attributes_section = Regex.run(~r/attributes do\n(.*?)\n  end/s, result)
      assert attributes_section, "Attributes section not found"
      [_, attributes_content] = attributes_section

      # Extract complete attribute definitions (handling multi-line attributes)
      attribute_defs =
        attributes_content
        |> String.split(~r/(?=attribute :)/)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      assert length(attribute_defs) == 4

      # Find each attribute definition
      name_attr = Enum.find(attribute_defs, &(&1 =~ ~r/^attribute :name,/))
      code_attr = Enum.find(attribute_defs, &(&1 =~ ~r/^attribute :code,/))
      description_attr = Enum.find(attribute_defs, &(&1 =~ ~r/^attribute :description,/))
      status_attr = Enum.find(attribute_defs, &(&1 =~ ~r/^attribute :status,/))

      # Required fields should have allow_nil?: false
      assert name_attr =~ ~r/^attribute :name, :string/
      assert name_attr =~ ~r/allow_nil\?: false/
      assert name_attr =~ ~r/public\?: true/

      assert code_attr =~ ~r/^attribute :code, :string/
      assert code_attr =~ ~r/allow_nil\?: false/
      assert code_attr =~ ~r/public\?: true/

      # Optional fields should have allow_nil?: true
      assert description_attr =~ ~r/^attribute :description, :string/
      assert description_attr =~ ~r/allow_nil\?: true/
      assert description_attr =~ ~r/public\?: true/

      assert status_attr =~ ~r/^attribute :status, MyApp.Enums.Station.Status/
      assert status_attr =~ ~r/description: "Station status"/
      assert status_attr =~ ~r/allow_nil\?: true/
      assert status_attr =~ ~r/public\?: true/

      # Verify enum type definition
      assert result =~ ~r/defmodule MyApp.Enums.Station.Status/
      assert result =~ ~r/@moduledoc/
      assert result =~ ~r/Station status/
      assert result =~ ~r/use Ash.Type.Enum/
      assert result =~ ~r/values: \["active", "inactive"\]/
    end

    test "handles nested required properties" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "location" => %{
            "type" => "object",
            "properties" => %{
              "latitude" => %{"type" => "number"},
              "longitude" => %{"type" => "number"},
              "name" => %{"type" => "string"}
            },
            "required" => ["latitude", "longitude"]
          }
        }
      }

      result = GenerateSchemas.generate_ash_resource("Station", schema, "TestApp")

      {:ok, ast} = Code.string_to_quoted(result)

      # Find the main module's attributes
      {_, main_attributes} =
        Macro.prewalk(ast, nil, fn
          {:defmodule, _,
           [{:__aliases__, _, [:TestApp, :Resources, :Station]}, [do: {:__block__, _, contents}]]} =
              node,
          _acc ->
            # Find the attributes block that's directly in the main module (not in nested modules)
            attributes =
              Enum.find(contents, fn
                {:attributes, _, [[do: {:attribute, _, _}]]} -> true
                _ -> false
              end)

            case attributes do
              {:attributes, _, [[do: attr]]} -> {node, attr}
              _ -> {node, nil}
            end

          node, acc ->
            {node, acc}
        end)

      assert {:attribute, _,
              [
                :location,
                {:__aliases__, _, [:TestApp, :Resources, :StationLocation]},
                [allow_nil?: true, public?: true]
              ]} = main_attributes

      # Also verify the nested resource is defined
      assert result =~ ~r/defmodule TestApp\.Resources\.StationLocation do/
      assert result =~ ~r/attribute :latitude, :float, allow_nil\?: false, public\?: true/
      assert result =~ ~r/attribute :longitude, :float, allow_nil\?: false, public\?: true/
      assert result =~ ~r/attribute :name, :string, allow_nil\?: true, public\?: true/
    end

    test "debug nested resource generation" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "location" => %{
            "type" => "object",
            "properties" => %{
              "latitude" => %{"type" => "number"},
              "longitude" => %{"type" => "number"},
              "name" => %{"type" => "string"}
            },
            "required" => ["latitude", "longitude"]
          }
        }
      }

      {attr_def, resource_defs} =
        GenerateSchemas.generate_attribute(
          {"location", schema["properties"]["location"]},
          "Station",
          false,
          "TestApp"
        )

      assert attr_def =~ ~r/^attribute :location/
      assert length(resource_defs) == 1
    end
  end

  describe "nested object handling" do
    setup do
      nested_schema = %{
        "type" => "object",
        "properties" => %{
          "location" => %{
            "type" => "object",
            "properties" => %{
              "latitude" => %{"type" => "number"},
              "longitude" => %{"type" => "number"},
              "name" => %{"type" => "string"}
            },
            "required" => ["latitude", "longitude"]
          }
        }
      }

      {:ok, schema: nested_schema}
    end

    test "map_type/4 correctly handles nested object", %{schema: schema} do
      location_schema = get_in(schema, ["properties", "location"])

      {type_name, [resource_def]} =
        GenerateSchemas.map_type(location_schema, "Station", "location", "TestApp")

      assert type_name == "TestApp.Resources.StationLocation"
      assert resource_def =~ ~r/defmodule TestApp.Resources.StationLocation do/
    end

    test "generate_attribute/4 creates single attribute for nested object", %{schema: schema} do
      location_property = {"location", get_in(schema, ["properties", "location"])}

      {attr_def, resource_defs} =
        GenerateSchemas.generate_attribute(location_property, "Station", false, "TestApp")

      assert length(resource_defs) == 1
      assert attr_def =~ ~r/^attribute :location, TestApp.Resources.StationLocation/
    end

    test "extract_nested_schemas handles nested objects", %{schema: schema} do
      nested_schemas = GenerateSchemas.extract_nested_schemas(schema, %{})

      assert map_size(nested_schemas) == 1

      assert Map.has_key?(nested_schemas, "StationLocation") ||
               Enum.any?(Map.keys(nested_schemas), &String.ends_with?(&1, "Location"))
    end
  end

  describe "extract_nested_schemas/2" do
    test "extracts nested schemas from array items" do
      spec = %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => "string"},
            "code" => %{"type" => "string"}
          }
        }
      }

      nested_schemas = GenerateSchemas.extract_nested_schemas(spec, %{})
      assert map_size(nested_schemas) == 1
      assert Map.has_key?(nested_schemas, "Item") || Map.has_key?(nested_schemas, "ArrayItem")
    end

    test "extracts nested schemas from allOf" do
      spec = %{
        "allOf" => [
          %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string"}
            }
          },
          %{
            "type" => "object",
            "properties" => %{
              "location" => %{
                "type" => "object",
                "properties" => %{
                  "latitude" => %{"type" => "number"},
                  "longitude" => %{"type" => "number"}
                }
              }
            }
          }
        ]
      }

      nested_schemas = GenerateSchemas.extract_nested_schemas(spec, %{})
      assert map_size(nested_schemas) == 1
      assert Map.has_key?(nested_schemas, "Location")
    end

    test "extracts nested schemas from oneOf" do
      spec = %{
        "oneOf" => [
          %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string"}
            }
          },
          %{
            "type" => "object",
            "properties" => %{
              "address" => %{
                "type" => "object",
                "properties" => %{
                  "street" => %{"type" => "string"},
                  "city" => %{"type" => "string"}
                }
              }
            }
          }
        ]
      }

      nested_schemas = GenerateSchemas.extract_nested_schemas(spec, %{})
      assert map_size(nested_schemas) == 1
      assert Map.has_key?(nested_schemas, "Address")
    end

    test "extracts nested schemas from complex combinations" do
      spec = %{
        "type" => "object",
        "properties" => %{
          "mainLocation" => %{
            "type" => "object",
            "properties" => %{
              "coordinates" => %{
                "type" => "object",
                "properties" => %{
                  "latitude" => %{"type" => "number"},
                  "longitude" => %{"type" => "number"}
                }
              }
            }
          },
          "alternateLocations" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "name" => %{"type" => "string"},
                "coordinates" => %{
                  "type" => "object",
                  "properties" => %{
                    "latitude" => %{"type" => "number"},
                    "longitude" => %{"type" => "number"}
                  }
                }
              }
            }
          },
          "status" => %{
            "oneOf" => [
              %{
                "type" => "object",
                "properties" => %{
                  "details" => %{
                    "type" => "object",
                    "properties" => %{
                      "code" => %{"type" => "string"},
                      "message" => %{"type" => "string"}
                    }
                  }
                }
              }
            ]
          }
        }
      }

      nested_schemas = GenerateSchemas.extract_nested_schemas(spec, %{})
      assert map_size(nested_schemas) == 5
      assert Map.has_key?(nested_schemas, "MainLocation")
      assert Map.has_key?(nested_schemas, "Coordinates")
      assert Map.has_key?(nested_schemas, "AlternateLocation")
      assert Map.has_key?(nested_schemas, "Details")
    end
  end
end

defmodule AshOpenApi.SchemaExtractorTest do
  use ExUnit.Case, async: true
  alias AshOpenApi.SchemaExtractor

  alias OpenApiSpex.{
    OpenApi,
    Operation,
    PathItem,
    RequestBody,
    Response,
    Schema,
    Reference,
    Components,
    MediaType,
    Parameter,
    Info
  }

  describe "extract_all_schemas/1" do
    test "extracts component schemas" do
      spec = %OpenApi{
        info: %Info{
          title: "Test API",
          version: "1.0.0"
        },
        paths: %{},
        components: %Components{
          schemas: %{
            "User" => %Schema{
              type: :object,
              properties: %{
                name: %Schema{type: :string}
              }
            }
          },
          responses: %{
            "Error" => %Response{
              description: "Error response",
              content: %{
                "application/json" => %MediaType{
                  schema: %Schema{
                    type: :object,
                    properties: %{
                      code: %Schema{type: :integer}
                    }
                  }
                }
              }
            }
          }
        }
      }

      schemas = SchemaExtractor.extract_all_schemas(spec)
      assert %Schema{} = schemas["schemas/User"]
      assert schemas["schemas/User"].properties.name.type == :string
    end

    test "extracts inline operation schemas" do
      spec = %OpenApi{
        info: %Info{
          title: "Test API",
          version: "1.0.0"
        },
        paths: %{
          "/users" => %PathItem{
            post: %Operation{
              requestBody: %RequestBody{
                content: %{
                  "application/json" => %MediaType{
                    schema: %Schema{
                      type: :object,
                      properties: %{
                        name: %Schema{type: :string}
                      }
                    }
                  }
                }
              },
              responses: %{
                "200" => %Response{
                  description: "Successful response",
                  content: %{
                    "application/json" => %MediaType{
                      schema: %Schema{
                        type: :object,
                        properties: %{
                          id: %Schema{type: :string}
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      schemas = SchemaExtractor.extract_all_schemas(spec)
      assert schemas["requestBodies//users_application/json"].type == :object
      assert schemas["responses//users_200_application/json"].type == :object
    end

    test "extracts parameter schemas" do
      spec = %OpenApi{
        info: %Info{
          title: "Test API",
          version: "1.0.0"
        },
        paths: %{
          "/users/{id}" => %PathItem{
            get: %Operation{
              operationId: "getUserById",
              parameters: [
                %Parameter{
                  name: "id",
                  in: :path,
                  schema: %Schema{type: :string, format: :uuid}
                }
              ],
              responses: %{
                "200" => %Response{
                  description: "Successful response"
                }
              }
            }
          }
        }
      }

      schemas = SchemaExtractor.extract_all_schemas(spec)
      assert schemas["parameters/getUserById.Parameters.id"].type == :string
      assert schemas["parameters/getUserById.Parameters.id"].format == :uuid
    end

    test "handles references in schemas" do
      spec = %OpenApi{
        info: %Info{
          title: "Test API",
          version: "1.0.0"
        },
        paths: %{
          "/users" => %PathItem{
            post: %Operation{
              requestBody: %RequestBody{
                content: %{
                  "application/json" => %MediaType{
                    schema: %Reference{"$ref": "#/components/schemas/User"}
                  }
                }
              },
              responses: %{
                "200" => %Response{
                  description: "Successful response"
                }
              }
            }
          }
        },
        components: %Components{
          schemas: %{
            "User" => %Schema{
              type: :object,
              properties: %{
                name: %Schema{type: :string}
              }
            }
          }
        }
      }

      schemas = SchemaExtractor.extract_all_schemas(spec)
      assert %Reference{} = schemas["requestBodies//users_application/json"]
      assert schemas["schemas/User"].type == :object
    end

    test "handles missing components" do
      spec = %OpenApi{
        info: %Info{
          title: "Test API",
          version: "1.0.0"
        },
        paths: %{},
        components: %Components{}
      }

      schemas = SchemaExtractor.extract_all_schemas(spec)
      assert schemas == %{}
    end
  end
end

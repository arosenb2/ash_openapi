defmodule AshOpenApi.ResourceConverterTest do
  use ExUnit.Case, async: false
  alias OpenApiSpex.{Reference, Schema}
  alias AshOpenApi.{ResourceConverter, Context}

  setup do
    # Stop any existing context
    Context.stop()
    # Start a fresh context
    {:ok, _} = Context.start_link()
    on_exit(fn -> Context.stop() end)
    :ok
  end

  describe "to_ash_resources/3" do
    test "converts basic schema with attributes" do
      schemas = %{
        "User" => %Schema{
          type: :object,
          properties: %{
            id: %Schema{type: :string, format: :uuid},
            name: %Schema{type: :string},
            email: %Schema{type: :string, format: :email},
            age: %Schema{type: :integer},
            is_active: %Schema{type: :boolean, default: true},
            created_at: %Schema{type: :string, format: :"date-time"}
          },
          required: ["name", "email"]
        }
      }

      result = ResourceConverter.to_ash_resources(schemas, "Api", "schemas")
      assert map_size(result) == 1
      assert Map.has_key?(result, "AshOpenapi.Api.Schemas.User")

      user_module = result["AshOpenapi.Api.Schemas.User"]
      assert user_module =~ "use Ash.Resource"
      assert user_module =~ "data_layer: :embedded"
      assert user_module =~ "attribute :name, :string, allow_nil?: false, public?: true"
    end

    test "converts headers" do
      schemas = %{
        "StandardHeaders" => %Schema{
          type: :object,
          properties: %{
            "X-Request-ID": %Schema{type: :string, format: :uuid}
          },
          required: ["X-Request-ID"]
        }
      }

      result = ResourceConverter.to_ash_resources(schemas, "Api", "headers")
      header_module = result["AshOpenapi.Api.Headers.StandardHeaders"]

      assert header_module =~ "use Ash.Resource"
      assert header_module =~ "data_layer: :embedded"

      assert header_module =~
               ~s(attribute :"X-Request-ID", :uuid, allow_nil?: false, public?: true)
    end

    test "converts responses" do
      schemas = %{
        "Error" => %Schema{
          type: :object,
          properties: %{
            code: %Schema{type: :integer},
            message: %Schema{type: :string}
          },
          required: ["code", "message"]
        }
      }

      result = ResourceConverter.to_ash_resources(schemas, "Api", "responses")
      response_module = result["AshOpenapi.Api.Responses.Error"]

      assert response_module =~ "use Ash.Resource"
      assert response_module =~ "data_layer: :embedded"
      assert response_module =~ "attribute :code, :integer, allow_nil?: false, public?: true"
    end

    test "handles references with correct namespace" do
      schemas = %{
        "Post" => %Schema{
          type: :object,
          properties: %{
            author: %Reference{"$ref": "#/components/schemas/User"},
            category: %Reference{"$ref": "#/components/requestBodies/Category"}
          },
          required: ["author"]
        }
      }

      result = ResourceConverter.to_ash_resources(schemas, "V1", "schemas")
      post_module = result["AshOpenapi.V1.Schemas.Post"]

      assert post_module =~
               "attribute :author, AshOpenapi.V1.Schemas.User, public?: true, allow_nil?: false"

      assert post_module =~
               "attribute :category, AshOpenapi.V1.RequestBodies.Category, public?: true"
    end

    test "handles nullable fields" do
      schemas = %{
        "Profile" => %Schema{
          type: :object,
          properties: %{
            bio: %Schema{type: :string, nullable: true},
            website: %Schema{type: :string, format: :uri, nullable: true}
          }
        }
      }

      result = ResourceConverter.to_ash_resources(schemas, "Api", "schemas")
      profile_module = result["AshOpenapi.Api.Schemas.Profile"]

      assert profile_module =~ "attribute :bio, :string, allow_nil?: true, public?: true"
      assert profile_module =~ "attribute :website, :string, allow_nil?: true, public?: true"
    end

    test "handles required fields" do
      schemas = %{
        "Comment" => %Schema{
          type: :object,
          properties: %{
            id: %Schema{type: :string, format: :uuid},
            content: %Schema{type: :string},
            author: %Schema{type: :string}
          },
          required: ["content", "author"]
        }
      }

      result = ResourceConverter.to_ash_resources(schemas, "Api", "schemas")
      comment_module = result["AshOpenapi.Api.Schemas.Comment"]

      assert comment_module =~ "attribute :content, :string, allow_nil?: false, public?: true"
      assert comment_module =~ "attribute :author, :string, allow_nil?: false, public?: true"
      assert comment_module =~ "attribute :id, :uuid, public?: true"
    end

    test "includes all constraints" do
      schemas = %{
        "Product" => %Schema{
          type: :object,
          properties: %{
            name: %Schema{
              type: :string,
              minLength: 3,
              maxLength: 50,
              pattern: "^[A-Za-z]"
            },
            price: %Schema{
              type: :number,
              minimum: 0,
              exclusiveMinimum: true,
              maximum: 1000,
              multipleOf: 0.01
            },
            status: %Schema{
              type: :string,
              enum: ["draft", "published", "archived"]
            }
          }
        }
      }

      result = ResourceConverter.to_ash_resources(schemas, "Api", "schemas")
      product_module = result["AshOpenapi.Api.Schemas.Product"]

      assert product_module =~ "min_length: 3"
      assert product_module =~ "max_length: 50"
      assert product_module =~ ~s|match: Regex.compile!("^[A-Za-z]")|
      assert product_module =~ "min: 0"
      assert product_module =~ "exclusive_min?: true"
      assert product_module =~ "max: 1000"
      assert product_module =~ "multiple_of: 0.01"
      assert product_module =~ ~s(one_of: ["draft", "published", "archived"])
    end

    test "handles required references" do
      schemas = %{
        "Post" => %Schema{
          type: :object,
          properties: %{
            author: %Reference{"$ref": "#/components/schemas/User"},
            category: %Reference{"$ref": "#/components/schemas/Category"}
          },
          required: ["author"]
        }
      }

      result = ResourceConverter.to_ash_resources(schemas, "Api", "schemas")
      post_module = result["AshOpenapi.Api.Schemas.Post"]

      assert post_module =~
               "attribute :author, AshOpenapi.Api.Schemas.User, public?: true, allow_nil?: false"

      assert post_module =~ "attribute :category, AshOpenapi.Api.Schemas.Category, public?: true"
    end

    test "handles array properties with references" do
      schemas = %{
        "BlogPost" => %Schema{
          type: :object,
          properties: %{
            title: %Schema{type: :string},
            tags: %Schema{
              type: :array,
              items: %Reference{"$ref": "#/components/schemas/Tag"}
            },
            comments: %Schema{
              type: :array,
              items: %Reference{"$ref": "#/components/responses/Comment"}
            }
          },
          required: ["title"]
        }
      }

      result = ResourceConverter.to_ash_resources(schemas, "Api", "schemas")
      blog_post_module = result["AshOpenapi.Api.Schemas.BlogPost"]

      assert blog_post_module =~ "attribute :title, :string, allow_nil?: false, public?: true"

      assert blog_post_module =~
               "attribute :tags, {:array, AshOpenapi.Api.Schemas.Tag}, public?: true"

      assert blog_post_module =~
               "attribute :comments, {:array, AshOpenapi.Api.Responses.Comment}, public?: true"
    end

    test "converts string enum to Ash.Type.Enum" do
      schemas = %{
        "Status" => %Schema{
          type: :string,
          enum: ["pending", "active", "completed"],
          description: "The status of the item"
        }
      }

      result = ResourceConverter.to_ash_resources(schemas, "Api", "schemas")
      assert map_size(result) == 1

      status_module = result["AshOpenapi.Api.Schemas.Status"]

      assert status_module =~
               "use Ash.Type.Enum, values: [:pending, :active, :completed]"

      assert status_module =~ "@moduledoc"
      assert status_module =~ "The status of the item"
    end

    test "ignores unsupported component types" do
      schemas = %{
        "x-apiture-errors" => nil,
        "some-extension" => %Schema{
          type: :object,
          properties: %{
            code: %Schema{type: :string}
          }
        }
      }

      # Simply verify that unsupported types return empty maps
      result = ResourceConverter.to_ash_resources(schemas, "Api", "extensions")
      assert result == %{}
    end

    test "handles nil schemas in supported component types" do
      schemas = %{
        "ValidSchema" => %Schema{
          type: :object,
          properties: %{
            name: %Schema{type: :string}
          }
        },
        "NilSchema" => nil
      }

      result = ResourceConverter.to_ash_resources(schemas, "Api", "schemas")

      # Should only contain the valid schema
      assert map_size(result) == 1
      assert Map.has_key?(result, "AshOpenapi.Api.Schemas.ValidSchema")
    end

    test "processes only supported component types" do
      supported_types = ~w(schemas responses headers parameters)
      unsupported_types = ~w(extensions securitySchemes)

      schema = %Schema{
        type: :object,
        properties: %{
          name: %Schema{type: :string}
        }
      }

      # Test supported types
      for type <- supported_types do
        result = ResourceConverter.to_ash_resources(%{"Test" => schema}, "Api", type)

        assert map_size(result) == 1,
               "Expected #{type} to be processed"

        module_name = "AshOpenapi.Api.#{Macro.camelize(type)}.Test"

        assert Map.has_key?(result, module_name),
               "Expected #{type} to generate module #{module_name}"
      end

      # Test unsupported types
      for type <- unsupported_types do
        result = ResourceConverter.to_ash_resources(%{"Test" => schema}, "Api", type)

        assert result == %{},
               "Expected #{type} to be ignored"
      end
    end

    test "handles mixed valid and nil schemas" do
      schemas = %{
        "ValidEnum" => %Schema{
          type: :string,
          enum: ["one", "two"],
          description: "A valid enum"
        },
        "NilSchema" => nil,
        "ValidObject" => %Schema{
          type: :object,
          properties: %{
            field: %Schema{type: :string}
          }
        }
      }

      result = ResourceConverter.to_ash_resources(schemas, "Api", "schemas")

      assert map_size(result) == 2
      assert Map.has_key?(result, "AshOpenapi.Api.Schemas.ValidEnum")
      assert Map.has_key?(result, "AshOpenapi.Api.Schemas.ValidObject")

      # Verify enum was generated correctly
      assert result["AshOpenapi.Api.Schemas.ValidEnum"] =~
               "use Ash.Type.Enum, values: [:one, :two]"
    end

    test "handles raw map schemas" do
      schemas = %{
        "Address" => %{
          "type" => "object",
          "properties" => %{
            "address1" => %{
              "type" => "string",
              "format" => "text",
              "maxLength" => 35,
              "description" => "The first line of the postal address",
              "example" => "1600 Pennsylvania Ave NW"
            },
            "zipCode" => %{
              "type" => "string",
              "pattern" => "^\\d{5}(-\\d{4})?$",
              "description" => "ZIP code"
            }
          },
          "required" => ["address1"]
        }
      }

      result = ResourceConverter.to_ash_resources(schemas, "Api", "schemas")

      assert map_size(result) == 1
      module_content = result["AshOpenapi.Api.Schemas.Address"]

      # Verify the content includes the converted attributes
      assert module_content =~ "attribute :address1, :string"
      assert module_content =~ "description: \"The first line of the postal address\""
      assert module_content =~ "max_length: 35"
      assert module_content =~ "allow_nil?: false"

      assert module_content =~ "attribute :zipCode, :string"
      assert module_content =~ ~s|match: Regex.compile!("^\\\\d{5}(-\\\\d{4})?$")|
      assert module_content =~ "description: \"ZIP code\""
    end
  end
end

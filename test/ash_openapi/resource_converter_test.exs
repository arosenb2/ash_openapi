defmodule AshOpenApi.ResourceConverterTest do
  use ExUnit.Case, async: true
  alias OpenApiSpex.{Reference, Schema}
  alias AshOpenApi.{ResourceConverter, Context}

  setup do
    start_supervised!({Context, []}, restart: :temporary)
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

      assert user_module =~ "defmodule AshOpenapi.Api.Schemas.User do"
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

      assert header_module =~ "defmodule AshOpenapi.Api.Headers.StandardHeaders do"

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

      assert response_module =~ "defmodule AshOpenapi.Api.Responses.Error do"
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
      assert product_module =~ ~s(match: ~r/^[A-Za-z]/)
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
               "use Ash.Type.Enum, values: [\"pending\", \"active\", \"completed\"]"

      assert status_module =~ "@moduledoc"
      assert status_module =~ "The status of the item"
    end
  end
end

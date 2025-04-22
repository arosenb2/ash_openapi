defmodule AshOpenApi.TypeConverterTest do
  use ExUnit.Case, async: true
  alias OpenApiSpex.Schema
  alias AshOpenApi.TypeConverter

  describe "to_ash_type/1" do
    test "converts basic types" do
      assert :string == TypeConverter.to_ash_type(%Schema{type: :string})
      assert :integer == TypeConverter.to_ash_type(%Schema{type: :integer})
      assert :decimal == TypeConverter.to_ash_type(%Schema{type: :number})
      assert :boolean == TypeConverter.to_ash_type(%Schema{type: :boolean})
      assert :map == TypeConverter.to_ash_type(%Schema{type: :object})
    end

    test "converts string formats" do
      assert :utc_datetime ==
               TypeConverter.to_ash_type(%Schema{type: :string, format: :"date-time"})

      assert :date == TypeConverter.to_ash_type(%Schema{type: :string, format: :date})
      assert :time == TypeConverter.to_ash_type(%Schema{type: :string, format: :time})
      assert :ci_string == TypeConverter.to_ash_type(%Schema{type: :string, format: :email})
      assert :uuid == TypeConverter.to_ash_type(%Schema{type: :string, format: :uuid})
      assert :string == TypeConverter.to_ash_type(%Schema{type: :string, format: :uri})
      assert :binary == TypeConverter.to_ash_type(%Schema{type: :string, format: :binary})
    end

    test "converts array types" do
      assert {:array, :string} ==
               TypeConverter.to_ash_type(%Schema{
                 type: :array,
                 items: %Schema{type: :string}
               })

      assert {:array, :integer} ==
               TypeConverter.to_ash_type(%Schema{
                 type: :array,
                 items: %Schema{type: :integer}
               })

      assert {:array, :decimal} ==
               TypeConverter.to_ash_type(%Schema{
                 type: :array,
                 items: %Schema{type: :number}
               })
    end

    test "converts nested array types" do
      assert {:array, {:array, :string}} ==
               TypeConverter.to_ash_type(%Schema{
                 type: :array,
                 items: %Schema{
                   type: :array,
                   items: %Schema{type: :string}
                 }
               })
    end

    test "converts enums to atoms" do
      schema = %Schema{
        type: :string,
        enum: ["pending", "active", "completed"]
      }

      assert :atom == TypeConverter.to_ash_type(schema)
    end

    test "enum conversion takes precedence over format" do
      schema = %Schema{
        type: :string,
        format: :email,
        enum: ["personal", "work"]
      }

      assert :atom == TypeConverter.to_ash_type(schema)
    end

    test "handles missing type" do
      assert :string == TypeConverter.to_ash_type(%Schema{})
    end

    test "handles unknown formats" do
      assert :string == TypeConverter.to_ash_type(%Schema{type: :string, format: :unknown})
    end

    test "handles unknown types" do
      assert :string == TypeConverter.to_ash_type(%Schema{type: :unknown})
    end
  end

  describe "real world examples from OpenAPI spec" do
    test "converts station schema fields" do
      station_schema = %Schema{
        type: :object,
        properties: %{
          id: %Schema{type: :string, format: :uuid},
          name: %Schema{type: :string},
          country_code: %Schema{type: :string, format: :text},
          timezone: %Schema{type: :string}
        }
      }

      assert :uuid == TypeConverter.to_ash_type(station_schema.properties.id)
      assert :string == TypeConverter.to_ash_type(station_schema.properties.name)
      assert :string == TypeConverter.to_ash_type(station_schema.properties.country_code)
      assert :string == TypeConverter.to_ash_type(station_schema.properties.timezone)
    end

    test "converts payment status enum" do
      status_schema = %Schema{
        type: :string,
        enum: ["pending", "succeeded", "failed"],
        description: "The status of the payment"
      }

      assert :atom == TypeConverter.to_ash_type(status_schema)
    end

    test "converts date-time fields" do
      datetime_schema = %Schema{
        type: :string,
        format: :"date-time",
        description: "The date and time when the trip departs"
      }

      assert :utc_datetime == TypeConverter.to_ash_type(datetime_schema)
    end
  end
end

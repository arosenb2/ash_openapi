defmodule AshOpenapi.TypeSpecTest do
  use ExUnit.Case, async: true

  alias AshOpenapi.TypeSpec

  describe "to_type_spec/1" do
    test "converts basic types" do
      assert TypeSpec.to_type_spec(:string) == "String.t()"
      assert TypeSpec.to_type_spec(:integer) == "integer()"
      assert TypeSpec.to_type_spec(:decimal) == "Decimal.t()"
      assert TypeSpec.to_type_spec(:boolean) == "boolean()"
      assert TypeSpec.to_type_spec(:date) == "Date.t()"
      assert TypeSpec.to_type_spec(:utc_datetime) == "DateTime.t()"
      assert TypeSpec.to_type_spec(:atom) == "atom()"
    end

    test "converts array types" do
      assert TypeSpec.to_type_spec({:array, :string}) == "[String.t()]"
      assert TypeSpec.to_type_spec({:array, :integer}) == "[integer()]"
      assert TypeSpec.to_type_spec({:array, {:array, :string}}) == "[[String.t()]]"
    end

    test "converts union types" do
      assert TypeSpec.to_type_spec({:union, [:string, :integer]}) == "(String.t() | integer())"
      assert TypeSpec.to_type_spec({:union, [:boolean, nil]}) == "(boolean() | nil)"
    end

    test "converts embedded types" do
      assert TypeSpec.to_type_spec({:embedded, [type: MyApp.Schemas.Address]}) ==
               "MyApp.Schemas.Address.t()"
    end

    test "handles unknown types by inspecting them" do
      assert TypeSpec.to_type_spec(:unknown_type) == ":unknown_type"
      assert TypeSpec.to_type_spec({:custom, "type"}) == "{:custom, \"type\"}"
    end
  end

  describe "schema_to_type_spec/2" do
    test "returns base type when no constraints" do
      assert TypeSpec.schema_to_type_spec(:string) == "String.t()"
      assert TypeSpec.schema_to_type_spec(:integer, []) == "integer()"
    end

    test "handles one_of constraints" do
      constraints = [constraints: [one_of: ["pending", "active", "completed"]]]

      assert TypeSpec.schema_to_type_spec(:string, constraints) ==
               "(\"pending\" | \"active\" | \"completed\")"
    end

    test "handles one_of constraints with atoms" do
      constraints = [constraints: [one_of: [:pending, :active, :completed]]]

      assert TypeSpec.schema_to_type_spec(:atom, constraints) ==
               "(:pending | :active | :completed)"
    end

    test "ignores other constraints" do
      constraints = [constraints: [min: 0, max: 100]]
      assert TypeSpec.schema_to_type_spec(:integer, constraints) == "integer()"
    end

    test "handles complex types with constraints" do
      type = {:array, {:union, [:string, :integer]}}
      assert TypeSpec.schema_to_type_spec(type) == "[(String.t() | integer())]"
    end
  end
end

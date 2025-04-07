defmodule Mix.Tasks.AshOpenapi.GenerateStubsTest do
  use ExUnit.Case
  require Igniter.Test
  alias Mix.Tasks.AshOpenapi.GenerateStubs

  @fixtures_path "test/fixtures"
  @test_prefix "MyApp"

  setup [:setup_igniter, :setup_openapi_spec]

  setup_all do
    [
      area: nil
    ]
  end

  describe "route_generation:generate_routes_from_spec/1" do
    setup do
      [area: :route_generation]
    end

    test "generates routes from OpenAPI paths", %{spec: spec} do
      routes = GenerateStubs.generate_routes_from_spec(spec)
      assert length(routes) > 0

      # Test specific routes
      assert Enum.any?(routes, fn {path, method, _operation} ->
               path == "/stations" && method == "get"
             end)

      assert Enum.any?(routes, fn {path, method, _operation} ->
               path == "/stations/{station_id}/departures" && method == "get"
             end)
    end
  end

  describe "route_generation:format_routes/1" do
    test "formats routes into Phoenix route declarations" do
      routes = [
        {"/stations", "get",
         %{
           "operationId" => "list_stations",
           "tags" => ["Stations"]
         }},
        {"/stations/{station_id}/departures", "get",
         %{
           "operationId" => "list_departures",
           "tags" => ["Departures"]
         }}
      ]

      formatted = GenerateStubs.format_routes(routes)
      assert is_binary(formatted)
      assert String.contains?(formatted, "get \"stations\", StationsController, :list_stations")

      assert String.contains?(
               formatted,
               "get \"stations/:station_id/departures\", DeparturesController, :list_departures"
             )
    end
  end

  describe "route generation" do
    test "handles path parameters correctly", %{spec: _spec} do
      path = "/stations/{station_id}/departures/{departure_id}"

      assert GenerateStubs.openapi_path_to_phoenix(path) ==
               "stations/:station_id/departures/:departure_id"
    end
  end

  describe "controller generation" do
    test "groups operations by tag", %{spec: spec} do
      operations = GenerateStubs.extract_operations(spec)
      controller_name = GenerateStubs.get_controller_name(%{"tags" => ["stations"]})

      assert controller_name == "StationsController"
      assert length(operations) == 2
    end

    test "generates action names from operationId", %{spec: _spec} do
      action = GenerateStubs.get_action_name("get", %{"operationId" => "list_stations"})
      assert action == "list_stations"
    end

    test "generates fallback action names when operationId is missing", %{spec: _spec} do
      action = GenerateStubs.get_action_name("get", %{})
      assert action == "index"

      action = GenerateStubs.get_action_name("post", %{})
      assert action == "create"
    end

    test "generates controller module with wrapped response data", %{spec: spec} do
      operations = [
        {"/stations", "get", spec["paths"]["/stations"]["get"]}
      ]

      content =
        GenerateStubs.generate_controller_module(
          "StationsController",
          operations,
          @test_prefix,
          spec
        )

      content_type =
        GenerateStubs.extract_content_types(spec["paths"]["/stations"]["get"])
        |> List.first()

      assert content =~ "defmodule #{@test_prefix}Web.Controllers.StationsController"
      assert content =~ "def list_stations(conn, params)"
      assert content =~ ~s|format_response(response, "#{content_type}")|
    end
  end

  describe "content type handling" do
    test "extracts content types from operation", %{spec: spec} do
      operation = spec["paths"]["/stations"]["get"]
      content_types = GenerateStubs.extract_content_types(operation)

      assert content_types == ["application/json"]
    end
  end

  describe "operation stub generation" do
    test "generates operation stub with correct module name and description", %{spec: spec} do
      {path, method, operation} =
        {"/stations", "get", spec["paths"]["/stations"]["get"]}

      stub =
        GenerateStubs.generate_operation_stub(
          path,
          method,
          operation,
          @test_prefix,
          spec
        )

      assert stub =~ "defmodule #{@test_prefix}.Operations.ListStations"
      assert stub =~ "def call(params)"
      # From operation description in OpenAPI spec
      assert stub =~ "List all stations"
    end
  end

  describe "controllers:configure_controllers/4" do
    setup do
      [area: :controllers]
    end

    test "creates new controllers", %{igniter: igniter, spec: spec} do
      operations = [
        {"/stations", "get",
         %{
           "operationId" => "list_stations",
           "description" => "List all stations",
           "tags" => ["Stations"]
         }}
      ]

      result = GenerateStubs.configure_controllers(igniter, operations, @test_prefix, spec)

      assert {:ok, _igniter, _meta} = Igniter.Test.apply_igniter(result)

      assert_patch_contains(
        result,
        "lib/my_app_web/controllers/stations_controller.ex",
        "def list_stations(conn, params)"
      )
    end

    test "updates existing controllers", %{igniter: igniter, spec: spec} do
      initial_operations = [
        {"/stations", "get",
         %{
           "operationId" => "list_stations",
           "description" => "List stations",
           "tags" => ["Stations"]
         }}
      ]

      igniter =
        GenerateStubs.configure_controllers(igniter, initial_operations, @test_prefix, spec)

      updated_operations = [
        {"/stations", "get",
         %{
           "operationId" => "list_stations",
           "description" => "List all stations",
           "tags" => ["Stations"]
         }},
        {"/stations/{id}", "get",
         %{
           "operationId" => "get_station",
           "description" => "Get a station",
           "tags" => ["Stations"]
         }}
      ]

      result =
        GenerateStubs.configure_controllers(igniter, updated_operations, @test_prefix, spec)

      assert {:ok, _igniter, _meta} = Igniter.Test.apply_igniter(result)

      assert_patch_contains(
        result,
        "lib/my_app_web/controllers/stations_controller.ex",
        "def get_station(conn, params)"
      )
    end
  end

  describe "controllers:create_or_update_controller/5" do
    setup do
      [area: :controllers]
    end

    test "creates a new controller", %{igniter: igniter, spec: spec} do
      operations = [
        {"/stations", "get",
         %{
           "operationId" => "list_stations",
           "description" => "List all stations",
           "tags" => ["Stations"]
         }}
      ]

      result =
        GenerateStubs.create_or_update_controller(
          igniter,
          "StationsController",
          operations,
          @test_prefix,
          spec
        )

      assert {:ok, _igniter, _meta} = Igniter.Test.apply_igniter(result)

      assert_patch_contains(
        result,
        "lib/my_app_web/controllers/stations_controller.ex",
        "def list_stations(conn, params)"
      )
    end
  end

  describe "routers:configure_router/3" do
    setup do
      [area: :routers]
    end

    test "configures router with new routes", %{igniter: igniter} do
      operations = [
        {"/stations", "get",
         %{
           "operationId" => "list_stations",
           "tags" => ["Stations"]
         }},
        {"/stations/{id}", "get",
         %{
           "operationId" => "get_station",
           "tags" => ["Stations"]
         }}
      ]

      result = GenerateStubs.configure_router(igniter, operations, @test_prefix)

      assert {:ok, _igniter, _meta} = Igniter.Test.apply_igniter(result)

      assert_patch_contains(
        result,
        "lib/my_app_web/router.ex",
        "get(\"stations\", StationsController, :list_stations)"
      )
    end
  end

  describe "group_operations_by_controller/1" do
    test "groups operations by controller name" do
      operations = [
        {"/stations", "get", %{"tags" => ["Stations"]}},
        {"/stations/{id}", "get", %{"tags" => ["Stations"]}},
        {"/stations/{station_id}/departures", "get", %{"tags" => ["Departures"]}}
      ]

      grouped = GenerateStubs.group_operations_by_controller(operations)
      assert map_size(grouped) == 2
      assert "StationsController" in Map.keys(grouped)
      assert "DeparturesController" in Map.keys(grouped)
      assert length(grouped["StationsController"]) == 2
      assert length(grouped["DeparturesController"]) == 1
    end
  end

  describe "controller_file_path/2" do
    test "generates correct file path" do
      path = GenerateStubs.controller_file_path(@test_prefix, "StationsController")
      assert path == "lib/my_app_web/controllers/stations_controller.ex"
    end
  end

  describe "controller_module_name/2" do
    test "generates correct module name" do
      module_name = GenerateStubs.controller_module_name(@test_prefix, "StationsController")
      module = Module.split(module_name) |> Enum.join(".")
      assert module == "MyAppWeb.Controllers.StationsController"
    end
  end

  defp setup_igniter(_context) do
    [igniter: Igniter.Test.test_project(app_name: :my_app)]
  end

  defp setup_openapi_spec(_context) do
    yaml_path = Path.join(@fixtures_path, "openapi.yaml")
    {:ok, spec} = AshOpenapi.Spec.parse_spec_file(yaml_path)
    [spec: spec]
  end

  defp assert_patch_contains(igniter, file_path, line) do
    diff = Igniter.Test.diff(igniter, only: file_path)

    assert diff, "No diff found for #{file_path}"

    assert String.contains?(diff, line),
           "Expected diff to contain '#{line}' but it did not.\nActual diff:\n#{diff}"
  end
end

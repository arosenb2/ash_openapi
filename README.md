# AshOpenAPI

AshOpenAPI is an Elixir library that provides OpenAPI integration for the Ash Framework. It allows you to parse, manipulate, and work with OpenAPI specifications in your Ash-powered applications.

## Features

- Parse OpenAPI 3.x.x documents from JSON or YAML formats
- Store and manage OpenAPI schemas in a Context
- Convert OpenAPI schemas for use with Ash resources
- Seamless integration with the Ash Framework ecosystem

## Installation

Add `ash_openapi` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_openapi, "~> 0.1.0"}
  ]
end
```

## Design Decisions

### What Isn't Included

- Router configuration
- Controller stubs
- Behaviours for operation responses
- Automatic request/response validation

### Type Mapping

Consistent mapping of OpenAPI types to Ash attribute types:

| OpenAPI Type       | Ash Attribute Type     |
| ------------------ | ---------------------- |
| string             | :string                |
| integer            | :integer               |
| number             | :decimal               |
| boolean            | :boolean               |
| string (date-time) | :utc_datetime          |
| string (date)      | :date                  |
| string (enum)      | :atom or Ash.Type.Enum |
| string (email)     | :ci_string             |
| object             | Embedded Resource      |
| array              | {:array, type}         |
| oneOf              | {:union, types}        |

## Usage

### Parsing OpenAPI Documents

You can parse OpenAPI documents from various formats:

```elixir
# From JSON
json = File.read!("openapi.json")
{:ok, openapi_document} = AshOpenApi.parse_document(json)

# From YAML
yaml = File.read!("openapi.yaml")
{:ok, openapi_document} = AshOpenApi.parse_document(yaml)
```

### Working with Schemas

Initialize the context and work with schemas:

```elixir
# Initialize with an OpenAPI document
openapi_doc = %{components: %{schemas: %{...}}}
AshOpenApi.init(openapi_doc)

# Get a specific schema
schema = AshOpenApi.get_schema("Station")

# Get all schemas
schemas = AshOpenApi.get_all_schemas()
```

### Using as an Igniter Task

AshOpenAPI can be used as an Igniter task to generate Ash resources from your OpenAPI specification. This is particularly useful when embedding the functionality in your project's build process.

To use the generator task:

```bash
mix ash_openapi.generate --definition path/to/openapi.yaml --namespace Api
```

Options:

- `--definition`: Path to your OpenAPI definition file (supports both JSON and YAML formats)
- `--namespace`: The namespace under which to generate the resources (e.g., if namespace is "Api", resources will be generated under `YourApp.Api.Schemas`, `YourApp.Api.Responses`, etc.)

The generator will:

1. Parse your OpenAPI definition
2. Extract all component schemas and inline schemas from operations
3. Generate corresponding Ash resources
4. Create or update the resource modules in your project

Generated resources will include:

- Proper type conversions from OpenAPI to Ash types
- Attribute constraints (min/max length, patterns, enums, etc.)
- Required field validations
- Proper handling of references and relationships
- Support for array types and nested structures

## License

This project is licensed under the MIT License.

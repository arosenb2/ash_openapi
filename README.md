# AshOpenapi

AshOpenapi is an [Igniter](https://hexdocs.pm/igniter) tool for automatically generating [Ash Framework](https://ash-hq.org) resources and operations from OpenAPI 3.1 documents. It streamlines the process of building Phoenix APIs by automating the creation of resources, operations, and validations based on your OpenAPI documentation.

## Features

### Schema Generation

- **Rich Type Support**:
  - All common data types (string, integer, number, boolean)
  - Date/time formats (date, time, date-time)
  - Complex types (arrays, objects, unions via oneOf)
  - Enums with proper Ash.Type.Enum generation
  - Decimal type for precise number handling
  - Proper handling of nullable fields
- **Relationship Support**:
  - Nested object embedding
  - Array relationships
  - Reference handling
- **Metadata Preservation**:
  - Descriptions and documentation
  - Validation constraints
  - Required field handling

### Operation Generation

- **API Implementation**:
  - Operation behaviour modules for business logic
  - Request/response schema validation
  - Content type negotiation (JSON/XML)
  - Problem+JSON/XML error responses
- **Phoenix Integration**:
  - Router configuration
  - Operation implementations
  - Proper error handling

## Installation

Add `ash_openapi` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_openapi, "~> 0.1.0"}
  ]
end
```

## Usage

AshOpenapi provides several Mix tasks to help you generate code from your OpenAPI specification:

### Generate Everything

```bash
mix ash_openapi.generate path/to/openapi.yaml --output-dir lib/my_app
```

This task:

- Generates Ash resources from all schemas
- Creates operation behaviour modules
- Sets up proper request/response handling

Options:

- `--output-dir` or `-o`: Base directory for generated files
- `--prefix` or `-p`: Module prefix for generated modules (defaults to app name)

### Generate Schemas Only

```bash
mix ash_openapi.generate_schemas path/to/openapi.yaml --output-dir lib/my_app/schemas
```

This task generates only the Ash resources from your OpenAPI schemas, including:

- Embedded resources for object types
- Enum types
- Proper type mappings and constraints

Options:

- `--output-dir` or `-o`: Directory where generated resources will be saved
- `--prefix` or `-p`: Module prefix for generated resources (defaults to app name)

### Generate Operations

```bash
mix ash_openapi.generate_stubs path/to/openapi.yaml --output-dir lib/my_app/operations
```

This task generates operation implementations including:

- Operation behaviour modules
- Request/response validation
- Content type negotiation
- Error handling

Options:

- `--output-dir` or `-o`: Directory where generated operations will be saved
- `--prefix` or `-p`: Module prefix for generated operations (defaults to app name)

## Generated Code Structure

The generator creates the following structure:

```
lib/my_app/
├── schemas/ # Generated Ash resources
│ ├── enums/ # Generated enum types
│ └── resources/ # Generated Ash resources
└── operations/ # Operation implementations
└── ... # Organized by OpenAPI tags
```

## Design Decisions

AshOpenapi makes several opinionated choices to provide a consistent and robust API experience:

### Module Organization

- **Resources**: Generated under `YourApp.Resources.*`

  - Basic resources are named after their schema (e.g., `YourApp.Resources.User`)
  - Nested objects use parent name as prefix (e.g., `YourApp.Resources.UserAddress`)
  - Pluralized names are automatically singularized (e.g., "addresses" becomes `Address`)

- **Enums**: Generated under `YourApp.Enums.*`

  - Nested enums include parent context (e.g., `YourApp.Enums.User.Status`)
  - Each enum is a proper `Ash.Type.Enum` with documentation

- **Operations**: Generated under `YourApp.Operations.*`
  - Organized by OpenAPI tags (e.g., `YourApp.Operations.Users.CreateUser`)
  - Uses `operationId` or sanitized summary for naming
  - Includes behaviour specifications for type safety

### Error Handling

The generator implements RFC 7807 Problem Details for HTTP APIs:

- **Content Negotiation**:

  - Supports both `application/problem+json` and `application/problem+xml`
  - Automatically negotiates based on Accept header
  - Falls back to JSON when no preference specified

- **Error Structure**:

```json
{
  "type": "https://your-api.com/errors/not_acceptable",
  "title": "Not Acceptable",
  "status": 406,
  "detail": "The requested content type is not available"
}
```

### Response Handling

- **Content Type Support**:

  - JSON responses by default
  - XML support when specified in OpenAPI document
  - Content negotiation based on Accept headers
  - Proper content-type headers in responses

- **Status Codes**:
  - Maps OpenAPI response codes to HTTP status codes
  - Preserves response schemas for validation
  - Handles both success and error responses

### Type Mapping

Consistent mapping of OpenAPI types to Elixir/Ash types:

| OpenAPI Type       | Ash/Elixir Type   |
| ------------------ | ----------------- |
| string             | :string           |
| integer            | :integer          |
| number             | :decimal          |
| boolean            | :boolean          |
| string (date-time) | :utc_datetime     |
| string (date)      | :date             |
| string (enum)      | Ash.Type.Enum     |
| object             | Embedded Resource |
| array              | {:array, type}    |
| oneOf              | {:union, types}   |

### Naming Conventions

- **Controllers**: Named after OpenAPI tags with `Controller` suffix
- **Actions**: Derived from `operationId` or HTTP method
- **Routes**: Converted from OpenAPI paths to Phoenix route format
  - Parameters converted from `{param}` to `:param`
  - Nested resources preserved in URL structure

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## License

This project is licensed under the MIT License.

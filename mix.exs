defmodule AshOpenapi.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_openapi,
      version: "0.1.0",
      elixir: "~> 1.14",
      description: "Generate Ash resources and operations from OpenAPI specs",
      package: package(),
      source_url: "https://github.com/arosenb2/ash_openapi",
      docs: docs(),
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :dev,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:ash, ">= 3.0.0 and < 4.0.0"},
      {:igniter, ">= 0.4.8 and < 1.0.0-0", override: true},
      {:rewrite, ">= 1.1.1 and < 2.0.0-0", override: true},
      {:splode, ">= 0.2.6 and < 1.0.0-0", override: true},
      {:reactor, "~> 0.11", override: true},
      {:jason, ">= 1.2.0 and < 3.0.0"},
      {:yaml_elixir, ">= 2.9.0 and < 4.0.0"},
      {:open_api_spex, ">= 3.18.0 and < 4.0.0"},
      {:xml_builder, ">= 2.2.0 and < 4.0.0", optional: true},
      {:ex_doc, ">= 0.29.0 and < 2.0.0", only: :dev, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get"],
      test: ["test"]
    ]
  end

  defp package do
    [
      maintainers: ["Aaron Rosenbaum"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/arosenb2/ash_openapi"},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_url: "https://github.com/arosenb2/ash_openapi"
    ]
  end
end

defmodule AshOpenApi.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_openapi,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:igniter, "~> 0.5"},
      {:open_api_spex, "~> 3.21"},
      {:yaml_elixir, "~> 2.11"},
      {:jason, "~> 1.4"}
    ]
  end
end

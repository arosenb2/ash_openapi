defmodule AshOpenApi.Debug do
  @moduledoc false

  def log(msg, opts) when is_binary(msg) do
    if Keyword.get(opts, :verbose) do
      Mix.shell().info([:yellow, "* [DEBUG] ", :reset, msg])
    end
  end

  def log(msg, opts) do
    if Keyword.get(opts, :verbose) do
      Mix.shell().info([:yellow, "* [DEBUG] ", :reset, inspect(msg)])
    end
  end
end

defmodule Plastic.Parser do
  @moduledoc false

  def parse_file(absolute_path) do
    case File.read(absolute_path) do
      {:ok, code} -> parse_string(code)
      {:error, reason} -> {:error, reason}
    end
  end

  def parse_string(code) do
    case Spitfire.parse(code) do
      {:ok, ast} -> {:ok, ast}
      {:error, ast, _diagnostics} -> {:ok, ast}
      {:error, reason} -> {:error, reason}
    end
  end
end

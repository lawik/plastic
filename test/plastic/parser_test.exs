defmodule Plastic.ParserTest do
  use ExUnit.Case, async: true

  alias Plastic.Parser

  describe "parse_string/1" do
    test "parses a simple module" do
      code = """
      defmodule Foo do
        def bar, do: :ok
      end
      """

      assert {:ok, ast} = Parser.parse_string(code)
      assert {:defmodule, _, _} = ast
    end

    test "parses module with multiple functions" do
      code = """
      defmodule Foo do
        def bar, do: :ok
        def baz(x), do: x
      end
      """

      assert {:ok, ast} = Parser.parse_string(code)
      assert {:defmodule, _, _} = ast
    end

    test "handles code with syntax errors gracefully" do
      code = """
      defmodule Foo do
        def bar(
      end
      """

      assert {:ok, _ast} = Parser.parse_string(code)
    end

    test "parses empty module" do
      code = """
      defmodule Foo do
      end
      """

      assert {:ok, ast} = Parser.parse_string(code)
      assert {:defmodule, _, _} = ast
    end
  end

  describe "parse_file/1" do
    test "parses an existing elixir file" do
      path = Path.expand("lib/plastic/parser.ex")
      assert {:ok, ast} = Parser.parse_file(path)
      assert {:defmodule, _, _} = ast
    end

    test "returns error for missing file" do
      assert {:error, :enoent} = Parser.parse_file("/tmp/nonexistent_file_plastic.ex")
    end
  end
end

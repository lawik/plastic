defmodule Plastic.Editor.ModuleOpsTest do
  use ExUnit.Case, async: true

  alias Plastic.Editor.ModuleOps

  @kitchen_sink File.read!("sample/lib/sample/kitchen_sink.ex")

  defp assert_valid_elixir(source) do
    assert {:ok, _} = Code.string_to_quoted(source), "Generated code is not valid Elixir"
    source
  end

  describe "add_module/3" do
    test "appends a new empty module" do
      source = """
      defmodule Foo do
      end
      """

      {:ok, result} = ModuleOps.add_module(source, "Bar")
      assert_valid_elixir(result)
      assert result =~ "defmodule Bar do"
    end

    test "appends a module with body" do
      source = """
      defmodule Foo do
      end
      """

      {:ok, result} = ModuleOps.add_module(source, "Bar", body: "def hello, do: :world")
      assert_valid_elixir(result)
      assert result =~ "defmodule Bar do"
      assert result =~ "def hello, do: :world"
    end
  end

  describe "rename_module/3" do
    test "renames a simple module" do
      source = """
      defmodule Foo do
        def bar, do: :ok
      end
      """

      {:ok, result} = ModuleOps.rename_module(source, "Foo", "Baz")
      assert_valid_elixir(result)
      assert result =~ "defmodule Baz do"
      refute result =~ "defmodule Foo do"
    end

    test "renames a dotted module name" do
      source = """
      defmodule Foo.Bar do
        def baz, do: :ok
      end
      """

      {:ok, result} = ModuleOps.rename_module(source, "Foo.Bar", "Foo.Qux")
      assert_valid_elixir(result)
      assert result =~ "defmodule Foo.Qux do"
    end

    test "renames KitchenSink module" do
      {:ok, result} = ModuleOps.rename_module(@kitchen_sink, "Sample.KitchenSink", "Sample.Renamed")
      assert_valid_elixir(result)
      assert result =~ "defmodule Sample.Renamed do"
      refute result =~ "defmodule Sample.KitchenSink do"
    end

    test "returns :error for non-existent module" do
      source = """
      defmodule Foo do
      end
      """

      assert :error = ModuleOps.rename_module(source, "NonExistent", "New")
    end
  end

  describe "remove_module/2" do
    test "removes a module" do
      source = """
      defmodule Foo do
        def bar, do: :ok
      end

      defmodule Baz do
        def qux, do: :ok
      end
      """

      {:ok, result} = ModuleOps.remove_module(source, "Foo")
      assert_valid_elixir(result)
      refute result =~ "defmodule Foo do"
      assert result =~ "defmodule Baz do"
    end

    test "returns :error for non-existent module" do
      source = """
      defmodule Foo do
      end
      """

      assert :error = ModuleOps.remove_module(source, "NonExistent")
    end
  end
end

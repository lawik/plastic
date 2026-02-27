defmodule Plastic.Editor.FunctionOpsTest do
  use ExUnit.Case, async: true

  alias Plastic.Editor.FunctionOps

  @kitchen_sink File.read!("sample/lib/sample/kitchen_sink.ex")

  defp assert_valid_elixir(source) do
    assert {:ok, _} = Code.string_to_quoted(source), "Generated code is not valid Elixir"
    source
  end

  describe "add_function/3" do
    test "adds a function to a module" do
      source = """
      defmodule Foo do
        def bar, do: :ok
      end
      """

      {:ok, result} = FunctionOps.add_function(source, "Foo", "def baz(x), do: x * 2")
      assert_valid_elixir(result)
      assert result =~ "def baz(x), do: x * 2"
      assert result =~ "def bar, do: :ok"
    end

    test "adds a function to kitchen sink" do
      {:ok, result} = FunctionOps.add_function(
        @kitchen_sink,
        "Sample.KitchenSink",
        "def new_function(x), do: x + 1"
      )
      assert_valid_elixir(result)
      assert result =~ "def new_function(x), do: x + 1"
    end
  end

  describe "rename_function/5" do
    test "renames a single-clause function" do
      source = """
      defmodule Foo do
        def bar(x), do: x * 2
      end
      """

      {:ok, result} = FunctionOps.rename_function(source, "Foo", :bar, 1, :baz)
      assert_valid_elixir(result)
      assert result =~ "def baz(x)"
      refute result =~ "def bar(x)"
    end

    test "renames all clauses of a multi-clause function" do
      source = """
      defmodule Foo do
        def bar(:a), do: 1
        def bar(:b), do: 2
        def bar(:c), do: 3
      end
      """

      {:ok, result} = FunctionOps.rename_function(source, "Foo", :bar, 1, :qux)
      assert_valid_elixir(result)

      # All three clauses renamed
      assert length(Regex.scan(~r/def qux/, result)) == 3
      refute result =~ "def bar"
    end

    test "renames classify/1 in kitchen sink (9 clauses)" do
      {:ok, result} = FunctionOps.rename_function(
        @kitchen_sink,
        "Sample.KitchenSink",
        :classify,
        1,
        :categorize
      )
      assert_valid_elixir(result)

      classify_count = length(Regex.scan(~r/def categorize/, result))
      assert classify_count == 9
      refute result =~ "def classify"
    end

    test "returns :error for non-existent function" do
      source = """
      defmodule Foo do
        def bar, do: :ok
      end
      """

      assert :error = FunctionOps.rename_function(source, "Foo", :missing, 0, :new_name)
    end
  end

  describe "remove_function/4" do
    test "removes a single-clause function" do
      source = """
      defmodule Foo do
        def bar, do: :ok
        def baz, do: :ok
      end
      """

      {:ok, result} = FunctionOps.remove_function(source, "Foo", :bar, 0)
      assert_valid_elixir(result)
      refute result =~ "def bar"
      assert result =~ "def baz"
    end

    test "removes all clauses of a multi-clause function" do
      source = """
      defmodule Foo do
        def bar(:a), do: 1
        def bar(:b), do: 2
        def bar(:c), do: 3
        def baz, do: :ok
      end
      """

      {:ok, result} = FunctionOps.remove_function(source, "Foo", :bar, 1)
      assert_valid_elixir(result)
      refute result =~ "def bar"
      assert result =~ "def baz"
    end

    test "removes transform/1 (3 clauses) from kitchen sink" do
      {:ok, result} = FunctionOps.remove_function(
        @kitchen_sink,
        "Sample.KitchenSink",
        :transform,
        1
      )
      assert_valid_elixir(result)
      refute result =~ "defp transform("
    end

    test "returns :error for non-existent function" do
      source = """
      defmodule Foo do
        def bar, do: :ok
      end
      """

      assert :error = FunctionOps.remove_function(source, "Foo", :missing, 0)
    end
  end

  describe "add_function_head/5" do
    test "adds a new clause after the last one" do
      source = """
      defmodule Foo do
        def bar(:a), do: 1
        def bar(:b), do: 2
      end
      """

      {:ok, result} = FunctionOps.add_function_head(
        source,
        "Foo",
        :bar,
        1,
        "def bar(:c), do: 3"
      )
      assert_valid_elixir(result)
      assert result =~ "def bar(:c), do: 3"
    end

    test "adds a function head to classify/1 in kitchen sink" do
      {:ok, result} = FunctionOps.add_function_head(
        @kitchen_sink,
        "Sample.KitchenSink",
        :classify,
        1,
        "def classify(x) when is_tuple(x), do: :tuple"
      )
      assert_valid_elixir(result)
      assert result =~ "def classify(x) when is_tuple(x), do: :tuple"
    end

    test "returns :error for non-existent function" do
      source = """
      defmodule Foo do
        def bar, do: :ok
      end
      """

      assert :error = FunctionOps.add_function_head(source, "Foo", :missing, 0, "def missing, do: :ok")
    end
  end

  describe "update_function/5" do
    test "replaces a function with new code" do
      source = """
      defmodule Foo do
        def bar(x), do: x * 2
      end
      """

      {:ok, result} = FunctionOps.update_function(
        source,
        "Foo",
        :bar,
        1,
        "def bar(x), do: x * 3"
      )
      assert_valid_elixir(result)
      assert result =~ "x * 3"
      refute result =~ "x * 2"
    end

    test "replaces a multi-clause function" do
      source = """
      defmodule Foo do
        def bar(:a), do: 1
        def bar(:b), do: 2
        def baz, do: :ok
      end
      """

      {:ok, result} = FunctionOps.update_function(
        source,
        "Foo",
        :bar,
        1,
        "def bar(x), do: x"
      )
      assert_valid_elixir(result)
      assert result =~ "def bar(x), do: x"
      assert result =~ "def baz, do: :ok"
      refute result =~ "def bar(:a)"
      refute result =~ "def bar(:b)"
    end
  end

  describe "remove_function_head/5" do
    test "removes a specific clause by index" do
      source = """
      defmodule Foo do
        def bar(:a), do: 1
        def bar(:b), do: 2
        def bar(:c), do: 3
      end
      """

      {:ok, result} = FunctionOps.remove_function_head(source, "Foo", :bar, 1, 1)
      assert_valid_elixir(result)
      assert result =~ "def bar(:a)"
      refute result =~ "def bar(:b)"
      assert result =~ "def bar(:c)"
    end

    test "removes a specific classify/1 clause from kitchen sink" do
      # Remove the 4th clause (index 3): def classify(0), do: :zero
      {:ok, result} = FunctionOps.remove_function_head(
        @kitchen_sink,
        "Sample.KitchenSink",
        :classify,
        1,
        3
      )
      assert_valid_elixir(result)
      # The :zero clause should be gone
      refute result =~ "def classify(0), do: :zero"
      # Other clauses remain
      assert result =~ "def classify(x) when is_binary(x)"
    end

    test "returns :error for out-of-range index" do
      source = """
      defmodule Foo do
        def bar(:a), do: 1
      end
      """

      assert :error = FunctionOps.remove_function_head(source, "Foo", :bar, 1, 5)
    end
  end
end

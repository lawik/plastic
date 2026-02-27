defmodule Plastic.Editor.FindTest do
  use ExUnit.Case, async: true

  alias Plastic.Editor.Find

  @kitchen_sink File.read!("sample/lib/sample/kitchen_sink.ex")

  describe "module/2" do
    test "finds a module by name" do
      source = """
      defmodule Foo do
        def bar, do: :ok
      end
      """

      assert {:ok, _zipper} = Find.module(source, "Foo")
    end

    test "finds a nested module name" do
      source = """
      defmodule Foo.Bar.Baz do
        def bar, do: :ok
      end
      """

      assert {:ok, _zipper} = Find.module(source, "Foo.Bar.Baz")
    end

    test "returns :error for non-existent module" do
      source = """
      defmodule Foo do
      end
      """

      assert :error = Find.module(source, "Bar")
    end

    test "finds KitchenSink module" do
      assert {:ok, _zipper} = Find.module(@kitchen_sink, "Sample.KitchenSink")
    end

    test "finds nested Helpers module in kitchen sink" do
      assert {:ok, _zipper} = Find.module(@kitchen_sink, "Helpers")
    end
  end

  describe "function/4" do
    test "finds a function by name and arity" do
      source = """
      defmodule Foo do
        def bar(x), do: x
        def baz(x, y), do: {x, y}
      end
      """

      assert {:ok, _zipper} = Find.function(source, "Foo", :bar, 1)
      assert {:ok, _zipper} = Find.function(source, "Foo", :baz, 2)
    end

    test "returns :error for wrong arity" do
      source = """
      defmodule Foo do
        def bar(x), do: x
      end
      """

      assert :error = Find.function(source, "Foo", :bar, 2)
    end

    test "finds classify/1 in kitchen sink" do
      assert {:ok, _zipper} = Find.function(@kitchen_sink, "Sample.KitchenSink", :classify, 1)
    end

    test "finds private function" do
      source = """
      defmodule Foo do
        defp secret(x), do: x
      end
      """

      assert {:ok, _zipper} = Find.function(source, "Foo", :secret, 1)
    end
  end

  describe "function_clauses/4" do
    test "finds all clauses of a multi-clause function" do
      source = """
      defmodule Foo do
        def bar(:a), do: 1
        def bar(:b), do: 2
        def bar(:c), do: 3
      end
      """

      clauses = Find.function_clauses(source, "Foo", :bar, 1)
      assert length(clauses) == 3
    end

    test "returns single clause for single-clause function" do
      source = """
      defmodule Foo do
        def bar(x), do: x
      end
      """

      clauses = Find.function_clauses(source, "Foo", :bar, 1)
      assert length(clauses) == 1
    end

    test "finds all 9 classify/1 clauses in kitchen sink" do
      clauses = Find.function_clauses(@kitchen_sink, "Sample.KitchenSink", :classify, 1)
      assert length(clauses) == 9
    end

    test "returns empty list for non-existent function" do
      source = """
      defmodule Foo do
        def bar, do: :ok
      end
      """

      clauses = Find.function_clauses(source, "Foo", :baz, 0)
      assert clauses == []
    end
  end

  describe "function_clause/5" do
    test "finds specific clause by index" do
      source = """
      defmodule Foo do
        def bar(:a), do: 1
        def bar(:b), do: 2
        def bar(:c), do: 3
      end
      """

      assert {:ok, _} = Find.function_clause(source, "Foo", :bar, 1, 0)
      assert {:ok, _} = Find.function_clause(source, "Foo", :bar, 1, 2)
    end

    test "returns :error for out-of-range index" do
      source = """
      defmodule Foo do
        def bar(:a), do: 1
      end
      """

      assert :error = Find.function_clause(source, "Foo", :bar, 1, 5)
    end
  end

  describe "last_in_module/2" do
    test "finds the last expression in a module" do
      source = """
      defmodule Foo do
        use GenServer
        def bar, do: :ok
        def baz, do: :ok
      end
      """

      assert {:ok, zipper} = Find.last_in_module(source, "Foo")
      node = Sourceror.Zipper.node(zipper)
      assert {:def, _, [{:baz, _, _} | _]} = node
    end
  end

  describe "case_expr/2" do
    test "finds a case expression inside a function" do
      source = """
      defmodule Foo do
        def bar(x) do
          case x do
            :a -> 1
            :b -> 2
          end
        end
      end
      """

      assert {:ok, zipper} = Find.case_expr(source, module_name: "Foo", fun_name: :bar, arity: 1)
      node = Sourceror.Zipper.node(zipper)
      assert {:case, _, _} = node
    end
  end

  describe "attribute/3" do
    test "finds an attribute by name" do
      source = """
      defmodule Foo do
        @moduledoc false
        @custom_attr 42
      end
      """

      assert {:ok, _} = Find.attribute(source, "Foo", :moduledoc)
      assert {:ok, _} = Find.attribute(source, "Foo", :custom_attr)
    end

    test "returns :error for non-existent attribute" do
      source = """
      defmodule Foo do
        @custom 1
      end
      """

      assert :error = Find.attribute(source, "Foo", :missing)
    end
  end

  describe "directive/4" do
    test "finds use directive" do
      source = """
      defmodule Foo do
        use GenServer
      end
      """

      assert {:ok, _} = Find.directive(source, "Foo", :use, "GenServer")
    end

    test "finds import directive" do
      source = """
      defmodule Foo do
        import Enum, only: [map: 2]
      end
      """

      assert {:ok, _} = Find.directive(source, "Foo", :import, "Enum")
    end

    test "finds alias directive" do
      source = """
      defmodule Foo do
        alias Foo.Bar
      end
      """

      assert {:ok, _} = Find.directive(source, "Foo", :alias, "Foo.Bar")
    end

    test "finds use GenServer in kitchen sink" do
      assert {:ok, _} = Find.directive(@kitchen_sink, "Sample.KitchenSink", :use, "GenServer")
    end
  end
end

defmodule Plastic.Editor.AttributeOpsTest do
  use ExUnit.Case, async: true

  alias Plastic.Editor.AttributeOps

  @kitchen_sink File.read!("sample/lib/sample/kitchen_sink.ex")

  defp assert_valid_elixir(source) do
    assert {:ok, _} = Code.string_to_quoted(source), "Generated code is not valid Elixir"
    source
  end

  describe "add_attribute/3" do
    test "adds an attribute to a module" do
      source = """
      defmodule Foo do
        def bar, do: :ok
      end
      """

      {:ok, result} = AttributeOps.add_attribute(source, "Foo", "@my_attr 42")
      assert_valid_elixir(result)
      assert result =~ "@my_attr 42"
    end
  end

  describe "remove_attribute/3" do
    test "removes an attribute" do
      source = """
      defmodule Foo do
        @custom_attr 42
        def bar, do: :ok
      end
      """

      {:ok, result} = AttributeOps.remove_attribute(source, "Foo", :custom_attr)
      assert_valid_elixir(result)
      refute result =~ "@custom_attr"
      assert result =~ "def bar"
    end

    test "returns :error for non-existent attribute" do
      source = """
      defmodule Foo do
        def bar, do: :ok
      end
      """

      assert :error = AttributeOps.remove_attribute(source, "Foo", :missing)
    end
  end

  describe "add_use/3" do
    test "adds a use directive at the beginning of a module" do
      source = """
      defmodule Foo do
        def bar, do: :ok
      end
      """

      {:ok, result} = AttributeOps.add_use(source, "Foo", "GenServer")
      assert_valid_elixir(result)
      assert result =~ "use GenServer"
    end
  end

  describe "add_import/3" do
    test "adds an import directive" do
      source = """
      defmodule Foo do
        def bar, do: :ok
      end
      """

      {:ok, result} = AttributeOps.add_import(source, "Foo", "Enum")
      assert_valid_elixir(result)
      assert result =~ "import Enum"
    end
  end

  describe "add_alias/3" do
    test "adds an alias directive" do
      source = """
      defmodule Foo do
        def bar, do: :ok
      end
      """

      {:ok, result} = AttributeOps.add_alias(source, "Foo", "Foo.Bar")
      assert_valid_elixir(result)
      assert result =~ "alias Foo.Bar"
    end

    test "adds an alias to kitchen sink" do
      {:ok, result} = AttributeOps.add_alias(
        @kitchen_sink,
        "Sample.KitchenSink",
        "Sample.NewModule"
      )
      assert_valid_elixir(result)
      assert result =~ "alias Sample.NewModule"
    end
  end

  describe "remove_directive/4" do
    test "removes a use directive" do
      source = """
      defmodule Foo do
        use GenServer
        def bar, do: :ok
      end
      """

      {:ok, result} = AttributeOps.remove_directive(source, "Foo", :use, "GenServer")
      assert_valid_elixir(result)
      refute result =~ "use GenServer"
      assert result =~ "def bar"
    end

    test "removes use GenServer from kitchen sink" do
      {:ok, result} = AttributeOps.remove_directive(
        @kitchen_sink,
        "Sample.KitchenSink",
        :use,
        "GenServer"
      )
      assert_valid_elixir(result)
      refute result =~ "use GenServer"
      # Other directives remain
      assert result =~ "require Logger"
      assert result =~ "import Enum"
    end

    test "removes an import directive" do
      source = """
      defmodule Foo do
        import Enum
        def bar, do: :ok
      end
      """

      {:ok, result} = AttributeOps.remove_directive(source, "Foo", :import, "Enum")
      assert_valid_elixir(result)
      refute result =~ "import Enum"
    end

    test "returns :error for non-existent directive" do
      source = """
      defmodule Foo do
        def bar, do: :ok
      end
      """

      assert :error = AttributeOps.remove_directive(source, "Foo", :use, "GenServer")
    end
  end
end

defmodule Plastic.Editor.OperationsTest do
  use ExUnit.Case, async: true

  alias Plastic.Editor.Operations

  describe "applicable_operations/1" do
    test "returns module operations for :module" do
      ops = Operations.applicable_operations(:module)
      names = Enum.map(ops, & &1.name)
      assert :add_module in names
      assert :rename_module in names
      assert :remove_module in names
      assert :add_function in names
      assert :add_attribute in names
      assert :add_use in names
      assert :add_import in names
      assert :add_alias in names
    end

    test "returns function operations for :function" do
      ops = Operations.applicable_operations(:function)
      names = Enum.map(ops, & &1.name)
      assert :rename_function in names
      assert :remove_function in names
      assert :update_function in names
      assert :add_function_head in names
      assert :add_function in names
    end

    test "returns clause operations for :function_clause" do
      ops = Operations.applicable_operations(:function_clause)
      names = Enum.map(ops, & &1.name)
      assert :add_function_head in names
      assert :remove_function_head in names
    end

    test "returns case operations for :case_expr" do
      ops = Operations.applicable_operations(:case_expr)
      names = Enum.map(ops, & &1.name)
      assert :add_case_clause in names
    end

    test "returns clause operations for :clause" do
      ops = Operations.applicable_operations(:clause)
      names = Enum.map(ops, & &1.name)
      assert :remove_case_clause in names
      assert :update_case_clause in names
    end

    test "returns attribute operations for :attribute" do
      ops = Operations.applicable_operations(:attribute)
      names = Enum.map(ops, & &1.name)
      assert :add_attribute in names
      assert :remove_attribute in names
    end

    test "returns remove for :moduledoc" do
      ops = Operations.applicable_operations(:moduledoc)
      names = Enum.map(ops, & &1.name)
      assert :remove_attribute in names
    end

    test "returns directive operations for :use" do
      ops = Operations.applicable_operations(:use)
      names = Enum.map(ops, & &1.name)
      assert :add_use in names
      assert :remove_directive in names
    end

    test "returns directive operations for :import" do
      ops = Operations.applicable_operations(:import)
      names = Enum.map(ops, & &1.name)
      assert :add_import in names
      assert :remove_directive in names
    end

    test "returns directive operations for :alias" do
      ops = Operations.applicable_operations(:alias)
      names = Enum.map(ops, & &1.name)
      assert :add_alias in names
      assert :remove_directive in names
    end

    test "returns directive operations for :require" do
      ops = Operations.applicable_operations(:require)
      names = Enum.map(ops, & &1.name)
      assert :remove_directive in names
    end

    test "returns empty list for unknown node kind" do
      assert Operations.applicable_operations(:unknown_kind) == []
    end

    test "all operations have required keys" do
      for op <- Operations.all_operations() do
        assert Map.has_key?(op, :name), "Missing :name in #{inspect(op)}"
        assert Map.has_key?(op, :label), "Missing :label in #{inspect(op)}"
        assert Map.has_key?(op, :description), "Missing :description in #{inspect(op)}"
        assert Map.has_key?(op, :applies_to), "Missing :applies_to in #{inspect(op)}"
        assert is_list(op.applies_to), ":applies_to should be a list in #{inspect(op)}"
      end
    end
  end
end

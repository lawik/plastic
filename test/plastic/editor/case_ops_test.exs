defmodule Plastic.Editor.CaseOpsTest do
  use ExUnit.Case, async: true

  alias Plastic.Editor.CaseOps

  defp assert_valid_elixir(source) do
    assert {:ok, _} = Code.string_to_quoted(source), "Generated code is not valid Elixir"
    source
  end

  @case_source """
  defmodule Foo do
    def bar(x) do
      case x do
        :a -> 1
        :b -> 2
        _ -> 0
      end
    end
  end
  """

  describe "add_case_clause/2" do
    test "adds a clause to a case expression" do
      {:ok, result} = CaseOps.add_case_clause(@case_source,
        module_name: "Foo",
        fun_name: :bar,
        arity: 1,
        clause_code: ":c -> 3"
      )
      assert_valid_elixir(result)
      assert result =~ ":c -> 3"
    end
  end

  describe "remove_case_clause/2" do
    test "removes a clause by index" do
      {:ok, result} = CaseOps.remove_case_clause(@case_source,
        module_name: "Foo",
        fun_name: :bar,
        arity: 1,
        clause_index: 1
      )
      assert_valid_elixir(result)
      assert result =~ ":a -> 1"
      refute result =~ ":b -> 2"
      assert result =~ "_ -> 0"
    end

    test "returns :error for out-of-range index" do
      assert :error = CaseOps.remove_case_clause(@case_source,
        module_name: "Foo",
        fun_name: :bar,
        arity: 1,
        clause_index: 10
      )
    end
  end

  describe "update_case_clause/2" do
    test "replaces a clause" do
      {:ok, result} = CaseOps.update_case_clause(@case_source,
        module_name: "Foo",
        fun_name: :bar,
        arity: 1,
        clause_index: 0,
        clause_code: ":a -> 100"
      )
      assert_valid_elixir(result)
      assert result =~ ":a -> 100"
      refute result =~ ":a -> 1\n"
    end

    test "returns :error for out-of-range index" do
      assert :error = CaseOps.update_case_clause(@case_source,
        module_name: "Foo",
        fun_name: :bar,
        arity: 1,
        clause_index: 10,
        clause_code: ":z -> 99"
      )
    end
  end
end

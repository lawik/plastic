defmodule Plastic.Editor.CaseOps do
  @moduledoc false

  alias Plastic.Editor.Find
  alias Sourceror.Zipper

  @doc """
  Add a clause to a case expression.
  Parses the clause via a wrapper case, then inserts at the end of the case's do block.

  opts:
    - module_name, fun_name, arity: locate the function containing the case
    - case_index: which case (0-indexed, default 0)
    - clause_code: the clause to add, e.g. `:new_pattern -> :new_result`
  """
  def add_case_clause(source, opts) do
    clause_code = Keyword.fetch!(opts, :clause_code)

    with {:ok, case_zipper} <- find_case(source, opts) do
      case_node = Zipper.node(case_zipper)
      range = Sourceror.get_range(case_node)

      # Insert before the `end` of the case — which is at the end position
      # We want to insert a new clause just before the end keyword
      end_line = range.end[:line]
      _end_col = range.end[:column]

      # Find the indentation of existing clauses by looking at the source
      lines = String.split(source, "\n")
      # Find the line with "end" for this case
      case_end_line = Enum.at(lines, end_line - 1)
      indent = String.duplicate(" ", count_leading_spaces(case_end_line) + 2)

      # Insert before the end keyword
      insert_range = %{
        start: [line: end_line, column: 1],
        end: [line: end_line, column: 1]
      }

      patch = %{range: insert_range, change: "#{indent}#{clause_code}\n"}

      {:ok, Sourceror.patch_string(source, [patch])}
    end
  end

  @doc """
  Remove a clause from a case expression.

  opts:
    - module_name, fun_name, arity, case_index: locate the case
    - clause_index: which clause to remove (0-indexed)
  """
  def remove_case_clause(source, opts) do
    clause_index = Keyword.fetch!(opts, :clause_index)

    with {:ok, case_zipper} <- find_case(source, opts) do
      clauses = get_case_clauses(case_zipper)

      if clause_index >= 0 and clause_index < length(clauses) do
        clause = Enum.at(clauses, clause_index)
        range = Sourceror.get_range(clause)
        patch = %{range: range, change: ""}
        result = Sourceror.patch_string(source, [patch])
        {:ok, Plastic.Editor.cleanup_blank_lines(result)}
      else
        :error
      end
    end
  end

  @doc """
  Update (replace) a clause in a case expression.

  opts:
    - module_name, fun_name, arity, case_index: locate the case
    - clause_index: which clause to replace (0-indexed)
    - clause_code: the new clause code
  """
  def update_case_clause(source, opts) do
    clause_index = Keyword.fetch!(opts, :clause_index)
    clause_code = Keyword.fetch!(opts, :clause_code)

    with {:ok, case_zipper} <- find_case(source, opts) do
      clauses = get_case_clauses(case_zipper)

      if clause_index >= 0 and clause_index < length(clauses) do
        clause = Enum.at(clauses, clause_index)
        range = Sourceror.get_range(clause)
        patch = %{range: range, change: clause_code}
        {:ok, Sourceror.patch_string(source, [patch])}
      else
        :error
      end
    end
  end

  # --- Private ---

  defp find_case(source, opts) do
    module_name = Keyword.fetch!(opts, :module_name)
    fun_name = Keyword.fetch!(opts, :fun_name)
    arity = Keyword.fetch!(opts, :arity)
    case_index = Keyword.get(opts, :case_index, 0)

    Find.case_expr(source,
      module_name: module_name,
      fun_name: fun_name,
      arity: arity,
      index: case_index
    )
  end

  defp get_case_clauses(case_zipper) do
    case_node = Zipper.node(case_zipper)
    {:case, _, [_subject, block]} = case_node

    # Sourceror uses [{do_block_key, clauses}] format
    clauses =
      case block do
        [do: clauses] when is_list(clauses) -> clauses
        [{_, clauses}] when is_list(clauses) -> clauses
        _ -> []
      end

    clauses
  end

  defp count_leading_spaces(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, spaces] -> String.length(spaces)
      _ -> 0
    end
  end
end

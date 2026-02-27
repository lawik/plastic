defmodule Plastic.Editor.FunctionOps do
  @moduledoc false

  alias Plastic.Editor.Find
  alias Sourceror.Zipper

  @doc """
  Add a function to a module by inserting after the last expression in the module body.
  """
  def add_function(source, module_name, fun_code) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         zipper <- Zipper.zip(ast),
         {:ok, last_zipper} <- Find.last_in_module(zipper, module_name) do
      last_node = Zipper.node(last_zipper)
      range = Sourceror.get_range(last_node)
      end_pos = range.end

      insert_range = %{start: end_pos, end: end_pos}
      patch = %{range: insert_range, change: "\n\n  #{fun_code}"}
      {:ok, Sourceror.patch_string(source, [patch])}
    end
  end

  @doc """
  Rename all clauses of a function (name nodes) from old_name to new_name.
  """
  def rename_function(source, module_name, old_name, arity, new_name) do
    new_name_atom = ensure_atom(new_name)
    clauses = Find.function_clauses(source, module_name, old_name, arity)

    if clauses == [] do
      :error
    else
      patches =
        clauses
        |> Enum.flat_map(fn clause_zipper ->
          node = Zipper.node(clause_zipper)
          name_patches(node, new_name_atom)
        end)

      {:ok, Sourceror.patch_string(source, patches)}
    end
  end

  @doc """
  Remove all clauses of a function.
  """
  def remove_function(source, module_name, fun_name, arity) do
    clauses = Find.function_clauses(source, module_name, fun_name, arity)

    if clauses == [] do
      :error
    else
      patches =
        Enum.map(clauses, fn clause_zipper ->
          node = Zipper.node(clause_zipper)
          range = Sourceror.get_range(node)
          %{range: range, change: ""}
        end)

      result = Sourceror.patch_string(source, patches)
      {:ok, Plastic.Editor.cleanup_blank_lines(result)}
    end
  end

  @doc """
  Add a new function head (clause) after the last existing clause.
  """
  def add_function_head(source, module_name, fun_name, arity, head_code) do
    clauses = Find.function_clauses(source, module_name, fun_name, arity)

    if clauses == [] do
      :error
    else
      last_clause = List.last(clauses)
      last_node = Zipper.node(last_clause)
      range = Sourceror.get_range(last_node)
      end_pos = range.end

      insert_range = %{start: end_pos, end: end_pos}
      patch = %{range: insert_range, change: "\n  #{head_code}"}
      {:ok, Sourceror.patch_string(source, [patch])}
    end
  end

  @doc """
  Replace the entire function (all clauses) with new code.
  """
  def update_function(source, module_name, fun_name, arity, new_code) do
    clauses = Find.function_clauses(source, module_name, fun_name, arity)

    if clauses == [] do
      :error
    else
      first_node = Zipper.node(List.first(clauses))
      last_node = Zipper.node(List.last(clauses))

      first_range = Sourceror.get_range(first_node)
      last_range = Sourceror.get_range(last_node)

      full_range = %{start: first_range.start, end: last_range.end}
      patch = %{range: full_range, change: new_code}
      {:ok, Sourceror.patch_string(source, [patch])}
    end
  end

  @doc """
  Remove a specific clause by index (0-based).
  """
  def remove_function_head(source, module_name, fun_name, arity, index) do
    with {:ok, _ast} <- Sourceror.parse_string(source),
         {:ok, clause_zipper} <- Find.function_clause(source, module_name, fun_name, arity, index) do
      node = Zipper.node(clause_zipper)
      range = Sourceror.get_range(node)
      patch = %{range: range, change: ""}
      result = Sourceror.patch_string(source, [patch])
      {:ok, Plastic.Editor.cleanup_blank_lines(result)}
    end
  end

  # Extract the function name node and build a rename patch for it
  defp name_patches(node, new_name) do
    case node do
      {def_kind, _, [{:when, _, [{name_atom, meta, args} | _guard]} | _body]}
      when def_kind in [:def, :defp, :defmacro, :defmacrop] ->
        name_range = name_node_range({name_atom, meta, args})
        if name_range do
          [%{range: name_range, change: to_string(new_name)}]
        else
          []
        end

      {def_kind, _, [{name_atom, meta, args} | _body]}
      when def_kind in [:def, :defp, :defmacro, :defmacrop] ->
        name_range = name_node_range({name_atom, meta, args})
        if name_range do
          [%{range: name_range, change: to_string(new_name)}]
        else
          []
        end

      _ ->
        []
    end
  end

  defp name_node_range({name_atom, meta, _args}) when is_list(meta) do
    line = Keyword.get(meta, :line)
    column = Keyword.get(meta, :column)

    if line && column do
      name_str = to_string(name_atom)
      %{
        start: [line: line, column: column],
        end: [line: line, column: column + String.length(name_str)]
      }
    end
  end

  defp name_node_range(_), do: nil

  defp ensure_atom(name) when is_atom(name), do: name
  defp ensure_atom(name) when is_binary(name), do: String.to_atom(name)
end

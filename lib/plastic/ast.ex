defmodule Plastic.AST do
  @moduledoc false

  defmodule Node do
    @moduledoc false

    defstruct [
      :id,
      :kind,
      :name,
      :meta,
      :ast,
      children: [],
      collapsed: true
    ]

    @type t :: %__MODULE__{
            id: String.t(),
            kind: atom(),
            name: String.t(),
            meta: map(),
            ast: Macro.t(),
            children: [t()],
            collapsed: boolean()
          }
  end

  @doc """
  Analyze a top-level AST and return a tree of Node structs grouped logically.
  """
  def analyze(ast) do
    analyze_top_level(ast, "root")
  end

  defp analyze_top_level({:__block__, _meta, children}, prefix) do
    analyze_expressions(children, prefix)
  end

  defp analyze_top_level(ast, prefix) do
    analyze_expressions([ast], prefix)
  end

  @default_blocks [
    Plastic.AST.Block.Moduledoc,
    Plastic.AST.Block.Behaviour,
    Plastic.AST.Block.AnnotatedFunction
  ]

  defp analyze_expressions(expressions, prefix) do
    expressions
    |> Enum.with_index()
    |> Enum.flat_map(fn {expr, idx} ->
      analyze_expression(expr, prefix, idx)
    end)
    |> group_function_clauses()
    |> apply_blocks(@default_blocks)
  end

  defp analyze_expression({:defmodule, meta, [alias_ast, [do: body]]}, prefix, _idx) do
    mod_name = module_name(alias_ast)
    id = "#{prefix}/mod:#{mod_name}"

    children = analyze_module_body(body, id)

    [
      %Node{
        id: id,
        kind: :module,
        name: mod_name,
        meta: extract_meta(meta),
        ast: {:defmodule, meta, [alias_ast, [do: body]]},
        children: children,
        collapsed: false
      }
    ]
  end

  # def with when clause: def foo(x) when is_integer(x), do: ...
  # Must come before the generic function clause match below
  defp analyze_expression(
         {def_kind, meta, [{:when, _, [{name, _, args} | _]} | _]} = ast,
         prefix,
         idx
       )
       when def_kind in [:def, :defp, :defmacro, :defmacrop] do
    arity = if is_list(args), do: length(args), else: 0
    label = "#{name}/#{arity}"
    id = "#{prefix}/#{def_kind}:#{name}/#{arity}:#{idx}"

    [
      %Node{
        id: id,
        kind: :function_clause,
        name: label,
        meta: Map.merge(extract_meta(meta), %{def_kind: def_kind, fun_name: name, arity: arity}),
        ast: ast,
        children: [],
        collapsed: true
      }
    ]
  end

  defp analyze_expression({def_kind, meta, [{name, _, args} | _]} = ast, prefix, idx)
       when def_kind in [:def, :defp, :defmacro, :defmacrop] do
    arity = if is_list(args), do: length(args), else: 0
    label = "#{name}/#{arity}"
    id = "#{prefix}/#{def_kind}:#{name}/#{arity}:#{idx}"

    [
      %Node{
        id: id,
        kind: :function_clause,
        name: label,
        meta: Map.merge(extract_meta(meta), %{def_kind: def_kind, fun_name: name, arity: arity}),
        ast: ast,
        children: [],
        collapsed: true
      }
    ]
  end

  defp analyze_expression({:@, meta, [{attr_name, _, attr_args}]} = ast, prefix, idx) do
    kind = categorize_attribute(attr_name)
    id = "#{prefix}/#{kind}:#{attr_name}:#{idx}"
    label = attribute_label(attr_name, attr_args)

    [
      %Node{
        id: id,
        kind: kind,
        name: label,
        meta: Map.put(extract_meta(meta), :attr_name, attr_name),
        ast: ast,
        children: [],
        collapsed: true
      }
    ]
  end

  defp analyze_expression({directive, meta, args} = ast, prefix, idx)
       when directive in [:use, :import, :alias, :require] do
    label = directive_label(args)
    id = "#{prefix}/#{directive}:#{idx}"

    [
      %Node{
        id: id,
        kind: directive,
        name: label,
        meta: extract_meta(meta),
        ast: ast,
        children: [],
        collapsed: true
      }
    ]
  end

  defp analyze_expression(ast, prefix, idx) do
    label =
      ast
      |> Macro.to_string()
      |> String.slice(0, 60)

    id = "#{prefix}/expr:#{idx}"

    [
      %Node{
        id: id,
        kind: :expression,
        name: label,
        meta: extract_meta(ast),
        ast: ast,
        children: [],
        collapsed: true
      }
    ]
  end

  defp analyze_module_body({:__block__, _meta, children}, prefix) do
    analyze_expressions(children, prefix)
  end

  defp analyze_module_body(ast, prefix) do
    analyze_expressions([ast], prefix)
  end

  # Group consecutive function clauses with the same name/arity into a parent function node
  defp group_function_clauses(nodes) do
    do_group(nodes, [], [])
  end

  # No more nodes — flush any accumulated clauses and reverse the result
  defp do_group([], [], result), do: Enum.reverse(result)

  defp do_group([], clause_acc, result) do
    Enum.reverse([finalize_function_group(Enum.reverse(clause_acc)) | result])
  end

  # Current node is a function clause
  defp do_group([%Node{kind: :function_clause} = node | rest], [], result) do
    do_group(rest, [node], result)
  end

  defp do_group([%Node{kind: :function_clause} = node | rest], [prev | _] = clause_acc, result) do
    if same_function?(prev, node) do
      do_group(rest, [node | clause_acc], result)
    else
      grouped = finalize_function_group(Enum.reverse(clause_acc))
      do_group(rest, [node], [grouped | result])
    end
  end

  # Current node is not a function clause — flush any accumulated clauses first
  defp do_group([node | rest], [], result) do
    do_group(rest, [], [node | result])
  end

  defp do_group([node | rest], clause_acc, result) do
    grouped = finalize_function_group(Enum.reverse(clause_acc))
    do_group(rest, [], [node | [grouped | result]])
  end

  defp same_function?(%Node{meta: %{fun_name: n, arity: a}}, %Node{meta: %{fun_name: n, arity: a}}),
    do: true

  defp same_function?(_, _), do: false

  defp finalize_function_group([single]), do: promote_clause(single)

  defp finalize_function_group([first | _] = clauses) do
    %{fun_name: name, arity: arity} = first.meta
    id = String.replace(first.id, ~r/:\d+$/, "")

    numbered_clauses =
      clauses
      |> Enum.with_index()
      |> Enum.map(fn {%Node{} = clause, i} ->
        %Node{clause | name: "clause #{i + 1}", id: "#{id}:clause:#{i}"}
      end)

    %Node{
      id: id,
      kind: :function,
      name: "#{name}/#{arity}",
      meta: first.meta,
      ast: nil,
      children: numbered_clauses,
      collapsed: true
    }
  end

  defp promote_clause(%Node{} = clause) do
    %Node{clause | kind: :function}
  end

  defp attribute_label(attr_name, nil), do: "#{attr_name}"

  defp attribute_label(attr_name, [value]) do
    value_str =
      value
      |> Macro.to_string()
      |> String.slice(0, 40)

    "#{attr_name} #{value_str}"
  end

  defp attribute_label(attr_name, _), do: "#{attr_name}"

  # Extract just the module name(s) from directive args, dropping the keyword like `use`/`import`
  defp directive_label([{:__aliases__, _, _} = alias_ast | _]), do: module_name(alias_ast)
  defp directive_label([{:__block__, _, [{{:., _, _}, _, _} = nested]} | _]), do: Macro.to_string(nested)
  defp directive_label(args), do: Macro.to_string(args)

  defp module_name({:__aliases__, _, parts}) do
    Enum.map_join(parts, ".", &to_string/1)
  end

  defp module_name(other) do
    Macro.to_string(other)
  end

  defp extract_meta({_, meta, _}) when is_list(meta) do
    %{
      line: Keyword.get(meta, :line),
      column: Keyword.get(meta, :column)
    }
  end

  defp extract_meta(meta) when is_list(meta) do
    %{
      line: Keyword.get(meta, :line),
      column: Keyword.get(meta, :column)
    }
  end

  defp extract_meta(_), do: %{}

  defp categorize_attribute(name) when name in [:type, :typep, :opaque, :spec, :callback, :macrocallback],
    do: :typespec

  defp categorize_attribute(_), do: :attribute

  # Block application — runs registered block recognizers over a node list

  defp apply_blocks(nodes, blocks) do
    do_apply_blocks(nodes, blocks, [])
  end

  defp do_apply_blocks([], _blocks, acc), do: Enum.reverse(acc)

  defp do_apply_blocks(nodes, blocks, acc) do
    case try_blocks(nodes, blocks) do
      {:ok, node, rest} -> do_apply_blocks(rest, blocks, [node | acc])
      :skip -> do_apply_blocks(tl(nodes), blocks, [hd(nodes) | acc])
    end
  end

  defp try_blocks(_nodes, []), do: :skip

  defp try_blocks(nodes, [block | rest]) do
    case block.match(nodes) do
      {:ok, _node, _remaining} = result -> result
      :skip -> try_blocks(nodes, rest)
    end
  end
end

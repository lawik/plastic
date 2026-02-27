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
  Extract a flat list of definition maps from raw AST for indexing.
  Returns entries like `%{kind: :module, name: "Foo.Bar", line: 1}`.
  """
  def extract_definitions(ast) do
    extract_defs(ast, nil, []) |> Enum.reverse()
  end

  defp extract_defs({:defmodule, meta, [alias_ast, [do: body]]}, current_module, acc) do
    short_name = module_name(alias_ast)

    mod =
      if current_module && !String.contains?(short_name, ".") do
        current_module <> "." <> short_name
      else
        short_name
      end

    line = Keyword.get(meta, :line)
    acc = [%{kind: :module, name: mod, line: line} | acc]
    extract_defs(body, mod, acc)
  end

  defp extract_defs({def_kind, meta, [{:when, _, [{name, _, args} | _]} | _]}, current_module, acc)
       when def_kind in [:def, :defp, :defmacro, :defmacrop] do
    arity = if is_list(args), do: length(args), else: 0
    line = Keyword.get(meta, :line)
    [%{kind: def_kind, module: current_module, name: name, arity: arity, line: line} | acc]
  end

  defp extract_defs({def_kind, meta, [{name, _, args} | _]}, current_module, acc)
       when def_kind in [:def, :defp, :defmacro, :defmacrop] do
    arity = if is_list(args), do: length(args), else: 0
    line = Keyword.get(meta, :line)
    [%{kind: def_kind, module: current_module, name: name, arity: arity, line: line} | acc]
  end

  defp extract_defs({guard_kind, meta, [{:when, _, [{name, _, args}, _guard]}]}, current_module, acc)
       when guard_kind in [:defguard, :defguardp] do
    arity = if is_list(args), do: length(args), else: 0
    line = Keyword.get(meta, :line)
    [%{kind: guard_kind, module: current_module, name: name, arity: arity, line: line} | acc]
  end

  defp extract_defs({:defstruct, meta, _}, current_module, acc) do
    line = Keyword.get(meta, :line)
    [%{kind: :struct, module: current_module, line: line} | acc]
  end

  defp extract_defs({:@, meta, [{type_kind, _, [{:"::", _, [{name, _, args} | _]} | _]}]}, current_module, acc)
       when type_kind in [:type, :typep, :opaque] do
    arity = if is_list(args), do: length(args), else: 0
    line = Keyword.get(meta, :line)
    [%{kind: type_kind, module: current_module, name: name, arity: arity, line: line} | acc]
  end

  defp extract_defs({:@, meta, [{type_kind, _, [{name, _, args}]}]}, current_module, acc)
       when type_kind in [:type, :typep, :opaque] do
    arity = if is_list(args), do: length(args), else: 0
    line = Keyword.get(meta, :line)
    [%{kind: type_kind, module: current_module, name: name, arity: arity, line: line} | acc]
  end

  defp extract_defs({:@, meta, [{cb_kind, _, [{:"::", _, [{name, _, args} | _]} | _]}]}, current_module, acc)
       when cb_kind in [:callback, :macrocallback] do
    arity = if is_list(args), do: length(args), else: 0
    line = Keyword.get(meta, :line)
    [%{kind: cb_kind, module: current_module, name: name, arity: arity, line: line} | acc]
  end

  defp extract_defs({:__block__, _, children}, current_module, acc) do
    Enum.reduce(children, acc, fn child, acc -> extract_defs(child, current_module, acc) end)
  end

  defp extract_defs(_, _current_module, acc), do: acc

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

  defp analyze_expressions(expressions, prefix, context \\ %{}) do
    expressions
    |> Enum.with_index()
    |> Enum.flat_map(fn {expr, idx} ->
      analyze_expression(expr, prefix, idx, context)
    end)
    |> group_function_clauses()
    |> apply_blocks(@default_blocks)
  end

  defp analyze_expression({:defmodule, meta, [alias_ast, [do: body]]}, prefix, _idx, _context) do
    mod_name = module_name(alias_ast)
    id = "#{prefix}/mod:#{mod_name}"

    children = analyze_module_body(body, id, %{module_name: mod_name})

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
         idx,
         _context
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
        children: extract_body_children(ast, id),
        collapsed: true
      }
    ]
  end

  defp analyze_expression({def_kind, meta, [{name, _, args} | _]} = ast, prefix, idx, _context)
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
        children: extract_body_children(ast, id),
        collapsed: true
      }
    ]
  end

  defp analyze_expression({:@, meta, [{attr_name, _, attr_args}]}, prefix, idx, _context) do
    kind = categorize_attribute(attr_name)
    id = "#{prefix}/#{kind}:#{attr_name}:#{idx}"

    label =
      case kind do
        :typespec -> typespec_label(attr_args)
        _ -> attribute_label(attr_name, attr_args)
      end

    [
      %Node{
        id: id,
        kind: kind,
        name: label,
        meta: Map.put(extract_meta(meta), :attr_name, attr_name),
        ast: nil,
        children: [],
        collapsed: true
      }
    ]
  end

  defp analyze_expression({:defstruct, meta, [fields]}, prefix, idx, context) do
    mod_prefix = if context[:module_name], do: "#{context.module_name} ", else: ""
    label = mod_prefix <> struct_label(fields)
    id = "#{prefix}/defstruct:#{idx}"

    [
      %Node{
        id: id,
        kind: :defstruct,
        name: label,
        meta: extract_meta(meta),
        ast: nil,
        children: [],
        collapsed: true
      }
    ]
  end

  defp analyze_expression({guard_kind, meta, [{:when, _, [{name, _, args}, _guard]}]} = ast, prefix, idx, _context)
       when guard_kind in [:defguard, :defguardp] do
    arity = if is_list(args), do: length(args), else: 0
    label = "#{name}/#{arity}"
    id = "#{prefix}/#{guard_kind}:#{name}/#{arity}:#{idx}"

    [
      %Node{
        id: id,
        kind: guard_kind,
        name: label,
        meta: extract_meta(meta),
        ast: ast,
        children: [],
        collapsed: true
      }
    ]
  end

  defp analyze_expression({directive, meta, args} = ast, prefix, idx, _context)
       when directive in [:use, :import, :alias, :require] do
    label = directive_label(args)
    id = "#{prefix}/#{directive}:#{idx}"
    has_options = length(args) > 1

    [
      %Node{
        id: id,
        kind: directive,
        name: label,
        meta: extract_meta(meta),
        ast: if(has_options, do: ast),
        children: [],
        collapsed: true
      }
    ]
  end

  defp analyze_expression(ast, prefix, idx, _context) do
    label = Macro.to_string(ast)

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

  defp analyze_module_body({:__block__, _meta, children}, prefix, context) do
    analyze_expressions(children, prefix, context)
  end

  defp analyze_module_body(ast, prefix, context) do
    analyze_expressions([ast], prefix, context)
  end

  # -- Function body breakdown --

  # Extract body children from a function clause AST.
  # Returns [] for one-liner bodies (single simple expression) so they keep showing code.
  defp extract_body_children({_def_kind, _, [_ | [[do: body] | _]]}, id) do
    analyze_body(body, id)
  end

  defp extract_body_children({_def_kind, _, [{:when, _, [_ | _]} | [[do: body] | _]]}, id) do
    analyze_body(body, id)
  end

  defp extract_body_children(_, _id), do: []

  defp analyze_body({:__block__, _, exprs}, prefix) do
    exprs
    |> Enum.with_index()
    |> Enum.map(fn {expr, idx} -> analyze_body_expr(expr, prefix, idx) end)
  end

  defp analyze_body(expr, prefix) do
    # Single expression — if it's a leaf (not a structured expression), return []
    # so the function keeps showing code for one-liners
    if structured_expr?(expr) do
      [analyze_body_expr(expr, prefix, 0)]
    else
      []
    end
  end

  @structured_tags [:|>, :case, :if, :unless, :cond, :with, :try, :receive, :for, :fn]

  defp structured_expr?({tag, _, _}) when tag in @structured_tags, do: true
  defp structured_expr?({:=, _, [_, rhs]}), do: structured_expr?(rhs)
  defp structured_expr?(_), do: false

  # Pipe chain
  defp analyze_body_expr({:|>, _, _} = ast, prefix, idx) do
    id = "#{prefix}/pipe:#{idx}"
    steps = flatten_pipe(ast)
    first_step = Macro.to_string(hd(steps))

    children =
      steps
      |> Enum.with_index()
      |> Enum.map(fn {step, i} ->
        prefix_str = if i == 0, do: "|  ", else: "|> "

        %Node{
          id: "#{id}/step:#{i}",
          kind: :expression,
          name: prefix_str <> Macro.to_string(step),
          meta: extract_meta(step),
          ast: nil,
          children: [],
          collapsed: true
        }
      end)

    %Node{
      id: id,
      kind: :pipe,
      name: "#{first_step} |> ...",
      meta: extract_meta(ast),
      ast: nil,
      children: children,
      collapsed: true
    }
  end

  # Match with structured RHS
  defp analyze_body_expr({:=, _, [pattern, rhs]} = ast, prefix, idx) do
    id = "#{prefix}/match:#{idx}"
    pattern_str = Macro.to_string(pattern)

    if structured_expr?(rhs) do
      %Node{
        id: id,
        kind: :match,
        name: "#{pattern_str} =",
        meta: extract_meta(ast),
        ast: nil,
        children: [analyze_body_expr(rhs, id, 0)],
        collapsed: true
      }
    else
      %Node{
        id: id,
        kind: :match,
        name: "#{pattern_str} = #{Macro.to_string(rhs)}",
        meta: extract_meta(ast),
        ast: nil,
        children: [],
        collapsed: true
      }
    end
  end

  # case
  defp analyze_body_expr({:case, _, [subject, [do: clauses]]} = ast, prefix, idx) do
    id = "#{prefix}/case:#{idx}"

    %Node{
      id: id,
      kind: :case_expr,
      name: Macro.to_string(subject),
      meta: extract_meta(ast),
      ast: nil,
      children: analyze_clauses(clauses, id),
      collapsed: true
    }
  end

  # if
  defp analyze_body_expr({:if, _, [condition | [blocks]]} = ast, prefix, idx) do
    id = "#{prefix}/if:#{idx}"

    %Node{
      id: id,
      kind: :if_expr,
      name: Macro.to_string(condition),
      meta: extract_meta(ast),
      ast: nil,
      children: analyze_block_children(blocks, id),
      collapsed: true
    }
  end

  # unless
  defp analyze_body_expr({:unless, _, [condition | [blocks]]} = ast, prefix, idx) do
    id = "#{prefix}/unless:#{idx}"

    %Node{
      id: id,
      kind: :unless_expr,
      name: Macro.to_string(condition),
      meta: extract_meta(ast),
      ast: nil,
      children: analyze_block_children(blocks, id),
      collapsed: true
    }
  end

  # cond
  defp analyze_body_expr({:cond, _, [[do: clauses]]} = ast, prefix, idx) do
    id = "#{prefix}/cond:#{idx}"

    %Node{
      id: id,
      kind: :cond_expr,
      name: "",
      meta: extract_meta(ast),
      ast: nil,
      children: analyze_clauses(clauses, id),
      collapsed: true
    }
  end

  # with
  defp analyze_body_expr({:with, _, args} = ast, prefix, idx) do
    id = "#{prefix}/with:#{idx}"
    {clauses, blocks} = split_clauses_and_blocks(args)

    with_clause_children =
      clauses
      |> Enum.with_index()
      |> Enum.map(fn {clause, i} ->
        %Node{
          id: "#{id}/clause:#{i}",
          kind: :with_clause,
          name: Macro.to_string(clause),
          meta: extract_meta(clause),
          ast: nil,
          children: [],
          collapsed: true
        }
      end)

    block_children = analyze_block_children(blocks, id)

    %Node{
      id: id,
      kind: :with_expr,
      name: "",
      meta: extract_meta(ast),
      ast: nil,
      children: with_clause_children ++ block_children,
      collapsed: true
    }
  end

  # try
  defp analyze_body_expr({:try, _, [blocks]} = ast, prefix, idx) do
    id = "#{prefix}/try:#{idx}"

    %Node{
      id: id,
      kind: :try_expr,
      name: "",
      meta: extract_meta(ast),
      ast: nil,
      children: analyze_block_children(blocks, id),
      collapsed: true
    }
  end

  # receive
  defp analyze_body_expr({:receive, _, [blocks]} = ast, prefix, idx) do
    id = "#{prefix}/receive:#{idx}"

    %Node{
      id: id,
      kind: :receive_expr,
      name: "",
      meta: extract_meta(ast),
      ast: nil,
      children: analyze_block_children(blocks, id),
      collapsed: true
    }
  end

  # for comprehension
  defp analyze_body_expr({:for, _, args} = ast, prefix, idx) do
    id = "#{prefix}/for:#{idx}"
    {generators, blocks} = split_for_args(args)

    gen_children =
      generators
      |> Enum.with_index()
      |> Enum.map(fn {gen, i} ->
        %Node{
          id: "#{id}/gen:#{i}",
          kind: :expression,
          name: Macro.to_string(gen),
          meta: extract_meta(gen),
          ast: nil,
          children: [],
          collapsed: true
        }
      end)

    block_children = analyze_block_children(blocks, id)

    %Node{
      id: id,
      kind: :for_expr,
      name: "",
      meta: extract_meta(ast),
      ast: nil,
      children: gen_children ++ block_children,
      collapsed: true
    }
  end

  # fn
  defp analyze_body_expr({:fn, _, clauses} = ast, prefix, idx) do
    id = "#{prefix}/fn:#{idx}"

    %Node{
      id: id,
      kind: :fn_expr,
      name: "",
      meta: extract_meta(ast),
      ast: nil,
      children: analyze_clauses(clauses, id),
      collapsed: true
    }
  end

  # Fallback — leaf expression
  defp analyze_body_expr(ast, prefix, idx) do
    id = "#{prefix}/expr:#{idx}"

    %Node{
      id: id,
      kind: :expression,
      name: Macro.to_string(ast),
      meta: extract_meta(ast),
      ast: nil,
      children: [],
      collapsed: true
    }
  end

  # Analyze `->` clauses (used by case, cond, receive, fn, with-else)
  defp analyze_clauses(clauses, prefix) when is_list(clauses) do
    clauses
    |> Enum.with_index()
    |> Enum.map(fn {{:->, _, [patterns, body]}, i} ->
      id = "#{prefix}/clause:#{i}"
      pattern_str = Enum.map_join(patterns, ", ", &Macro.to_string/1)

      body_children = case body do
        {:__block__, _, exprs} ->
          exprs
          |> Enum.with_index()
          |> Enum.map(fn {expr, j} -> analyze_body_expr(expr, id, j) end)

        expr ->
          if structured_expr?(expr) do
            [analyze_body_expr(expr, id, 0)]
          else
            []
          end
      end

      %Node{
        id: id,
        kind: :clause,
        name: pattern_str,
        meta: %{},
        ast: if(body_children == [], do: body),
        children: body_children,
        collapsed: true
      }
    end)
  end

  defp analyze_clauses(_, _prefix), do: []

  # Analyze keyword blocks (do/else/rescue/catch/after)
  defp analyze_block_children(blocks, prefix) when is_list(blocks) do
    Enum.flat_map(blocks, fn {key, body} ->
      id = "#{prefix}/block:#{key}"

      children = case {key, body} do
        {k, clauses} when k in [:rescue, :catch] and is_list(clauses) ->
          analyze_clauses(clauses, id)

        {_k, clauses} when is_list(clauses) ->
          # do: [clause1, clause2] — list of -> clauses (e.g., receive/case do block)
          if match?([{:->, _, _} | _], clauses) do
            analyze_clauses(clauses, id)
          else
            clauses
            |> Enum.with_index()
            |> Enum.map(fn {expr, j} -> analyze_body_expr(expr, id, j) end)
          end

        {_k, {:__block__, _, exprs}} ->
          exprs
          |> Enum.with_index()
          |> Enum.map(fn {expr, j} -> analyze_body_expr(expr, id, j) end)

        {_k, nil} ->
          []

        {_k, expr} ->
          if structured_expr?(expr) do
            [analyze_body_expr(expr, id, 0)]
          else
            [%Node{
              id: "#{id}/expr:0",
              kind: :expression,
              name: Macro.to_string(expr),
              meta: extract_meta(expr),
              ast: nil,
              children: [],
              collapsed: true
            }]
          end
      end

      if children == [] do
        []
      else
        [%Node{
          id: id,
          kind: :block,
          name: "#{key}",
          meta: %{},
          ast: nil,
          children: children,
          collapsed: true
        }]
      end
    end)
  end

  defp analyze_block_children(_, _prefix), do: []

  # Flatten nested pipe operators into a list of steps
  defp flatten_pipe({:|>, _, [left, right]}) do
    flatten_pipe(left) ++ [right]
  end

  defp flatten_pipe(other), do: [other]

  # Split args into {non-block items, keyword blocks} for with/for expressions.
  # The last element(s) that are keyword lists with keys like :do, :else, etc. are blocks.
  defp split_clauses_and_blocks(args) do
    case List.pop_at(args, -1) do
      {last, rest} when is_list(last) and last != [] ->
        if Keyword.keyword?(last) and Keyword.has_key?(last, :do) do
          {rest, last}
        else
          {args, []}
        end

      _ ->
        {args, []}
    end
  end

  # Split `for` comprehension args into {generators, keyword_blocks}
  defp split_for_args(args) do
    case List.pop_at(args, -1) do
      {last, rest} when is_list(last) and last != [] ->
        if Keyword.keyword?(last) and Keyword.has_key?(last, :do) do
          # Check if the item before last is also a keyword list (like [reduce: []])
          case List.pop_at(rest, -1) do
            {penult, rest2} when is_list(penult) and penult != [] ->
              if Keyword.keyword?(penult) do
                {rest2, penult ++ last}
              else
                {rest, last}
              end

            _ ->
              {rest, last}
          end
        else
          {args, []}
        end

      _ ->
        {args, []}
    end
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
        %Node{clause | name: clause_label(clause.ast), id: "#{id}:clause:#{i}"}
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

  # Extract a readable clause signature from the def AST
  defp clause_label({_def_kind, _, [{:when, _, [{name, _, args}, guard]} | _]}) do
    args_str = args_to_string(args)
    guard_str = Macro.to_string(guard)
    "#{name}(#{args_str}) when #{guard_str}"
  end

  defp clause_label({_def_kind, _, [{name, _, args} | _]}) do
    args_str = args_to_string(args)
    "#{name}(#{args_str})"
  end

  defp clause_label(_), do: "?"

  defp args_to_string(nil), do: ""
  defp args_to_string([]), do: ""

  defp args_to_string(args) when is_list(args) do
    Enum.map_join(args, ", ", fn arg ->
      Macro.to_string(arg)
    end)
  end

  defp typespec_label(nil), do: ""

  defp typespec_label([value]) do
    Macro.to_string(value)
  end

  defp typespec_label(_), do: ""

  defp struct_label(fields) when is_list(fields) do
    parts =
      Enum.map(fields, fn
        {key, value} when is_atom(key) -> "#{key}: #{Macro.to_string(value)}"
        key when is_atom(key) -> "#{key}"
        other -> Macro.to_string(other)
      end)

    Enum.join(parts, ", ")
  end

  defp struct_label(_), do: ""

  defp attribute_label(attr_name, nil), do: "#{attr_name}"

  defp attribute_label(attr_name, [value]) do
    "#{attr_name} #{Macro.to_string(value)}"
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

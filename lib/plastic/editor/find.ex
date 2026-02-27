defmodule Plastic.Editor.Find do
  @moduledoc false

  alias Sourceror.Zipper

  @doc """
  Find a defmodule node by its module name string (e.g. "Foo.Bar").
  Accepts either a zipper or source string.
  Returns {:ok, zipper_at_node} or :error.
  """
  def module(source, module_name) when is_binary(source) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      zipper = ast |> Zipper.zip()
      module(zipper, module_name)
    end
  end

  def module(%Zipper{} = zipper, module_name) do
    result =
      zipper
      |> Zipper.find(fn
        {:defmodule, _, [{:__aliases__, _, parts}, _]} ->
          Enum.map_join(parts, ".", &to_string/1) == module_name

        _ ->
          false
      end)

    if result, do: {:ok, result}, else: :error
  end

  @doc """
  Find the first def/defp matching fun_name and arity within a module.
  Returns {:ok, zipper_at_node} or :error.
  """
  def function(source, module_name, fun_name, arity) when is_binary(source) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      zipper = ast |> Zipper.zip()
      function(zipper, module_name, fun_name, arity)
    end
  end

  def function(%Zipper{} = zipper, module_name, fun_name, arity) do
    fun_atom = ensure_atom(fun_name)

    with {:ok, mod_zipper} <- module(zipper, module_name) do
      result =
        mod_zipper
        |> Zipper.find(fn node -> match_function?(node, fun_atom, arity) end)

      if result, do: {:ok, result}, else: :error
    end
  end

  @doc """
  Find all clauses (def/defp heads) for fun_name/arity within a module.
  Returns a list of zipper positions (may be empty).
  """
  def function_clauses(source, module_name, fun_name, arity) when is_binary(source) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      zipper = ast |> Zipper.zip()
      function_clauses(zipper, module_name, fun_name, arity)
    end
  end

  def function_clauses(%Zipper{} = zipper, module_name, fun_name, arity) do
    fun_atom = ensure_atom(fun_name)

    with {:ok, mod_zipper} <- module(zipper, module_name) do
      collect_all(mod_zipper, fn node -> match_function?(node, fun_atom, arity) end)
    else
      _ -> []
    end
  end

  @doc """
  Find the nth clause (0-indexed) for fun_name/arity within a module.
  Returns {:ok, zipper_at_node} or :error.
  """
  def function_clause(source, module_name, fun_name, arity, index) when is_binary(source) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      zipper = ast |> Zipper.zip()
      function_clause(zipper, module_name, fun_name, arity, index)
    end
  end

  def function_clause(%Zipper{} = zipper, module_name, fun_name, arity, index) do
    clauses = function_clauses(zipper, module_name, fun_name, arity)

    if index >= 0 and index < length(clauses) do
      {:ok, Enum.at(clauses, index)}
    else
      :error
    end
  end

  @doc """
  Find the last expression in a module's body.
  Returns {:ok, zipper_at_node} or :error.
  """
  def last_in_module(source, module_name) when is_binary(source) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      zipper = ast |> Zipper.zip()
      last_in_module(zipper, module_name)
    end
  end

  def last_in_module(%Zipper{} = zipper, module_name) do
    with {:ok, mod_zipper} <- module(zipper, module_name) do
      body = extract_module_body(Zipper.node(mod_zipper))

      case body do
        {:__block__, _, children} when is_list(children) and children != [] ->
          last = List.last(children)
          result =
            mod_zipper
            |> Zipper.find(fn node -> node == last end)

          if result, do: {:ok, result}, else: :error

        nil ->
          :error

        single_expr ->
          result =
            mod_zipper
            |> Zipper.find(fn node -> node == single_expr end)

          if result, do: {:ok, result}, else: :error
      end
    end
  end

  @doc """
  Find a case expression by function context and optional index.
  opts:
    - module_name: required
    - fun_name: required
    - arity: required
    - index: which case expr (0-indexed, default 0)
  Returns {:ok, zipper_at_node} or :error.
  """
  def case_expr(source, opts) when is_binary(source) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      zipper = ast |> Zipper.zip()
      case_expr(zipper, opts)
    end
  end

  def case_expr(%Zipper{} = zipper, opts) do
    module_name = Keyword.fetch!(opts, :module_name)
    fun_name = ensure_atom(Keyword.fetch!(opts, :fun_name))
    arity = Keyword.fetch!(opts, :arity)
    index = Keyword.get(opts, :index, 0)

    with {:ok, fun_zipper} <- function(%Zipper{} = zipper, module_name, fun_name, arity) do
      cases = collect_all(fun_zipper, fn
        {:case, _, [_, _]} -> true
        _ -> false
      end)

      if index >= 0 and index < length(cases) do
        {:ok, Enum.at(cases, index)}
      else
        :error
      end
    end
  end

  @doc """
  Find an @attribute by name within a module.
  Returns {:ok, zipper_at_node} or :error.
  """
  def attribute(source, module_name, attr_name) when is_binary(source) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      zipper = ast |> Zipper.zip()
      attribute(zipper, module_name, attr_name)
    end
  end

  def attribute(%Zipper{} = zipper, module_name, attr_name) do
    attr_atom = ensure_atom(attr_name)

    with {:ok, mod_zipper} <- module(zipper, module_name) do
      result =
        mod_zipper
        |> Zipper.find(fn
          {:@, _, [{^attr_atom, _, _}]} -> true
          _ -> false
        end)

      if result, do: {:ok, result}, else: :error
    end
  end

  @doc """
  Find a directive (use/import/alias/require) by kind and target module within a module.
  Returns {:ok, zipper_at_node} or :error.
  """
  def directive(source, module_name, kind, target) when is_binary(source) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      zipper = ast |> Zipper.zip()
      directive(zipper, module_name, kind, target)
    end
  end

  def directive(%Zipper{} = zipper, module_name, kind, target) do
    kind_atom = ensure_atom(kind)
    target_str = to_string(target)

    with {:ok, mod_zipper} <- module(zipper, module_name) do
      result =
        mod_zipper
        |> Zipper.find(fn
          {^kind_atom, _, [{:__aliases__, _, parts} | _]} ->
            Enum.map_join(parts, ".", &to_string/1) == target_str

          _ ->
            false
        end)

      if result, do: {:ok, result}, else: :error
    end
  end

  # --- Private helpers ---

  # Sourceror wraps do blocks as keyword lists: [{:do_block, body}]
  # Standard Elixir AST uses [do: body]
  defp extract_module_body({:defmodule, _, [_, [{_, body}]]}) do
    body
  end

  defp extract_module_body({:defmodule, _, [_, [do: body]]}) do
    body
  end

  defp extract_module_body(_), do: nil

  defp match_function?(node, fun_atom, arity) do
    case node do
      {def_kind, _, [{:when, _, [{^fun_atom, _, args} | _]} | _]}
      when def_kind in [:def, :defp, :defmacro, :defmacrop] ->
        args_arity(args) == arity

      {def_kind, _, [{^fun_atom, _, args} | _]}
      when def_kind in [:def, :defp, :defmacro, :defmacrop] ->
        args_arity(args) == arity

      _ ->
        false
    end
  end

  defp args_arity(nil), do: 0
  defp args_arity(args) when is_list(args), do: length(args)

  defp ensure_atom(name) when is_atom(name), do: name
  defp ensure_atom(name) when is_binary(name), do: String.to_atom(name)

  defp collect_all(zipper, pred) do
    do_collect(zipper, pred, [])
  end

  defp do_collect(nil, _pred, acc), do: Enum.reverse(acc)

  defp do_collect(zipper, pred, acc) do
    node = Zipper.node(zipper)
    acc = if pred.(node), do: [zipper | acc], else: acc

    case Zipper.next(zipper) do
      nil -> Enum.reverse(acc)
      next_z ->
        if next_z == zipper do
          Enum.reverse(acc)
        else
          do_collect(next_z, pred, acc)
        end
    end
  end
end

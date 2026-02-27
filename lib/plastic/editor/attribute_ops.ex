defmodule Plastic.Editor.AttributeOps do
  @moduledoc false

  alias Plastic.Editor.Find
  alias Sourceror.Zipper

  @doc """
  Add an attribute expression at the end of a module body.
  attr_code should be like `@my_attr 42`.
  """
  def add_attribute(source, module_name, attr_code) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         zipper <- Zipper.zip(ast),
         {:ok, last_zipper} <- Find.last_in_module(zipper, module_name) do
      last_node = Zipper.node(last_zipper)
      range = Sourceror.get_range(last_node)
      end_pos = range.end

      insert_range = %{start: end_pos, end: end_pos}
      patch = %{range: insert_range, change: "\n\n  #{attr_code}"}
      {:ok, Sourceror.patch_string(source, [patch])}
    end
  end

  @doc """
  Remove an @attribute from a module.
  """
  def remove_attribute(source, module_name, attr_name) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         zipper <- Zipper.zip(ast),
         {:ok, attr_zipper} <- Find.attribute(zipper, module_name, attr_name) do
      node = Zipper.node(attr_zipper)
      range = Sourceror.get_range(node)
      patch = %{range: range, change: ""}
      result = Sourceror.patch_string(source, [patch])
      {:ok, Plastic.Editor.cleanup_blank_lines(result)}
    end
  end

  @doc """
  Add a `use` directive at the beginning of a module body.
  """
  def add_use(source, module_name, target) do
    add_directive_at_beginning(source, module_name, "use #{target}")
  end

  @doc """
  Add an `import` directive at the beginning of a module body.
  """
  def add_import(source, module_name, target) do
    add_directive_at_beginning(source, module_name, "import #{target}")
  end

  @doc """
  Add an `alias` directive at the beginning of a module body.
  """
  def add_alias(source, module_name, target) do
    add_directive_at_beginning(source, module_name, "alias #{target}")
  end

  @doc """
  Remove a directive (use/import/alias/require) from a module.
  """
  def remove_directive(source, module_name, kind, target) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         zipper <- Zipper.zip(ast),
         {:ok, dir_zipper} <- Find.directive(zipper, module_name, kind, target) do
      node = Zipper.node(dir_zipper)
      range = Sourceror.get_range(node)
      patch = %{range: range, change: ""}
      result = Sourceror.patch_string(source, [patch])
      {:ok, Plastic.Editor.cleanup_blank_lines(result)}
    end
  end

  # --- Private ---

  # Insert a directive after the module's `do` keyword (before the first expression)
  defp add_directive_at_beginning(source, module_name, directive_code) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         zipper <- Zipper.zip(ast),
         {:ok, mod_zipper} <- Find.module(zipper, module_name) do
      mod_node = Zipper.node(mod_zipper)
      body = extract_body(mod_node)

      case body do
        {:__block__, _, [first_expr | _]} ->
          range = Sourceror.get_range(first_expr)
          start_pos = range.start

          insert_range = %{start: start_pos, end: start_pos}
          patch = %{range: insert_range, change: "#{directive_code}\n  "}
          {:ok, Sourceror.patch_string(source, [patch])}

        nil ->
          # Empty module — insert after `do`
          mod_range = Sourceror.get_range(mod_node)
          # Just insert after the module alias on the first line
          # For an empty module like `defmodule Foo do\nend`, we insert after `do`
          insert_at = %{
            start: [line: mod_range.start[:line], column: mod_range.end[:column]],
            end: [line: mod_range.start[:line], column: mod_range.end[:column]]
          }
          patch = %{range: insert_at, change: "\n  #{directive_code}\n"}
          {:ok, Sourceror.patch_string(source, [patch])}

        single_expr ->
          range = Sourceror.get_range(single_expr)
          start_pos = range.start

          insert_range = %{start: start_pos, end: start_pos}
          patch = %{range: insert_range, change: "#{directive_code}\n  "}
          {:ok, Sourceror.patch_string(source, [patch])}
      end
    end
  end

  defp extract_body({:defmodule, _, [_, [{_, body}]]}), do: body
  defp extract_body({:defmodule, _, [_, [do: body]]}), do: body
  defp extract_body(_), do: nil
end

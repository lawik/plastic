defmodule Plastic.Editor.ModuleOps do
  @moduledoc false

  alias Plastic.Editor.Find

  @doc """
  Append a new defmodule to the source.
  Simple string concat — no AST manipulation needed.
  """
  def add_module(source, name, opts \\ []) do
    body = Keyword.get(opts, :body, "")

    new_module =
      if body == "" do
        "\ndefmodule #{name} do\nend\n"
      else
        "\ndefmodule #{name} do\n  #{body}\nend\n"
      end

    {:ok, source <> new_module}
  end

  @doc """
  Rename a module by patching the alias node inside defmodule.
  """
  def rename_module(source, old_name, new_name) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         zipper <- Sourceror.Zipper.zip(ast),
         {:ok, mod_zipper} <- Find.module(zipper, old_name) do
      {:defmodule, _, [alias_node, _]} = Sourceror.Zipper.node(mod_zipper)
      range = Sourceror.get_range(alias_node)

      patch = %{range: range, change: new_name}
      {:ok, Sourceror.patch_string(source, [patch])}
    end
  end

  @doc """
  Remove an entire defmodule from source.
  """
  def remove_module(source, name) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         zipper <- Sourceror.Zipper.zip(ast),
         {:ok, mod_zipper} <- Find.module(zipper, name) do
      mod_node = Sourceror.Zipper.node(mod_zipper)
      range = Sourceror.get_range(mod_node)

      patch = %{range: range, change: ""}
      result = Sourceror.patch_string(source, [patch])
      {:ok, Plastic.Editor.cleanup_blank_lines(result)}
    end
  end
end

defmodule Plastic.Project do
  @moduledoc false

  defstruct [:root_path, :name]

  @type t :: %__MODULE__{
          root_path: String.t(),
          name: String.t()
        }

  def open(path) do
    path = Path.expand(path)

    if File.exists?(Path.join(path, "mix.exs")) do
      {:ok, %__MODULE__{root_path: path, name: Path.basename(path)}}
    else
      {:error, :not_a_mix_project}
    end
  end

  def list_source_files(%__MODULE__{root_path: root}) do
    Path.join(root, "lib/**/*.{ex,exs}")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(fn abs ->
      %{path: Path.relative_to(abs, root), absolute_path: abs}
    end)
  end

  def file_tree(%__MODULE__{} = project) do
    project
    |> list_source_files()
    |> Enum.reduce(%{}, fn %{path: path}, tree ->
      parts = Path.split(path)
      put_in_tree(tree, parts)
    end)
  end

  defp put_in_tree(tree, [file]) do
    Map.put(tree, file, :file)
  end

  defp put_in_tree(tree, [dir | rest]) do
    subtree = Map.get(tree, dir, %{})
    Map.put(tree, dir, put_in_tree(subtree, rest))
  end
end

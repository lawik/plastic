defmodule Plastic.AST.Block.Moduledoc do
  @moduledoc false
  @behaviour Plastic.AST.Block

  alias Plastic.AST.Node

  @impl true
  def match([%Node{kind: :attribute, meta: %{attr_name: :moduledoc}} = node | rest]) do
    name = strip_attr_prefix(node.name, "moduledoc")
    {:ok, %Node{node | kind: :moduledoc, name: name}, rest}
  end

  def match(_nodes), do: :skip

  defp strip_attr_prefix(name, prefix) do
    case String.trim_leading(name, prefix) do
      "" -> ""
      " " <> value -> value
      other -> other
    end
  end
end

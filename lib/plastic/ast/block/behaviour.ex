defmodule Plastic.AST.Block.Behaviour do
  @moduledoc false
  @behaviour Plastic.AST.Block

  alias Plastic.AST.Node

  @impl true
  def match([%Node{kind: :attribute, meta: %{attr_name: :behaviour}} = node | rest]) do
    name = strip_attr_prefix(node.name, "behaviour")
    {:ok, %Node{node | kind: :behaviour, name: name}, rest}
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

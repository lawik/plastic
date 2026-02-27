defmodule Plastic.AST.Block.Moduledoc do
  @moduledoc false
  @behaviour Plastic.AST.Block

  alias Plastic.AST.Node

  @impl true
  def match([%Node{kind: :attribute, meta: %{attr_name: :moduledoc}, ast: ast} = node | rest]) do
    name = strip_attr_prefix(node.name, "moduledoc")
    doc_text = extract_doc_text(ast)
    meta = Map.put(node.meta, :doc_text, doc_text)
    {:ok, %Node{node | kind: :moduledoc, name: name, meta: meta}, rest}
  end

  def match(_nodes), do: :skip

  defp strip_attr_prefix(name, prefix) do
    case String.trim_leading(name, prefix) do
      "" -> ""
      " " <> value -> value
      other -> other
    end
  end

  defp extract_doc_text({:@, _, [{:moduledoc, _, [text]}]}) when is_binary(text), do: text
  defp extract_doc_text(_), do: nil
end

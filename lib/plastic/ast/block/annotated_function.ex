defmodule Plastic.AST.Block.AnnotatedFunction do
  @moduledoc false
  @behaviour Plastic.AST.Block

  alias Plastic.AST.Node

  @annotation_attrs [:doc, :spec, :impl]

  @impl true
  def match(nodes) do
    case collect_annotations(nodes, %{}) do
      {annotations, [%Node{kind: kind} = fun_node | rest]}
      when kind in [:function, :function_clause] and map_size(annotations) > 0 ->
        new_kind = if Map.has_key?(annotations, :impl), do: :callback_impl, else: kind
        merged_meta = Map.put(fun_node.meta, :annotations, annotations)
        {:ok, %Node{fun_node | kind: new_kind, meta: merged_meta}, rest}

      _ ->
        :skip
    end
  end

  defp collect_annotations(
         [%Node{kind: kind, meta: %{attr_name: attr_name}} = node | rest],
         acc
       )
       when kind in [:attribute, :typespec] and attr_name in @annotation_attrs do
    collect_annotations(rest, Map.put(acc, attr_name, node))
  end

  defp collect_annotations(rest, acc), do: {acc, rest}
end

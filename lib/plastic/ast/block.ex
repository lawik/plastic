defmodule Plastic.AST.Block do
  @moduledoc false

  alias Plastic.AST.Node

  @doc """
  Try to match a higher-level block pattern at the head of a node list.

  Receives the remaining list of sibling nodes. If the block recognizes a
  pattern (one or more consecutive nodes that form a logical unit), it
  returns `{:ok, block_node, remaining_nodes}`. Otherwise it returns `:skip`
  and the engine tries the next registered block.
  """
  @callback match(nodes :: [Node.t()]) :: {:ok, Node.t(), [Node.t()]} | :skip
end

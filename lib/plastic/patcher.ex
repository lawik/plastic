defmodule Plastic.Patcher do
  @moduledoc false

  def to_code(ast) do
    Sourceror.to_string(ast)
  end

  def patch(original_code, patches) do
    Sourceror.patch_string(original_code, patches)
  end
end

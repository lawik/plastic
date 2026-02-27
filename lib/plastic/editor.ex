defmodule Plastic.Editor do
  @moduledoc false

  alias Plastic.Editor.{Find, ModuleOps, FunctionOps, CaseOps, AttributeOps}

  def parse(source) do
    Sourceror.parse_string(source)
  end

  def to_source(ast) do
    Sourceror.to_string(ast)
  end

  # Module operations
  defdelegate add_module(source, name, opts \\ []), to: ModuleOps
  defdelegate rename_module(source, old_name, new_name), to: ModuleOps
  defdelegate remove_module(source, name), to: ModuleOps

  # Function operations
  defdelegate add_function(source, module_name, fun_code), to: FunctionOps
  defdelegate rename_function(source, module_name, old_name, arity, new_name), to: FunctionOps
  defdelegate remove_function(source, module_name, fun_name, arity), to: FunctionOps
  defdelegate add_function_head(source, module_name, fun_name, arity, head_code), to: FunctionOps
  defdelegate update_function(source, module_name, fun_name, arity, new_code), to: FunctionOps
  defdelegate remove_function_head(source, module_name, fun_name, arity, index), to: FunctionOps

  # Case operations
  defdelegate add_case_clause(source, opts), to: CaseOps
  defdelegate remove_case_clause(source, opts), to: CaseOps
  defdelegate update_case_clause(source, opts), to: CaseOps

  # Attribute operations
  defdelegate add_attribute(source, module_name, attr_code), to: AttributeOps
  defdelegate remove_attribute(source, module_name, attr_name), to: AttributeOps
  defdelegate add_use(source, module_name, target), to: AttributeOps
  defdelegate add_import(source, module_name, target), to: AttributeOps
  defdelegate add_alias(source, module_name, target), to: AttributeOps
  defdelegate remove_directive(source, module_name, kind, target), to: AttributeOps

  # Find operations
  defdelegate find_module(source_or_zipper, module_name), to: Find, as: :module
  defdelegate find_function(source_or_zipper, module_name, fun_name, arity), to: Find, as: :function

  @doc """
  Remove excessive blank lines (3+ consecutive newlines become 2).
  """
  def cleanup_blank_lines(source) do
    String.replace(source, ~r/\n{3,}/, "\n\n")
  end
end

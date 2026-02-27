defmodule Plastic.Editor.Operations do
  @moduledoc false

  @doc """
  Returns the list of applicable operations for a given node kind.
  Each operation is a map with :name, :label, :description, and :applies_to.
  """
  def applicable_operations(node_kind) do
    all_operations()
    |> Enum.filter(fn op -> node_kind in op.applies_to end)
  end

  @doc """
  Returns all defined operations.
  """
  def all_operations do
    [
      # Module operations
      %{
        name: :add_module,
        label: "Add Module",
        description: "Add a new module",
        applies_to: [:module]
      },
      %{
        name: :rename_module,
        label: "Rename Module",
        description: "Rename this module",
        applies_to: [:module]
      },
      %{
        name: :remove_module,
        label: "Remove Module",
        description: "Remove this module",
        applies_to: [:module]
      },

      # Function operations
      %{
        name: :add_function,
        label: "Add Function",
        description: "Add a new function to the module",
        applies_to: [:module, :function]
      },
      %{
        name: :rename_function,
        label: "Rename Function",
        description: "Rename this function",
        applies_to: [:function]
      },
      %{
        name: :remove_function,
        label: "Remove Function",
        description: "Remove this function and all its clauses",
        applies_to: [:function]
      },
      %{
        name: :update_function,
        label: "Update Function",
        description: "Replace this function with new code",
        applies_to: [:function]
      },

      # Function clause operations
      %{
        name: :add_function_head,
        label: "Add Clause",
        description: "Add a new clause to this function",
        applies_to: [:function, :function_clause]
      },
      %{
        name: :remove_function_head,
        label: "Remove Clause",
        description: "Remove this function clause",
        applies_to: [:function_clause]
      },

      # Case operations
      %{
        name: :add_case_clause,
        label: "Add Clause",
        description: "Add a new clause to this case expression",
        applies_to: [:case_expr]
      },
      %{
        name: :remove_case_clause,
        label: "Remove Clause",
        description: "Remove this case clause",
        applies_to: [:clause]
      },
      %{
        name: :update_case_clause,
        label: "Update Clause",
        description: "Update this case clause",
        applies_to: [:clause]
      },

      # Attribute operations
      %{
        name: :add_attribute,
        label: "Add Attribute",
        description: "Add a module attribute",
        applies_to: [:module, :attribute]
      },
      %{
        name: :remove_attribute,
        label: "Remove Attribute",
        description: "Remove this attribute",
        applies_to: [:attribute, :moduledoc]
      },

      # Directive operations
      %{
        name: :add_use,
        label: "Add use",
        description: "Add a use directive",
        applies_to: [:module, :use]
      },
      %{
        name: :add_import,
        label: "Add import",
        description: "Add an import directive",
        applies_to: [:module, :import]
      },
      %{
        name: :add_alias,
        label: "Add alias",
        description: "Add an alias directive",
        applies_to: [:module, :alias]
      },
      %{
        name: :remove_directive,
        label: "Remove Directive",
        description: "Remove this directive",
        applies_to: [:use, :import, :alias, :require]
      }
    ]
  end
end

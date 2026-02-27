defmodule Plastic.ASTTest do
  use ExUnit.Case, async: true

  alias Plastic.AST
  alias Plastic.AST.Node
  alias Plastic.Parser

  defp analyze(code) do
    {:ok, ast} = Parser.parse_string(code)
    AST.analyze(ast)
  end

  describe "analyze/1 modules" do
    test "identifies a simple module" do
      nodes = analyze("defmodule Foo do\nend")

      assert [%Node{kind: :module, name: "Foo"}] = nodes
    end

    test "identifies nested module name" do
      nodes = analyze("defmodule Foo.Bar.Baz do\nend")

      assert [%Node{kind: :module, name: "Foo.Bar.Baz"}] = nodes
    end

    test "identifies multiple top-level modules" do
      nodes =
        analyze("""
        defmodule Foo do
        end

        defmodule Bar do
        end
        """)

      assert [%Node{kind: :module, name: "Foo"}, %Node{kind: :module, name: "Bar"}] = nodes
    end
  end

  describe "analyze/1 functions" do
    test "identifies def and defp" do
      nodes =
        analyze("""
        defmodule Foo do
          def public_fun, do: :ok
          defp private_fun, do: :ok
        end
        """)

      [%Node{children: children}] = nodes
      assert [
        %Node{kind: :function, name: "public_fun/0", meta: %{def_kind: :def}},
        %Node{kind: :function, name: "private_fun/0", meta: %{def_kind: :defp}}
      ] = children
    end

    test "identifies function arity" do
      nodes =
        analyze("""
        defmodule Foo do
          def zero_arity, do: :ok
          def two_arity(a, b), do: {a, b}
        end
        """)

      [%Node{children: children}] = nodes
      assert [%Node{name: "zero_arity/0"}, %Node{name: "two_arity/2"}] = children
    end

    test "groups multiple clauses of the same function" do
      nodes =
        analyze("""
        defmodule Foo do
          def bar(:a), do: 1
          def bar(:b), do: 2
          def bar(:c), do: 3
        end
        """)

      [%Node{children: children}] = nodes
      assert [%Node{kind: :function, name: "bar/1", children: clauses}] = children
      assert length(clauses) == 3
      assert Enum.all?(clauses, &(&1.kind == :function_clause))
    end

    test "does not group different functions together" do
      nodes =
        analyze("""
        defmodule Foo do
          def bar, do: 1
          def baz, do: 2
        end
        """)

      [%Node{children: children}] = nodes
      assert [%Node{name: "bar/0"}, %Node{name: "baz/0"}] = children
    end

    test "does not group same name with different arity" do
      nodes =
        analyze("""
        defmodule Foo do
          def bar, do: 1
          def bar(x), do: x
        end
        """)

      [%Node{children: children}] = nodes
      assert [%Node{name: "bar/0"}, %Node{name: "bar/1"}] = children
    end

    test "handles function with when guard" do
      nodes =
        analyze("""
        defmodule Foo do
          def bar(x) when is_integer(x), do: x
        end
        """)

      [%Node{children: children}] = nodes
      assert [%Node{kind: :function, name: "bar/1"}] = children
    end
  end

  describe "analyze/1 attributes" do
    test "identifies module attributes" do
      nodes =
        analyze("""
        defmodule Foo do
          @moduledoc "hello"
          @custom_attr 42
        end
        """)

      [%Node{children: children}] = nodes
      assert [%Node{kind: :moduledoc, name: "\"hello\""}, %Node{kind: :attribute, name: "custom_attr 42"}] = children
    end

    test "identifies typespecs" do
      nodes =
        analyze("""
        defmodule Foo do
          @type t :: :ok
          @spec bar() :: :ok
          @callback baz(integer()) :: :ok
        end
        """)

      [%Node{children: children}] = nodes
      kinds = Enum.map(children, & &1.kind)
      assert kinds == [:typespec, :typespec, :typespec]
    end
  end

  describe "analyze/1 directives" do
    test "identifies use, import, alias, require" do
      nodes =
        analyze("""
        defmodule Foo do
          use GenServer
          import Enum
          alias Foo.Bar
          require Logger
        end
        """)

      [%Node{children: children}] = nodes
      kinds = Enum.map(children, & &1.kind)
      assert kinds == [:use, :import, :alias, :require]
      names = Enum.map(children, & &1.name)
      assert names == ["GenServer", "Enum", "Foo.Bar", "Logger"]
    end
  end

  describe "analyze/1 mixed content" do
    test "handles a realistic module with attributes, use, and functions" do
      nodes =
        analyze("""
        defmodule MyApp.Worker do
          @moduledoc false

          use GenServer

          @impl true
          def start(_type, _args) do
            children = []
            opts = [strategy: :one_for_one]
            Supervisor.start_link(children, opts)
          end

          @impl true
          def config_change(changed, _new, removed) do
            :ok
          end
        end
        """)

      [%Node{kind: :module, name: "MyApp.Worker", children: children}] = nodes
      kinds = Enum.map(children, & &1.kind)
      assert :moduledoc in kinds
      assert :use in kinds
      assert :callback_impl in kinds
    end

    test "handles application.ex style module" do
      # This is the pattern that was crashing
      nodes =
        analyze("""
        defmodule Plastic.Application do
          @moduledoc false

          use Application

          @impl true
          def start(_type, _args) do
            children = [
              SomeModule,
              {AnotherModule, []}
            ]

            opts = [strategy: :one_for_one, name: Plastic.Supervisor]
            Supervisor.start_link(children, opts)
          end

          @impl true
          def config_change(changed, _new, removed) do
            :ok
          end
        end
        """)

      [%Node{kind: :module, name: "Plastic.Application", children: children}] = nodes

      assert length(children) > 0

      callback_nodes = Enum.filter(children, &(&1.kind == :callback_impl))
      callback_names = Enum.map(callback_nodes, & &1.name)
      assert "start/2" in callback_names
      assert "config_change/3" in callback_names
    end

    test "non-function expressions between functions don't break grouping" do
      nodes =
        analyze("""
        defmodule Foo do
          def bar(:a), do: 1
          def bar(:b), do: 2

          @doc "something"
          def baz, do: :ok
        end
        """)

      [%Node{children: children}] = nodes
      function_nodes = Enum.filter(children, &(&1.kind == :function))
      assert length(function_nodes) == 2
    end
  end

  describe "analyze/1 node IDs" do
    test "all nodes have unique IDs" do
      nodes =
        analyze("""
        defmodule Foo do
          use Bar
          @attr 1
          def baz, do: :ok
          def qux(x), do: x
        end
        """)

      ids = collect_ids(nodes)
      assert length(ids) == length(Enum.uniq(ids))
    end

    test "node IDs are stable strings" do
      nodes = analyze("defmodule Foo do\n  def bar, do: :ok\nend")

      [%Node{id: mod_id, children: [%Node{id: fn_id}]}] = nodes
      assert is_binary(mod_id)
      assert is_binary(fn_id)
    end
  end

  describe "analyze/1 edge cases" do
    test "handles empty module body" do
      nodes = analyze("defmodule Foo do\nend")
      assert [%Node{kind: :module, children: []}] = nodes
    end

    test "handles top-level expression (no module)" do
      nodes = analyze("IO.puts(\"hello\")")
      assert [%Node{kind: :expression}] = nodes
    end
  end

  describe "blocks — moduledoc" do
    test "@moduledoc becomes :moduledoc kind with just the value as name" do
      nodes =
        analyze("""
        defmodule Foo do
          @moduledoc "some docs"
        end
        """)

      [%Node{children: [%Node{kind: :moduledoc, name: "\"some docs\""}]}] = nodes
    end

    test "@moduledoc false is also :moduledoc" do
      nodes =
        analyze("""
        defmodule Foo do
          @moduledoc false
        end
        """)

      [%Node{children: [%Node{kind: :moduledoc, name: "false"}]}] = nodes
    end

    test "other attributes remain :attribute" do
      nodes =
        analyze("""
        defmodule Foo do
          @custom 42
        end
        """)

      [%Node{children: [%Node{kind: :attribute}]}] = nodes
    end
  end

  describe "blocks — behaviour" do
    test "@behaviour becomes :behaviour kind with module as name" do
      nodes =
        analyze("""
        defmodule Foo do
          @behaviour GenServer
        end
        """)

      [%Node{children: [%Node{kind: :behaviour, name: "GenServer"}]}] = nodes
    end

    test "multiple behaviours are each recognized" do
      nodes =
        analyze("""
        defmodule Foo do
          @behaviour GenServer
          @behaviour Supervisor
        end
        """)

      [%Node{children: children}] = nodes
      assert [%Node{kind: :behaviour, name: "GenServer"}, %Node{kind: :behaviour, name: "Supervisor"}] = children
    end
  end

  describe "blocks — annotated function" do
    test "@doc is folded into the function" do
      nodes =
        analyze("""
        defmodule Foo do
          @doc "Does a thing."
          def bar, do: :ok
        end
        """)

      [%Node{children: [%Node{kind: :function, name: "bar/0", meta: meta}]}] = nodes
      assert %{annotations: %{doc: %Node{kind: :attribute}}} = meta
    end

    test "@spec is folded into the function" do
      nodes =
        analyze("""
        defmodule Foo do
          @spec bar() :: :ok
          def bar, do: :ok
        end
        """)

      [%Node{children: [%Node{kind: :function, name: "bar/0", meta: meta}]}] = nodes
      assert %{annotations: %{spec: %Node{kind: :typespec}}} = meta
    end

    test "@doc + @spec + def are all folded together" do
      nodes =
        analyze("""
        defmodule Foo do
          @doc "Does a thing."
          @spec bar() :: :ok
          def bar, do: :ok
        end
        """)

      [%Node{children: [%Node{kind: :function, meta: meta}]}] = nodes
      assert %{annotations: %{doc: %Node{}, spec: %Node{}}} = meta
    end

    test "@impl + def becomes :callback_impl" do
      nodes =
        analyze("""
        defmodule Foo do
          @impl true
          def init(state), do: {:ok, state}
        end
        """)

      [%Node{children: [%Node{kind: :callback_impl, name: "init/1", meta: meta}]}] = nodes
      assert %{annotations: %{impl: %Node{}}} = meta
    end

    test "@doc + @impl + def becomes :callback_impl with doc" do
      nodes =
        analyze("""
        defmodule Foo do
          @doc "Initializes state."
          @impl true
          def init(state), do: {:ok, state}
        end
        """)

      [%Node{children: [%Node{kind: :callback_impl, name: "init/1", meta: meta}]}] = nodes
      assert %{annotations: %{doc: %Node{}, impl: %Node{}}} = meta
    end

    test "@impl + @doc + def (reversed order) also works" do
      nodes =
        analyze("""
        defmodule Foo do
          @impl true
          @doc "Initializes state."
          def init(state), do: {:ok, state}
        end
        """)

      [%Node{children: [%Node{kind: :callback_impl, name: "init/1", meta: meta}]}] = nodes
      assert %{annotations: %{doc: %Node{}, impl: %Node{}}} = meta
    end

    test "unannotated function stays :function" do
      nodes =
        analyze("""
        defmodule Foo do
          def bar, do: :ok
        end
        """)

      [%Node{children: [%Node{kind: :function, meta: meta}]}] = nodes
      refute Map.has_key?(meta, :annotations)
    end

    test "@doc folds into multi-clause function" do
      nodes =
        analyze("""
        defmodule Foo do
          @doc "Pattern matches."
          def bar(:a), do: 1
          def bar(:b), do: 2
        end
        """)

      [%Node{children: [%Node{kind: :function, name: "bar/1", meta: meta, children: clauses}]}] = nodes
      assert %{annotations: %{doc: %Node{}}} = meta
      assert length(clauses) == 2
    end

    test "standalone @doc without function stays as :attribute" do
      nodes =
        analyze("""
        defmodule Foo do
          @doc "orphan doc"
          @custom_attr 42
        end
        """)

      [%Node{children: children}] = nodes
      kinds = Enum.map(children, & &1.kind)
      assert kinds == [:attribute, :attribute]
    end
  end

  describe "defstruct module name" do
    test "defstruct label includes parent module name" do
      nodes =
        analyze("""
        defmodule MyApp.User do
          defstruct name: "", age: 0
        end
        """)

      [%Node{children: [%Node{kind: :defstruct, name: name}]}] = nodes
      assert name =~ "MyApp.User"
      assert name =~ "name:"
    end

    test "defstruct is not expandable" do
      nodes =
        analyze("""
        defmodule Foo do
          defstruct [:a, :b]
        end
        """)

      [%Node{children: [%Node{kind: :defstruct, ast: ast}]}] = nodes
      assert ast == nil
    end
  end

  describe "function body breakdown" do
    test "one-liner function has no body children" do
      nodes =
        analyze("""
        defmodule Foo do
          def bar(x) when is_integer(x), do: x * 2
        end
        """)

      [%Node{children: [%Node{kind: :function, children: []}]}] = nodes
    end

    test "multi-expression function body is broken down" do
      nodes =
        analyze("""
        defmodule Foo do
          def bar(opts) do
            name = Keyword.get(opts, :name)
            Logger.info(name)
            {:ok, name}
          end
        end
        """)

      [%Node{children: [%Node{kind: :function, children: children}]}] = nodes
      assert length(children) == 3
      assert [%Node{kind: :match}, %Node{kind: :expression}, %Node{kind: :expression}] = children
    end

    test "multi-clause function has body children per clause" do
      nodes =
        analyze("""
        defmodule Foo do
          def process(:ok) do
            x = 1
            Logger.info("ok")
            x
          end

          def process(:error) do
            Logger.error("bad")
            :error
          end
        end
        """)

      [%Node{children: [%Node{kind: :function, children: clauses}]}] = nodes
      assert length(clauses) == 2
      [clause1, clause2] = clauses
      assert length(clause1.children) == 3
      assert length(clause2.children) == 2
    end
  end

  describe "pipe breakdown" do
    test "pipe chain is flattened into steps" do
      nodes =
        analyze("""
        defmodule Foo do
          def bar(items) do
            items
            |> Enum.filter(&(&1 > 0))
            |> Enum.map(&to_string/1)
            |> Enum.join(", ")
          end
        end
        """)

      [%Node{children: [%Node{children: [%Node{kind: :pipe, children: steps}]}]}] = nodes
      assert length(steps) == 4
      assert hd(steps).name =~ "|  "
      assert Enum.at(steps, 1).name =~ "|> "
    end

    test "pipe assigned to variable wraps in match" do
      nodes =
        analyze("""
        defmodule Foo do
          def bar(items) do
            result =
              items
              |> Enum.filter(&is_integer/1)
              |> Enum.sum()

            result
          end
        end
        """)

      [%Node{children: [%Node{children: [%Node{kind: :match, children: [%Node{kind: :pipe}]}, _]}]}] = nodes
    end
  end

  describe "case breakdown" do
    test "case expression has clause children" do
      nodes =
        analyze("""
        defmodule Foo do
          def bar(x) do
            case x do
              :a -> 1
              :b -> 2
              _ -> 0
            end
          end
        end
        """)

      [%Node{children: [%Node{children: [%Node{kind: :case_expr, name: name, children: clauses}]}]}] = nodes
      assert name == "x"
      assert length(clauses) == 3
      assert Enum.all?(clauses, &(&1.kind == :clause))
    end
  end

  describe "if/unless breakdown" do
    test "if expression has do/else blocks" do
      nodes =
        analyze("""
        defmodule Foo do
          def bar(x) do
            if x > 0 do
              :positive
            else
              :non_positive
            end
          end
        end
        """)

      [%Node{children: [%Node{children: [%Node{kind: :if_expr, name: name, children: blocks}]}]}] = nodes
      assert name == "x > 0"
      block_names = Enum.map(blocks, & &1.name)
      assert "do" in block_names
      assert "else" in block_names
    end
  end

  describe "with breakdown" do
    test "with expression has clause and block children" do
      nodes =
        analyze("""
        defmodule Foo do
          def bar(x) do
            with {:ok, a} <- fetch(x),
                 {:ok, b} <- process(a) do
              {:ok, b}
            else
              {:error, r} -> {:error, r}
            end
          end
        end
        """)

      [%Node{children: [%Node{children: [%Node{kind: :with_expr, name: "", children: children}]}]}] = nodes
      with_clauses = Enum.filter(children, &(&1.kind == :with_clause))
      blocks = Enum.filter(children, &(&1.kind == :block))
      assert length(with_clauses) == 2
      assert length(blocks) == 2
    end
  end

  describe "try breakdown" do
    test "try expression has do/rescue/after blocks" do
      nodes =
        analyze("""
        defmodule Foo do
          def bar(x) do
            try do
              risky(x)
            rescue
              RuntimeError -> :error
            after
              cleanup()
            end
          end
        end
        """)

      [%Node{children: [%Node{children: [%Node{kind: :try_expr, name: "", children: blocks}]}]}] = nodes
      block_names = Enum.map(blocks, & &1.name)
      assert "do" in block_names
      assert "rescue" in block_names
      assert "after" in block_names
    end
  end

  describe "receive breakdown" do
    test "receive expression has do/after blocks" do
      nodes =
        analyze("""
        defmodule Foo do
          def bar do
            receive do
              {:msg, data} -> data
              :ping -> :pong
            after
              5000 -> :timeout
            end
          end
        end
        """)

      [%Node{children: [%Node{children: [%Node{kind: :receive_expr, name: "", children: blocks}]}]}] = nodes
      block_names = Enum.map(blocks, & &1.name)
      assert "do" in block_names
      assert "after" in block_names
    end
  end

  describe "for breakdown" do
    test "for comprehension has generator and block children" do
      nodes =
        analyze("""
        defmodule Foo do
          def bar(items) do
            for item <- items,
                item != nil do
              item * 2
            end
          end
        end
        """)

      [%Node{children: [%Node{children: [%Node{kind: :for_expr, name: "", children: children}]}]}] = nodes
      blocks = Enum.filter(children, &(&1.kind == :block))
      generators = Enum.filter(children, &(&1.kind == :expression))
      assert length(generators) >= 1
      assert length(blocks) == 1
    end
  end

  describe "fn breakdown" do
    test "anonymous function has clause children" do
      nodes =
        analyze("""
        defmodule Foo do
          def bar do
            fn
              :a -> 1
              :b -> 2
            end
          end
        end
        """)

      [%Node{children: [%Node{children: [%Node{kind: :fn_expr, name: "", children: clauses}]}]}] = nodes
      assert length(clauses) == 2
      assert Enum.all?(clauses, &(&1.kind == :clause))
    end
  end

  describe "leaf nodes not expandable" do
    test "typespecs have ast: nil" do
      nodes =
        analyze("""
        defmodule Foo do
          @type t :: :ok
          @spec bar() :: :ok
        end
        """)

      [%Node{children: children}] = nodes
      assert Enum.all?(children, &(&1.ast == nil))
    end

    test "attributes have ast: nil" do
      nodes =
        analyze("""
        defmodule Foo do
          @custom 42
        end
        """)

      [%Node{children: [%Node{kind: :attribute, ast: nil}]}] = nodes
    end
  end

  describe "extract_definitions/1" do
    defp extract_defs(code) do
      {:ok, ast} = Parser.parse_string(code)
      AST.extract_definitions(ast)
    end

    test "extracts module definition" do
      defs = extract_defs("defmodule Foo.Bar do\nend")
      assert [%{kind: :module, name: "Foo.Bar", line: 1}] = defs
    end

    test "extracts def and defp" do
      defs =
        extract_defs("""
        defmodule Foo do
          def bar(x), do: x
          defp baz(x, y), do: {x, y}
        end
        """)

      assert [
               %{kind: :module, name: "Foo"},
               %{kind: :def, name: :bar, arity: 1},
               %{kind: :defp, name: :baz, arity: 2}
             ] = defs
    end

    test "extracts function with guard" do
      defs =
        extract_defs("""
        defmodule Foo do
          def bar(x) when is_integer(x), do: x
        end
        """)

      assert [%{kind: :module}, %{kind: :def, name: :bar, arity: 1}] = defs
    end

    test "extracts defmacro and defmacrop" do
      defs =
        extract_defs("""
        defmodule Foo do
          defmacro my_macro(arg), do: arg
          defmacrop private_macro(arg), do: arg
        end
        """)

      assert [
               %{kind: :module},
               %{kind: :defmacro, name: :my_macro, arity: 1},
               %{kind: :defmacrop, name: :private_macro, arity: 1}
             ] = defs
    end

    test "extracts defstruct" do
      defs =
        extract_defs("""
        defmodule Foo do
          defstruct [:a, :b]
        end
        """)

      assert [%{kind: :module, name: "Foo"}, %{kind: :struct, module: "Foo"}] = defs
    end

    test "extracts @type" do
      defs =
        extract_defs("""
        defmodule Foo do
          @type status :: :ok | :error
        end
        """)

      assert [%{kind: :module}, %{kind: :type, name: :status, arity: 0}] = defs
    end

    test "extracts defguard" do
      defs =
        extract_defs("""
        defmodule Foo do
          defguard is_positive(n) when is_integer(n) and n > 0
        end
        """)

      assert [%{kind: :module}, %{kind: :defguard, name: :is_positive, arity: 1}] = defs
    end

    test "extracts nested module with fully qualified name" do
      defs =
        extract_defs("""
        defmodule Foo do
          defmodule Bar do
            def baz, do: :ok
          end
        end
        """)

      assert [
               %{kind: :module, name: "Foo"},
               %{kind: :module, name: "Foo.Bar"},
               %{kind: :def, name: :baz, module: "Foo.Bar"}
             ] = defs
    end

    test "includes line numbers" do
      defs =
        extract_defs("""
        defmodule Foo do
          def bar, do: :ok
        end
        """)

      assert [%{kind: :module, line: 1}, %{kind: :def, line: 2}] = defs
    end

    test "extracts @callback" do
      defs =
        extract_defs("""
        defmodule Foo do
          @callback on_event(term()) :: :ok
        end
        """)

      assert [%{kind: :module}, %{kind: :callback, name: :on_event, arity: 1}] = defs
    end
  end

  defp collect_ids(nodes) do
    Enum.flat_map(nodes, fn node ->
      [node.id | collect_ids(node.children)]
    end)
  end
end

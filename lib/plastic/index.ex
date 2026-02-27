defmodule Plastic.Index do
  @moduledoc false

  use GenServer

  alias Plastic.Project
  alias Plastic.Parser
  alias Plastic.AST

  # -- Public API --

  def start_link(opts) do
    {project, opts} = Keyword.pop!(opts, :project)
    {table_name, opts} = Keyword.pop(opts, :table_name, :plastic_index)
    GenServer.start_link(__MODULE__, {project, table_name}, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Look up a module by name. Returns `{:ok, %{file: path, line: line, source: source}}` or `:error`.
  """
  def lookup_module(module_name, table \\ :plastic_index) do
    case :ets.lookup(table, {:module, module_name}) do
      [{_, file, line, source} | _] -> {:ok, %{file: file, line: line, source: source}}
      [] -> :error
    end
  end

  @doc """
  Ensure a module is indexed. If not found in ETS, tries to find it in deps.
  """
  def ensure_indexed(module_name, server \\ __MODULE__) do
    case lookup_module(module_name) do
      {:ok, _} -> :ok
      :error -> GenServer.call(server, {:index_module, module_name}, 30_000)
    end
  end

  # -- GenServer callbacks --

  @impl true
  def init({%Project{} = project, table_name}) do
    table = :ets.new(table_name, [:bag, :public, :named_table, read_concurrency: true])
    send(self(), :index_project)
    {:ok, %{project: project, table: table}}
  end

  @impl true
  def handle_info(:index_project, state) do
    files = Project.list_source_files(state.project)

    for %{path: rel_path, absolute_path: abs_path} <- files do
      index_file(state.table, abs_path, rel_path, :project)
    end

    Phoenix.PubSub.broadcast(Plastic.PubSub, "index", :project_indexed)
    {:noreply, state}
  end

  @impl true
  def handle_call({:index_module, module_name}, _from, state) do
    result = lazy_index_dep(state.table, state.project, module_name)
    {:reply, result, state}
  end

  # -- Internals --

  defp index_file(table, abs_path, rel_path, source) do
    case Parser.parse_file(abs_path) do
      {:ok, ast} ->
        defs = AST.extract_definitions(ast)

        for def_entry <- defs do
          case def_entry do
            %{kind: :module, name: name, line: line} ->
              :ets.insert(table, {{:module, name}, rel_path, line, source})

            %{kind: kind, module: mod, name: name, arity: arity, line: line} ->
              :ets.insert(table, {{:exports, mod}, name, arity, kind, line})

            %{kind: :struct, module: mod, line: line} ->
              :ets.insert(table, {{:exports, mod}, :__struct__, 0, :struct, line})
          end
        end

        :ok

      {:error, _} ->
        :error
    end
  end

  defp lazy_index_dep(table, project, module_name) do
    candidate_files = dep_candidate_files(project.root_path) ++ elixir_lib_files()

    matching_file =
      Enum.find(candidate_files, fn file ->
        case File.read(file) do
          {:ok, content} -> String.contains?(content, "defmodule #{module_name}")
          _ -> false
        end
      end)

    case matching_file do
      nil ->
        :error

      file ->
        index_file(table, file, file, :dep)

        case lookup_module(module_name, table) do
          {:ok, _} -> :ok
          :error -> :error
        end
    end
  end

  defp dep_candidate_files(root) do
    Path.wildcard(Path.join(root, "deps/*/lib/**/*.ex"))
  end

  defp elixir_lib_files do
    elixir_lib = :code.lib_dir(:elixir) |> to_string()
    Path.wildcard(Path.join(elixir_lib, "lib/**/*.ex"))
  end
end

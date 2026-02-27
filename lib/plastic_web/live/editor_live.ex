defmodule PlasticWeb.EditorLive do
  use PlasticWeb, :live_view

  alias Plastic.Project
  alias Plastic.Parser
  alias Plastic.AST

  @impl true
  def mount(_params, _session, socket) do
    {:ok, project} = Project.open(Path.join(File.cwd!(), "sample"))
    file_tree = Project.file_tree(project)

    {:ok,
     assign(socket,
       project: project,
       file_tree: file_tree,
       selected_file: nil,
       ast_tree: nil,
       parse_error: nil,
       expanded: MapSet.new()
     ), layout: false}
  end

  @impl true
  def handle_params(%{"path" => path} = params, _uri, socket) do
    expanded_from_params = parse_expanded(params)

    socket =
      if socket.assigns.selected_file == path do
        assign(socket, expanded: expanded_from_params)
      else
        open_file(socket, path, expanded_from_params)
      end

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_file", %{"path" => path}, socket) do
    dir_ids = parent_dir_ids(path)
    {:noreply, patch_with_expanded(socket, path, dir_ids)}
  end

  def handle_event("toggle_node", %{"id" => id}, socket) do
    expanded = toggle_in_set(socket.assigns.expanded, id)
    {:noreply, patch_with_expanded(socket, socket.assigns.selected_file, expanded)}
  end

  def handle_event("toggle_dir", %{"path" => path}, socket) do
    expanded = toggle_in_set(socket.assigns.expanded, "dir:" <> path)
    {:noreply, patch_with_expanded(socket, socket.assigns.selected_file, expanded)}
  end

  def handle_event("expand_all", _, socket) do
    all_ids = collect_all_node_ids(socket.assigns.ast_tree || [])
    expanded = MapSet.union(socket.assigns.expanded, MapSet.new(all_ids))
    {:noreply, patch_with_expanded(socket, socket.assigns.selected_file, expanded)}
  end

  def handle_event("collapse_all", _, socket) do
    # Keep dir expansions, clear AST node expansions
    dirs = socket.assigns.expanded |> Enum.filter(&String.starts_with?(&1, "dir:")) |> MapSet.new()
    {:noreply, patch_with_expanded(socket, socket.assigns.selected_file, dirs)}
  end

  defp toggle_in_set(set, id) do
    if MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id)
  end

  defp patch_with_expanded(socket, nil, _expanded), do: push_patch(socket, to: ~p"/")

  defp patch_with_expanded(socket, path, expanded) do
    params = %{path: path, expanded: encode_expanded(expanded)}
    push_patch(socket, to: ~p"/?#{params}", replace: true)
  end

  defp open_file(socket, path, expanded_from_params) do
    abs_path = Path.join(socket.assigns.project.root_path, path)
    dir_ids = parent_dir_ids(path)

    case Parser.parse_file(abs_path) do
      {:ok, ast} ->
        nodes = AST.analyze(ast)

        auto_expanded =
          nodes
          |> Enum.filter(&(&1.kind == :module))
          |> Enum.map(& &1.id)
          |> MapSet.new()
          |> MapSet.union(dir_ids)

        expanded = MapSet.union(auto_expanded, expanded_from_params)

        assign(socket,
          selected_file: path,
          ast_tree: nodes,
          parse_error: nil,
          expanded: expanded
        )

      {:error, reason} ->
        assign(socket,
          selected_file: path,
          ast_tree: nil,
          parse_error: inspect(reason),
          expanded: MapSet.union(dir_ids, expanded_from_params)
        )
    end
  end

  defp parent_dir_ids(path) do
    path
    |> Path.split()
    |> Enum.drop(-1)
    |> Enum.scan(fn part, acc -> acc <> "/" <> part end)
    |> Enum.map(&("dir:" <> &1))
    |> MapSet.new()
  end

  defp collect_all_node_ids(nodes) do
    Enum.flat_map(nodes, fn node ->
      [node.id | collect_all_node_ids(node.children)]
    end)
  end

  defp encode_expanded(expanded) do
    expanded |> MapSet.to_list() |> Enum.join(",")
  end

  defp parse_expanded(%{"expanded" => ""}), do: MapSet.new()

  defp parse_expanded(%{"expanded" => str}) when is_binary(str) do
    str |> String.split(",", trim: true) |> MapSet.new()
  end

  defp parse_expanded(_), do: MapSet.new()

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-base-100 text-base-content">
      <!-- Sidebar -->
      <aside class="w-64 border-r border-base-300 flex flex-col shrink-0">
        <div class="p-3 border-b border-base-300 font-semibold text-sm">
          {@project.name}
        </div>
        <nav class="flex-1 overflow-y-auto p-2 text-sm">
          <.file_tree_node
            tree={@file_tree}
            path=""
            selected={@selected_file}
            expanded={@expanded}
          />
        </nav>
      </aside>

      <!-- Main Panel -->
      <main class="flex-1 flex flex-col overflow-hidden">
        <div :if={@selected_file} class="flex items-center gap-2 p-3 border-b border-base-300 text-sm">
          <span class="font-mono font-semibold">{@selected_file}</span>
          <div class="ml-auto flex gap-1">
            <button phx-click="expand_all" class="btn btn-xs btn-ghost">Expand all</button>
            <button phx-click="collapse_all" class="btn btn-xs btn-ghost">Collapse all</button>
          </div>
        </div>

        <div class="flex-1 overflow-y-auto p-4">
          <div :if={@parse_error} class="alert alert-error text-sm mb-4">
            Parse error: {@parse_error}
          </div>

          <div :if={@ast_tree} class="font-mono text-sm space-y-0.5">
            <.ast_node :for={node <- @ast_tree} node={node} expanded={@expanded} depth={0} />
          </div>

          <div :if={!@selected_file} class="text-base-content/50 text-sm">
            Select a file from the sidebar to explore its AST.
          </div>
        </div>
      </main>
    </div>
    """
  end

  # -- File tree component --

  attr :tree, :map, required: true
  attr :path, :string, required: true
  attr :selected, :string, default: nil
  attr :expanded, :any, required: true

  defp file_tree_node(assigns) do
    sorted =
      assigns.tree
      |> Enum.sort_by(fn {name, val} -> {if(val == :file, do: 1, else: 0), name} end)

    assigns = assign(assigns, :entries, sorted)

    ~H"""
    <ul class="space-y-0.5">
      <li :for={{name, val} <- @entries}>
        <%= if val == :file do %>
          <% file_path = if(@path == "", do: name, else: @path <> "/" <> name) %>
          <button
            phx-click="select_file"
            phx-value-path={file_path}
            class={"block w-full text-left px-2 py-1 rounded cursor-pointer hover:bg-base-200 truncate #{if @selected == file_path, do: "bg-primary/15 text-primary font-semibold", else: ""}"}
          >
            <span class="text-base-content/40 mr-1">&#9782;</span>
            {name}
          </button>
        <% else %>
          <% dir_path = if(@path == "", do: name, else: @path <> "/" <> name) %>
          <% dir_expanded = MapSet.member?(@expanded, "dir:" <> dir_path) %>
          <button
            phx-click="toggle_dir"
            phx-value-path={dir_path}
            class="block w-full text-left px-2 py-1 rounded cursor-pointer hover:bg-base-200 font-semibold truncate"
          >
            <span class="text-base-content/40 mr-1">{if dir_expanded, do: "▼", else: "▶"}</span>
            {name}/
          </button>
          <div :if={dir_expanded} class="pl-3">
            <.file_tree_node tree={val} path={dir_path} selected={@selected} expanded={@expanded} />
          </div>
        <% end %>
      </li>
    </ul>
    """
  end

  # -- AST node component --

  attr :node, Plastic.AST.Node, required: true
  attr :expanded, :any, required: true
  attr :depth, :integer, required: true

  defp ast_node(assigns) do
    has_children = assigns.node.children != []
    is_expanded = MapSet.member?(assigns.expanded, assigns.node.id)
    expandable = has_children or assigns.node.ast != nil
    assigns = assign(assigns, has_children: has_children, is_expanded: is_expanded, expandable: expandable)

    ~H"""
    <div style={"padding-left: #{@depth * 16}px"}>
      <div class="flex items-center gap-1.5 py-0.5 group">
        <!-- expand toggle -->
        <button
          :if={@expandable}
          phx-click="toggle_node"
          phx-value-id={@node.id}
          class="w-4 text-center text-base-content/40 hover:text-base-content cursor-pointer"
        >
          {if @is_expanded, do: "▼", else: "▶"}
        </button>
        <span :if={!@expandable} class="w-4" />

        <!-- kind badge -->
        <span class={["inline-block px-1.5 py-0.5 rounded text-xs font-semibold leading-none", kind_class(@node.kind)]}>
          {kind_label(@node)}
        </span>

        <!-- name -->
        <span
          class={["break-all", if(@expandable, do: "cursor-pointer hover:underline", else: "")]}
          phx-click={if(@expandable, do: "toggle_node")}
          phx-value-id={@node.id}
        >
          {@node.name}
        </span>

        <!-- line number -->
        <span :if={@node.meta[:line]} class="text-xs text-base-content/30 ml-auto shrink-0">
          L{@node.meta[:line]}
        </span>
      </div>

      <div :if={@is_expanded}>
        <!-- moduledoc rendered preview -->
        <div
          :if={@node.kind == :moduledoc && @node.meta[:doc_text]}
          style={"padding-left: #{(@depth + 1) * 16}px"}
          class="text-sm bg-base-200/50 rounded p-3 my-1 prose prose-sm max-w-none"
        >
          {render_markdown(@node.meta.doc_text)}
        </div>
        <!-- source code preview (leaf nodes without special rendering) -->
        <pre
          :if={@node.kind != :moduledoc && @node.ast && !@has_children}
          style={"padding-left: #{(@depth + 1) * 16}px"}
          class="text-xs text-base-content/60 bg-base-200/50 rounded p-2 my-1 overflow-x-auto whitespace-pre-wrap"
        >{node_source(@node)}</pre>
        <!-- children -->
        <.ast_node :for={child <- @node.children} node={child} expanded={@expanded} depth={@depth + 1} />
      </div>
    </div>
    """
  end

  defp node_source(%{ast: ast}) when ast != nil do
    Macro.to_string(ast)
  end

  defp render_markdown(text) do
    case MDEx.to_html(text) do
      {:ok, html} -> Phoenix.HTML.raw(html)
      _ -> text
    end
  end

  defp kind_label(%{kind: kind, meta: meta}) when kind in [:function, :function_clause, :callback_impl] do
    case Map.get(meta, :def_kind) do
      :def -> if kind == :callback_impl, do: "impl", else: "def"
      :defp -> "defp"
      :defmacro -> "defmacro"
      :defmacrop -> "defmacrop"
      _ -> "fn"
    end
  end

  defp kind_label(%{kind: :defstruct}), do: "struct"
  defp kind_label(%{kind: :defguard}), do: "defguard"
  defp kind_label(%{kind: :defguardp}), do: "defguardp"
  defp kind_label(%{kind: :module}), do: "module"
  defp kind_label(%{kind: :moduledoc}), do: "moduledoc"
  defp kind_label(%{kind: :behaviour}), do: "behaviour"
  defp kind_label(%{kind: :attribute}), do: "attr"
  defp kind_label(%{kind: :typespec, meta: %{attr_name: name}}), do: "#{name}"
  defp kind_label(%{kind: :typespec}), do: "type"
  defp kind_label(%{kind: :use}), do: "use"
  defp kind_label(%{kind: :import}), do: "import"
  defp kind_label(%{kind: :alias}), do: "alias"
  defp kind_label(%{kind: :require}), do: "require"
  defp kind_label(%{kind: :expression}), do: "expr"
  defp kind_label(_), do: "?"

  defp kind_class(:defstruct), do: "bg-cyan-500/20 text-cyan-400"
  defp kind_class(:defguard), do: "bg-amber-500/20 text-amber-400"
  defp kind_class(:defguardp), do: "bg-amber-500/20 text-amber-400"
  defp kind_class(:module), do: "bg-purple-500/20 text-purple-400"
  defp kind_class(:function), do: "bg-blue-500/20 text-blue-400"
  defp kind_class(:function_clause), do: "bg-blue-500/20 text-blue-400"
  defp kind_class(:callback_impl), do: "bg-indigo-500/20 text-indigo-400"
  defp kind_class(:moduledoc), do: "bg-green-500/20 text-green-400"
  defp kind_class(:behaviour), do: "bg-pink-500/20 text-pink-400"
  defp kind_class(:attribute), do: "bg-yellow-500/20 text-yellow-400"
  defp kind_class(:typespec), do: "bg-teal-500/20 text-teal-400"
  defp kind_class(:use), do: "bg-orange-500/20 text-orange-400"
  defp kind_class(:import), do: "bg-orange-500/20 text-orange-400"
  defp kind_class(:alias), do: "bg-orange-500/20 text-orange-400"
  defp kind_class(:require), do: "bg-orange-500/20 text-orange-400"
  defp kind_class(:expression), do: "bg-base-300 text-base-content/60"
  defp kind_class(_), do: "bg-base-300 text-base-content/60"
end

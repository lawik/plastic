# Plastic — AST-Based Elixir Project Editor

## Vision

An editor for Elixir projects that operates on the AST and high-level language abstractions rather than raw text files. Instead of editing lines of code, you manipulate modules, functions, attributes, and expressions as structured objects. Spitfire parses Elixir into AST, Sourceror patches and converts AST back to code, and the LiveView UI presents this as an explorable, editable tree.

## Prototype Scope

A single LiveView page with:
1. A **sidebar** showing the project's file/module structure
2. A **main panel** showing a structured AST tree for the selected file
3. The AST tree groups nodes logically (module > attributes/functions > clauses > expressions)

No text editing. No Ash resources for this prototype — pure LiveView + backend modules.

---

## Architecture

### Core Modules

#### `Plastic.Project`
Represents an opened Elixir project. For the prototype, this is a hardcoded path (or configurable via the UI).

- `open(path)` — validates the path is a Mix project (has `mix.exs`), returns a project struct
- `list_source_files(project)` — walks `lib/` recursively, returns list of `%{path: relative_path, absolute_path: ...}`
- `file_tree(project)` — returns the file list structured as a nested tree by directory

#### `Plastic.Parser`
Wraps Spitfire to parse files into AST.

- `parse_file(absolute_path)` — reads file, parses with `Spitfire.parse/1`, returns `{:ok, ast}` or `{:error, diagnostics}`
- `parse_string(code)` — parses a code string, returns `{:ok, ast}` or `{:error, diagnostics}`

#### `Plastic.AST`
Transforms raw Elixir AST into a structured, UI-friendly tree. This is the heart of the prototype.

- `analyze(ast)` — takes a top-level AST and returns a tree of `%Plastic.AST.Node{}` structs
- Groups nodes into logical categories:
  - **Module** — `defmodule` calls. Children are the module body contents.
  - **Function** — `def`, `defp`, `defmacro`, `defmacrop`. Groups all clauses of the same function/arity together.
  - **Attribute** — `@moduledoc`, `@doc`, `@behaviour`, `@impl`, custom attributes
  - **Use/Import/Alias/Require** — dependency declarations
  - **TypeSpec** — `@type`, `@spec`, `@callback`, `@opaque`
  - **Expression** — anything else (module-level expressions, guards, body expressions)

##### `%Plastic.AST.Node{}`

```elixir
%Plastic.AST.Node{
  id: String.t(),          # unique id for the node within the file, for LiveView tracking
  kind: atom(),            # :module | :function | :attribute | :use | :import | :alias | :require | :typespec | :expression
  name: String.t(),        # display name, e.g. "MyApp.Router", "def handle_event/3"
  meta: map(),             # AST metadata (line, column) + kind-specific data
  children: [Node.t()],    # nested nodes
  ast: Macro.t(),          # the original AST fragment for this node
  collapsed: boolean()     # UI state hint, default true for large subtrees
}
```

#### `Plastic.Patcher`
Wraps Sourceror for AST-to-code operations. Not heavily used in prototype v1, but establishes the pattern.

- `to_code(ast)` — converts AST back to Elixir source string using `Sourceror.to_string/1`
- `patch(original_code, patches)` — applies Sourceror patches to source code

---

### LiveView

#### Route

```
live "/", PlasticWeb.EditorLive
```

Replace the default `PageController` route.

#### `PlasticWeb.EditorLive`

Single LiveView that manages the editor state.

**Assigns:**
- `project` — the `Plastic.Project` struct
- `file_tree` — nested directory/file tree for the sidebar
- `selected_file` — currently selected file path (or nil)
- `ast_tree` — the analyzed `%Plastic.AST.Node{}` tree for the selected file (or nil)
- `parse_error` — error info if parsing failed (or nil)
- `expanded` — MapSet of node IDs that are currently expanded in the tree

**Mount:**
- Open the project (hardcoded path initially, or self — `File.cwd!()`)
- Build the file tree
- No file selected initially

**Events:**
- `select_file(path)` — parse the file, analyze the AST, set assigns
- `toggle_node(node_id)` — expand/collapse a node in the AST tree
- `expand_all` / `collapse_all` — bulk toggle

#### Components

##### `sidebar` (function component or live component)
- Renders `file_tree` as a collapsible directory tree
- Files are clickable, triggers `select_file`
- Highlights the currently selected file
- Shows `.ex` and `.exs` files only

##### `ast_tree` (function component)
- Renders the analyzed AST as a nested, collapsible tree
- Each node shows:
  - An icon or tag indicating kind (Module, Function, Attribute, etc.)
  - The display name
  - Line number from source
  - Expand/collapse toggle if it has children
- Color-coding by node kind
- Clicking a node expands/collapses it

##### Layout
```
+------------------+------------------------------------------+
|                  |                                          |
|  Sidebar         |  AST Tree                                |
|  (file tree)     |                                          |
|                  |  Module: MyApp.Router                    |
|  lib/            |    use PlasticWeb, :router               |
|    plastic/      |    Function: pipeline/2                  |
|      app...      |      clause 1: pipeline(:browser, ...)   |
|    plastic_web/  |    Function: scope/3                     |
|      router.ex * |      ...                                 |
|      ...         |                                          |
|                  |                                          |
+------------------+------------------------------------------+
```

Sidebar: ~250px fixed width, scrollable.
Main panel: fills remaining space, scrollable.

---

## Implementation Plan

### Step 1: `Plastic.Project`
- Struct with `root_path`
- `open/1` checks for `mix.exs`
- `list_source_files/1` globs `lib/**/*.{ex,exs}`
- `file_tree/1` builds nested map from flat file list

### Step 2: `Plastic.Parser`
- `parse_file/1` reads + parses with Spitfire
- Handle parse errors gracefully (Spitfire returns partial AST + errors)

### Step 3: `Plastic.AST`
- Define `%Plastic.AST.Node{}` struct
- `analyze/1` walks the AST:
  - Top-level: look for `defmodule` calls
  - Inside module body: categorize each expression by kind
  - Functions: group clauses with same name/arity
  - Recursion: modules can nest modules
- Generate stable IDs (e.g., based on path in tree: `"mod:MyApp.Router/fn:pipeline/2/clause:0"`)

### Step 4: LiveView + Sidebar
- Add route
- `EditorLive` mount loads project, builds file tree
- Sidebar component renders directory tree with expand/collapse
- Click file triggers `select_file`

### Step 5: AST Tree Panel
- `select_file` parses + analyzes, stores in assigns
- `ast_tree` component renders the node tree
- Expand/collapse per node via `toggle_node`
- Style with Tailwind: indentation, kind-based colors, icons

### Step 6: Polish
- Show parse errors inline
- Show source line numbers on nodes
- Keyboard navigation (up/down/left/right to navigate tree)
- Loading state while parsing large files

---

## Non-Goals for Prototype

- **No text editing** — view-only for now
- **No AST modification** — no adding/removing/rewriting nodes yet
- **No Ash resources** — pure LiveView state, no persistence
- **No multi-project** — single hardcoded project
- **No file watching** — manual refresh only
- **No syntax highlighting of code snippets** — just the structured tree

## Future (Post-Prototype)

- Click a function node to see its source code (rendered via `Sourceror.to_string/1`)
- Edit operations: rename function, add argument, move function between modules
- Sourceror-based patching to write changes back to files
- FileSystem watcher for live reload
- Search across AST (find all calls to a function, all modules using a behaviour)
- Ash resources for project/file state if persistence is needed

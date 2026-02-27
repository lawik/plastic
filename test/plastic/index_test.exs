defmodule Plastic.IndexTest do
  use ExUnit.Case, async: false

  alias Plastic.Index
  alias Plastic.Project

  setup do
    # Use the sample project for testing
    {:ok, project} = Project.open(Path.join(File.cwd!(), "sample"))
    table = :ets.new(:test_index, [:bag, :public, read_concurrency: true])
    {:ok, project: project, table: table}
  end

  describe "lookup_module/2" do
    test "returns :error when module not found", %{table: table} do
      assert :error == Index.lookup_module("NonExistent.Module", table)
    end

    test "returns module info after insertion", %{table: table} do
      :ets.insert(table, {{:module, "Foo.Bar"}, "lib/foo/bar.ex", 1, :project})

      assert {:ok, %{file: "lib/foo/bar.ex", line: 1, source: :project}} =
               Index.lookup_module("Foo.Bar", table)
    end
  end

  describe "GenServer integration" do
    test "indexes project files on startup", %{project: project} do
      id = System.unique_integer([:positive])
      name = :"index_test_server_#{id}"
      table_name = :"index_test_table_#{id}"
      {:ok, pid} = Index.start_link(project: project, name: name, table_name: table_name)

      # Wait for async indexing to complete
      :sys.get_state(pid)

      assert {:ok, %{file: file, source: :project}} =
               Index.lookup_module("Sample.KitchenSink", table_name)

      assert file =~ "kitchen_sink.ex"

      GenServer.stop(pid)
    end
  end
end

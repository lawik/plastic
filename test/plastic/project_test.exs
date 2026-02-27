defmodule Plastic.ProjectTest do
  use ExUnit.Case, async: true

  alias Plastic.Project

  describe "open/1" do
    test "opens a valid mix project" do
      assert {:ok, %Project{name: "plastic"}} = Project.open(File.cwd!())
    end

    test "rejects a non-mix directory" do
      assert {:error, :not_a_mix_project} = Project.open("/tmp")
    end
  end

  describe "list_source_files/1" do
    test "returns source files with relative and absolute paths" do
      {:ok, project} = Project.open(File.cwd!())
      files = Project.list_source_files(project)

      assert length(files) > 0
      assert Enum.all?(files, &match?(%{path: _, absolute_path: _}, &1))

      paths = Enum.map(files, & &1.path)
      assert "lib/plastic.ex" in paths
      assert "lib/plastic/project.ex" in paths
    end
  end

  describe "file_tree/1" do
    test "builds nested directory structure" do
      {:ok, project} = Project.open(File.cwd!())
      tree = Project.file_tree(project)

      assert is_map(tree["lib"])
      assert tree["lib"]["plastic.ex"] == :file
      assert is_map(tree["lib"]["plastic"])
      assert tree["lib"]["plastic"]["project.ex"] == :file
    end
  end
end

defmodule PlasticWeb.EditorLiveTest do
  use PlasticWeb.ConnCase

  test "GET / renders the editor", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Select a file from the sidebar"
  end
end

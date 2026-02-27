defmodule PlasticWeb.PageController do
  use PlasticWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

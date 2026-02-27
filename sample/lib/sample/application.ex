defmodule Sample.Application do
  @moduledoc false

  use Application
  require Logger
  alias Sample.KitchenSink

  @impl true
  def start(_type, _args) do
    children = [
      {KitchenSink, name: :kitchen_sink}
    ]

    opts = [strategy: :one_for_one, name: Sample.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

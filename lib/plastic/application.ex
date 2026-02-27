defmodule Plastic.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    {:ok, project} = Plastic.Project.open(Path.join(File.cwd!(), "sample"))

    children = [
      PlasticWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:plastic, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Plastic.PubSub},
      {Plastic.Index, project: project},
      PlasticWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Plastic.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PlasticWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

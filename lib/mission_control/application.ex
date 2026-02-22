defmodule MissionControl.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MissionControlWeb.Telemetry,
      MissionControl.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:mission_control, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:mission_control, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MissionControl.PubSub},
      MissionControl.Config,
      {Registry, keys: :unique, name: MissionControl.AgentRegistry},
      MissionControl.Agents.AgentSupervisor,
      # Reset agents left as "running" from a previous server session
      {Task, &MissionControl.Agents.reset_stale_agents/0},
      # Start to serve requests, typically the last entry
      MissionControlWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MissionControl.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MissionControlWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end

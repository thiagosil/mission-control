defmodule MissionControl.Agents.AgentSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_agent(agent) do
    spec = {MissionControl.Agents.AgentProcess, agent}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def stop_agent(agent_id) do
    case Registry.lookup(MissionControl.AgentRegistry, agent_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_running}
    end
  rescue
    ArgumentError -> {:error, :not_running}
  end
end

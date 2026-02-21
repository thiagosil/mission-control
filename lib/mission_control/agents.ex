defmodule MissionControl.Agents do
  import Ecto.Query
  alias MissionControl.Repo
  alias MissionControl.Agents.{Agent, AgentProcess, AgentSupervisor}

  # --- CRUD ---

  def list_agents do
    Agent |> order_by(desc: :id) |> Repo.all()
  end

  def get_agent!(id), do: Repo.get!(Agent, id)

  def create_agent(attrs) do
    %Agent{} |> Agent.changeset(attrs) |> Repo.insert()
  end

  def update_agent(%Agent{} = agent, attrs) do
    agent |> Agent.changeset(attrs) |> Repo.update()
  end

  # --- Lifecycle ---

  def spawn_agent(attrs \\ %{}) do
    attrs = Map.put_new(attrs, :name, "Agent #{System.unique_integer([:positive])}")

    with {:ok, agent} <- create_agent(Map.put(attrs, :status, "running")),
         {:ok, _pid} <- AgentSupervisor.start_agent(agent) do
      broadcast_agent_change(agent)
      {:ok, agent}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def stop_agent(agent_id) do
    case AgentSupervisor.stop_agent(agent_id) do
      :ok ->
        agent = get_agent!(agent_id)
        {:ok, agent} = update_agent(agent, %{status: "stopped"})
        broadcast_agent_change(agent)
        {:ok, agent}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Queries ---

  def get_buffer(agent_id) do
    if agent_alive?(agent_id) do
      AgentProcess.get_buffer(agent_id)
    else
      []
    end
  end

  def agent_alive?(agent_id), do: AgentProcess.alive?(agent_id)

  # --- PubSub ---

  def subscribe do
    Phoenix.PubSub.subscribe(MissionControl.PubSub, "agents")
  end

  def subscribe_to_output(agent_id) do
    Phoenix.PubSub.subscribe(MissionControl.PubSub, "agent_output:#{agent_id}")
  end

  def unsubscribe_from_output(agent_id) do
    Phoenix.PubSub.unsubscribe(MissionControl.PubSub, "agent_output:#{agent_id}")
  end

  defp broadcast_agent_change(agent) do
    Phoenix.PubSub.broadcast(MissionControl.PubSub, "agents", {:agent_changed, agent})
  end
end

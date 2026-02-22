defmodule MissionControl.Agents do
  import Ecto.Query
  alias MissionControl.Repo
  alias MissionControl.Activity
  alias MissionControl.Agents.{Agent, AgentProcess, AgentSupervisor}

  # --- Startup ---

  def reset_stale_agents do
    from(a in Agent, where: a.status == "running")
    |> Repo.update_all(set: [status: "stopped"])
  end

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

      Activity.append(%{
        type: "agent_spawned",
        agent_id: agent.id,
        task_id: agent.config["task_id"],
        message: "Agent \"#{agent.name}\" spawned"
      })

      {:ok, agent}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def restart_agent(agent_id) do
    agent = get_agent!(agent_id)

    if agent.status == "running" do
      {:error, :already_running}
    else
      {:ok, agent} = update_agent(agent, %{status: "running"})

      case AgentSupervisor.start_agent(agent) do
        {:ok, _pid} ->
          broadcast_agent_change(agent)

          Activity.append(%{
            type: "agent_restarted",
            agent_id: agent.id,
            task_id: agent.config["task_id"],
            message: "Agent \"#{agent.name}\" restarted"
          })

          {:ok, agent}

        {:error, reason} ->
          update_agent(agent, %{status: "stopped"})
          {:error, reason}
      end
    end
  end

  def stop_agent(agent_id) do
    case AgentSupervisor.stop_agent(agent_id) do
      :ok ->
        agent = get_agent!(agent_id)
        {:ok, agent} = update_agent(agent, %{status: "stopped"})
        broadcast_agent_change(agent)

        Activity.append(%{
          type: "agent_stopped",
          agent_id: agent.id,
          message: "Agent \"#{agent.name}\" stopped"
        })

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

  # --- Task integration ---

  def spawn_agent_for_task(task, opts \\ []) do
    branch_name = Keyword.get(opts, :branch_name)
    prompt = build_task_prompt(task, branch_name)
    command = AgentProcess.default_command()

    config =
      %{"command" => command, "task_id" => task.id, "prompt" => prompt}
      |> then(fn c ->
        if branch_name, do: Map.put(c, "branch", branch_name), else: c
      end)

    attrs = %{
      name: "Agent for: #{String.slice(task.title, 0, 40)}",
      config: config
    }

    spawn_agent(attrs)
  end

  defp build_task_prompt(task, branch_name) do
    desc = if task.description, do: "\n\n#{task.description}", else: ""
    branch = if branch_name, do: "\nBranch: #{branch_name}", else: ""
    "Task: #{task.title}#{desc}#{branch}"
  end

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

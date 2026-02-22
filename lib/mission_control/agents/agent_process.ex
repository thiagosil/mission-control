defmodule MissionControl.Agents.AgentProcess do
  use GenServer, restart: :temporary

  @max_scrollback 1000

  # --- Client API ---

  def default_command, do: MissionControl.Config.agent_command_template()

  def start_link(%{id: agent_id} = agent) do
    GenServer.start_link(__MODULE__, agent, name: via(agent_id))
  end

  def get_buffer(agent_id) do
    GenServer.call(via(agent_id), :get_buffer)
  end

  def alive?(agent_id) do
    case Registry.lookup(MissionControl.AgentRegistry, agent_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  rescue
    ArgumentError -> false
  end

  defp via(agent_id) do
    {:via, Registry, {MissionControl.AgentRegistry, agent_id}}
  end

  # --- Server Callbacks ---

  @impl true
  def init(agent) do
    config = agent.config || %{}
    command = Map.get(config, "command", default_command())
    task_id = Map.get(config, "task_id")

    port =
      Port.open({:spawn, command}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout
      ])

    {:ok,
     %{
       agent_id: agent.id,
       port: port,
       buffer: [],
       task_id: task_id
     }}
  end

  @impl true
  def handle_call(:get_buffer, _from, state) do
    {:reply, Enum.reverse(state.buffer), state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    lines = String.split(data, "\n", trim: true)

    new_buffer =
      Enum.reduce(lines, state.buffer, fn line, buf ->
        [line | buf] |> Enum.take(@max_scrollback)
      end)

    for line <- lines do
      Phoenix.PubSub.broadcast(
        MissionControl.PubSub,
        "agent_output:#{state.agent_id}",
        {:output, state.agent_id, line}
      )
    end

    {:noreply, %{state | buffer: new_buffer}}
  end

  def handle_info({port, {:exit_status, exit_status}}, %{port: port} = state) do
    new_status = if exit_status == 0, do: "stopped", else: "crashed"

    case MissionControl.Repo.get(MissionControl.Agents.Agent, state.agent_id) do
      nil ->
        :ok

      agent ->
        MissionControl.Agents.Agent.changeset(agent, %{status: new_status})
        |> MissionControl.Repo.update()
    end

    MissionControl.Activity.append(%{
      type: "agent_exited",
      agent_id: state.agent_id,
      task_id: state.task_id,
      message: "Agent exited (#{new_status})",
      metadata: %{"exit_status" => exit_status}
    })

    transition_task_on_exit(state.task_id, exit_status)

    Phoenix.PubSub.broadcast(
      MissionControl.PubSub,
      "agents",
      {:agent_exited, state.agent_id, new_status}
    )

    {:stop, :normal, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Task auto-transitions ---

  defp transition_task_on_exit(nil, _exit_status), do: :ok

  defp transition_task_on_exit(task_id, 0) do
    case MissionControl.Tasks.get_task_for_agent_by_id(task_id) do
      %{column: "in_progress"} = task -> MissionControl.Tasks.move_task(task, "review")
      _ -> :ok
    end
  end

  defp transition_task_on_exit(_task_id, _nonzero), do: :ok
end

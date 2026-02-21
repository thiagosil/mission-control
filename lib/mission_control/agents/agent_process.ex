defmodule MissionControl.Agents.AgentProcess do
  use GenServer, restart: :temporary

  @max_scrollback 1000
  @default_command Application.compile_env(
                     :mission_control,
                     :default_agent_command,
                     "bash -c 'for i in $(seq 1 20); do echo \"[agent] step $i: working...\"; sleep 0.3; done; echo \"[agent] done.\"'"
                   )

  # --- Client API ---

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
  end

  defp via(agent_id) do
    {:via, Registry, {MissionControl.AgentRegistry, agent_id}}
  end

  # --- Server Callbacks ---

  @impl true
  def init(agent) do
    command = Map.get(agent.config || %{}, "command", @default_command)

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
       buffer: []
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
end

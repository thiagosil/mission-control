defmodule MissionControl.Agents.AgentProcessTest do
  use MissionControl.DataCase

  alias MissionControl.Agents

  setup do
    on_exit(fn ->
      MissionControl.Agents.AgentSupervisor
      |> DynamicSupervisor.which_children()
      |> Enum.each(fn {_, pid, _, _} ->
        DynamicSupervisor.terminate_child(MissionControl.Agents.AgentSupervisor, pid)
      end)
    end)

    :ok
  end

  test "captures output in buffer while running" do
    {:ok, agent} = Agents.create_agent(%{name: "Buffer Test", status: "running"})

    command = "bash -c 'echo line1; echo line2; sleep 5'"

    {:ok, _pid} =
      MissionControl.Agents.AgentSupervisor.start_agent(%{
        agent
        | config: %{"command" => command}
      })

    Process.sleep(500)

    buffer = MissionControl.Agents.AgentProcess.get_buffer(agent.id)
    assert "line1" in buffer
    assert "line2" in buffer
  end

  test "broadcasts output via PubSub" do
    {:ok, agent} = Agents.create_agent(%{name: "PubSub Test", status: "running"})
    Phoenix.PubSub.subscribe(MissionControl.PubSub, "agent_output:#{agent.id}")

    {:ok, _pid} =
      MissionControl.Agents.AgentSupervisor.start_agent(%{
        agent
        | config: %{"command" => "echo hello_pubsub"}
      })

    assert_receive {:output, _, "hello_pubsub"}, 2000
  end

  test "broadcasts exit status via PubSub on clean exit" do
    Phoenix.PubSub.subscribe(MissionControl.PubSub, "agents")

    {:ok, agent} = Agents.create_agent(%{name: "Exit Test", status: "running"})

    {:ok, _pid} =
      MissionControl.Agents.AgentSupervisor.start_agent(%{
        agent
        | config: %{"command" => "echo done"}
      })

    assert_receive {:agent_exited, _, "stopped"}, 2000
  end

  test "broadcasts crashed status on non-zero exit" do
    Phoenix.PubSub.subscribe(MissionControl.PubSub, "agents")

    {:ok, agent} = Agents.create_agent(%{name: "Crash Test", status: "running"})

    {:ok, _pid} =
      MissionControl.Agents.AgentSupervisor.start_agent(%{
        agent
        | config: %{"command" => "exit 1"}
      })

    assert_receive {:agent_exited, _, "crashed"}, 2000
  end
end

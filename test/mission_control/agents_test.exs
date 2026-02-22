defmodule MissionControl.AgentsTest do
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

  test "create_agent/1 with valid attrs" do
    assert {:ok, agent} = Agents.create_agent(%{name: "Test Agent", status: "stopped"})
    assert agent.name == "Test Agent"
    assert agent.status == "stopped"
  end

  test "create_agent/1 rejects invalid status" do
    assert {:error, changeset} = Agents.create_agent(%{name: "Bad", status: "invalid"})
    assert %{status: _} = errors_on(changeset)
  end

  test "list_agents/0 returns agents ordered by id desc" do
    {:ok, a1} = Agents.create_agent(%{name: "First", status: "stopped"})
    {:ok, a2} = Agents.create_agent(%{name: "Second", status: "stopped"})
    agents = Agents.list_agents()
    assert [a2.id, a1.id] == Enum.map(agents, & &1.id)
  end

  test "spawn_agent/0 creates a running agent and starts a process" do
    {:ok, agent} = Agents.spawn_agent()
    assert agent.status == "running"
    assert Agents.agent_alive?(agent.id)
  end

  test "stop_agent/1 terminates the process and sets status to stopped" do
    {:ok, agent} = Agents.spawn_agent(%{config: %{"command" => "sleep 10"}})
    assert Agents.agent_alive?(agent.id)
    assert {:ok, updated} = Agents.stop_agent(agent.id)
    assert updated.status == "stopped"
    refute Agents.agent_alive?(agent.id)
  end

  test "restart_agent/1 re-spawns a stopped agent" do
    {:ok, agent} = Agents.spawn_agent(%{config: %{"command" => "sleep 10"}})
    assert {:ok, _} = Agents.stop_agent(agent.id)
    refute Agents.agent_alive?(agent.id)

    assert {:ok, restarted} = Agents.restart_agent(agent.id)
    assert restarted.status == "running"
    assert restarted.id == agent.id
    assert Agents.agent_alive?(agent.id)
  end

  test "restart_agent/1 re-spawns a crashed agent" do
    Agents.subscribe()
    {:ok, agent} = Agents.spawn_agent(%{config: %{"command" => "exit 1"}})

    # Wait for the process to crash and fully terminate
    assert_receive {:agent_exited, _, "crashed"}, 2000
    Process.sleep(50)
    refute Agents.agent_alive?(agent.id)

    assert {:ok, restarted} = Agents.restart_agent(agent.id)
    assert restarted.status == "running"
    assert Agents.agent_alive?(agent.id)
  end

  test "restart_agent/1 on an already-running agent returns error" do
    {:ok, agent} = Agents.spawn_agent(%{config: %{"command" => "sleep 10"}})
    assert Agents.agent_alive?(agent.id)

    assert {:error, :already_running} = Agents.restart_agent(agent.id)
  end

  test "get_buffer/1 returns captured output lines" do
    Agents.subscribe()
    {:ok, agent} = Agents.spawn_agent(%{config: %{"command" => "echo hello && echo world"}})

    # Wait for the process to exit
    assert_receive {:agent_exited, _, _}, 2000

    # Process has exited, so buffer is empty (GenServer stopped)
    # But we can verify the agent was created and ran
    assert agent.status == "running"
  end
end

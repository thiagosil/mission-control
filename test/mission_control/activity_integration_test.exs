defmodule MissionControl.ActivityIntegrationTest do
  use MissionControl.DataCase

  alias MissionControl.Activity
  alias MissionControl.Agents
  alias MissionControl.Tasks

  setup do
    Activity.subscribe()

    on_exit(fn ->
      MissionControl.Agents.AgentSupervisor
      |> DynamicSupervisor.which_children()
      |> Enum.each(fn {_, pid, _, _} ->
        DynamicSupervisor.terminate_child(MissionControl.Agents.AgentSupervisor, pid)
      end)
    end)

    :ok
  end

  describe "agent lifecycle events" do
    test "spawning an agent emits agent_spawned event" do
      {:ok, agent} = Agents.spawn_agent()

      assert_receive {:new_event, event}
      assert event.type == "agent_spawned"
      assert event.agent_id == agent.id
      assert event.message =~ agent.name
    end

    test "stopping an agent emits agent_stopped event" do
      {:ok, agent} = Agents.spawn_agent()
      assert_receive {:new_event, _spawn_event}

      {:ok, _} = Agents.stop_agent(agent.id)

      assert_receive {:new_event, event}
      assert event.type == "agent_stopped"
      assert event.agent_id == agent.id
      assert event.message =~ agent.name
    end
  end

  describe "task lifecycle events" do
    test "creating a task emits task_created event" do
      {:ok, task} = Tasks.create_task(%{title: "Test task"})

      assert_receive {:new_event, event}
      assert event.type == "task_created"
      assert event.task_id == task.id
      assert event.message =~ "Test task"
    end

    test "updating a task emits task_updated event" do
      {:ok, task} = Tasks.create_task(%{title: "Original"})
      assert_receive {:new_event, _create_event}

      {:ok, _} = Tasks.update_task(task, %{title: "Updated"})

      assert_receive {:new_event, event}
      assert event.type == "task_updated"
      assert event.task_id == task.id
    end

    test "deleting a task emits task_deleted event" do
      {:ok, task} = Tasks.create_task(%{title: "Delete me"})
      assert_receive {:new_event, _create_event}

      {:ok, _} = Tasks.delete_task(task)

      assert_receive {:new_event, event}
      assert event.type == "task_deleted"
      assert event.message =~ "Delete me"
    end
  end
end

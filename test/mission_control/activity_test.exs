defmodule MissionControl.ActivityTest do
  use MissionControl.DataCase

  alias MissionControl.Activity
  alias MissionControl.Activity.Event

  describe "append/1" do
    test "inserts a valid event" do
      assert {:ok, event} =
               Activity.append(%{type: "task_created", message: "Task created"})

      assert event.type == "task_created"
      assert event.message == "Task created"
      assert event.id
    end

    test "inserts event with agent_id and task_id" do
      {:ok, agent} = MissionControl.Agents.create_agent(%{name: "Test Agent", status: "running"})
      {:ok, task} = MissionControl.Tasks.create_task(%{title: "Test Task"})

      assert {:ok, event} =
               Activity.append(%{
                 type: "task_assigned",
                 message: "Task assigned",
                 agent_id: agent.id,
                 task_id: task.id
               })

      assert event.agent_id == agent.id
      assert event.task_id == task.id
    end

    test "rejects invalid event type" do
      assert {:error, changeset} =
               Activity.append(%{type: "invalid_type", message: "Bad event"})

      assert errors_on(changeset).type != []
    end

    test "rejects missing message" do
      assert {:error, changeset} =
               Activity.append(%{type: "task_created"})

      assert errors_on(changeset).message != []
    end

    test "broadcasts event via PubSub" do
      Activity.subscribe()

      {:ok, event} = Activity.append(%{type: "task_created", message: "Task created"})

      assert_receive {:new_event, ^event}
    end

    test "preloads associations on broadcast" do
      Activity.subscribe()
      {:ok, agent} = MissionControl.Agents.create_agent(%{name: "Test Agent", status: "running"})

      {:ok, _event} =
        Activity.append(%{type: "agent_spawned", message: "Agent spawned", agent_id: agent.id})

      assert_receive {:new_event, event}
      assert event.agent.name == "Test Agent"
    end
  end

  describe "list/1" do
    test "returns events ordered by inserted_at desc" do
      {:ok, _e1} = Activity.append(%{type: "task_created", message: "First"})
      {:ok, _e2} = Activity.append(%{type: "task_updated", message: "Second"})

      events = Activity.list()
      assert length(events) == 2
      assert hd(events).message == "Second"
    end

    test "filters by type" do
      {:ok, _} = Activity.append(%{type: "task_created", message: "Created"})
      {:ok, _} = Activity.append(%{type: "agent_spawned", message: "Spawned"})

      events = Activity.list(type: "task_created")
      assert length(events) == 1
      assert hd(events).type == "task_created"
    end

    test "filters by agent_id" do
      {:ok, agent} = MissionControl.Agents.create_agent(%{name: "A1", status: "running"})
      {:ok, _} = Activity.append(%{type: "agent_spawned", message: "S1", agent_id: agent.id})
      {:ok, _} = Activity.append(%{type: "task_created", message: "T1"})

      events = Activity.list(agent_id: agent.id)
      assert length(events) == 1
      assert hd(events).agent_id == agent.id
    end

    test "filters by since" do
      {:ok, old} = Activity.append(%{type: "task_created", message: "Old"})

      # Ensure the next event has a later timestamp
      since = old.inserted_at |> DateTime.add(1, :second)

      {:ok, _new} =
        %Event{}
        |> Event.changeset(%{type: "task_updated", message: "New"})
        |> Ecto.Changeset.force_change(:inserted_at, DateTime.add(since, 1, :second))
        |> Repo.insert()

      events = Activity.list(since: since)
      assert length(events) == 1
      assert hd(events).message == "New"
    end

    test "respects limit" do
      for i <- 1..5 do
        Activity.append(%{type: "task_created", message: "Event #{i}"})
      end

      events = Activity.list(limit: 3)
      assert length(events) == 3
    end

    test "defaults to limit of 50" do
      for i <- 1..55 do
        Activity.append(%{type: "task_created", message: "Event #{i}"})
      end

      events = Activity.list()
      assert length(events) == 50
    end

    test "preloads agent and task associations" do
      {:ok, agent} = MissionControl.Agents.create_agent(%{name: "A1", status: "running"})
      {:ok, task} = MissionControl.Tasks.create_task(%{title: "T1"})

      {:ok, _} =
        Activity.append(%{
          type: "task_assigned",
          message: "Assigned",
          agent_id: agent.id,
          task_id: task.id
        })

      events = Activity.list(type: "task_assigned")
      assert length(events) == 1
      event = hd(events)
      assert event.agent.name == "A1"
      assert event.task.title == "T1"
    end
  end
end

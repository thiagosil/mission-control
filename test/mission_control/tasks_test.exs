defmodule MissionControl.TasksTest do
  use MissionControl.DataCase

  alias MissionControl.Tasks
  alias MissionControl.Tasks.Task

  describe "create_task/1" do
    test "creates a task with valid attrs" do
      assert {:ok, task} = Tasks.create_task(%{title: "Fix bug"})
      assert task.title == "Fix bug"
      assert task.column == "inbox"
      assert task.priority == "normal"
    end

    test "creates a task with all fields" do
      attrs = %{
        title: "Add auth",
        description: "Implement JWT authentication",
        priority: "urgent",
        tags: ["backend", "security"]
      }

      assert {:ok, task} = Tasks.create_task(attrs)
      assert task.title == "Add auth"
      assert task.description == "Implement JWT authentication"
      assert task.priority == "urgent"
      assert task.tags == ["backend", "security"]
    end

    test "rejects task without title" do
      assert {:error, changeset} = Tasks.create_task(%{})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects invalid column" do
      assert {:error, changeset} = Tasks.create_task(%{title: "Bad", column: "invalid"})
      assert %{column: _} = errors_on(changeset)
    end

    test "rejects invalid priority" do
      assert {:error, changeset} = Tasks.create_task(%{title: "Bad", priority: "low"})
      assert %{priority: _} = errors_on(changeset)
    end
  end

  describe "list_tasks/0" do
    test "returns all tasks ordered by id" do
      {:ok, t1} = Tasks.create_task(%{title: "First"})
      {:ok, t2} = Tasks.create_task(%{title: "Second"})
      tasks = Tasks.list_tasks()
      assert [t1.id, t2.id] == Enum.map(tasks, & &1.id)
    end

    test "returns empty list when no tasks" do
      assert Tasks.list_tasks() == []
    end
  end

  describe "get_task!/1" do
    test "returns the task with the given id" do
      {:ok, task} = Tasks.create_task(%{title: "Find me"})
      assert Tasks.get_task!(task.id).id == task.id
    end

    test "raises when task does not exist" do
      assert_raise Ecto.NoResultsError, fn -> Tasks.get_task!(999) end
    end
  end

  describe "update_task/2" do
    test "updates a task with valid attrs" do
      {:ok, task} = Tasks.create_task(%{title: "Original"})
      assert {:ok, updated} = Tasks.update_task(task, %{title: "Updated"})
      assert updated.title == "Updated"
    end

    test "rejects invalid attrs on update" do
      {:ok, task} = Tasks.create_task(%{title: "Original"})
      assert {:error, _changeset} = Tasks.update_task(task, %{title: ""})
    end
  end

  describe "delete_task/1" do
    test "deletes a task" do
      {:ok, task} = Tasks.create_task(%{title: "Delete me"})
      assert {:ok, _deleted} = Tasks.delete_task(task)
      assert_raise Ecto.NoResultsError, fn -> Tasks.get_task!(task.id) end
    end
  end

  describe "move_task/2" do
    test "inbox -> assigned is valid" do
      {:ok, task} = Tasks.create_task(%{title: "Move me"})
      assert {:ok, moved} = Tasks.move_task(task, "assigned")
      assert moved.column == "assigned"
    end

    test "assigned -> in_progress is valid" do
      {:ok, task} = Tasks.create_task(%{title: "Move me", column: "assigned"})
      assert {:ok, moved} = Tasks.move_task(task, "in_progress")
      assert moved.column == "in_progress"
    end

    test "in_progress -> review is valid" do
      {:ok, task} = Tasks.create_task(%{title: "Move me", column: "in_progress"})
      assert {:ok, moved} = Tasks.move_task(task, "review")
      assert moved.column == "review"
    end

    test "review -> done is valid" do
      {:ok, task} = Tasks.create_task(%{title: "Move me", column: "review"})
      assert {:ok, moved} = Tasks.move_task(task, "done")
      assert moved.column == "done"
    end

    test "backward transitions are valid (assigned -> inbox)" do
      {:ok, task} = Tasks.create_task(%{title: "Move back", column: "assigned"})
      assert {:ok, moved} = Tasks.move_task(task, "inbox")
      assert moved.column == "inbox"
    end

    test "inbox -> done is invalid (cannot skip columns)" do
      {:ok, task} = Tasks.create_task(%{title: "Skip"})
      assert {:error, :invalid_transition} = Tasks.move_task(task, "done")
    end

    test "inbox -> in_progress is invalid" do
      {:ok, task} = Tasks.create_task(%{title: "Skip"})
      assert {:error, :invalid_transition} = Tasks.move_task(task, "in_progress")
    end

    test "inbox -> review is invalid" do
      {:ok, task} = Tasks.create_task(%{title: "Skip"})
      assert {:error, :invalid_transition} = Tasks.move_task(task, "review")
    end

    test "done -> inbox is invalid" do
      {:ok, task} = Tasks.create_task(%{title: "Reverse", column: "done"})
      assert {:error, :invalid_transition} = Tasks.move_task(task, "inbox")
    end
  end

  describe "pubsub" do
    test "broadcasts task_created on create" do
      Tasks.subscribe()
      {:ok, task} = Tasks.create_task(%{title: "New"})
      assert_receive {:task_created, ^task}
    end

    test "broadcasts task_updated on update" do
      Tasks.subscribe()
      {:ok, task} = Tasks.create_task(%{title: "Original"})
      assert_receive {:task_created, _}
      {:ok, updated} = Tasks.update_task(task, %{title: "Changed"})
      assert_receive {:task_updated, ^updated}
    end

    test "broadcasts task_deleted on delete" do
      Tasks.subscribe()
      {:ok, task} = Tasks.create_task(%{title: "Doomed"})
      assert_receive {:task_created, _}
      {:ok, _} = Tasks.delete_task(task)
      assert_receive {:task_deleted, _}
    end
  end

  describe "assign_and_start_task/1" do
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

    test "spawns agent, links to task, and moves to in_progress" do
      {:ok, task} = Tasks.create_task(%{title: "Auto-assign me"})
      assert {:ok, updated_task, agent} = Tasks.assign_and_start_task(task)

      assert updated_task.column == "in_progress"
      assert updated_task.agent_id == agent.id
      assert agent.status == "running"
      assert agent.name =~ "Agent for:"
    end
  end

  describe "get_task_for_agent/1" do
    test "returns the task assigned to the agent" do
      {:ok, agent} = MissionControl.Agents.create_agent(%{name: "Test Agent", status: "running"})
      {:ok, task} = Tasks.create_task(%{title: "Linked task", column: "in_progress"})
      {:ok, task} = Tasks.update_task(task, %{agent_id: agent.id})

      found = Tasks.get_task_for_agent(agent.id)
      assert found.id == task.id
    end

    test "returns nil when no task is assigned" do
      assert Tasks.get_task_for_agent(999) == nil
    end

    test "does not return tasks in done column" do
      {:ok, agent} = MissionControl.Agents.create_agent(%{name: "Test Agent", status: "running"})
      {:ok, task} = Tasks.create_task(%{title: "Done task", column: "done"})
      {:ok, _task} = Tasks.update_task(task, %{agent_id: agent.id})

      assert Tasks.get_task_for_agent(agent.id) == nil
    end
  end

  describe "Task.valid_transition?/2" do
    test "returns true for valid transitions" do
      assert Task.valid_transition?("inbox", "assigned")
      assert Task.valid_transition?("assigned", "in_progress")
      assert Task.valid_transition?("in_progress", "review")
      assert Task.valid_transition?("review", "done")
    end

    test "returns false for invalid transitions" do
      refute Task.valid_transition?("inbox", "done")
      refute Task.valid_transition?("inbox", "in_progress")
      refute Task.valid_transition?("done", "inbox")
      refute Task.valid_transition?("review", "assigned")
    end
  end

  describe "task dependencies" do
    test "creates a task with dependencies" do
      {:ok, blocker} = Tasks.create_task(%{title: "Blocker"})
      {:ok, task} = Tasks.create_task(%{title: "Blocked", dependencies: [blocker.id]})
      assert task.dependencies == [blocker.id]
    end

    test "move to in_progress is blocked when dependencies are not done" do
      {:ok, blocker} = Tasks.create_task(%{title: "Blocker"})

      {:ok, task} =
        Tasks.create_task(%{title: "Blocked", column: "assigned", dependencies: [blocker.id]})

      assert {:error, :blocked_by_dependencies} = Tasks.move_task(task, "in_progress")
    end

    test "move to in_progress is allowed when all dependencies are done" do
      {:ok, blocker} = Tasks.create_task(%{title: "Blocker", column: "done"})

      {:ok, task} =
        Tasks.create_task(%{title: "Unblocked", column: "assigned", dependencies: [blocker.id]})

      assert {:ok, moved} = Tasks.move_task(task, "in_progress")
      assert moved.column == "in_progress"
    end

    test "move to in_progress is blocked when some dependencies are not done" do
      {:ok, done_blocker} = Tasks.create_task(%{title: "Done blocker", column: "done"})
      {:ok, open_blocker} = Tasks.create_task(%{title: "Open blocker", column: "in_progress"})

      {:ok, task} =
        Tasks.create_task(%{
          title: "Partially blocked",
          column: "assigned",
          dependencies: [done_blocker.id, open_blocker.id]
        })

      assert {:error, :blocked_by_dependencies} = Tasks.move_task(task, "in_progress")
    end

    test "task without dependencies can move to in_progress normally" do
      {:ok, task} = Tasks.create_task(%{title: "No deps", column: "assigned"})
      assert {:ok, moved} = Tasks.move_task(task, "in_progress")
      assert moved.column == "in_progress"
    end

    test "has_unresolved_dependencies? returns false for empty dependencies" do
      {:ok, task} = Tasks.create_task(%{title: "No deps"})
      refute Tasks.has_unresolved_dependencies?(task)
    end

    test "has_unresolved_dependencies? returns true when blocker is not done" do
      {:ok, blocker} = Tasks.create_task(%{title: "Blocker"})
      {:ok, task} = Tasks.create_task(%{title: "Blocked", dependencies: [blocker.id]})
      assert Tasks.has_unresolved_dependencies?(task)
    end

    test "has_unresolved_dependencies? returns false when all blockers are done" do
      {:ok, blocker} = Tasks.create_task(%{title: "Blocker", column: "done"})
      {:ok, task} = Tasks.create_task(%{title: "Unblocked", dependencies: [blocker.id]})
      refute Tasks.has_unresolved_dependencies?(task)
    end

    test "unresolved_dependency_ids returns IDs of non-done dependencies" do
      {:ok, done} = Tasks.create_task(%{title: "Done", column: "done"})
      {:ok, open} = Tasks.create_task(%{title: "Open", column: "inbox"})

      {:ok, task} =
        Tasks.create_task(%{title: "Mixed deps", dependencies: [done.id, open.id]})

      assert Tasks.unresolved_dependency_ids(task) == [open.id]
    end

    test "when blocking task moves to done, downstream task becomes unblocked" do
      {:ok, blocker} = Tasks.create_task(%{title: "Blocker", column: "review"})

      {:ok, task} =
        Tasks.create_task(%{title: "Blocked", column: "assigned", dependencies: [blocker.id]})

      # Cannot move yet
      assert {:error, :blocked_by_dependencies} = Tasks.move_task(task, "in_progress")

      # Move blocker to done
      {:ok, _} = Tasks.move_task(blocker, "done")

      # Now the downstream task is unblocked
      assert {:ok, moved} = Tasks.move_task(task, "in_progress")
      assert moved.column == "in_progress"
    end
  end

  describe "circular dependency prevention" do
    test "rejects self-dependency" do
      {:ok, task} = Tasks.create_task(%{title: "Self dep"})
      assert {:error, changeset} = Tasks.update_task(task, %{dependencies: [task.id]})
      assert %{dependencies: ["a task cannot depend on itself"]} = errors_on(changeset)
    end

    test "rejects direct circular dependency (A->B, B->A)" do
      {:ok, a} = Tasks.create_task(%{title: "A"})
      {:ok, b} = Tasks.create_task(%{title: "B"})

      # A depends on B
      {:ok, a} = Tasks.update_task(a, %{dependencies: [b.id]})
      assert a.dependencies == [b.id]

      # B depends on A — would create a cycle
      assert {:error, changeset} = Tasks.update_task(b, %{dependencies: [a.id]})
      assert %{dependencies: ["would create a circular dependency"]} = errors_on(changeset)
    end

    test "rejects transitive circular dependency (A->B->C, C->A)" do
      {:ok, a} = Tasks.create_task(%{title: "A"})
      {:ok, b} = Tasks.create_task(%{title: "B"})
      {:ok, c} = Tasks.create_task(%{title: "C"})

      {:ok, _a} = Tasks.update_task(a, %{dependencies: [b.id]})
      {:ok, _b} = Tasks.update_task(b, %{dependencies: [c.id]})

      # C depends on A — would create A->B->C->A cycle
      assert {:error, changeset} = Tasks.update_task(c, %{dependencies: [a.id]})
      assert %{dependencies: ["would create a circular dependency"]} = errors_on(changeset)
    end

    test "allows non-circular dependencies" do
      {:ok, a} = Tasks.create_task(%{title: "A"})
      {:ok, b} = Tasks.create_task(%{title: "B"})
      {:ok, c} = Tasks.create_task(%{title: "C"})

      # A depends on B, C depends on B — no cycle
      {:ok, a} = Tasks.update_task(a, %{dependencies: [b.id]})
      assert a.dependencies == [b.id]

      {:ok, c} = Tasks.update_task(c, %{dependencies: [b.id]})
      assert c.dependencies == [b.id]
    end
  end
end

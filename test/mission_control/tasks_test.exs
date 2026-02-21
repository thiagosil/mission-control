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
end

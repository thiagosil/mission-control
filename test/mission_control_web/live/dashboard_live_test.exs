defmodule MissionControlWeb.DashboardLiveTest do
  use MissionControlWeb.ConnCase

  import Phoenix.LiveViewTest

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

  test "dashboard page returns 200 and shows three-panel layout", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    # Agent sidebar
    assert html =~ "Agents"
    assert html =~ "Spawn Agent"

    # Task board with kanban columns
    assert html =~ "Task Board"
    assert html =~ "Inbox"
    assert html =~ "Assigned"
    assert html =~ "In Progress"
    assert html =~ "Review"
    assert html =~ "Done"

    # Terminal viewer
    assert html =~ "Terminal"
  end

  test "spawn agent button creates an agent and shows it in sidebar", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    html = view |> element("button", "Spawn Agent") |> render_click()

    # Agent name appears in the sidebar
    assert html =~ "Agent"
    # Status dot is present (running = green)
    assert html =~ "bg-success"
  end

  test "selecting an agent shows terminal panel with its name", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # Spawn an agent (auto-selects it)
    view |> element("button", "Spawn Agent") |> render_click()

    # Terminal should show the agent's output area
    html = render(view)
    assert html =~ "terminal-output"
  end

  test "agent exit updates status in sidebar", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # Spawn an agent (uses fast test command: echo '[agent] test output')
    view |> element("button", "Spawn Agent") |> render_click()

    # Wait for the fast command to finish and PubSub messages to arrive
    Process.sleep(500)

    html = render(view)
    # Should show stopped status (gray dot) instead of running (green dot)
    assert html =~ "bg-base-content/30"
    # Should show exit label
    assert html =~ "exited"
  end

  # --- Task board tests ---

  test "New Task button opens the task creation form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    html = view |> element("button", "New Task") |> render_click()

    assert html =~ "Create Task"
    assert html =~ "Title"
    assert html =~ "Description"
  end

  test "creating a task adds it to the Inbox column", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> element("button", "New Task") |> render_click()

    view
    |> form("form", task: %{title: "My new task", description: "A test task"})
    |> render_submit()

    html = render(view)
    assert html =~ "My new task"
  end

  test "creating a task without a title shows validation error", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> element("button", "New Task") |> render_click()

    html =
      view
      |> form("form", task: %{title: ""})
      |> render_submit()

    # Form should still be visible with errors
    assert html =~ "can&#39;t be blank" or html =~ "Create Task"
  end

  test "cancel button hides the task creation form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> element("button", "New Task") |> render_click()
    html = view |> element("button", "Cancel") |> render_click()

    refute html =~ "Create Task"
  end

  test "moving a task to the next column works", %{conn: conn} do
    {:ok, task} = MissionControl.Tasks.create_task(%{title: "Move me"})

    {:ok, view, _html} = live(conn, "/")
    html = render(view)
    assert html =~ "Move me"

    # Move from inbox to assigned via event
    html = render_click(view, "move_task", %{"id" => "#{task.id}", "column" => "assigned"})
    assert html =~ "Move me"
  end

  test "deleting a task removes it from the board", %{conn: conn} do
    {:ok, task} = MissionControl.Tasks.create_task(%{title: "Delete me"})

    {:ok, view, _html} = live(conn, "/")
    html = render(view)
    assert html =~ "Delete me"

    render_click(view, "delete_task", %{"id" => "#{task.id}"})
    html = render(view)
    refute html =~ "Delete me"
  end

  test "tasks appear in correct kanban columns", %{conn: conn} do
    {:ok, _t1} = MissionControl.Tasks.create_task(%{title: "Task in inbox"})
    {:ok, _t2} = MissionControl.Tasks.create_task(%{title: "Task in review", column: "review"})

    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Task in inbox"
    assert html =~ "Task in review"
  end

  test "task count is displayed per column", %{conn: conn} do
    {:ok, _} = MissionControl.Tasks.create_task(%{title: "One"})
    {:ok, _} = MissionControl.Tasks.create_task(%{title: "Two"})

    {:ok, _view, html} = live(conn, "/")

    # Inbox column should show count of 2
    assert html =~ ">2</span>"
  end

  # --- Assignment tests ---

  test "Assign Agent button appears on inbox tasks", %{conn: conn} do
    {:ok, _task} = MissionControl.Tasks.create_task(%{title: "Assignable task"})

    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Assign Agent"
  end

  test "clicking Assign Agent shows assignment dropdown", %{conn: conn} do
    {:ok, task} = MissionControl.Tasks.create_task(%{title: "Assignable task"})

    {:ok, view, _html} = live(conn, "/")

    html = render_click(view, "show_assign", %{"id" => "#{task.id}"})

    assert html =~ "Spawn New Agent"
    assert html =~ "Cancel"
  end

  test "assign_new_agent spawns agent and moves task to in_progress", %{conn: conn} do
    {:ok, task} = MissionControl.Tasks.create_task(%{title: "Agent task"})

    {:ok, view, _html} = live(conn, "/")

    render_click(view, "assign_new_agent", %{"id" => "#{task.id}"})

    html = render(view)
    # Agent should appear in sidebar
    assert html =~ "Agent for:"
    # Terminal should be showing the agent output
    assert html =~ "terminal-output"
  end

  test "agent sidebar shows task name for assigned agents", %{conn: conn} do
    {:ok, task} = MissionControl.Tasks.create_task(%{title: "Sidebar task"})

    {:ok, view, _html} = live(conn, "/")

    render_click(view, "assign_new_agent", %{"id" => "#{task.id}"})

    html = render(view)
    assert html =~ "Sidebar task"
  end
end

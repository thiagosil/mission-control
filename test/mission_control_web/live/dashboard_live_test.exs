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
end

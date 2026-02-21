defmodule MissionControlWeb.DashboardLiveTest do
  use MissionControlWeb.ConnCase

  import Phoenix.LiveViewTest

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
end

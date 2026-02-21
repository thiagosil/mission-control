defmodule MissionControlWeb.DashboardLive do
  use MissionControlWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Dashboard")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen overflow-hidden bg-base-200">
      <%!-- Agent Sidebar (left) --%>
      <aside class="w-64 flex-shrink-0 flex flex-col bg-base-100 border-r border-base-300">
        <div class="p-4 border-b border-base-300">
          <h2 class="text-lg font-semibold">Agents</h2>
        </div>
        <div class="flex-1 overflow-y-auto p-4">
          <p class="text-sm text-base-content/50">No agents running</p>
        </div>
        <div class="p-4 border-t border-base-300">
          <button class="btn btn-primary btn-sm w-full" disabled>
            Spawn Agent
          </button>
        </div>
      </aside>

      <%!-- Task Board (center) --%>
      <main class="flex-1 flex flex-col overflow-hidden">
        <div class="p-4 border-b border-base-300 bg-base-100">
          <h2 class="text-lg font-semibold">Task Board</h2>
        </div>
        <div class="flex-1 overflow-x-auto p-4">
          <div class="flex gap-4 h-full min-w-max">
            <.kanban_column title="Inbox" />
            <.kanban_column title="Assigned" />
            <.kanban_column title="In Progress" />
            <.kanban_column title="Review" />
            <.kanban_column title="Done" />
          </div>
        </div>
      </main>

      <%!-- Terminal Viewer (right) --%>
      <aside class="w-96 flex-shrink-0 flex flex-col bg-base-100 border-l border-base-300">
        <div class="p-4 border-b border-base-300">
          <h2 class="text-lg font-semibold">Terminal</h2>
        </div>
        <div class="flex-1 overflow-y-auto p-4 bg-neutral text-neutral-content font-mono text-sm">
          <p class="text-neutral-content/50">Select an agent to view its terminal output</p>
        </div>
      </aside>
    </div>
    """
  end

  defp kanban_column(assigns) do
    ~H"""
    <div class="w-56 flex-shrink-0 flex flex-col bg-base-100 rounded-box">
      <div class="p-3 border-b border-base-300">
        <h3 class="text-sm font-medium">{@title}</h3>
      </div>
      <div class="flex-1 p-2 min-h-32">
        <p class="text-xs text-base-content/40 text-center mt-4">No tasks</p>
      </div>
    </div>
    """
  end
end

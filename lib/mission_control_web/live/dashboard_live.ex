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
        <div class="p-4 border-b border-base-300 flex items-center justify-between">
          <div class="flex items-center gap-2.5">
            <div class="w-7 h-7 rounded-lg bg-gradient-to-br from-indigo-500 to-indigo-700 flex items-center justify-center text-white text-xs font-bold">
              M
            </div>
            <span class="text-sm font-semibold text-base-content tracking-tight">
              Mission Control
            </span>
          </div>
          <button
            phx-click={JS.dispatch("phx:toggle-theme")}
            class="p-1.5 rounded-md hover:bg-base-200 text-base-content/50 hover:text-base-content transition-colors cursor-pointer"
            aria-label="Toggle theme"
          >
            <.icon name="hero-moon-micro" class="size-4 dark:!hidden" />
            <.icon name="hero-sun-micro" class="size-4 hidden dark:!inline-block" />
          </button>
        </div>

        <div class="px-5 pt-4 pb-2">
          <span class="text-[10px] font-semibold tracking-widest uppercase text-base-content/40">
            Agents
          </span>
        </div>

        <div class="flex-1 overflow-y-auto px-2">
          <p class="text-sm text-base-content/40 px-3 mt-2">No agents running</p>
        </div>

        <div class="p-3 border-t border-base-300">
          <button
            class="w-full flex items-center justify-center gap-1.5 px-3 py-2 rounded-lg bg-base-200 text-sm text-base-content/60 hover:bg-base-300 hover:text-base-content transition-colors cursor-pointer"
            disabled
          >
            <span class="text-base text-base-content/30">+</span>
            Spawn Agent
          </button>
        </div>
      </aside>

      <%!-- Task Board (center) --%>
      <main class="flex-1 flex flex-col overflow-hidden">
        <div class="px-5 py-4 border-b border-base-300 bg-base-100">
          <h2 class="text-sm font-semibold text-base-content tracking-tight">Task Board</h2>
        </div>
        <div class="flex-1 overflow-x-auto p-4">
          <div class="flex gap-0.5 h-full min-w-max">
            <.kanban_column title="Inbox" count={0} />
            <.kanban_column title="Assigned" count={0} />
            <.kanban_column title="In Progress" count={0} />
            <.kanban_column title="Review" count={0} />
            <.kanban_column title="Done" count={0} />
          </div>
        </div>
      </main>

      <%!-- Terminal Viewer (right, always dark) --%>
      <aside class="w-96 flex-shrink-0 flex flex-col border-l border-base-300" data-theme="dark">
        <div class="px-5 py-3.5 border-b border-base-300 bg-base-100">
          <span class="text-xs font-medium text-base-content/50">Terminal</span>
        </div>
        <div class="flex-1 overflow-y-auto p-4 bg-base-100 font-mono text-sm text-base-content/50">
          <p>Select an agent to view its terminal output</p>
        </div>
      </aside>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :count, :integer, default: 0

  defp kanban_column(assigns) do
    ~H"""
    <div class="w-48 flex-shrink-0 flex flex-col">
      <div class="px-2.5 py-2 flex items-center justify-between mb-1.5">
        <span class="text-xs font-medium text-base-content/40">{@title}</span>
        <span class="text-[11px] text-base-content/20 tabular-nums">{@count}</span>
      </div>
      <div class="flex-1 flex flex-col gap-1.5 p-1 min-h-32 overflow-y-auto">
        <p class="text-xs text-base-content/30 text-center mt-4">No tasks</p>
      </div>
    </div>
    """
  end
end

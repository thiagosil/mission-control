defmodule MissionControlWeb.DashboardLive do
  use MissionControlWeb, :live_view

  alias MissionControl.Agents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Agents.subscribe()
    end

    agents = Agents.list_agents()

    {:ok,
     assign(socket,
       page_title: "Dashboard",
       agents: agents,
       selected_agent_id: nil,
       terminal_lines: [],
       terminal_status: nil
     )}
  end

  @impl true
  def handle_event("spawn_agent", _params, socket) do
    case Agents.spawn_agent() do
      {:ok, agent} ->
        agents = update_agent_in_list(socket.assigns.agents, agent)
        socket = assign(socket, agents: agents)
        socket = select_agent(socket, agent.id)
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to spawn agent")}
    end
  end

  def handle_event("stop_agent", %{"id" => id}, socket) do
    agent_id = String.to_integer(id)

    case Agents.stop_agent(agent_id) do
      {:ok, agent} ->
        agents = update_agent_in_list(socket.assigns.agents, agent)
        socket = assign(socket, agents: agents)

        socket =
          if socket.assigns.selected_agent_id == agent_id do
            assign(socket, terminal_status: "stopped")
          else
            socket
          end

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("select_agent", %{"id" => id}, socket) do
    {:noreply, select_agent(socket, String.to_integer(id))}
  end

  @impl true
  def handle_info({:agent_changed, agent}, socket) do
    agents = update_agent_in_list(socket.assigns.agents, agent)
    {:noreply, assign(socket, agents: agents)}
  end

  def handle_info({:agent_exited, agent_id, new_status}, socket) do
    agents =
      Enum.map(socket.assigns.agents, fn a ->
        if a.id == agent_id, do: %{a | status: new_status}, else: a
      end)

    socket = assign(socket, agents: agents)

    socket =
      if socket.assigns.selected_agent_id == agent_id do
        assign(socket, terminal_status: new_status)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:output, agent_id, line}, socket) do
    if socket.assigns.selected_agent_id == agent_id do
      {:noreply, assign(socket, terminal_lines: socket.assigns.terminal_lines ++ [line])}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp select_agent(socket, agent_id) do
    # Unsubscribe from previous agent
    if socket.assigns.selected_agent_id do
      Agents.unsubscribe_from_output(socket.assigns.selected_agent_id)
    end

    if connected?(socket) do
      Agents.subscribe_to_output(agent_id)
    end

    buffer = Agents.get_buffer(agent_id)

    status =
      if Agents.agent_alive?(agent_id) do
        nil
      else
        agent = Agents.get_agent!(agent_id)
        agent.status
      end

    assign(socket,
      selected_agent_id: agent_id,
      terminal_lines: buffer,
      terminal_status: status
    )
  end

  defp update_agent_in_list(agents, agent) do
    if Enum.any?(agents, &(&1.id == agent.id)) do
      Enum.map(agents, fn a -> if a.id == agent.id, do: agent, else: a end)
    else
      [agent | agents]
    end
  end

  defp status_color("running"), do: "bg-success"
  defp status_color("stopped"), do: "bg-base-content/30"
  defp status_color("crashed"), do: "bg-error"
  defp status_color(_), do: "bg-base-content/30"

  defp selected_agent(_agents, nil), do: nil
  defp selected_agent(agents, id), do: Enum.find(agents, &(&1.id == id))

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
          <%= if @agents == [] do %>
            <p class="text-sm text-base-content/40 px-3 mt-2">No agents running</p>
          <% else %>
            <ul class="space-y-0.5">
              <li :for={agent <- @agents}>
                <button
                  phx-click="select_agent"
                  phx-value-id={agent.id}
                  class={"w-full flex items-center gap-2.5 px-3 py-2 rounded-lg text-sm transition-colors cursor-pointer " <>
                    if(@selected_agent_id == agent.id,
                      do: "bg-base-200 text-base-content",
                      else: "text-base-content/60 hover:bg-base-200 hover:text-base-content"
                    )}
                >
                  <span class={"w-2 h-2 rounded-full flex-shrink-0 " <> status_color(agent.status)} />
                  <span class="truncate">{agent.name}</span>
                </button>
              </li>
            </ul>
          <% end %>
        </div>

        <div class="p-3 border-t border-base-300">
          <button
            phx-click="spawn_agent"
            class="w-full flex items-center justify-center gap-1.5 px-3 py-2 rounded-lg bg-base-200 text-sm text-base-content/60 hover:bg-base-300 hover:text-base-content transition-colors cursor-pointer"
          >
            <span class="text-base text-base-content/30">+</span> Spawn Agent
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
        <div class="px-5 py-3.5 border-b border-base-300 bg-base-100 flex items-center justify-between">
          <span class="text-xs font-medium text-base-content/50">
            <%= if agent = selected_agent(@agents, @selected_agent_id) do %>
              {agent.name}
            <% else %>
              Terminal
            <% end %>
          </span>
          <%= if @selected_agent_id && selected_agent(@agents, @selected_agent_id) && selected_agent(@agents, @selected_agent_id).status == "running" do %>
            <button
              phx-click="stop_agent"
              phx-value-id={@selected_agent_id}
              class="text-xs text-error/70 hover:text-error transition-colors cursor-pointer"
            >
              Stop
            </button>
          <% end %>
        </div>
        <div
          id="terminal-output"
          phx-hook="TerminalScroll"
          class="flex-1 overflow-y-auto p-4 bg-base-100 font-mono text-sm text-base-content/80"
        >
          <%= if @selected_agent_id == nil do %>
            <p class="text-base-content/50">Select an agent to view its terminal output</p>
          <% else %>
            <div :for={line <- @terminal_lines} class="whitespace-pre-wrap break-all leading-relaxed">
              {line}
            </div>
            <%= if @terminal_status do %>
              <div class={"mt-2 text-xs font-medium " <> if(@terminal_status == "crashed", do: "text-error", else: "text-base-content/40")}>
                — process {if @terminal_status == "crashed", do: "crashed", else: "exited"} —
              </div>
            <% end %>
          <% end %>
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

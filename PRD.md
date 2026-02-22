# Mission Control — Product Requirements Document

## Implementation Status

V1 is **complete**. All 11 planned GitHub issues have been implemented and merged:

| # | Issue | Status |
|---|-------|--------|
| 1 | Phoenix Bootstrap + Static Dashboard Shell | Done |
| 2 | Spawn & Stream a Single Agent | Done |
| 3 | Task CRUD + Kanban Board | Done |
| 4 | Assign Task to Agent + Auto State Transitions | Done |
| 5 | Git Branch-per-Task | Done |
| 6 | Activity Feed | Done |
| 7 | Agent Lifecycle Management (Stop, Restart, Failures) | Done |
| 8 | Goal Decomposition (Orchestrator) | Done |
| 9 | Task Dependencies | Done |
| 10 | Dashboard Header, Tags, Priority & Panel Controls | Done |
| 11 | Configurable Agent Backend | Done |

All user stories from 1–28 below are addressed by the implementation. See the "Out of Scope" section for items deferred to future versions.

## Problem Statement

Running multiple AI coding agents (Claude Code, Codex, etc.) today is a manual, fragmented experience. You open multiple terminal tabs, copy-paste context between them, manually track what each agent is working on, and lose visibility into the overall progress of a multi-agent workflow. There is no unified way to spawn agents, assign tasks, monitor their real-time output, and coordinate their work — especially when agents need to produce work that feeds into other agents' tasks.

Existing tools like Antfarm solve orchestration at the CLI/YAML level but lack a visual dashboard for real-time monitoring. The user needs a local, developer-friendly mission control that combines task management, agent lifecycle management, and live terminal streaming into a single interface.

## Solution

Mission Control is a locally-run Elixir/Phoenix application that provides a web-based dashboard for spawning, monitoring, and coordinating multiple AI coding agents. It treats each agent as a supervised CLI subprocess, displays their real-time terminal output, and organizes work through a kanban-style task board.

Key capabilities:
- **Spawn and supervise** multiple `claude` (or `codex`) CLI processes from a single dashboard
- **Manage tasks** through a kanban board (Inbox → Assigned → In Progress → Review → Done)
- **Stream terminal output** from each agent in real-time via Phoenix Channels
- **Decompose goals** by spawning an on-demand orchestrator agent that breaks high-level goals into actionable tasks
- **Isolate work** by creating a git branch per task/agent
- **Persist state** in SQLite so you can restart without losing context

The tool runs locally, scoped to a single git repository, and is designed for 2–5 concurrent agents.

## User Stories

1. As a developer, I want to start Mission Control in my repo with a single command (`mix mission_control.start`), so that I can begin managing agents immediately without complex setup.
2. As a developer, I want to see a dashboard in my browser that shows all active agents, their status, and current tasks, so that I have a single pane of glass for all agent activity.
3. As a developer, I want to spawn a new Claude Code agent from the dashboard, so that I don't have to open a new terminal and manually start it.
4. As a developer, I want to assign a task to an agent and have it automatically start working on that task, so that I can delegate work without switching contexts.
5. As a developer, I want to see the full streaming terminal output of each agent in real-time, so that I can monitor exactly what each agent is doing.
6. As a developer, I want to click on an agent in the sidebar to see its live terminal output, so that I can drill into any agent's work at any time.
7. As a developer, I want to create tasks manually through the UI (title, description, tags, priority), so that I can build a backlog of work for agents to pick up.
8. As a developer, I want to submit a high-level goal (e.g., "Add user authentication with JWT") and have an orchestrator agent break it down into subtasks, so that I don't have to manually decompose complex features.
9. As a developer, I want to review and approve the orchestrator's proposed task breakdown before agents start working, so that I maintain control over the plan.
10. As a developer, I want each agent to work on its own git branch automatically, so that work is isolated and I can review changes via PRs.
11. As a developer, I want to see a live activity feed showing what agents are doing (task started, file changed, task completed), so that I can passively monitor progress.
12. As a developer, I want to be notified in the UI when an agent gets stuck or fails, so that I can intervene quickly.
13. As a developer, I want to stop or restart an agent from the dashboard, so that I can manage agent lifecycle without using the terminal.
14. As a developer, I want tasks to move through the kanban board as agents work on them (automatically moving from "Assigned" to "In Progress" when an agent starts, to "Review" when done), so that the board reflects reality.
15. As a developer, I want to drag tasks between kanban columns manually, so that I can override automatic state transitions when needed.
16. As a developer, I want to filter the activity feed by agent or event type (task, comment, status), so that I can focus on specific activity.
17. As a developer, I want to see how many agents are active and how many tasks are in the queue in the header, so that I have an at-a-glance overview.
18. As a developer, I want Mission Control to persist its state across restarts, so that I don't lose my task board and agent configuration when I restart the server.
19. As a developer, I want to configure agents to run in auto-accept mode (skipping permission prompts), so that agents can work autonomously without blocking on user input.
20. As a developer, I want to switch the agent backend from Claude Code to Codex (or another CLI tool) without changing the rest of the system, so that I'm not locked into a single AI provider.
21. As a developer, I want to define task dependencies (task B is blocked by task A), so that agents don't start work that depends on incomplete upstream tasks.
22. As a developer, I want to see which branch an agent is working on, so that I know where to find their changes.
23. As a developer, I want the orchestrator to terminate after decomposing a goal (not stay running), so that I'm not paying for an idle agent.
24. As a developer, I want to tag tasks with labels, so that I can categorize and filter work.
25. As a developer, I want to set task priority (normal/urgent), so that agents can pick up the most important work first.
26. As a developer, I want to delete tasks from the board, so that I can clean up completed or irrelevant work.
27. As a developer, I want to see the timestamp of each activity in the feed, so that I can understand the timeline of events.
28. As a developer, I want to resize or toggle the terminal output panel, so that I can focus on either the task board or the terminal output.

## Implementation Decisions

### Major Modules

**1. Agent Supervisor (OTP Supervision Tree)**
Manages the lifecycle of all agent processes. Each agent is a GenServer that wraps a Port (for PTY/streaming output). The supervisor monitors agents, detects crashes, and reports failures to the UI. Agents run CLI subprocesses (`claude --dangerously-skip-permissions` or equivalent).

Interface: `start_agent(config)`, `stop_agent(id)`, `list_agents()`, `get_agent_status(id)`.

**2. Terminal Capture**
Captures streaming stdout/stderr from agent Ports. Maintains a scrollback buffer per agent. Broadcasts output chunks to Phoenix Channels for real-time UI rendering. Uses Erlang Ports (or ExPTY if needed) to handle terminal escape codes and interactive output.

Interface: `subscribe(agent_id)`, `get_buffer(agent_id, opts)`.

**3. Task Engine**
Core state machine for task management. Handles CRUD, state transitions (inbox → assigned → in_progress → review → done), dependency tracking, and agent assignment. Emits events on state changes that the activity feed consumes.

State transitions are validated — e.g., a task can only move to "in_progress" if it has an assigned agent and no unresolved blockers.

Interface: `create_task(attrs)`, `update_task(id, attrs)`, `move_task(id, column)`, `assign_task(id, agent_id)`, `delete_task(id)`, `list_tasks(filters)`.

**4. Orchestrator**
An on-demand module that spawns a temporary Claude agent with a specialized prompt to decompose a high-level goal into tasks. The orchestrator parses the agent's structured output (JSON) and creates tasks in the Task Engine. Once decomposition is complete, the agent process is terminated.

Interface: `decompose_goal(goal_text)` → returns proposed task list for user approval. `approve_plan(plan_id)` → creates tasks in the engine.

**5. Git Manager**
Creates and manages branches for tasks. Branch naming convention: `mc/<task-id>-<slug>` (e.g., `mc/t7-add-auth`). Checks out branches before passing work to agents. Detects merge conflicts and reports them through the task engine.

Interface: `create_branch(task)`, `get_current_branch(agent_id)`, `list_branches()`.

**6. Activity Feed**
Collects events from all other modules (agent started, task moved, agent output milestones) into a chronological feed. Events are persisted in SQLite and broadcast to the UI via Phoenix Channels.

Interface: `append(event)`, `list(filters)`, `subscribe()`.

**7. Web Layer (Phoenix LiveView + Channels)**
Phoenix LiveView for the dashboard UI (agent list, task board, terminal view). Phoenix Channels for real-time terminal streaming and activity feed updates. The UI is a simpler layout to start: agent list + task list + embedded terminal viewer. Three-panel layout that can evolve toward the richer mockup design over time.

**8. Persistence Layer (Ecto + SQLite)**
Ecto schemas for agents, tasks, activity events, and configuration. SQLite adapter via `ecto_sqlite3`. Migrations for schema changes.

Schemas:
- `agents`: id, name, role, status, config (JSON), pid reference
- `tasks`: id, title, description, column, agent_id, priority, tags (JSON), branch_name, dependencies (JSON), timestamps
- `events`: id, type, agent_id, task_id, message, metadata (JSON), timestamp

**9. CLI Interface**
Mix tasks for starting/stopping the server, basic configuration. Entry point: `mix mission_control.start` (starts Phoenix server). Configuration via `mission_control.toml` or environment variables.

### Architectural Decisions

- **Elixir/Phoenix** chosen for OTP supervision trees (natural fit for managing agent processes), Phoenix Channels (built-in WebSocket), and LiveView (real-time UI without a separate frontend framework).
- **Ports over NIFs** for agent processes — Ports provide isolation (agent crash doesn't crash the VM) and natural streaming.
- **SQLite over Postgres** — zero-dependency local tool. Single file database. Easy to inspect and back up.
- **Agent-agnostic subprocess interface** — the agent spawning layer accepts a command template (e.g., `claude --dangerously-skip-permissions -p "{prompt}"`) that can be swapped for `codex` or any other CLI tool. The rest of the system doesn't care what's running inside the subprocess.
- **Branch-per-task** git workflow — each task gets its own branch. Agent is instructed (via its prompt) to work on the assigned branch. The Git Manager handles checkout before the agent starts.
- **On-demand orchestrator** — the orchestrator is just another agent subprocess with a specialized system prompt. It outputs structured JSON. No persistent orchestrator process.
- **Auto-accept mode by default** — agents run with permission-skipping flags to enable fully autonomous operation.

## Testing Decisions

### What Makes a Good Test
Tests should verify **external behavior**, not implementation details. A good test:
- Calls a public interface and asserts on observable outcomes (return values, state changes, side effects)
- Does not assert on internal data structures, private function calls, or process message ordering
- Uses the actual module interfaces, not mocked internals
- Is deterministic and does not depend on timing

### Modules to Test

**Agent Supervisor**
- Test that `start_agent` spawns a process and returns a handle
- Test that `stop_agent` terminates the process gracefully
- Test that agent failure is detected and reported (use a mock subprocess that exits with an error)
- Test that `list_agents` returns correct statuses

**Task Engine**
- Test full CRUD lifecycle (create, read, update, delete)
- Test state transition validation (valid transitions succeed, invalid ones are rejected)
- Test dependency blocking (task with unresolved blocker cannot move to in_progress)
- Test assignment (assigning agent to task, reassigning)
- Test filtering by column, agent, priority, tags

**Orchestrator**
- Test that a goal is sent to a subprocess with the correct system prompt
- Test that structured JSON output is parsed into a task list
- Test that `approve_plan` creates the correct tasks in the Task Engine
- Test error handling when the orchestrator agent produces invalid output

**Git Manager**
- Test branch creation with correct naming convention
- Test branch listing
- Test that branch creation fails gracefully when branch already exists

**Activity Feed**
- Test that events from other modules are correctly captured
- Test filtering by type, agent, time range
- Test persistence (events survive restart)

### Test Approach
Use ExUnit with `Ecto.Adapters.SQL.Sandbox` for database tests. For agent subprocess tests, use mock scripts (simple bash scripts) instead of actual Claude CLI to keep tests fast and deterministic.

## Out of Scope (V1)

- **Multi-user / authentication** — Mission Control is a single-user, locally-run tool. No login, sessions, or access control.
- **Cloud deployment** — No remote access, no hosting, no SaaS mode. Runs exclusively on `localhost`.
- **Agent memory / learning** — No persistent memory across sessions. Each agent starts fresh. Context is passed via task descriptions and git state.
- **Multi-repo support** — V1 is scoped to a single git repository.
- **Drag-and-drop kanban** — V1 uses button-based column changes. Drag-and-drop is a future polish item.
- **Agent-to-agent direct messaging** — Agents communicate only through task state. No chat between agents.
- **Cost tracking / token usage** — No tracking of API costs or token consumption.
- **Mobile or responsive UI** — Desktop browser only.
- **Panel resizing** — Terminal panel can be toggled open/closed but not resized via drag.

## Further Notes

- The project name "Mission Control" may conflict with existing tools. Consider alternatives if publishing to Hex.
- Antfarm (antfarm.cool) is a reference for workflow orchestration patterns but uses a fundamentally different architecture (YAML workflows, cron scheduling). Mission Control prioritizes real-time visual monitoring over declarative workflow definitions.
- Since agents run in auto-accept mode, the user should be aware of security implications — agents can modify files, run commands, and make git changes without confirmation.

## Future Work

Potential enhancements for future versions:
- Drag-and-drop kanban columns
- Panel resize via drag handle
- Agent templates/presets
- Workflow recording and replay
- Integration with GitHub Issues/PRs
- Cost tracking and token usage monitoring
- Multi-repo support
- Agent-to-agent communication channels

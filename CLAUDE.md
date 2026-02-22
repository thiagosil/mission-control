# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Mission Control is a locally-run Elixir/Phoenix app that provides a web dashboard for spawning, monitoring, and coordinating multiple AI coding agents (Claude Code, Codex, etc.). It manages agents as supervised CLI subprocesses, streams their terminal output in real-time, and organizes work through a kanban task board. Designed for 2–5 concurrent agents scoped to a single git repo.

See `PRD.md` for the full product spec including user stories and planned modules.

## Commands

```bash
mix setup                        # Install deps, create DB, build assets
mix phx.server                   # Start server on localhost:4000
mix test                         # Run all tests (auto-creates and migrates DB)
mix test test/path/file_test.exs # Run a single test file
mix test test/path/file_test.exs:42  # Run a single test at line
mix format                       # Format all Elixir code
mix precommit                    # Compile (warnings-as-errors) + unused deps check + format + test
mix ecto.migrate                 # Run pending migrations
mix ecto.reset                   # Drop and recreate DB from scratch
```

The `precommit` alias runs in the test environment (configured via `cli/preferred_envs`).

## Architecture

**Stack**: Elixir 1.19+ / OTP 28 / Phoenix 1.8 / LiveView 1.1 / SQLite3 / Tailwind 4 + daisyUI

Three-layer design:
1. **Web layer** (`lib/mission_control_web/`) — Single LiveView (`DashboardLive`) with three-panel layout: agents sidebar | kanban task board | terminal/activity viewer. Real-time updates via PubSub. All UI state (~30 assigns) managed in one LiveView process with inline function components (`kanban_column/1`, `task_card/1`).
2. **Domain layer** (`lib/mission_control/`) — Context modules + OTP processes:
   - `Agents` — CRUD, spawn/stop/restart lifecycle. `AgentProcess` GenServer wraps an Erlang Port subprocess with 1000-line scrollback buffer. `AgentSupervisor` (DynamicSupervisor) + `AgentRegistry` for process management. On clean exit (code 0), associated tasks auto-transition from "in_progress" to "review".
   - `Tasks` — CRUD, column state machine (inbox → assigned → in_progress → review → done), assignment flow (`assign_and_start_task/1` creates branch + spawns agent). Dependency management with circular dependency prevention (DFS validation). Blocks movement to "in_progress" if dependencies are unresolved.
   - `Git` — Branch-per-task operations: `create_branch/2`, `checkout_branch/2`, `generate_branch_name/1`. All via `System.cmd`. Uses compile-time module injection (`@git Application.compile_env(:mission_control, :git_module, MissionControl.Git)`) for testability.
   - `Activity` — Append-only event log with filtering (`list/1` supports `type:`, `agent_id:`, `task_id:`, `since:`, `limit:`). Other modules call `Activity.append/1` on state changes.
   - `Orchestrator` — Goal decomposition: builds a shell command with a system prompt, spawns an agent to execute it, parses JSON task proposals (handles markdown fences + embedded JSON), and presents proposals for user approval via `approve_plan/1`.
   - `Config` — GenServer for runtime configuration loaded from three sources (priority: env vars > TOML file > defaults). Provides `agent_command_template/0` and `interpolate_command/2`. Supports `reload/0`.
3. **Persistence** (`lib/mission_control/repo.ex`) — Ecto with SQLite via `ecto_sqlite3`. Schemas: agents, tasks, events.

### Supervision Tree

`Application` starts (in order): Telemetry → Repo → Ecto.Migrator (auto-migrate) → DNSCluster → PubSub → Config → AgentRegistry → AgentSupervisor → stale agent reset → Endpoint.

### PubSub Topics

- `"agents"` — agent lifecycle broadcasts (`{:agent_changed, agent}`, `{:agent_exited, id, status}`)
- `"agent_output:<id>"` — per-agent terminal output (`{:output, id, line}`)
- `"tasks"` — task CRUD broadcasts (`{:task_created, t}`, `{:task_updated, t}`, `{:task_deleted, t}`)
- `"activity"` — activity feed (`{:new_event, event}`)

### Database Schemas

**agents**: `name` (string), `role` (string), `status` (string, default "stopped"), `config` (map), timestamps. Statuses: `running`, `stopped`, `crashed`.

**tasks**: `title` (string), `description` (text), `column` (string, default "inbox"), `priority` (string, default "normal"), `tags` ({:array, :string}), `branch_name` (string), `dependencies` ({:array, :integer}), `agent_id` (FK), timestamps. Columns: `inbox`, `assigned`, `in_progress`, `review`, `done`. Priorities: `normal`, `urgent`.

**events**: `type` (string), `message` (string), `metadata` (map), `agent_id` (FK), `task_id` (FK), timestamps. Types: `agent_spawned`, `agent_stopped`, `agent_restarted`, `agent_exited`, `task_created`, `task_updated`, `task_deleted`, `task_assigned`, `orchestrator_started`, `orchestrator_completed`, `orchestrator_failed`.

### Key Architectural Decisions

- **Ports over NIFs** for agent subprocesses — crash isolation + streaming
- **SQLite** — zero-dependency local tool, single-file DB
- **Agent-agnostic interface** — command template accepts any CLI tool (`claude`, `codex`, etc.)
- **Branch-per-task** git workflow — branches named `mc/<task-id>-<slug>`
- **Auto-migrate on boot** — Ecto.Migrator runs in the supervision tree (skipped for releases)
- **Layered config** — env vars > TOML (`mission_control.toml`) > defaults, via `Config` GenServer
- **Git module injection** — `@git` compile-time attribute in `Tasks` allows `Git.Sandbox` in tests

## Agent Configuration

Agent backend is configured via three layered sources (highest priority first):

1. **Environment variables**: `MC_AGENT_BACKEND`, `MC_AGENT_AUTO_ACCEPT` (true/1/false/0), `MC_AGENT_COMMAND`, `MC_AGENT_COMMAND_TEMPLATE`
2. **TOML file** (`mission_control.toml` in project root, optional):
   ```toml
   [agent]
   backend = "claude"       # or "codex"
   auto_accept = true       # auto-approve agent actions
   command = "/path/to/bin" # custom binary (optional)
   command_template = "..." # full template override (optional)
   ```
3. **Defaults**: backend `"claude"`, auto_accept `true`

Known backends and their templates:
- `claude` — `claude --dangerously-skip-permissions -p "{prompt}"` (auto_accept) / `claude -p "{prompt}"`
- `codex` — `codex --auto-approve "{prompt}"` (auto_accept) / `codex "{prompt}"`

`command_template` overrides everything. `command` replaces just the executable in the resolved template. `{prompt}` is the interpolation placeholder.

## UI & Styling

- Tailwind CSS 4 with daisyUI components (buttons, alerts, toasts)
- Two custom themes ("Graphite" style): "light" (default) and "dark", switchable via theme toggle with `localStorage` persistence (`phx:theme` key, `data-theme` attribute)
- Heroicons v2.2 for icons
- Terminal panel always uses dark theme (`data-theme="dark"`)
- Fonts: DM Sans (UI), JetBrains Mono (terminal/code)
- daisyUI, heroicons, and topbar are vendored in `assets/vendor/`
- Custom `TerminalScroll` LiveView hook for auto-scrolling terminal output
- Dashboard header shows active agent count, queued task count, and backend name
- Task filter bar for filtering by priority and tags

## Testing

- `DataCase` for domain tests (Ecto SQL Sandbox), `ConnCase` for LiveView tests
- `MissionControl.Git.Sandbox` (`test/support/git_sandbox.ex`) — no-op Git implementation used in tests via `:git_module` config
- Test agent config uses `echo` commands that exit immediately (configured in `config/test.exs`)
- Tests clean up DynamicSupervisor children in `on_exit` callbacks
- Notable dep: `lazy_html` (test only) for HTML assertions in LiveView tests

## Git Workflow

Branch naming: `mc/<issue-number>-<short-slug>` (e.g. `mc/1-phoenix-bootstrap`)

Use `/next-issue` command to pick up the next unblocked GitHub issue automatically.

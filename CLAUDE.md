# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Mission Control is a locally-run Elixir/Phoenix app that provides a web dashboard for spawning, monitoring, and coordinating multiple AI coding agents (Claude Code, Codex, etc.). It manages agents as supervised CLI subprocesses, streams their terminal output in real-time, and organizes work through a kanban task board. Designed for 2–5 concurrent agents scoped to a single git repo.

See `PRD.md` for the full product spec including user stories and planned modules.

## Commands

```bash
mix setup                        # Install deps, create DB, build assets
mix mission_control.start        # Start server on localhost:4000
mix phx.server                   # Alternative way to start server
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
1. **Web layer** (`lib/mission_control_web/`) — Single LiveView (`DashboardLive`) with three-panel layout: agents sidebar | kanban task board | terminal viewer. Real-time updates via PubSub.
2. **Domain layer** (`lib/mission_control/`) — Context modules + OTP processes:
   - `Agents` — CRUD, spawn/stop lifecycle. `AgentProcess` GenServer wraps an Erlang Port subprocess with 1000-line scrollback buffer. `AgentSupervisor` (DynamicSupervisor) + `AgentRegistry` for process management.
   - `Tasks` — CRUD, column state machine (inbox → assigned → in_progress → review → done), assignment flow (`assign_and_start_task/1` creates branch + spawns agent).
   - `Git` — Branch-per-task operations: `create_branch/2`, `checkout_branch/2`, `generate_branch_name/1`. All via `System.cmd`.
   - `Activity` — Append-only event log with filtering (`list/1` supports `type:`, `agent_id:`, `task_id:`, `since:`, `limit:`). Other modules call `Activity.append/1` on state changes.
3. **Persistence** (`lib/mission_control/repo.ex`) — Ecto with SQLite via `ecto_sqlite3`. Schemas: agents, tasks, events.

### Supervision Tree

`Application` starts (in order): Telemetry → Repo → Ecto.Migrator (auto-migrate) → DNSCluster → PubSub → AgentRegistry → AgentSupervisor → stale agent reset → Endpoint.

### PubSub Topics

- `"agents"` — agent lifecycle broadcasts (`{:agent_changed, agent}`, `{:agent_exited, id, status}`)
- `"agent_output:<id>"` — per-agent terminal output (`{:output, id, line}`)
- `"tasks"` — task CRUD broadcasts (`{:task_created, t}`, `{:task_updated, t}`, `{:task_deleted, t}`)
- `"activity"` — activity feed (`{:new_event, event}`)

### Key Architectural Decisions

- **Ports over NIFs** for agent subprocesses — crash isolation + streaming
- **SQLite** — zero-dependency local tool, single-file DB
- **Agent-agnostic interface** — command template accepts any CLI tool (`claude`, `codex`, etc.)
- **Branch-per-task** git workflow — branches named `mc/<task-id>-<slug>`
- **Auto-migrate on boot** — Ecto.Migrator runs in the supervision tree (skipped for releases)

## UI & Styling

- Tailwind CSS 4 with daisyUI components (buttons, alerts, toasts)
- Two themes: "light" (default) and "dark", switchable via theme toggle with localStorage persistence
- Heroicons v2.2 for icons
- Terminal panel always uses dark theme (`data-theme="dark"`)
- daisyUI and heroicons are vendored in `assets/vendor/`

## Git Workflow

Branch naming: `mc/<issue-number>-<short-slug>` (e.g. `mc/1-phoenix-bootstrap`)

Use `/next-issue` command to pick up the next unblocked GitHub issue automatically.

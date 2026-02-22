# Mission Control

A locally-run Elixir/Phoenix web dashboard for spawning, monitoring, and coordinating multiple AI coding agents. Manage agents as supervised CLI subprocesses, stream their terminal output in real-time, and organize work through a kanban task board.

Designed for 2-5 concurrent agents scoped to a single git repository.

## Features

- **Agent management** -- Spawn, stop, and restart AI agents (Claude Code, Codex, or any CLI tool) directly from the dashboard
- **Real-time terminal streaming** -- Watch agent output live via Phoenix PubSub, with 1000-line scrollback per agent
- **Kanban task board** -- Manage tasks through Inbox, Assigned, In Progress, Review, and Done columns with validated state transitions
- **Branch-per-task workflow** -- Automatically creates `mc/<id>-<slug>` git branches when assigning tasks to agents
- **Goal decomposition** -- Submit a high-level goal and an orchestrator agent breaks it into actionable subtasks with dependency relationships
- **Task dependencies** -- Define blocking relationships between tasks with circular dependency detection
- **Activity feed** -- Append-only event log with filtering by type, agent, and task
- **Configurable backends** -- Switch between Claude Code, Codex, or a custom CLI tool via TOML config or environment variables
- **Auto-accept mode** -- Agents run with permission-skipping flags for fully autonomous operation
- **Light/dark themes** -- Toggle between themes with localStorage persistence
- **Persistent state** -- SQLite database survives restarts; auto-migrates on boot

## Tech Stack

- **Elixir** 1.15+ / **OTP** 28
- **Phoenix** 1.8 / **LiveView** 1.1
- **SQLite3** via ecto_sqlite3
- **Tailwind CSS 4** + **daisyUI**
- **Heroicons** v2.2

## Prerequisites

- Elixir 1.15+ and Erlang/OTP 26+
- At least one supported AI CLI tool installed:
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`claude`)
  - [Codex](https://github.com/openai/codex) (`codex`)
  - Or any custom CLI that accepts a prompt argument

## Getting Started

```bash
# Clone and enter the repo
git clone <repo-url>
cd mission-control

# Install dependencies, create the database, and build assets
mix setup

# Start the server
mix mission_control.start
```

Then open [http://localhost:4000](http://localhost:4000) in your browser.

## Configuration

Copy the example config and edit as needed:

```bash
cp mission_control.toml.example mission_control.toml
```

### TOML options (`mission_control.toml`)

```toml
[agent]
backend = "claude"         # "claude", "codex", or any executable
auto_accept = true         # skip permission prompts
# command = "/path/to/custom-cli"
# command_template = "my-tool --flag '{prompt}'"
```

### Environment variables

Environment variables override TOML values:

| Variable | Description |
|---|---|
| `MC_AGENT_BACKEND` | CLI backend name (`claude`, `codex`, etc.) |
| `MC_AGENT_AUTO_ACCEPT` | `true`/`false` -- skip permission prompts |
| `MC_AGENT_COMMAND` | Override the base executable path |
| `MC_AGENT_COMMAND_TEMPLATE` | Fully custom command with `{prompt}` placeholder |

## Architecture

Three-layer design built on OTP supervision:

```
Application
  Telemetry
  Repo (SQLite)
  Ecto.Migrator (auto-migrate)
  PubSub
  Config (GenServer)
  AgentRegistry
  AgentSupervisor (DynamicSupervisor)
  Endpoint (Phoenix)
```

- **Web layer** -- Single LiveView (`DashboardLive`) with three-panel layout: agents sidebar, kanban board, terminal viewer. Real-time updates via PubSub.
- **Domain layer** -- Context modules (`Agents`, `Tasks`, `Activity`, `Git`, `Config`, `Orchestrator`) plus OTP processes (`AgentProcess` GenServer wrapping Erlang Ports, `AgentSupervisor`, `AgentRegistry`).
- **Persistence** -- Ecto with SQLite. Three schemas: agents, tasks, events.

### Key decisions

- **Ports over NIFs** for agent subprocesses -- crash isolation and natural streaming
- **SQLite** -- zero-dependency, single-file database
- **Agent-agnostic interface** -- command template accepts any CLI tool
- **Branch-per-task** -- branches named `mc/<task-id>-<slug>`
- **Auto-migrate on boot** -- Ecto.Migrator runs in the supervision tree

## Development

```bash
mix setup                        # Install deps, create DB, build assets
mix mission_control.start        # Start server on localhost:4000
mix test                         # Run all tests
mix test test/path/file_test.exs # Run a single test file
mix format                       # Format all Elixir code
mix precommit                    # Compile (warnings-as-errors) + format + test
mix ecto.reset                   # Drop and recreate DB from scratch
```

## Git Workflow

Branch naming convention: `mc/<issue-number>-<short-slug>` (e.g., `mc/1-phoenix-bootstrap`).

When a task is assigned to an agent, Mission Control automatically creates a branch and checks it out before the agent starts working.

## License

Private -- not yet published.

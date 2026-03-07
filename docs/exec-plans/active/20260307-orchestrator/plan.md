# Plan: Orchestrator — Multi-Plan Agent Coordinator

**Status:** In progress
**Created:** 2026-03-07

## Requirements

- Single orchestrator process with awareness of all exec plans (active, blocked, completed)
- Initiate ralph loops for plans — foreground (no worktree) or background (worktree)
- Dashboard showing all running loops, their status, iteration count, and last result
- View live terminal output of any running loop (drill-in)
- Close/stop terminals when done or on demand
- Works with existing ralph-loop.sh, ralph-worktree.sh, and terminal-session.sh
- Inspired by Supervibes (tmux-based multi-agent orchestration) and Canon SAS Conductor Agent spec

## Architecture

The orchestrator is a **Conductor pattern** — one process that manages N parallel
agent loops. It bridges two existing systems:

1. **Ralph Loop** (iteration engine) — worker/reviewer cycles on a single plan
2. **Worktree wrapper** (isolation) — git worktree per parallel loop

The orchestrator adds the missing layer: **plan awareness + session lifecycle + dashboard**.

### Design principles (from Canon SAS)

- **File-based state** — all orchestrator state in `.orchestrator/` as JSON/YAML files.
  Agents can read it, humans can inspect it, no database needed.
- **Terminal-as-file** — running loop output accessible as readable files (tmux capture-pane)
- **Agent-native** — orchestrator can be driven by a Claude agent OR by a human via CLI
- **No new IPC** — communication through files and tmux, same as Supervibes

### Modes

| Mode | Worktree | Terminal | Use case |
|------|----------|----------|----------|
| **Foreground** | No | Current shell | Single plan, watching output live |
| **Background** | Yes (`.claude/worktrees/`) | tmux session | Parallel plans, AFK execution |
| **Dashboard** | N/A | Dedicated tmux pane | Monitoring all running loops |

### Components

```
scripts/
  orchestrator.sh        ← Main entry point (CLI)
  orchestrator-dash.sh   ← Dashboard renderer (tmux pane)
  ralph-loop.sh          ← Existing (unchanged)
  ralph-worktree.sh      ← Existing (unchanged)

.orchestrator/
  state.json             ← Global orchestrator state
  sessions/
    <slug>.json          ← Per-session state (pid, tmux session, mode, status)
```

### CLI interface

```
Usage: orchestrator.sh <command> [options]

Plan management:
  list                    List all exec plans (active, blocked, completed)
  show <slug>             Show plan details and status

Session management:
  start <slug>            Start ralph loop for plan (foreground, no worktree)
  start <slug> --bg       Start ralph loop in background (worktree + tmux)
  stop <slug>             Stop a running loop (SIGTERM, cleanup)
  stop-all                Stop all running loops

Monitoring:
  status                  Show all running sessions with status
  watch <slug>            Attach to a running session's tmux pane (live output)
  logs <slug>             Show last N lines of a session's output
  dash                    Launch full dashboard (all sessions, auto-refresh)
```

### Dashboard layout

Single tmux window with dynamic panes:

```
┌─────────────────────────────────────────────────────────────┐
│ ORCHESTRATOR                                    3 running   │
│                                                             │
│ PLAN                        STATUS   ITER  LAST    MODE    │
│ 20260307-mcp-server         WORKER    2/20  REVISE  bg     │
│ 20260307-canon-templates    REVIEWER  1/20  —       bg     │
│ 20260306-cleanup-on-pr      IDLE      —     —       —      │
│                                                             │
│ [s]tart  [S]top  [w]atch  [q]uit                           │
│                                                             │
│ ─── Live: 20260307-mcp-server (iteration 2) ────────────── │
│ worker: implementing MCP tool #3 (canon_status)...         │
│ ...                                                         │
└─────────────────────────────────────────────────────────────┘
```

Top section: plan list with status. Bottom section: live output of selected session.
Keyboard shortcuts to switch between sessions, start/stop, or quit.

### State management

**`.orchestrator/state.json`:**
```json
{
  "version": 1,
  "sessions": {
    "20260307-mcp-server": {
      "slug": "20260307-mcp-server",
      "mode": "background",
      "pid": 12345,
      "tmux_session": "ralph-20260307-mcp-server",
      "worktree": ".claude/worktrees/20260307-mcp-server",
      "branch": "ralph/20260307-mcp-server",
      "started_at": "2026-03-07T14:30:00Z",
      "status": "running",
      "iteration": 2,
      "last_result": "REVISE"
    }
  }
}
```

Sessions are updated by polling `.ralph-state.json` in each plan directory.
The orchestrator doesn't modify ralph-loop internals — it reads their state files.

### Session lifecycle

**Start (background):**
1. Validate plan exists in `docs/exec-plans/active/<slug>/`
2. Call `ralph-worktree.sh <slug>` in a new tmux session
3. Record session in `.orchestrator/state.json`

**Start (foreground):**
1. Validate plan exists
2. Call `ralph-loop.sh <slug>` directly (blocks current shell)
3. No orchestrator state needed (single session)

**Stop:**
1. Send SIGTERM to ralph-loop PID
2. Ralph-loop.sh has existing trap handlers for cleanup
3. Update session state to "stopped"
4. If worktree has no changes, clean up

**Watch:**
1. `tmux attach -t ralph-<slug>` — attaches to the running session
2. Detach with Ctrl-B D to return to orchestrator

**Dashboard:**
1. Launches in a tmux pane
2. Polls `.orchestrator/state.json` + each session's `.ralph-state.json`
3. Renders table with `tput` / ANSI codes (no dependencies)
4. Bottom pane shows `tmux capture-pane` output from selected session

## Files to touch

| File | Change |
|------|--------|
| `scripts/orchestrator.sh` | New — main CLI entry point |
| `scripts/orchestrator-dash.sh` | New — dashboard renderer |
| `commands/apply-core.md` | Add orchestrator scripts to install manifest |

## Risks and open questions

- **tmux session naming collisions:** Using `ralph-<slug>` as session name.
  Slugs are unique (date-prefixed), so collisions are unlikely.
- **Stale sessions after crash:** Dashboard should detect dead PIDs and mark
  sessions as "crashed". `orchestrator.sh status` prunes dead sessions.
- **Dashboard complexity:** Start with the simplest shell-based renderer.
  Ink/React TUI is a future upgrade if shell proves too limited.

## Progress log

- [x] Resolve discovery questions and architecture decisions
- [ ] Write `scripts/orchestrator.sh` — CLI with list, start, stop, status, watch, logs
- [ ] Write `scripts/orchestrator-dash.sh` — dashboard renderer with plan table + live output
- [ ] Add `.orchestrator/` state directory management (create, read, update, prune)
- [ ] Implement foreground mode (direct ralph-loop.sh call)
- [ ] Implement background mode (ralph-worktree.sh in tmux session)
- [ ] Implement stop/stop-all with graceful SIGTERM + cleanup
- [ ] Implement watch (tmux attach to session)
- [ ] Implement logs (tmux capture-pane last N lines)
- [ ] Add dead PID detection and stale session pruning
- [ ] Add orchestrator scripts to `commands/apply-core.md`
- [ ] Test: start 2 background loops, verify dashboard shows both
- [ ] Test: stop one loop, verify cleanup and state update
- [ ] Test: watch a running session, detach, return to dashboard

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Shell scripts (bash), not Node/TypeScript | Supervibes uses Node server + HTML dashboard | Consistent with existing ralph-loop.sh stack. No new runtime dependency. Dashboard is terminal-native. |
| File-based state (`.orchestrator/`) | SQLite, in-memory | Canon SAS principle: file-based state for transparency and portability. Agents can read/write JSON files. |
| tmux for session management | Screen, background processes, Claude Agent tool | Already using tmux in terminal-session.sh. Proven pattern. Supports attach/detach for watch mode. |
| Read-only integration with ralph-loop | Modify ralph-loop for orchestrator hooks | Orchestrator reads `.ralph-state.json` — no changes to ralph-loop internals. Loose coupling. |
| Shell-based dashboard (tput/ANSI) | Ink React TUI, HTML dashboard | Simplest implementation. No build step. Runs in any terminal. Upgrade to Ink later if needed. |
| Foreground = no worktree, Background = worktree | Always use worktrees | Foreground is simpler for single-plan work. Worktrees add overhead only needed for parallelism. |

## Completion criteria

- [ ] `orchestrator.sh list` shows all exec plans with status
- [ ] `orchestrator.sh start <slug> --bg` launches ralph loop in background worktree
- [ ] `orchestrator.sh start <slug>` runs ralph loop in foreground
- [ ] `orchestrator.sh status` shows all running sessions
- [ ] `orchestrator.sh stop <slug>` gracefully stops a running loop
- [ ] `orchestrator.sh watch <slug>` attaches to a running session
- [ ] `orchestrator.sh dash` launches dashboard with plan table and live output
- [ ] Two background loops can run simultaneously without conflicts

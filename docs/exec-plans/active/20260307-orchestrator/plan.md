# Plan: Orchestrator Agent — Multi-Plan Conductor

**Status:** In progress
**Created:** 2026-03-07

## Requirements

- **Agent-first:** The orchestrator is a Claude agent you chat with in natural language.
  Ask it "what plans are active?", "start the MCP server plan in background",
  "show me what the docs-update loop is doing", "stop everything".
- Awareness of all exec plans (active, blocked, completed)
- Initiate ralph loops — foreground (no worktree) or background (worktree + tmux)
- Ink TUI dashboard showing all running loops, status, iteration count, last result
- View live terminal output of any running loop (drill-in)
- Close/stop terminals when done or on demand
- Works with existing ralph-loop.sh, ralph-worktree.sh, and terminal-session.sh
- Grounded in Canon SAS Conductor Agent spec and Supervibes patterns

## Architecture

The orchestrator is a **Claude agent with shell tools** — not a shell script with
subcommands. The agent has a persona prompt and access to helper scripts that it
calls via Bash. The user talks to it naturally; the agent translates intent into
actions.

### Why agent, not CLI

- Natural language: "start the two blocked plans once I answer their questions"
- Context: agent knows which plans exist, what state they're in, what depends on what
- Decision-making: agent can suggest which plan to run next based on dependencies
- Adaptable: agent can handle "stop everything and show me what happened" in one turn

### Components

```
agents/
  orchestrator.md          ← Agent persona + instructions + available tools

scripts/
  orch-list.sh             ← List plans with status (active/blocked/completed)
  orch-start.sh            ← Start ralph loop (foreground or background)
  orch-stop.sh             ← Stop a running loop (SIGTERM + cleanup)
  orch-status.sh           ← Show all running sessions from state file
  orch-watch.sh            ← Capture last N lines from a tmux session
  orch-dash.sh             ← Launch Ink dashboard in a tmux pane

scripts/terminal-ui/src/
  orchestrator-app.tsx     ← New Ink app for orchestrator dashboard
  session-table.tsx        ← Plan/session table component
  session-detail.tsx       ← Live output panel for selected session

.orchestrator/
  state.json               ← Global orchestrator state (sessions registry)
```

### Agent persona (`agents/orchestrator.md`)

The agent acts as a **Conductor** — a tech lead who manages parallel development
streams. It has access to:

1. **Plan awareness tools** — list plans, read plan.md, check completion criteria
2. **Session management tools** — start/stop ralph loops, check status
3. **Monitoring tools** — read live output, launch dashboard
4. **State tools** — read/update `.orchestrator/state.json`

The agent is invoked as a subagent or directly:
```bash
claude -p < agents/orchestrator.md
# or interactively:
claude --agent agents/orchestrator.md
```

Or from within a Claude session via the Agent tool with the orchestrator prompt.

### Ink Dashboard

Extends the existing Ink TUI (`scripts/terminal-ui/`). New orchestrator view
watches `.orchestrator/state.json` instead of a single `.terminal-ui-state.json`.

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│ ORCHESTRATOR                              3 sessions active │
├─────────────────────────────────────────────────────────────┤
│ PLAN                        MODE   ITER  RESULT   STATUS   │
│ 20260307-mcp-server         bg      2/20  REVISE  worker   │
│ 20260307-canon-templates    bg      1/20  —       reviewer │
│ 20260306-cleanup-on-pr      —       —     —       idle     │
├─────────────────────────────────────────────────────────────┤
│ ─── 20260307-mcp-server (iter 2, worker) ──────────────── │
│ implementing MCP tool #3 (canon_status)...                  │
│ reading src/mcp/tools.ts...                                 │
│ writing tests for canon_status handler...                   │
└─────────────────────────────────────────────────────────────┘
```

Top: session table (all plans). Bottom: live output of selected session.
State file is polled via chokidar (same pattern as existing App component).

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

The orchestrator agent reads this file to know what's running. The helper scripts
update it. Ralph loop's `.ralph-state.json` is the source of truth for iteration
data — the orchestrator scripts sync from it.

### Helper scripts (agent's tools)

Each script is a small, focused tool the agent calls via Bash:

| Script | Purpose | Args |
|--------|---------|------|
| `orch-list.sh` | List all plans with status | `[--active\|--completed\|--all]` |
| `orch-start.sh` | Start ralph loop | `<slug> [--bg]` |
| `orch-stop.sh` | Stop running loop | `<slug> \| --all` |
| `orch-status.sh` | Show running sessions | (reads state.json) |
| `orch-watch.sh` | Capture live output | `<slug> [--lines N]` |
| `orch-dash.sh` | Launch Ink dashboard | (starts in tmux pane) |

The agent doesn't need to know the script internals — it calls them by name
and reads stdout. Example agent interaction:

```
User: "what plans are active?"
Agent: runs `bash scripts/orch-list.sh --active`
Agent: "You have 3 active plans: ..."

User: "start the MCP server plan in background"
Agent: runs `bash scripts/orch-start.sh 20260307-mcp-server --bg`
Agent: "Started ralph loop for 20260307-mcp-server in background on branch ralph/20260307-mcp-server"

User: "what's happening in the mcp server loop?"
Agent: runs `bash scripts/orch-watch.sh 20260307-mcp-server --lines 30`
Agent: "The worker is on iteration 2, currently implementing..."

User: "stop everything"
Agent: runs `bash scripts/orch-stop.sh --all`
Agent: "Stopped 2 sessions. mcp-server had changes on branch ralph/..."
```

## Files to touch

| File | Change |
|------|--------|
| `agents/orchestrator.md` | New — agent persona with tool instructions |
| `scripts/orch-list.sh` | New — list exec plans with status |
| `scripts/orch-start.sh` | New — start ralph loop (fg or bg) |
| `scripts/orch-stop.sh` | New — stop running loop |
| `scripts/orch-status.sh` | New — show running sessions |
| `scripts/orch-watch.sh` | New — capture live output from tmux session |
| `scripts/orch-dash.sh` | New — launch Ink orchestrator dashboard |
| `scripts/terminal-ui/src/orchestrator-app.tsx` | New — Ink orchestrator view |
| `scripts/terminal-ui/src/session-table.tsx` | New — session table component |
| `scripts/terminal-ui/src/session-detail.tsx` | New — live output panel |
| `scripts/terminal-ui/src/orch-types.ts` | New — orchestrator state types |
| `commands/apply-core.md` | Add orchestrator scripts + agent to install manifest |

## Risks and open questions

- **Agent invocation pattern:** How exactly does the user launch the orchestrator
  agent? Options: `/orchestrate` command, `claude --agent`, or just a system prompt.
  Decision: Start with an agent file (`agents/orchestrator.md`) that can be used
  any of these ways. Add a `/orchestrate` command later that loads it.
- **Ink dashboard as separate process:** The dashboard runs in its own tmux pane.
  The agent can launch it but doesn't render it inline. This matches existing
  terminal-session.sh pattern.
- **State file locking:** Multiple scripts may write `.orchestrator/state.json`
  concurrently. Mitigation: atomic writes (write to tmp, mv into place) — same
  pattern as terminal-ui-write.sh.

## Progress log

- [x] Resolve architecture (agent-first, not CLI-first)
- [ ] Write `agents/orchestrator.md` — agent persona with tool catalog
- [ ] Write `scripts/orch-list.sh` — scan exec-plans dirs, output plan table
- [ ] Write `scripts/orch-start.sh` — start ralph loop (delegates to ralph-loop.sh or ralph-worktree.sh)
- [ ] Write `scripts/orch-stop.sh` — SIGTERM + cleanup + state update
- [ ] Write `scripts/orch-status.sh` — read state.json, sync from .ralph-state.json files
- [ ] Write `scripts/orch-watch.sh` — tmux capture-pane wrapper
- [ ] Write `scripts/orch-dash.sh` — launch Ink dashboard in tmux
- [ ] Write Ink orchestrator components (orchestrator-app.tsx, session-table.tsx, session-detail.tsx, orch-types.ts)
- [ ] Add `.orchestrator/` state management (create, atomic write, prune dead PIDs)
- [ ] Add orchestrator to `commands/apply-core.md` install manifest
- [ ] Test: chat with agent, ask to list plans, start a background loop
- [ ] Test: agent launches dashboard, user sees running sessions
- [ ] Test: agent stops a loop, verifies cleanup

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Agent with shell tools, not shell CLI | Pure shell CLI (orchestrator.sh) | Natural language interaction. Agent has context of plans, can suggest next actions, handle complex requests in one turn. |
| Ink TUI dashboard | Shell-based tput/ANSI renderer | Already have Ink infrastructure in scripts/terminal-ui/. Consistent with existing dashboard. Richer rendering. |
| Helper scripts as agent tools | MCP server, direct Bash commands | Scripts are testable standalone, reusable outside agent context. Agent calls them via Bash — simple, no new protocol. |
| File-based state (`.orchestrator/`) | SQLite, in-memory | Canon SAS principle: file-based for transparency. Agents can read JSON. Humans can inspect. |
| Atomic writes for state | File locking (flock) | Same proven pattern as terminal-ui-write.sh. Simpler than locks. |

## Completion criteria

- [ ] `agents/orchestrator.md` defines agent persona with tool catalog
- [ ] Agent can list all exec plans with status via natural language
- [ ] Agent can start ralph loops in foreground or background
- [ ] Agent can stop running loops and report results
- [ ] Agent can show live output from any running session
- [ ] Ink dashboard shows all sessions with status and live output
- [ ] Two background loops can run simultaneously without conflicts

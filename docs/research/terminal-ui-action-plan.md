# Terminal UI — Action Plan

**Date:** 2026-03-03
**Research:** `docs/research/terminal-ui-for-agent-dashboard.md`

---

## Architecture

```
tmux session (Core script)
├── Left pane:  claude (chat with Canon context)
└── Right pane: terminal-ui (Ink status dashboard, read-only)
        ↑
        reads
        ↑
    state.json (blackboard pattern)
        ↑
        writes
        ↑
    Canon agents / Ralph Loop / automation
```

---

## Plan 1: State File Spec

Define the JSON schema that any automation writes and `terminal-ui` reads.

**Generic shape:**

```jsonc
{
  "phase": "scaffold",           // current pipeline phase
  "status": "running",           // running | paused | idle | error
  "startedAt": "2026-03-03T...", // ISO timestamp
  "logs": [                      // recent log entries (ring buffer)
    { "ts": "...", "level": "info", "msg": "Scaffolding repo..." }
  ],
  "metrics": {                   // key-value pairs, domain-extensible
    "iteration": 3,
    "elapsed": "2m14s"
  }
}
```

- Canon extends with: strategy name, market, positions, balance
- Ralph Loop extends with: iteration count, max iterations, SHIP/REVISE decision
- Schema lives in `scripts/terminal-ui/src/types.ts` (source of truth)

**Deliverable:** TypeScript interface + JSON schema file.

---

## Plan 2: terminal-ui (Ink Status Dashboard)

Small Ink (React/TS) package. ~100-200 lines TSX.

**Location:** `scripts/terminal-ui/`
**Install target:** `~/.claude/scripts/terminal-ui/` (via `/apply-core`)

**Behavior:**
- Takes state file path as argument: `terminal-ui --state .canon/state.json`
- Watches file for changes, re-renders on update
- Renders: phase indicator, status badge, log stream, metrics table
- Graceful fallback if file missing or malformed

**Components:**
- `StatusBar` — phase + status badge (color-coded)
- `LogPanel` — scrolling log entries (most recent N)
- `MetricsPanel` — key-value pairs from state file

**Dependencies:** `ink`, `react`, `@inkjs/ui` (spinners, badges), `chokidar` (file watcher)

**Deliverable:** Working `terminal-ui` package, runnable with `npx` or direct node invocation.

---

## Plan 3: tmux Session Launcher

Shell script that creates a named tmux session with the standard two-pane layout.

**Location:** `scripts/terminal-session.sh`
**Install target:** `~/.claude/scripts/terminal-session.sh` (via `/apply-core`)

**Behavior:**
```bash
terminal-session.sh --name canon --state .canon/state.json
```

- Creates tmux session `<name>` if not exists, attaches if exists
- Splits: left pane (chat, 60%) + right pane (terminal-ui, 40%)
- Right pane runs `terminal-ui --state <path>`
- Status bar: session name, elapsed time
- Left pane is where the user runs `claude` or any command

**Deliverable:** Working shell script, <50 lines.

---

## Plan 4: /canon-start Command

Canon-specific guided workflow. The agent knows the pipeline and drives it.

**Location:** `canon/commands/canon-start.md`

**Pipeline phases:**
1. **Init** — check for existing repo, run `canon-init` if needed
2. **Scaffold** — verify `.canon/` structure, fill gaps
3. **Strategy** — prompt user for strategy direction or use existing spec
4. **Run** — start automation, update state file as phases progress

**Behavior:**
- Launches tmux session via `terminal-session.sh`
- Walks user through phases, recommends next step at each point
- Writes state updates to `.canon/state.json` as phases progress
- Asks only when blocked (missing auth, config decisions, ambiguous input)

**Deliverable:** Skill/command markdown that teaches the agent the full workflow.

---

## Plan 5: Wiring

Connect all pieces end-to-end.

- `/canon-start` calls `terminal-session.sh` with Canon state path
- Canon agents write to `.canon/state.json` during execution
- `terminal-ui` renders updates in real time
- Ralph Loop writes to its own state file; same `terminal-ui` renders it
- `/apply-core` installs `terminal-ui` and `terminal-session.sh` globally

**Deliverable:** End-to-end flow working: user runs `/canon-start`, sees two panes,
agent drives workflow, status updates appear in dashboard.

---

## Execution Order

Plans 1 → 2 → 3 can run in parallel (no dependencies between them after schema is defined).
Plan 4 can start once the schema shape is agreed.
Plan 5 requires 1-4 complete.

```
Plan 1 (schema) ──┐
Plan 2 (ink app) ──┼──→ Plan 5 (wiring)
Plan 3 (tmux)   ──┤
Plan 4 (command) ──┘
```

---

## Scope Control

If timeline pressure hits:
- **Cut first:** Rich metrics panel in terminal-ui (just show phase + logs)
- **Cut second:** Generic state schema (hardcode Canon shape, extract later)
- **Keep:** tmux launcher + `/canon-start` command (these deliver the demo experience)

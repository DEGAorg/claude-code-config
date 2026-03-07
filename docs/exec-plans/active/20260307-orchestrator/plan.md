# Plan: Orchestrator Agent — Multi-Plan Conductor

**Status:** In progress
**Created:** 2026-03-07
**Reference:** `ace/notes/orch.md` (PRD), Canon SAS Conductor Agent spec, Supervibes

## Requirements

- **Agent-first:** The orchestrator is a Claude agent you chat with in natural language.
  Ask it "how are we?", "run task 1 foreground", "stop everything".
- Awareness of all exec plans (active, blocked, completed)
- **Per-item parallelism:** Decompose a plan's progress log items into parallel workers,
  respecting dependencies between items. Worker pool with `max_parallel_workers`.
- **Final whole-plan review** after all items complete — one reviewer pass on the full diff
- Foreground mode: tmux grid (orchestrator + dashboard + up to 4 worker panes)
- Background mode: worktree + detached tmux, queryable via agent
- Ink TUI dashboard showing all workers, item progress, iteration count
- View live terminal output of any worker (drill-in)
- Close/stop terminals when done or on demand
- Context isolation: each worker starts with clean context + summary of prior items
- Shared context in handoffs: workers can read summaries from completed sibling items

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

### Startup: script bootstraps agent

**Foreground:** A shell script (`orch-grid.sh`) runs first. It creates the tmux
session, splits the grid (orchestrator + dashboard + 4 worker panes), launches
the Ink dashboard, then starts the orchestrator agent in the top-left pane.
The agent wakes up inside an already-built grid and manages workers from there.

```
User runs: bash scripts/orch-grid.sh <slug>
  → tmux session "orch-<slug>" created with 6 panes
  → Ink dashboard starts in top-right pane
  → orchestrator agent starts in top-left pane (claude with persona)
  → agent reads plan, parses items, starts scheduling workers into bottom panes
```

**Background:** No grid needed. User starts the agent in any terminal (or as a
subagent). The agent dispatches workers as detached tmux sessions with worktrees.
Dashboard is optional — agent launches it on request.

```
User runs: claude (with orchestrator prompt loaded)
  → agent reads plan, starts workers in background
  → user queries status via chat
```

The script handles mechanical tmux setup (deterministic, no AI needed). The agent
handles scheduling, monitoring, and user interaction (needs reasoning).

### Execution model: per-item workers

A plan's progress log contains items (checkboxes). The orchestrator parses these
into a work queue. Items can declare dependencies on other items. Independent items
run in parallel up to `max_parallel_workers`.

```
Plan: 20260307-mcp-server
Progress log items:
  1. [ ] Define MCP tool interfaces        (no deps)
  2. [ ] Implement canon_status tool        (deps: 1)
  3. [ ] Implement canon_market tool        (deps: 1)
  4. [ ] Implement canon_position tool      (deps: 1)
  5. [ ] Write integration tests            (deps: 2, 3, 4)
  6. [ ] Update apply-canon install         (deps: 2, 3, 4)

max_parallel_workers: 4

Execution:
  Wave 1: item 1 (single, has dependents)
  Wave 2: items 2, 3, 4 (parallel, all depend on 1)
  Wave 3: items 5, 6 (parallel, depend on wave 2)
  Final:  whole-plan review on full diff
```

Each worker is a ralph loop scoped to one item. Workers run in their own
worktree (background) or tmux pane (foreground).

### Item dependency format

Dependencies are declared inline in the progress log using `(deps: N, M)` syntax:

```markdown
## Progress log

- [ ] Define MCP tool interfaces
- [ ] Implement canon_status tool (deps: 1)
- [ ] Implement canon_market tool (deps: 1)
- [ ] Write integration tests (deps: 2, 3)
```

The orchestrator parses this. Items without `(deps:)` are ready immediately.
Items are numbered by their position in the list (1-indexed).

### Worker lifecycle

```
Queued → Assigned → Running (ralph loop) → Review → Completed
                         ↓
                    Review Fail → Iteration Retry
```

After all items complete:
```
All items done → Final whole-plan review (reviewer sees full diff) → SHIP or REVISE
```

If final review says REVISE, the orchestrator identifies which items need rework
and re-queues them.

### Context management

Each worker starts with:
1. Clean context (no prior conversation)
2. The plan's requirements and approach sections
3. Only its assigned item description
4. Summaries from completed dependency items (`work-summary.txt` per item)

This keeps context minimal. Workers don't see the full plan history — only
what they need.

**Shared handoff:** When item 2 depends on item 1, item 2's worker receives
item 1's `work-summary.txt` as part of its context. This is the "summarized
state passing" from the PRD.

### Tmux grid layout (foreground mode)

```
+------------------------+------------------------+
|    orchestrator        |      dashboard         |
|    (agent chat)        |      (Ink TUI)         |
+------------+-----------+------------+-----------+
|  worker 1  | worker 2  |  worker 3  | worker 4  |
+------------+-----------+------------+-----------+
```

- Top-left: orchestrator agent (user chats here)
- Top-right: Ink dashboard (session table + live metrics)
- Bottom: up to 4 worker panes (foreground workers visible live)
- Workers beyond 4 queue until a pane frees up

The orchestrator manages the grid via tmux commands. When a worker finishes,
its pane is released for the next queued item.

### Background mode

- Workers run in worktrees (`.claude/worktrees/<slug>-item-<N>`)
- Each in a detached tmux session
- No visible panes — agent queries status via `orch-watch.sh`
- Dashboard still available (launched in its own terminal if requested)

### Components

```
agents/
  orchestrator.md          ← Agent persona + instructions + available tools

scripts/
  orch-list.sh             ← List plans with status
  orch-start.sh            ← Start plan execution (parses items, spawns workers)
  orch-stop.sh             ← Stop workers (one, all, or by plan)
  orch-status.sh           ← Show running sessions from state file
  orch-watch.sh            ← Capture last N lines from a worker's tmux session
  orch-dash.sh             ← Launch Ink dashboard in a tmux pane
  orch-grid.sh             ← Set up foreground tmux grid layout
  orch-parse-items.sh      ← Parse progress log into item queue with deps

scripts/terminal-ui/src/
  orchestrator-app.tsx     ← Ink orchestrator dashboard view
  session-table.tsx        ← Worker/item table component
  session-detail.tsx       ← Live output panel for selected worker
  orch-types.ts            ← Orchestrator state types

.orchestrator/
  state.json               ← Global orchestrator state
  items/
    <slug>/
      item-1.json          ← Per-item state (status, worker pid, summary)
      item-2.json
      ...
```

### Agent persona (`agents/orchestrator.md`)

The agent acts as a **Conductor** — a tech lead who manages parallel development
streams. It has access to:

1. **Plan awareness** — list plans, read plan.md, parse items and dependencies
2. **Worker management** — start/stop workers, check item status
3. **Monitoring** — read live output, launch dashboard, launch grid
4. **Scheduling** — determine which items are ready based on dependency resolution
5. **Final review** — trigger whole-plan review after all items complete

### Ink Dashboard

Extends the existing Ink TUI (`scripts/terminal-ui/`). New orchestrator view
watches `.orchestrator/state.json`.

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│ ORCHESTRATOR                              5 items, 3 active │
├─────────────────────────────────────────────────────────────┤
│ PLAN: 20260307-mcp-server                     max workers: 4│
│                                                             │
│ #  ITEM                         STATUS   ITER  WORKER      │
│ 1  Define MCP interfaces        done     1/3   —           │
│ 2  Implement canon_status        worker   2/3   pane-1     │
│ 3  Implement canon_market        worker   1/3   pane-2     │
│ 4  Implement canon_position      worker   1/3   pane-3     │
│ 5  Write integration tests       queued   —     —           │
├─────────────────────────────────────────────────────────────┤
│ ─── worker pane-2: item 3 (iter 1) ─────────────────────── │
│ reading canon/skills/prediction-markets.md...               │
│ writing src/mcp/canon_market.ts...                          │
└─────────────────────────────────────────────────────────────┘
```

### State management

**`.orchestrator/state.json`:**
```json
{
  "version": 1,
  "plan": "20260307-mcp-server",
  "max_parallel_workers": 4,
  "mode": "foreground",
  "items": [
    {
      "id": 1,
      "description": "Define MCP tool interfaces",
      "deps": [],
      "status": "done",
      "worker_pid": null,
      "tmux_pane": null,
      "iteration": 1,
      "last_result": "SHIP"
    },
    {
      "id": 2,
      "description": "Implement canon_status tool",
      "deps": [1],
      "status": "running",
      "worker_pid": 12345,
      "tmux_pane": "pane-1",
      "worktree": ".claude/worktrees/20260307-mcp-server-item-2",
      "iteration": 2,
      "last_result": "REVISE"
    }
  ],
  "final_review": {
    "status": "pending",
    "result": null
  }
}
```

### Helper scripts (agent's tools)

| Script | Purpose | Args |
|--------|---------|------|
| `orch-list.sh` | List all plans with status | `[--active\|--completed\|--all]` |
| `orch-parse-items.sh` | Parse plan progress log into items + deps | `<slug>` |
| `orch-start.sh` | Start plan execution (parses items, schedules workers) | `<slug> [--bg] [--max-workers N]` |
| `orch-stop.sh` | Stop workers | `<slug> [--item N] \| --all` |
| `orch-status.sh` | Show running sessions and item progress | `[<slug>]` |
| `orch-watch.sh` | Capture live output from a worker | `<slug> --item N [--lines 30]` |
| `orch-dash.sh` | Launch Ink dashboard | `<slug>` |
| `orch-grid.sh` | Set up foreground tmux grid | `<slug> [--max-panes 4]` |

Example agent interaction:

```
User: "how are we?"
Agent: runs orch-list.sh --active, orch-status.sh
Agent: "3 active plans. mcp-server is running — 2 of 5 items done,
        3 workers active. canon-templates is idle."

User: "run mcp-server foreground"
Agent: runs orch-grid.sh 20260307-mcp-server
Agent: runs orch-start.sh 20260307-mcp-server --max-workers 4
Agent: "Grid is up. Item 1 has no deps — starting now in pane-1.
        Items 2-4 will start once item 1 finishes."

User: "what's worker 2 doing?"
Agent: runs orch-watch.sh 20260307-mcp-server --item 3 --lines 20
Agent: "Worker for item 3 (canon_market) is on iteration 1,
        writing the market data fetcher..."

User: "stop everything"
Agent: runs orch-stop.sh --all
Agent: "Stopped 3 workers. Items 2-4 have changes on their branches."
```

## Files to touch

| File | Change |
|------|--------|
| `agents/orchestrator.md` | New — agent persona with tool instructions |
| `scripts/orch-list.sh` | New — list exec plans with status |
| `scripts/orch-parse-items.sh` | New — parse progress log into items + deps |
| `scripts/orch-start.sh` | New — start plan execution, schedule workers |
| `scripts/orch-stop.sh` | New — stop workers |
| `scripts/orch-status.sh` | New — show running sessions and items |
| `scripts/orch-watch.sh` | New — capture live output from worker |
| `scripts/orch-dash.sh` | New — launch Ink dashboard |
| `scripts/orch-grid.sh` | New — set up foreground tmux grid layout |
| `scripts/terminal-ui/src/orchestrator-app.tsx` | New — Ink orchestrator view |
| `scripts/terminal-ui/src/session-table.tsx` | New — item/worker table component |
| `scripts/terminal-ui/src/session-detail.tsx` | New — live output panel |
| `scripts/terminal-ui/src/orch-types.ts` | New — orchestrator state types |
| `commands/apply-core.md` | Add orchestrator scripts + agent to install manifest |

## Risks and open questions

- **Item granularity:** Progress log items vary in size. Some are 5 minutes of
  work, others are hours. Workers may finish at very different times. The pool
  model handles this naturally — fast items free up slots for the next wave.
- **Merge conflicts in parallel items:** Mitigated by worktrees (each item gets
  its own branch). Final review catches integration issues. If conflicts occur,
  the orchestrator agent can mediate.
- **Worker scope enforcement:** Each worker should only touch files relevant to
  its item. Enforced via prompt instructions (worker prompt includes item scope).
  Not enforced structurally in v1.
- **State file concurrency:** Multiple workers updating state simultaneously.
  Mitigation: atomic writes (tmp + mv). Each item has its own state file to
  reduce contention.

## Progress log

- [x] Resolve architecture (agent-first, per-item workers, tmux grid)
- [ ] Write `scripts/orch-parse-items.sh` — parse progress log into item queue with deps
- [ ] Write `scripts/orch-grid.sh` — set up foreground tmux grid (orch + dash + 4 worker panes)
- [ ] Write `scripts/orch-start.sh` — schedule workers by dependency wave
- [ ] Write `scripts/orch-stop.sh` — stop workers by item, plan, or all
- [ ] Write `scripts/orch-status.sh` — read state, sync from worker state files
- [ ] Write `scripts/orch-watch.sh` — tmux capture-pane for specific worker
- [ ] Write `scripts/orch-list.sh` — scan exec-plans dirs, output plan table
- [ ] Write `scripts/orch-dash.sh` — launch Ink dashboard in tmux pane
- [ ] Write `agents/orchestrator.md` — agent persona with full tool catalog
- [ ] Write Ink components (orchestrator-app.tsx, session-table.tsx, session-detail.tsx, orch-types.ts)
- [ ] Add `.orchestrator/` state management (create, atomic write, prune dead PIDs)
- [ ] Implement final whole-plan review after all items complete
- [ ] Add orchestrator to `commands/apply-core.md` install manifest
- [ ] Test: parse a plan with deps, verify wave scheduling is correct
- [ ] Test: foreground grid with 2 parallel workers visible in panes
- [ ] Test: background mode with 3 workers, query status via agent
- [ ] Test: final review triggers after all items done

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Agent with shell tools | Pure shell CLI | Natural language. Agent has context, suggests next actions, handles complex requests. |
| Script bootstraps agent (Option A) | Agent bootstraps grid (Option B) | Agent can't move itself into a tmux pane after starting. tmux setup is deterministic shell work. Agent starts already inside the grid. |
| Per-item workers with dependency DAG | Per-plan workers (one loop per plan) | True parallelism within a plan. Faster completion. Matches PRD worker pool model. |
| Final whole-plan review after all items | No final review, rely on per-item review | Integration issues only visible at plan level. Per-item reviews miss cross-item regressions. |
| Ink TUI dashboard | Shell-based tput/ANSI | Already have Ink infrastructure. Consistent. Richer rendering. |
| Tmux grid: orch + dash + 4 workers | Separate terminals per worker | Single window visibility. User sees everything. Matches PRD Section 8.1. |
| Shared summaries in handoffs, no shared memory | Full shared context between workers | Keeps context minimal. Workers only see what they need. Summaries are sufficient (PRD Section 6). |
| `(deps: N, M)` inline syntax | Separate dependency file, YAML config | Zero friction — deps declared right where items are written. Human-readable. |
| Worker pool with max_parallel_workers | Unlimited parallelism, sequential only | Resource control. User decides how many concurrent sessions. Matches PRD Section 13. |
| Worktree per item (background) | Shared worktree for all items | Isolation. No merge conflicts during parallel work. Each item has its own branch. |

## Completion criteria

- [ ] `agents/orchestrator.md` defines agent persona with tool catalog
- [ ] Agent can list all exec plans with status via natural language
- [ ] Agent can parse a plan's progress log into items with dependencies
- [ ] Agent can start per-item workers respecting dependency order
- [ ] Foreground mode: tmux grid with orchestrator + dashboard + up to 4 worker panes
- [ ] Background mode: detached workers, queryable via agent
- [ ] Agent can stop workers and report results
- [ ] Agent can show live output from any worker
- [ ] Ink dashboard shows items, workers, and live output
- [ ] Final whole-plan review runs after all items complete
- [ ] Two parallel workers can run on the same plan without conflicts

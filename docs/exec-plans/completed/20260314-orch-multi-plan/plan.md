# Plan: Multi-Plan Orchestration with Master State

**Status:** In progress
**Created:** 2026-03-14

## Requirements

- Run multiple plans simultaneously, each fully isolated
- Introduce a master state file that tracks all running plans as a registry
- Per-plan state files namespaced by slug (no shared state between plans)
- Dashboard can display the master view (all plans) or drill into a single plan
- Workers from different plans don't conflict on files (worktree isolation)

## Current state

The orchestrator has a single `.orchestrator/state.json` that holds one plan's
items. Launching a second plan wipes the first plan's state (orch-run.sh:122-129).
Tmux sessions (`orch-${SLUG}`) and done-files (`done/${SLUG}/`) are already
namespaced — the state file is the only blocker.

## Architecture

### Directory layout (after)

```
.orchestrator/
├── master.json                   ← NEW: registry of all running plans
├── plans/
│   ├── <slug-a>/
│   │   ├── state.json            ← per-plan state (moved from root)
│   │   ├── done/                 ← done-files (moved from done/<slug>/)
│   │   └── reviews/              ← review files (moved from reviews/<slug>/)
│   └── <slug-b>/
│       ├── state.json
│       ├── done/
│       └── reviews/
└── worktrees/                    ← worktree checkouts per plan
    ├── <slug-a>/                 ← git worktree for plan A's workers
    └── <slug-b>/                 ← git worktree for plan B's workers
```

### Master state shape (`master.json`)

```json
{
  "version": 1,
  "plans": [
    {
      "slug": "20260314-add-auth",
      "status": "running",
      "statePath": "plans/20260314-add-auth/state.json",
      "tmuxSession": "orch-20260314-add-auth",
      "worktree": "worktrees/20260314-add-auth",
      "startedAt": "2026-03-14T10:00:00Z",
      "updatedAt": "2026-03-14T10:05:00Z",
      "progress": { "total": 5, "done": 2, "running": 1, "failed": 0 }
    }
  ],
  "updatedAt": "2026-03-14T10:05:00Z"
}
```

The `progress` field is a denormalized snapshot updated each poll cycle — avoids
the dashboard needing to read every per-plan state file.

### Per-plan state (`plans/<slug>/state.json`)

Same shape as today's `OrchestratorState`. No structural change, just a new path.

### Worktree isolation

Each plan gets a git worktree at `.orchestrator/worktrees/<slug>`. Workers
execute in the worktree so file edits from different plans don't conflict.
Created on plan start, cleaned up on plan completion.

The worktree is created from the current branch:
`git worktree add .orchestrator/worktrees/<slug> -b orch/<slug>`

Workers receive the worktree path and `cd` into it before running claude.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-state.sh` | Namespace `ORCH_STATE_FILE` to `plans/<slug>/state.json`. Add master state read/write functions. Add worktree create/cleanup helpers. |
| `scripts/orch-run.sh` | Use per-plan state path. Register plan in master.json on start. Update master progress each poll. Create worktree on start. Pass worktree path to workers. Deregister + cleanup on completion. |
| `scripts/orch-review.sh` | Use per-plan state path (`plans/<slug>/state.json`). Use per-plan review dir (`plans/<slug>/reviews/`). |
| `scripts/terminal-ui/src/orch-types.ts` | Add `MasterState` and `PlanEntry` types. Update `ORCH_STATE_FILE` constant. |
| `scripts/terminal-ui/src/orchestrator-app.tsx` | Support `--orch-master` flag to show all-plans view. Keep `--orch <path>` for single-plan drill-down. |
| `scripts/terminal-ui/src/cli.tsx` | Add `--orch-master` CLI mode that watches `master.json`. |

## Risks and open questions

- **Worktree branch conflicts:** If two plans are on the same branch, the
  worktree create will fail (git doesn't allow two worktrees on the same branch).
  Mitigation: each worktree creates a new branch `orch/<slug>` from HEAD.
  On completion, changes are merged/cherry-picked back to the source branch.
- **Master state atomicity:** Multiple `orch-run.sh` processes could write
  `master.json` simultaneously. Mitigation: use atomic write (tmp + mv) and
  flock if available. Acceptable race window at poll-interval granularity.
- **Worktree cleanup on crash:** If the orchestrator crashes, the worktree
  and master.json entry persist. Add a `--cleanup` flag to orch-run.sh that
  removes stale entries (plan finished or tmux session dead).
- **Dashboard file watching:** The master-view dashboard watches `master.json`
  for plan-level updates — no need to watch every per-plan state file.
  Single-plan drill-down watches the specific `plans/<slug>/state.json`.

## Progress log

- [x] Refactor `orch-state.sh`: namespace state/done/reviews under `plans/<slug>/`. Add `orch_master_register`, `orch_master_deregister`, `orch_master_update_progress` functions. (deps: none)
- [x] Add worktree helpers to `orch-state.sh`: `orch_create_worktree`, `orch_cleanup_worktree`. (deps: none)
- [x] Update `orch-run.sh`: per-plan state path, master register on start, master progress update each poll, worktree create, pass worktree to workers, deregister + cleanup on completion. (deps: 1, 2)
- [x] Update `orch-review.sh`: per-plan state and review paths. (deps: 1)
- [x] Update `orch-types.ts`: add `MasterState`, `PlanEntry` types, update path constants. (deps: none)
- [x] Add master-view mode to dashboard: `--orch-master` flag, all-plans table with progress bars, drill-down navigation. (deps: 5)
- [x] Update `cli.tsx`: add `--orch-master` mode. (deps: 6)
- [x] Smoke test: launch two plans simultaneously, verify isolated execution and master state updates. (deps: 3, 4, 7)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Per-plan subdirectory under `plans/` | Flat files with slug prefix | Subdirectory keeps state, done-files, and reviews colocated per plan — cleaner than scattered flat files |
| Master state as denormalized registry | Dashboard reads all per-plan state files | Single file watch is simpler and faster than N watchers. Progress snapshot updated each poll cycle. |
| Worktree per plan | Shared working directory | Workers from different plans editing the same files would conflict. Worktrees provide full git isolation. |
| New branch per worktree (`orch/<slug>`) | Detached HEAD | Named branch makes it easy to inspect, merge, and clean up worktree changes |

## Completion criteria

- [ ] Two plans can run simultaneously without state conflicts
- [ ] Master state shows all running plans with progress
- [ ] Dashboard has master view (all plans) and single-plan drill-down
- [ ] Workers execute in isolated worktrees
- [ ] Plan completion cleans up worktree and deregisters from master
- [ ] shellcheck clean on all modified scripts

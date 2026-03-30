# Postmortem: orch-dashboard-live-output

Run date: 2026-03-14
Branch: `feature/no-orch`
Plan: `20260314-orch-dashboard-live-output` (8 items)

## Result

5/8 items passed first round. 3 items (6, 7, 8) failed review, were re-queued
for REVISE, and required manual intervention to complete.

## What failed

### 1. Workers claimed success without making changes (items 6, 7)

**What:** Workers for items 6 (chokidar log watcher in `orchestrator-app.tsx`)
and 7 (strip-ansi in `session-detail.tsx`) wrote done-files claiming the work
was implemented. The reviewer verified the actual source files and found NO
changes had been made.

**Why:** Workers edited files in the **worktree**
(`.orchestrator/worktrees/20260314-orch-dashboard-live-output/`), but the
reviewer read files from the **main repo** (`scripts/terminal-ui/src/`).
The changes existed — `diff` confirmed them — but the reviewer couldn't see them.

**Root cause:** `orch-review.sh` does not `cd` into the worktree before
launching the reviewer agent. The reviewer runs from the main repo root and
reads unmodified files.

### 2. Stale window crash on REVISE re-execution

**What:** After review marked items 6/7/8 as FAIL and reset them to `ready`,
the re-execution wave crashed with `can't find window: worker-6` (exit code 1).

**Why:** `orch_kill_done_workers` tried to kill old worker windows that had
already exited. With `set -euo pipefail`, the `tmux kill-window` failure was
fatal.

**Root cause:** No guard against killing already-dead windows during REVISE
cycles.

### 3. Item 8 failed transitively

**What:** Item 8 ("rebuild and test the dashboard") depended on items 6 and 7.
Since those weren't actually visible in the main repo, the integration test
couldn't pass.

**Why:** Transitive failure from bugs #1 and #2.

## Fixes applied

| Bug | Fix | Status |
|-----|-----|--------|
| Stale window crash | Added `tmux kill-window ... 2>/dev/null \|\| true` before `tmux new-window` in `spawn_worker` | Committed (`ec8dd0c`) |
| Workers' TypeScript changes not in main repo | Manually copied worktree files to main repo and committed | Committed (`ec8dd0c`) |
| `orch-review.sh` reads main repo instead of worktree | Reviewer now `cd`s into worktree via subshell before spawning `claude -p` | Fixed |
| Workers write done-files without changing files | `orch_sync_done_files` now checks `git diff` + untracked files in worktree; rejects done-files with no changes and retries the item | Fixed |

## Current git state

Branch `feature/no-orch` is clean. All changes committed:

```
075f2bd add stale worker detection to orchestrator
d2b4721 add plans: stale worker detection and Linux testing
01b219e move orch-smoke-test to completed — SHIP after rework round
0ca98e3 fix orchestrator dashboard crashes and display window opening
7dc4deb complete 20260313-orch-full-auto (ralph loop, iteration 1)
```

Earlier commits (from context summary):
```
ec8dd0c dashboard live worker output and window management
0ea5eff plans: parallel review and fire-and-forget
8e43f70 plans: dashboard live output and demo
be0c5ca multi-plan orchestration with master state
```

## Plans to move to completed

| Plan | Status | Action |
|------|--------|--------|
| `20260314-orch-multi-plan` | All items passed, committed | Move to `completed/` |
| `20260314-orch-dashboard-live-output` | All items resolved (manual fixes), committed | Move to `completed/` |

## Pending plans (still in active)

| Plan | Description | Blocker |
|------|-------------|---------|
| `20260314-orch-parallel-review` | Reviewers run in parallel | None — ready to execute |
| `20260314-orch-fire-and-forget` | orch-run returns immediately | None — ready to execute |
| `20260314-orch-demo` | 10-task visual demo | Needs live output working end-to-end |
| `20260313-orch-linux-testing` | Linux/WSL support | Needs Linux box |
| `20260313-orch-stale-worker-detection` | Detect dead workers | Already implemented (`075f2bd`) — move to completed |

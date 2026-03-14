# Plan: Orchestrator Stale Worker Detection

**Status:** In progress
**Created:** 2026-03-13

## Requirements

- Detect workers that exited without writing a done-file (crashed, timed out, killed)
- Mark stale items as "ready" for retry instead of leaving them stuck as "running"
- Limit retries per item to `maxIterations` — fail the item after exhausting retries
- Log stale worker detection events clearly for debugging

## Approach

The poll loop in `orch-run.sh` already checks done-files every `poll_interval`.
Add a parallel check: for each item with status "running", verify its tmux pane
is still alive. If the pane is dead and no done-file exists, the worker crashed.

Detection method: `tmux list-windows -t $SESSION -F '#{window_name}'` returns
all window names. Worker panes are named `worker-N`. If `worker-N` is missing
from the list but item N has status "running", it's stale.

Recovery: increment the item's `iteration` counter, reset status to "ready" (so
it gets re-spawned next wave), and log the event. If `iteration >= maxIterations`,
mark as "failed" instead.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-state.sh` | Add `orch_detect_stale_workers()` function |
| `scripts/orch-run.sh` | Call stale detection in poll loop after `orch_sync_done_files` |

## Risks and open questions

- **Race condition:** A worker might still be starting up when we check for its
  pane. Mitigation: only check items that have been "running" for longer than one
  poll interval. This requires tracking `startedAt` per item — currently not in
  state. Decision: skip the timing check for v1; the poll interval (30s) provides
  enough buffer for worker startup.
- **tmux pane naming:** Workers use `worker-N` naming. If a worker finishes and
  its pane exits, `remain-on-exit` may keep the dead pane visible. Need to check
  pane status, not just existence. Use `#{pane_dead}` format in tmux list command.

## Progress log

- [x] Add `orch_detect_stale_workers()` to `orch-state.sh` — checks tmux panes vs running items
- [x] Integrate stale detection into poll loop in `orch-run.sh` (after sync, before spawn)
- [x] Handle iteration increment and max-retry failure
- [x] Test: kill a worker pane mid-run, verify item gets re-spawned
- [x] Test: kill a worker 3 times, verify item marked "failed" after max iterations

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Check tmux pane existence | PID tracking, heartbeat files | tmux pane check is zero-overhead, no worker cooperation needed |
| Reset to "ready" on stale | Reset to "queued" | "ready" skips dependency re-check since deps are already satisfied |
| Skip timing check for v1 | Track startedAt per item | 30s poll interval is sufficient buffer; adds complexity for marginal benefit |

## Completion criteria

- [x] Stale workers detected and retried automatically
- [x] Items fail after `maxIterations` retries
- [x] Detection integrated into poll loop
- [x] shellcheck clean

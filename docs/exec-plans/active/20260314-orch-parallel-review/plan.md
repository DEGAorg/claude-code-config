# Plan: Parallel Per-Item Review

**Status:** In progress
**Created:** 2026-03-14

## Requirements

- Reviewers run in parallel, not sequentially
- Respect max-workers concurrency limit (same as worker phase)
- Reviewers are read-only — no file conflicts, safe to parallelize
- Review results aggregated after all reviewers complete
- Dashboard shows review phase progress

## Current state

`orch-review.sh` runs a `for` loop over all item IDs, spawning one
`claude -p` reviewer at a time (line 79). For a 10-item plan, this
means 10 sequential reviewer invocations — each taking 30-60 seconds.
Total review time: 5-10 minutes. With parallel execution at 4
concurrency: ~2.5 minutes.

## Approach

Reuse the same tmux + poll + done-file pattern from the worker phase.
Instead of running reviewers inline, spawn them as tmux windows (like
workers) and poll for review result files. The orchestrator poll loop
handles concurrency and completion detection.

### Reviewer spawning

For each item, spawn a reviewer in a tmux window named `reviewer-N`.
The reviewer writes its decision to `reviews/item-N-review.txt`
(already the convention). The orchestrator polls for these files.

### Completion detection

Same pattern as worker done-files: poll for `item-N-review.txt` in the
review directory. When found, read the first line (PASS/FAIL), update
state, and kill the reviewer window.

### State tracking

Add a `reviewStatus` field per item in state.json: `"pending"` →
`"reviewing"` → `"passed"` / `"failed"`. The dashboard can show
review progress per item.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-review.sh` | Replace sequential loop with tmux spawn + poll pattern. Add concurrency control. |
| `scripts/orch-state.sh` | Add `orch_sync_review_files()` to detect completed reviews. |
| `scripts/terminal-ui/src/orch-types.ts` | Add `reviewStatus` to `OrchestratorItem`. |
| `scripts/terminal-ui/src/session-table.tsx` | Show review status indicator per item. |

## Risks and open questions

- **Max concurrency during review:** Should reviewers share the same
  `--max-workers` limit as workers, or have their own? Decision: share
  the same limit — keeps things simple, one knob to tune.
- **Reviewer foreground/background:** Reviewers are lightweight and
  fast. Use `claude -p` (headless) even in foreground mode — no need
  for interactive TUI on read-only review. Their output is captured
  via pipe-pane to logs for dashboard viewing.

## Progress log

- [x] Add `orch_sync_review_files()` to `orch-state.sh`: scans review dir for completed reviews, updates per-item review status in state. (deps: none)
- [x] Add `reviewStatus` field to `OrchestratorItem` in `orch-types.ts`. (deps: none)
- [x] Refactor `orch-review.sh`: replace sequential for-loop with tmux spawn + poll loop. Spawn reviewers as tmux windows `reviewer-N`, poll for review files, respect max-workers concurrency. (deps: 1)
- [ ] Update `session-table.tsx`: show review status indicator (checkmark/X/spinner) per item during review phase. (deps: 2)
- [x] Test: run review on a completed plan, verify all reviewers spawn in parallel up to max-workers, results aggregate correctly. (deps: 3, 4)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Reuse tmux spawn + poll pattern | Background subprocesses with wait | Consistent with worker phase, dashboard can show reviewer windows, stale detection works |
| Headless reviewers (claude -p) even in foreground | Interactive TUI for reviewers | Reviewers are fast and read-only — no need for interactive session, saves resources |
| Share max-workers limit | Separate reviewer concurrency | One knob, simpler, reviewer phase is short |

## Completion criteria

- [ ] Reviewers run in parallel up to max-workers
- [ ] Review phase completes in roughly (items / max-workers) * per-review-time
- [ ] Dashboard shows per-item review status
- [ ] PASS/FAIL aggregation works correctly
- [ ] shellcheck and tsc clean

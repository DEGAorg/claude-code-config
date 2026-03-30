# Plan: Orchestrator Tmux Execution Engine

**Status:** In progress
**Created:** 2026-03-13

## Requirements

- `orch-run.sh` spawns `claude -p` workers in tmux panes by dependency wave
- Wave-based scheduling: wave 1 runs all items with no/satisfied deps, wave 2 runs items unblocked after wave 1, etc.
- Max concurrency respected (from `--max-workers` flag or state.json `maxParallelWorkers`)
- 30-second polling loop detects done-files, updates state.json, promotes newly unblocked items
- Crash recovery: restart picks up from last completed item via state.json
- Tmux pane naming follows convention that enables future `orch-display.sh` to attach read-only
- Per-item review runs after all items complete (existing `orch-review.sh`)
- Ink dashboard (`scripts/terminal-ui/`) shows live orchestrator state
- Polling interval configurable via `ralph.yaml` (`poll_interval_seconds`)
- No Claude-specific features — only `claude -p` and tmux

## Approach

Rewrite the TODO stub in `orch-run.sh` (lines 170-181) with a tmux execution
engine. Reuse patterns from `ralph-loop.sh`: spawning `claude -p`, reading
prompts from file, building worker context, polling for completion.

### Tmux session layout

```
orch-<slug>                    ← tmux session name
├── pane: orch-dashboard       ← runs Ink dashboard watching state.json
├── pane: worker-1             ← claude -p for item N
├── pane: worker-2             ← claude -p for item M
└── ...up to max-workers
```

Panes are named `worker-<item_id>` so `orch-display.sh` can find and attach
to them by name. Dashboard pane runs in the first position.

### Execution loop

1. Create tmux session with dashboard pane
2. Compute wave 1: items with status "ready" (deps satisfied)
3. For each wave item (up to max-workers): create tmux pane, mark item "running" in state, spawn `claude -p` with worker prompt + context
4. Poll every 30s: check for new done-files, update state.json
5. When a done-file appears: mark item "done", check if any queued items are now unblocked, promote to "ready"
6. When all wave items complete: start next wave (go to step 2)
7. When all items complete: run `orch-review.sh` for per-item review
8. If review says SHIP: commit, archive plan, play sound
9. If review says REVISE: reset failed items to "ready", loop back

### Worker prompt construction

Read `agents/orch-worker.md` once, append per-item session context:
- Item ID, description, plan path, done-files dir
- Done-file contents from dependency items
- Review feedback (if rework iteration)

This mirrors how `ralph-loop.sh` builds worker context from template + state.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-run.sh` | Replace TODO stub with tmux session + wave polling loop |
| `agents/orch-worker.md` | Add section for review feedback on rework iterations |
| `ralph.yaml` | Add `poll_interval_seconds: 30` field |
| `scripts/orch-state.sh` | Add `orch_promote_ready_items` function (promote queued→ready when deps done) |
| `scripts/terminal-ui/src/orch-types.ts` | No changes needed — already has `tmuxPane`, `workerPid`, `ItemStatus` |

## Risks and open questions

- **Tmux pane limits**: tmux handles ~20 panes well, degrades past that. Max-workers of 4-8 is safe.
- **Concurrent plan.md edits**: Multiple workers marking checkboxes in the same file simultaneously. Risk of write conflicts. Mitigation: each worker marks only its own checkbox, and `plan-advance.sh` already handles this. Workers also write done-files as the primary completion signal.
- **Worker prompt size**: Large plans with many completed items could produce big context from done-file summaries. Cap at last 5 dependency summaries per worker.

## Progress log

- [x] Add `poll_interval_seconds` to `ralph.yaml` with default 30
- [x] Add `orch_promote_ready_items` to `scripts/orch-state.sh`: for each queued item, if all deps are done, set status to ready
- [x] Rewrite `scripts/orch-run.sh` execution engine: create tmux session, launch dashboard pane, implement wave loop (spawn workers in panes, poll done-files, promote items, advance waves) (deps: 1, 2)
- [x] Add rework feedback section to `agents/orch-worker.md` for review-iteration context (deps: 3)
- [x] Smoke test: reset `20260309-orch-smoke-test` state and run end-to-end with new tmux engine (deps: 3, 4)
- [x] Update `commands/apply-core.md` install manifest to reflect current orchestrator scripts (deps: 5)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Tmux for execution | Agent Teams, direct background processes | Portable (macOS/WSL/Linux), provides built-in visibility, session persistence across terminal disconnects |
| 30s polling | 5s, 10s, event-driven (inotify) | Cheap enough to be non-intrusive, fast enough for plan items that take minutes. Configurable via ralph.yaml for tuning. |
| Dashboard in first tmux pane | Separate terminal, no dashboard | Co-located with workers for single-window experience. Future orch-display.sh can pop it out. |
| Reuse orch-review.sh as-is | Inline review in orch-run.sh | Already works, tested in smoke test. Keep separation of concerns. |
| Named tmux panes (worker-N) | Anonymous panes | Enables future orch-display.sh to find and attach by name |

## Completion criteria

- [ ] `orch-run.sh <slug>` creates tmux session with dashboard and worker panes
- [ ] Items execute in correct dependency order (wave-based)
- [ ] Max workers concurrency respected
- [ ] Done-file detection triggers state update and wave advancement
- [ ] Crash recovery works: kill session, re-run, picks up from state.json
- [ ] Per-item review runs after all items complete
- [ ] Smoke test passes end-to-end (8 items, 4 waves)
- [ ] shellcheck and shfmt clean

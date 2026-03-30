# Plan: Orchestrator Hardening — Per-Item Scoping + Single State File

**Status:** In progress
**Created:** 2026-03-07

## Requirements

- Wire per-item worker scoping: `orch-start.sh` must launch a worker
  for ONE item, not the whole plan. The worker gets a prompt scoped
  to that item's description + dependency summaries.
- Collapse `.orchestrator/items/<slug>/item-N.json` into a single
  `.orchestrator/state.json` with an items array. Remove all per-item
  file reads/writes from `orch-state.sh` and consuming scripts.
- Ensure the orchestrator agent can run a multi-item plan end-to-end:
  parse items, schedule waves by dependency, run workers, final review.

## Approach

### Per-item worker scoping

`orch-start.sh` currently calls `ralph-loop.sh <slug>` which processes
ALL items. Instead, each worker should receive a focused prompt:

1. Add `orch-worker.sh <slug> --item N` — a wrapper that:
   - Reads the item description from state.json
   - Reads work-summary.txt from completed dependency items
   - Builds a focused worker prompt (plan context + just this item)
   - Runs `claude -p` with that prompt
   - On completion, marks the item done in state.json

2. `orch-start.sh` calls `orch-worker.sh` instead of `ralph-loop.sh`.

### Single state file

Remove `orch_write_item`, `orch_sync_item_state`, and the `items/` directory.
All state lives in `.orchestrator/state.json`. The orchestrator is the
singleton writer. Workers report completion via a simple file
(`.orchestrator/done/<slug>/item-N.txt`) that the orchestrator reads.

### Test plan

Use this plan itself as the test. Items 1-3 are independent (wave 1).
Item 4 depends on all three. Item 5 depends on 4.

## Progress log

- [x] Write `scripts/orch-worker.sh` — per-item worker wrapper (deps: )
- [x] Refactor `orch-state.sh` — remove per-item files, single state.json only (deps: )
- [x] Update `orch-start.sh` — call `orch-worker.sh` instead of `ralph-loop.sh` (deps: 1, 2)
- [x] Update `orch-stop.sh`, `orch-status.sh` — remove per-item file references (deps: 2)
- [x] End-to-end test: run this plan via orchestrator, verify wave scheduling (deps: 3, 4)

## Completion criteria

- [ ] `orch-worker.sh` exists and accepts `<slug> --item N`
- [ ] No `items/` subdirectory created in `.orchestrator/`
- [ ] `orch-start.sh` launches per-item workers (not whole-plan ralph loops)
- [ ] Worker receives only its item description + dependency summaries in prompt
- [ ] Items 1 and 2 can run in parallel (no dependency between them)
- [ ] Item 3 starts only after items 1 and 2 complete

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Workers write done-file, orchestrator reads | Workers update state.json directly | Avoids concurrent writes to single file. Orchestrator polls done-files. |
| orch-worker.sh wrapper | Modify ralph-loop.sh to accept --item | Keep ralph-loop.sh as the existing sequential engine. New script for orchestrator's per-item model. |

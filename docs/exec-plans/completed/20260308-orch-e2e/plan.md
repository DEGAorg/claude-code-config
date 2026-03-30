# Plan: Orchestrator End-to-End — Polling Loop + Review Integration

**Status:** In progress
**Created:** 2026-03-08

## Requirements

Make the orchestrator run a multi-item plan end-to-end without human
intervention: parse items, schedule dependency waves, poll for completion,
advance to next wave, run per-item final review, SHIP or REVISE.

Three gaps to close:

1. **orch-loop.sh** — polling loop that drives the full lifecycle:
   start workers → poll for done-files → schedule next wave → final review.
2. **orch-review.sh** — update to use `review-advance.sh` per-item pattern
   instead of the monolithic single-shot reviewer.
3. **Done-file detection in orch-start.sh** — after launching workers,
   the loop needs to detect when workers finish (done-files appear in
   `.orchestrator/done/<slug>/`) and mark items done in state.json.

## Approach

### orch-loop.sh — the AFK orchestrator

A shell loop that runs until all items are done + final review passes:

```bash
orch-start.sh <slug>          # parse, init state, launch wave 1
while items remain:
    sleep + poll done-files
    for each new done-file:
        mark item done in state.json
        check if any blocked items are now ready
        schedule newly ready items
    if all items done:
        run orch-review.sh (per-item)
        if SHIP → exit 0
        if REVISE → re-queue failed items, continue
```

Polls every 5 seconds. Timeout after configurable max (default 30 min).

### orch-review.sh — per-item review

Replace the monolithic reviewer with the same pattern as ralph-loop.sh:

1. Structural checks: all items done in state.json?
2. For each item, use context from done-files (`.orchestrator/done/<slug>/item-N.txt`)
   as handoff summaries for the reviewer.
3. Spawn one focused `claude -p` per item using `ralph-item-reviewer-prompt.md`.
4. Missing review file = FAIL. All PASS → SHIP.

### Done-file polling in the loop

Workers write done-files via `orch-worker.sh`. The loop checks
`.orchestrator/done/<slug>/item-N.txt` for each running item.
When a done-file appears, update `state.json`: mark item done,
resolve dependencies, mark newly ready items.

### State transitions

```
orch-loop.sh starts
  → orch-start.sh: parse items, schedule wave 1
  → poll loop:
      check done-files for running items
      running → done when done-file exists
      queued → ready when all deps done
      ready → running when scheduled
      all done → orch-review.sh
  → orch-review.sh: per-item review
      SHIP → exit 0
      REVISE → re-queue, continue poll loop
```

## Progress log

- [x] Write `scripts/orch-loop.sh` — polling loop that drives start → poll → advance → review
- [x] Update `scripts/orch-review.sh` — per-item review using done-files as handoff context
- [x] Add done-file polling to the loop — detect worker completion, update state, resolve deps
- [x] Add wave advancement — when items complete, schedule newly ready items
- [x] Test: create a 3-item plan with deps, run orch-loop.sh, verify waves execute in order

## Completion criteria

- [ ] `orch-loop.sh` exists and accepts `<slug> [--timeout N]`
- [ ] Loop polls for done-files and advances waves automatically
- [ ] `orch-review.sh` uses per-item review (not monolithic)
- [ ] A plan with dependencies completes end-to-end via `orch-loop.sh`

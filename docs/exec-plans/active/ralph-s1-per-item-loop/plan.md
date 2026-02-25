# Plan: Ralph S1 — Per-Item Loop

**Status:** In progress
**Created:** 2026-02-25
**Sequence:** Step 1 of 4 — must complete before S2, S3, S4

## Context

The current ralph loop gives the worker the full plan and says "do as much as you
can." That fails at scale: the agent loses orientation in large-context sessions,
misses checkbox updates, and the reviewer has no clear unit to evaluate.

This step replaces the single-prompt worker with a per-item loop. Each unchecked
plan item gets its own focused prompt. Session context is kept across items so the
agent carries forward what it just did — no re-reading, no re-orienting.

The reviewer still runs once per iteration (after all items in that iteration are
done), keeping reviewer cost constant.

## Requirements

- `ralph.yaml` default `max_iterations` is 3
- `.ralph-state.json` is initialised by `ralph-loop.sh` at loop start and updated
  after each reviewer decision; it is never written by the LLM
- `scripts/plan-advance.sh` extracts the next unchecked `[ ]` item from `plan.md`
  and writes it to `.ralph-state.json` as `current_task.text`
- `ralph-loop.sh` drives a per-item inner loop: for each unchecked item, spawn a
  focused worker prompt scoped to that single item, resuming the same session
- Worker prompt reads `current_task.text` from state — it does not scan checkboxes
- After all items in an iteration are done, the reviewer runs as before (once per
  iteration, fresh instance)
- The loop structure is: outer = iterations, inner = items per iteration

## Approach

### Loop structure

```
for iteration in 1..max_iterations:
  init/update .ralph-state.json (iteration N, status in_progress)
  SESSION_ID = ""
  for each unchecked [ ] item in plan.md:
    update .ralph-state.json: current_task.text = item
    prompt = render worker template with {CURRENT_TASK} + {TASK_DIR} + {STATE_FILE}
    if SESSION_ID == "":
      SESSION_ID = claude -p ... (capture session id from output)
    else:
      claude -p --resume SESSION_ID ...
  reviewer runs (fresh instance, no resume — deliberate isolation)
  read review-result.txt → SHIP / REVISE / BLOCKED
```

`--resume` keeps the worker's context across items. The reviewer is always a fresh
instance — it should evaluate without being influenced by the worker's session memory.

### .ralph-state.json schema (introduced in this step)

```json
{
  "slug": "task-name",
  "iteration": 1,
  "started_at": "2026-02-25T10:00:00Z",
  "last_updated": "2026-02-25T10:45:00Z",
  "status": "in_progress",
  "current_task": {
    "text": "First unchecked item text",
    "claimed_complete": false
  },
  "last_result": null,
  "iterations": []
}
```

### plan-advance.sh

```bash
#!/usr/bin/env bash
# Extract next unchecked [ ] item from plan.md and write to .ralph-state.json
# Usage: scripts/plan-advance.sh <plan.md> <state.json>
# Exits 0 if an item was found and written; exits 1 if no unchecked items remain.
```

Reads plan.md with `grep -m1 '^\s*- \[ \]'`, strips the checkbox prefix, writes
`current_task.text` into state via `jq`. Exits 1 when plan is fully checked —
the caller treats this as "all items done, move to reviewer."

### Worker prompt changes

Replace the "find first unchecked checkbox" orientation with:

```
Read .ralph-state.json. Your current task is: current_task.text
Work only on this item. When done, stop — the loop will give you the next item.
Do not scan plan.md for other items.
```

The worker is now scoped. It does one thing per invocation.

### Session ID capture

`claude -p` with `--output-format json` outputs a JSON envelope including
`session_id`. `ralph-loop.sh` captures it on the first item, then passes
`--resume $SESSION_ID` for subsequent items. If session ID capture fails,
fall back to stateless (no resume) with a warning — loop continues.

## Files to touch

| File | Change |
|------|--------|
| `ralph.yaml` | `max_iterations: 3` |
| `scripts/plan-advance.sh` | New: extract next `[ ]`, write `current_task` to state |
| `scripts/ralph-loop.sh` | Add state file init; replace single worker call with per-item inner loop; session `--resume` chaining; pass `{CURRENT_TASK}` and `{STATE_FILE}` to worker template |
| `scripts/ralph-worker-prompt.md` | Read `current_task.text` from state; work on one item; stop after it; remove checkbox-scanning orientation |

## Risks and open questions

- **Open:** `claude -p --output-format json` — verify it outputs `session_id` in the
  envelope. If not, per-item prompts run without session continuity (still correct,
  just no context carry-forward). Check `claude -p --help` before implementing.
- **Resolved:** Reviewer granularity = once per iteration (not per item). Keeps cost
  constant; reviewer sees the full iteration's work, which is the right unit.
- **Resolved:** `plan-advance.sh` exits 1 when no items remain — clean sentinel for
  the inner loop to stop.

## Progress log

- [ ] `ralph.yaml` — set `max_iterations: 3`
- [ ] `scripts/plan-advance.sh` — new script; shellcheck + shfmt clean
- [ ] `scripts/ralph-loop.sh` — state file init; per-item inner loop; session resume
- [ ] `scripts/ralph-worker-prompt.md` — read `current_task` from state; one item per invocation
- [ ] Verify `shellcheck scripts/plan-advance.sh scripts/ralph-loop.sh` exits 0
- [ ] Verify `shfmt -d scripts/plan-advance.sh scripts/ralph-loop.sh` exits 0
- [ ] Verify `bash scripts/ralph-check.sh` exits 0

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| `max_iterations: 3` | 5, 10 | Tighter feedback loop; human re-runs when more needed |
| Reviewer = once per iteration, not per item | Per-item review | Per-item review multiplies cost by item count. Iteration = natural unit for reviewer. |
| Worker uses `--resume` for context continuity | Fresh instance per item | Fresh instance = re-orientation cost, loses carry-forward. Resume = agent remembers item N when working on N+1. |
| Reviewer uses fresh instance always | Resume reviewer | Reviewer should evaluate without worker session bias |
| `plan-advance.sh` exit 1 as "no more items" sentinel | Write a sentinel field to state | Exit code is the simplest, most composable signal for a bash loop |

## Completion criteria

- [ ] All progress log items checked
- [ ] `ralph.yaml` has `max_iterations: 3`
- [ ] `scripts/plan-advance.sh` exists, is executable, passes shellcheck + shfmt
- [ ] `ralph-loop.sh` drives per-item inner loop with state file init
- [ ] `ralph-worker-prompt.md` references `current_task` from state, not checkbox scan
- [ ] `bash scripts/ralph-check.sh` exits 0

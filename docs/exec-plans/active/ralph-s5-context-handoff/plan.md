# Plan: Ralph S5 — Context Handoff

**Status:** In progress
**Created:** 2026-02-25
**Sequence:** Step 5 — builds on S1 (per-item loop); replaces --resume session chaining

## Context

S1 introduced per-item prompts and used `--resume` to keep session context across
items within an iteration. The problem: `--resume` carries the full conversation
history forward. By item 8 of a 10-item plan, the session contains 7 previous
items' tool calls, diffs, and outputs. Context grows unboundedly, token cost
increases per item, and older items' noise degrades the agent's focus on the
current task.

This step replaces `--resume` with a fresh session per item and a structured
handoff file. Each worker writes a short summary before stopping. The next worker
reads that summary as its only context reference — bounded, auditable, curated.

## Requirements

- Each plan item gets a **fresh** `claude -p` session (no `--resume`)
- `context-handoff.txt` lives in `{TASK_DIR}` and accumulates one entry per
  completed item
- Each entry is written by the worker before it stops; format is one short paragraph:
  what was done, what changed, what the next worker should know
- The next item's worker prompt includes `context-handoff.txt` contents as context
- `scripts/ralph-check.sh` blocks Stop if the current item's handoff entry was not
  written (same mandatory status as `task-complete.sh`)
- At iteration end, `context-handoff.txt` is archived into `iterations/<NNN>/`
  alongside `work-summary.txt` (S3 archive step handles this — add the file there
  or document the dependency)
- `context-handoff.txt` is reset at the start of each new iteration (previous
  iteration's handoff is irrelevant to a new iteration's fresh worker)

## Approach

### Why not --resume

`--resume` passes the full session history. That includes every tool call, every
file read, every diff the previous item generated. None of that is relevant to the
next item — only the outcome matters. A curated handoff entry is smaller, cheaper,
and forces the worker to articulate what actually matters to carry forward.

### context-handoff.txt format

One entry per item, appended:

```
--- item: <current_task.text> ---
<short paragraph: what was done, key decisions made, what changed, anything the
next item's worker needs to know. 3-5 sentences max.>
---
```

The format is freeform prose, not structured fields. The worker decides what's
relevant. The reader (next worker) gets a narrative, not a data dump.

### Loop change in ralph-loop.sh

Remove session ID tracking and `--resume` flag. The inner loop becomes:

```bash
for each unchecked item:
  update .ralph-state.json: current_task.text = item
  HANDOFF=""
  [[ -f "${TASK_DIR}/context-handoff.txt" ]] \
    && HANDOFF=$(cat "${TASK_DIR}/context-handoff.txt")
  PROMPT=$(render worker template with {CURRENT_TASK}, {TASK_DIR}, {HANDOFF})
  claude -p --dangerously-skip-permissions "${PROMPT}"
  # no --resume, no session ID capture
done
```

Each invocation is stateless at the session level. State lives in files, not
in the session.

### Worker prompt addition

Add a section between "Orient" and "Work":

```
### 1b. Read handoff context

If {TASK_DIR}/context-handoff.txt exists, read it. It contains summaries written
by previous workers this iteration. Use it to understand what has already been
done and avoid duplicating work.

Do not re-read or re-derive this from plan.md — trust the handoff.
```

Add to the "before stopping" instructions (alongside task-complete.sh):

```
Before stopping, append one entry to {TASK_DIR}/context-handoff.txt:

--- item: <your current task text> ---
<3-5 sentences: what you did, what files changed, any decisions or gotchas
the next worker should know>
---

This is mandatory. The Stop hook will block exit if the entry is missing.
```

### Stop hook enforcement (ralph-check.sh)

Add alongside the existing `task-complete.sh` check:

```bash
if [[ -n "$STATE_FILE" ]]; then
  CURRENT_TASK=$(jq -r '.current_task.text // ""' "$STATE_FILE")
  if [[ -n "$CURRENT_TASK" ]]; then
    HANDOFF_FILE="$(dirname "$STATE_FILE")/context-handoff.txt"
    if ! grep -qF "item: ${CURRENT_TASK}" "${HANDOFF_FILE}" 2>/dev/null; then
      echo "FAIL: no handoff entry found for current task"
      echo "  append an entry to context-handoff.txt before stopping"
      exit 1
    fi
  fi
fi
```

The check looks for the current task's text as a header in the handoff file. If
it is absent, Stop is blocked. The worker cannot exit without writing the entry.

### Iteration reset

At the start of each iteration (before the inner item loop), `ralph-loop.sh` resets
the handoff file:

```bash
# Reset handoff for new iteration — previous iteration's context is stale
rm -f "${TASK_DIR}/context-handoff.txt"
```

The S3 archive step (which runs before this reset) copies `context-handoff.txt`
into `iterations/<NNN>/` so it is not lost.

**Dependency on S3:** If S3 is not yet implemented, add `context-handoff.txt` to
the list of files copied in the archive step manually, or note it as a prerequisite.

## Files to touch

| File | Change |
|------|--------|
| `scripts/ralph-loop.sh` | Remove session ID capture and `--resume`; inject `context-handoff.txt` contents into worker prompt; reset handoff file at iteration start |
| `scripts/ralph-worker-prompt.md` | Add "read handoff" orientation step; add "write handoff entry" to pre-stop checklist |
| `scripts/ralph-check.sh` | Add Stop enforcement: block if current task has no handoff entry in `context-handoff.txt` |

## Risks and open questions

- **Resolved:** `context-handoff.txt` is separate from `work-summary.txt`. Different
  audiences: handoff is worker → next worker (what to know); work-summary is
  worker → reviewer (what was accomplished). Mixing them would blur both.
- **Resolved:** Handoff resets each iteration. A new iteration means a new reviewer
  decision (REVISE) and potentially a different approach — carrying forward the
  previous iteration's handoff would mislead the worker.
- **Open:** Handoff entry size. "3-5 sentences" is a prompt instruction, not
  enforced. A worker could write a 50-line entry. Consider adding a soft size
  warning in the Stop hook (`wc -l context-handoff.txt` > threshold → warn but
  don't block).
- **Resolved:** S3 runs before S5. S3's archive loop already exists when S5 lands.
  S5 adds `context-handoff.txt` to that loop in the same `ralph-loop.sh` edit that
  removes `--resume`. No separate prerequisite step needed.

## Progress log

- [ ] `scripts/ralph-loop.sh` — remove `--resume` and session ID logic; inject handoff contents into per-item worker prompt; reset `context-handoff.txt` at iteration start
- [ ] `scripts/ralph-worker-prompt.md` — add handoff read step (orientation); add handoff write requirement (pre-stop checklist)
- [ ] `scripts/ralph-check.sh` — add Stop enforcement for missing handoff entry
- [ ] Verify `shellcheck scripts/ralph-loop.sh scripts/ralph-check.sh` exits 0
- [ ] Verify `shfmt -d scripts/ralph-loop.sh scripts/ralph-check.sh` exits 0
- [ ] Verify `bash scripts/ralph-check.sh` exits 0

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Fresh session per item | `--resume` (S1 design) | `--resume` accumulates full tool call history; bounded handoff is cheaper and cleaner |
| Freeform prose entry | Structured fields (JSON, YAML) | Workers are better at writing narrative than filling schemas; the reader is another LLM, not a script |
| Separate `context-handoff.txt` from `work-summary.txt` | Single file for both | Reviewer and next-worker have different needs; one file per audience |
| Reset handoff each iteration | Accumulate across iterations | A REVISE decision means the approach may change; stale handoff from a failed iteration misleads the new worker |
| Stop hook checks for entry presence | task-complete.sh writes the entry | Separating concerns: task-complete.sh advances state, Stop hook validates pre-exit conditions |

## Completion criteria

- [ ] All progress log items checked
- [ ] `ralph-loop.sh` spawns fresh sessions (no `--resume`); passes handoff contents to each item prompt
- [ ] `ralph-worker-prompt.md` has both handoff read and write instructions
- [ ] `ralph-check.sh` blocks Stop when handoff entry is missing for current task
- [ ] `bash scripts/ralph-check.sh` exits 0 on clean state

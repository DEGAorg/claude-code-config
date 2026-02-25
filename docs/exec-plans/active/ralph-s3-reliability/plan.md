# Plan: Ralph S3 — Reliability

**Status:** In progress
**Created:** 2026-02-25
**Sequence:** Step 3 of 4 — requires S1 (state file) and S2 (enforcement) complete

## Context

S1 and S2 give a working per-item loop with safety gates. This step adds resilience:
iteration output is archived so history is never lost, stagnation detection exits
the loop when no real progress is happening, and a budget warning surfaces in the
terminal before the last iteration so the human can intervene.

## Requirements

- Before each worker phase (except iteration 1), `ralph-loop.sh` copies the previous
  iteration's output files into `iterations/<NNN>/`
- On SHIP, the full plan directory (including `iterations/`) moves to `completed/`
- When `git diff HEAD` hash is unchanged across two consecutive iterations,
  the loop exits with BLOCKED and message "no file changes in 2 consecutive iterations"
- When `iterations_used >= warn_at_iteration`, a warning prints in the terminal before
  the next iteration starts
- `ralph.yaml` has `budget.warn_at_iteration: 2`
- `.ralph-state.json` tracks `stagnation_count`, `last_diff_hash`, and
  `budget.warned`

## Approach

### Iteration archive

Before each worker inner loop (except iteration 1):

```bash
if [[ $i -gt 1 ]]; then
  ITER_DIR="${TASK_DIR}/iterations/$(printf '%03d' $((i-1)))"
  mkdir -p "${ITER_DIR}"
  for f in work-summary.txt review-result.txt review-feedback.txt; do
    [[ -f "${TASK_DIR}/$f" ]] && cp "${TASK_DIR}/$f" "${ITER_DIR}/$f"
  done
fi
```

`work-summary.txt`, `review-result.txt`, `review-feedback.txt` are copied — not
moved — so the current files remain in place for the reviewer prompt. The `iterations/`
directory accumulates a full audit trail.

### Stagnation detection

After the worker inner loop, before the reviewer runs:

```bash
CURRENT_HASH=$(git diff HEAD | sha256sum | cut -d' ' -f1)
PREV_HASH=$(jq -r '.last_diff_hash // ""' "$STATE_FILE")

if [[ "$CURRENT_HASH" == "$PREV_HASH" && -n "$PREV_HASH" ]]; then
  STAG=$(($(jq -r '.stagnation_count // 0' "$STATE_FILE") + 1))
  jq ".stagnation_count = $STAG" "$STATE_FILE" > /tmp/ralph_s.tmp \
    && mv /tmp/ralph_s.tmp "$STATE_FILE"
  if [[ $STAG -ge 2 ]]; then
    echo "ralph-loop: STAGNATED — no file changes in 2 consecutive iterations"
    echo "  Human review required. Re-run after diagnosing the blocker."
    exit 2
  fi
else
  jq ".stagnation_count = 0 | .last_diff_hash = \"$CURRENT_HASH\"" \
    "$STATE_FILE" > /tmp/ralph_s.tmp && mv /tmp/ralph_s.tmp "$STATE_FILE"
fi
```

Stagnation resets to 0 on any real diff change. Threshold is 2 — one stagnant
iteration could be a legitimate reviewer-only pass; two in a row is a loop.

### Budget warning

Read `warn_at_iteration` from `ralph.yaml`. Before starting iteration N:

```bash
WARN_AT=$(grep 'warn_at_iteration:' ralph.yaml | awk '{print $2}')
if [[ -n "$WARN_AT" && $i -ge $WARN_AT ]]; then
  WARNED=$(jq -r '.budget.warned // false' "$STATE_FILE")
  if [[ "$WARNED" == "false" ]]; then
    echo "⚠ ralph-loop: iteration $i of $MAX_ITERATIONS — approaching budget limit"
    echo "  Press Ctrl-C to stop. State is saved in $STATE_FILE"
    jq '.budget.warned = true' "$STATE_FILE" > /tmp/ralph_w.tmp \
      && mv /tmp/ralph_w.tmp "$STATE_FILE"
  fi
fi
```

Warning fires once (guarded by `budget.warned`) and gives the human a window to
interrupt before the next iteration starts.

### .ralph-state.json additions (on top of S1 schema)

```json
{
  "stagnation_count": 0,
  "last_diff_hash": "",
  "budget": {
    "iterations_used": 1,
    "iterations_max": 3,
    "warn_at_iteration": 2,
    "warned": false
  }
}
```

## Files to touch

| File | Change |
|------|--------|
| `ralph.yaml` | Add `budget.warn_at_iteration: 2` |
| `scripts/ralph-loop.sh` | Add iteration archive; stagnation detection; budget warning; update state with `stagnation_count`, `last_diff_hash`, `budget` fields |

## Risks and open questions

- **Resolved:** Archive copies, not moves — current files stay available for reviewer
  prompt and `ralph-check.sh`.
- **Resolved:** Stagnation threshold = 2. One stagnant iteration is tolerable (e.g.,
  reviewer gives REVISE but the worker had no new diffs yet). Two = broken loop.
- **Open:** `sha256sum` portability — macOS uses `shasum -a 256`, not `sha256sum`.
  Use `git diff HEAD | shasum -a 256 | cut -d' ' -f1` or check availability.

## Progress log

- [ ] `ralph.yaml` — add `budget.warn_at_iteration: 2`
- [ ] `scripts/ralph-loop.sh` — add iteration archive (copy to `iterations/<NNN>/` before each worker phase except iteration 1)
- [ ] `scripts/ralph-loop.sh` — add stagnation detection (hash check, exit on count >= 2)
- [ ] `scripts/ralph-loop.sh` — add budget warning (print once when `i >= warn_at_iteration`)
- [ ] `scripts/ralph-loop.sh` — init `.ralph-state.json` with `stagnation_count`, `last_diff_hash`, `budget` fields
- [ ] Verify `shellcheck scripts/ralph-loop.sh` exits 0
- [ ] Verify `shfmt -d scripts/ralph-loop.sh` exits 0
- [ ] Verify `bash scripts/ralph-check.sh` exits 0

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Archive by copy not move | Move files | Reviewer still needs current files in place; copy is safe |
| Stagnation threshold = 2 | 1, 3 | 1 is too sensitive (one clean pass is fine); 3 wastes an extra iteration |
| Budget warning fires once | Every iteration | Repeated warnings are noise; one warning + state flag is enough |
| `shasum -a 256` over `sha256sum` | `sha256sum` | macOS ships `shasum`, not `sha256sum`; portability matters |

## Completion criteria

- [ ] All progress log items checked
- [ ] `ralph.yaml` has `budget.warn_at_iteration: 2`
- [ ] `iterations/<NNN>/` directories created correctly after iteration 2+
- [ ] Stagnation exits loop with code 2 after 2 identical diffs
- [ ] Budget warning prints once when `i >= warn_at_iteration`
- [ ] `bash scripts/ralph-check.sh` exits 0

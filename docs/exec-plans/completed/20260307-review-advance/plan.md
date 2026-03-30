# Plan: Review-Advance — Per-Item Reviewer Loop

**Status:** In progress
**Created:** 2026-03-07

## Requirements

Mirror the worker's plan-advance pattern for the reviewer phase:

- `review-advance.sh` script that pops the next unreviewed handoff item,
  writes it to the state file, and exits 0. Exits 1 when all items reviewed.
- The ralph-loop.sh reviewer phase becomes a `while review-advance.sh` loop
  identical in structure to the worker's `while plan-advance.sh` loop.
- The Stop hook (`ralph-reviewer-stop.sh`) enforces that each per-item
  reviewer writes its `item-N-review.txt` before exiting.
- Missing review file = FAIL (not PASS).

## Approach

### review-advance.sh

Takes `<task-dir>` as argument. Reads `<task-dir>/context-handoff.txt`
to find handoff entries delimited by `--- item: <text> ---`. Numbers
them 1-indexed by position.

For each entry, checks if `<task-dir>/reviews/item-N-review.txt` exists.
If not, writes the item to the ralph state file and exits 0:

```json
{
  "current_review": {
    "num": 3,
    "text": "Write orch-start.sh",
    "handoff": "Created orch-start.sh with wave scheduling..."
  }
}
```

If all items have review files, exits 1 (done).

### ralph-loop.sh reviewer phase

Replace the inline handoff parsing with a loop:

```bash
while bash review-advance.sh "${TASK_DIR}"; do
    NUM=$(jq -r '.current_review.num' "${STATE_FILE}")
    TEXT=$(jq -r '.current_review.text' "${STATE_FILE}")
    HANDOFF=$(jq -r '.current_review.handoff' "${STATE_FILE}")
    # build per-item reviewer prompt from ralph-item-reviewer-prompt.md
    # spawn claude -p
done
# collect results from reviews/item-*-review.txt
```

### Stop hook enforcement

Update `ralph-reviewer-stop.sh` to also check for per-item review files.
When `RALPH_REVIEW_ITEM` env var is set (by the loop), the hook checks
for `reviews/item-N-review.txt` instead of `review-result.txt`.

### Missing review = FAIL

After the review loop, any item without a review file is treated as FAIL.
The loop writes REVISE to `review-result.txt` with feedback listing the
failed items.

## Progress log

- [x] Write `scripts/review-advance.sh` — pop next unreviewed item from handoff
- [x] Update ralph-loop.sh reviewer phase — replace inline parsing with while loop
- [x] Update `hooks/ralph-reviewer-stop.sh` — enforce per-item review file via RALPH_REVIEW_ITEM

## Completion criteria

- [ ] `review-advance.sh` exits 0 for unreviewed items, 1 when all reviewed
- [ ] ralph-loop.sh reviewer phase uses `while review-advance.sh` pattern
- [ ] Stop hook blocks reviewer exit if per-item review file missing
- [ ] Missing review file treated as FAIL, not PASS

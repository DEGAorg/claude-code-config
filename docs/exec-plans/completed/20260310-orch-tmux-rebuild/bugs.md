# Known Bugs — Found During Orchestrator Rebuild

## sed multiline substitution in ralph-loop.sh

**Found:** 2026-03-13, during per-item review step
**File:** `scripts/ralph-loop.sh` (line ~97, `{ITEM_HANDOFF}` substitution)
**Error:** `sed: 1: "s|{ITEM_HANDOFF}|Added ...": unescaped newline inside substitute pattern`

**Root cause:** The handoff text (`context-handoff.txt`) contains newlines.
The `sed` substitution `s|{ITEM_HANDOFF}|...|g` breaks when the replacement
string has unescaped newlines. This is a pre-existing bug — not introduced
by the orchestrator rebuild.

**Impact:** Per-item review fails to run. The review prompt template doesn't
get the handoff context injected, so the reviewer agent never starts.

**Fix options:**
1. Use `awk` or `perl` instead of `sed` for multiline substitution
2. Use bash parameter expansion (`${REVIEW_PROMPT//\{ITEM_HANDOFF\}/${HANDOFF}}`)
   like `orch-review.sh` already does (line 97)
3. Write prompt to temp file with heredoc instead of sed template substitution

Option 2 is the simplest — `orch-review.sh` already does this correctly.
The bug is in `ralph-loop.sh` which uses `sed` while `orch-review.sh` uses
bash expansion for the same substitution.

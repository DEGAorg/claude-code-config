# Ralph Loop: no recovery path after stagnation

**Discovered:** 2026-03-03
**Trigger:** `terminal-ui-state-spec` plan — work done in iteration 1, health check
failed on unrelated shfmt issue, loop stagnated at iteration 3
**Outcome:** Loop exited with code 2. Re-running would stagnate immediately again.
Manual state file edit or deletion was the only way forward.

## What happened

1. Worker completed all plan items in iteration 1.
2. Reviewer said SHIP, but `ralph-check.sh` failed (shfmt error in an unrelated file).
3. Loop deleted `review-result.txt` (line 249) and continued.
4. Iterations 2-3: worker found no items, produced no file changes, stagnation fired.
5. After diagnosing and fixing the shfmt issue externally, re-running the loop would
   not recover — the state file still has `stagnation_count: 3`, and the loop carries
   it forward.

## Root cause

The loop has no reset mechanism for stagnation state between runs. The sequence:

1. `for i in $(seq 1 "${MAX_ITERATIONS}")` — always starts at 1 (line 92)
2. State init reads `PREV_STAG` from existing `.ralph-state.json` (line 111)
3. Rebuilds state with the same `stagnation_count` (line 120, 132)
4. Worker finds no items, diff unchanged, STAG increments past threshold
5. Immediate exit — reviewer never runs

There is no `--resume`, `--reset`, or `--recover` flag. The stagnation exit message
says "Re-run after diagnosing the blocker" but re-running hits the same wall.

## Additional issue: misleading error message

Line 248 (now fixed) said "health check failed — repo not clean" for any health
check failure, regardless of cause. This sent both human operators and worker agents
down the wrong diagnostic path. Changed to "criteria not met" in both `scripts/ralph-loop.sh`
and `~/.claude/scripts/ralph-loop.sh`.

## Proposed fix

Add a `--recover` flag that resets stagnation state and resumes from the reviewer phase:

```bash
# ralph-loop.sh --recover <slug>
# 1. Reset stagnation_count to 0 in .ralph-state.json
# 2. Run health check
# 3. If health check passes: archive plan, commit, exit 0
# 4. If health check fails: print failing criteria, exit 1
```

This covers the common case: work is done, something external blocked SHIP, human
fixed it, now just need to land the result.

A simpler alternative: detect on loop start that `stagnation_count >= 2` in the
existing state file and auto-reset it to 0, since a new invocation implies the
human has diagnosed and addressed the blocker.

```bash
# After reading PREV_STAG (line 111)
if [[ ${PREV_STAG} -ge 2 ]]; then
    echo "→ resetting stagnation counter (previous run stagnated)"
    PREV_STAG=0
fi
```

## Relation to other tech debt

- `ralph-loop-stagnation-false-positive.md` — covers *preventing* false stagnation
  when all items are done. This doc covers *recovering* from stagnation that already
  happened (whether false or caused by external blockers like health check failures).
- Both fixes are complementary: the false-stagnation guard prevents the situation,
  the recovery path handles it when it still occurs.

## Files involved

| File | Role |
|------|------|
| `scripts/ralph-loop.sh:92` | Loop always starts at i=1, no resume |
| `scripts/ralph-loop.sh:111-140` | State init carries stagnation_count forward |
| `scripts/ralph-loop.sh:184-199` | Stagnation detector — exits before reviewer |
| `scripts/ralph-loop.sh:248` | Misleading error message (now fixed) |

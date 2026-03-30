# Ralph Loop: false stagnation when all plan items complete in one iteration

**Discovered:** 2026-03-02
**Trigger:** `remove-global-ralph-check` plan — 4 work items + 5 verify-only items
**Outcome:** Loop exhausted 3 iterations and exited with stagnation, despite all work being done in iteration 1

## What happened

1. **Iteration 1** — worker completed all 4 work items and checked off all 5 completion criteria in `plan.md`. Real file changes: `CLAUDE.md`, `settings.json`, `~/.claude/settings.json`.
2. **Iteration 2** — `plan-advance.sh` found zero unchecked `[ ]` items → worker while-loop exited immediately with zero new file changes. `git diff HEAD` hash identical to iteration 1 → `stagnation_count` incremented to 1.
3. **Iteration 3** — same as iteration 2 → `stagnation_count` hit 2 → loop exited with `STAGNATED`.

The reviewer phase was never reached in iteration 3 (stagnation exits before it). It's unclear whether the reviewer ran in iterations 1-2 or what it decided, since `.ralph-state.json` is rebuilt each iteration with `last_result: null`.

## Root cause

The stagnation detector (`ralph-loop.sh` lines 184-199) compares `git diff HEAD | shasum` between iterations. When plan-advance finds no items, the worker does nothing, the diff is identical, and stagnation fires — even though "no items left" means the work is done, not stuck.

The detector cannot distinguish:
- **True stagnation** — items exist but the worker failed to make progress
- **False stagnation** — no items remain because work is already complete

## Contributing factors

1. **Plan mixed work and verification tasks** — the progress log had "Remove X" items (produce file changes) and "Verify X" items (only check a box in plan.md). The worker did everything in one pass, leaving nothing for subsequent iterations.
2. **State file is rebuilt each iteration** — `last_result` is reset to `null` on each iteration init (line 117-140), so there's no memory of whether the reviewer already approved. If the reviewer said SHIP in iteration 1 but the health check failed, iteration 2 starts fresh with no record of that.
3. **Reviewer outcome from iteration 1 is lost** — no `review-result.txt` survived in the plan directory (it may have been cleaned up or never written).

## Proposed fix

After the worker phase, if `ITEM_NUM == 0` (plan-advance found zero items on the first call), skip the stagnation detector entirely. Zero items means the plan is fully checked off — the correct next step is the reviewer phase, not stagnation detection.

```bash
# After worker phase, before stagnation detection
if [[ ${ITEM_NUM} -eq 0 ]]; then
    echo "→ all plan items already complete — skipping stagnation check"
else
    # --- Stagnation detection (existing code) ---
    ...
fi
```

This is the minimal fix. A more thorough approach would also:
- Persist `last_result` across iterations instead of resetting it
- If the reviewer already said SHIP in a prior iteration but health check failed, carry that context forward so the next iteration focuses on fixing the health check failure rather than re-running the full worker loop
- Log the reviewer's decision to an iteration archive file that survives state rebuilds (partially done — `iterations/NNN/review-result.txt` is copied, but the loop doesn't read it back)

## Files involved

| File | Role |
|------|------|
| `scripts/ralph-loop.sh:184-199` | Stagnation detector — needs the `ITEM_NUM == 0` guard |
| `scripts/ralph-loop.sh:117-140` | State init — resets `last_result` each iteration |
| `scripts/plan-advance.sh` | Returns exit 1 when no unchecked items remain |

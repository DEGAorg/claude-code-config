# Plan: Orch done-file validation

**Status:** In progress
**Created:** 2026-03-15

## Requirements

- Done-files smaller than 20 bytes are rejected (catches empty or trivial files)
- A warning is logged when a done-file exists but the corresponding plan.md checkbox isn't checked
- State.json remains the single source of truth for item status

## Approach

Modify `orch_sync_done_files()` in `orch-state.sh`:

1. After checking that the done-file exists, check its size. If < 20 bytes, reject it (same path as the no-changes rejection: delete the file, increment iteration, reset to ready or fail).
2. After accepting a done-file, check if the plan.md checkbox for this item is `[x]`. If not, log a warning (non-blocking — the done-file is still accepted, but the warning is visible in the engine log).

The checkbox check is best-effort: match the item description text against plan.md lines. If the match is ambiguous, skip the warning.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-state.sh` | Add size check and checkbox warning in `orch_sync_done_files` |

## Risks and open questions

- None — size check is a simple guard, checkbox warning is non-blocking

## Progress log

- [x] Add minimum done-file size check (20 bytes) to `orch_sync_done_files` in orch-state.sh
- [x] Add checkbox-unchecked warning to `orch_sync_done_files` in orch-state.sh

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| 20-byte minimum | Parse done-file structure | Simple, catches empty files. Strict parsing is fragile. |
| Warning on unchecked checkbox | Block on unchecked | Non-blocking avoids false negatives from fuzzy matching. The completion criteria gate catches this at the end. |

## Completion criteria

- [ ] Done-files under 20 bytes are rejected
- [ ] Warning logged when done-file exists but checkbox unchecked
- [ ] `shellcheck scripts/orch-state.sh` clean

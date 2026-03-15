# Plan: AI plan registry

**Status:** In progress
**Created:** 2026-03-15

## Requirements

- `docs/exec-plans/REGISTRY.md` exists with a table of all plans (active, completed, failed)
- The orch SHIP path appends a row to the registry on every successful ship
- The ralph-loop SHIP path appends a row to the registry on every successful ship
- Backfill: all existing completed plans appear in the registry
- Columns: Date, Slug (links to plan.md), Status, Iterations, Method

## Approach

### 1. Create shared helper: `orch_registry_append`

Add a function to `scripts/orch-state.sh` that appends a row to `docs/exec-plans/REGISTRY.md`. Both orch-engine.sh and ralph-loop.sh call this same function.

```bash
orch_registry_append() {
    local slug="$1" status="$2" iterations="$3" method="$4"
    local registry="${ORCH_REPO_ROOT}/docs/exec-plans/REGISTRY.md"
    local date
    date=$(date -u +"%Y-%m-%d")
    # Create file with header if missing
    # Append row
}
```

### 2. Wire into orch-engine.sh SHIP path

After step 5 (commit plan move), call `orch_registry_append`. Extract iteration count from state.json (`max(.items[].iteration)`).

### 3. Wire into ralph-loop.sh SHIP path

After the `mv` and `git commit`, call `orch_registry_append` with method=ralph and iteration=$i.

### 4. Backfill existing completed plans

Write a one-time script or inline loop that scans `docs/exec-plans/completed/*/plan.md`, extracts the date from the slug, and appends rows. Run once, commit.

## Files to touch

| File | Change |
|------|--------|
| `docs/exec-plans/REGISTRY.md` | New — plan registry table |
| `scripts/orch-state.sh` | Add `orch_registry_append` helper |
| `scripts/orch-engine.sh` | Call registry append in SHIP path |
| `scripts/ralph-loop.sh` | Call registry append in SHIP path |

## Risks and open questions

- **P2:** ralph-loop.sh doesn't source orch-state.sh. Either source it or inline the append logic. Recommendation: source orch-state.sh (it's safe — just function defs).

## Progress log

- [ ] Add `orch_registry_append` helper to orch-state.sh
- [x] Create `docs/exec-plans/REGISTRY.md` with header row
- [ ] Wire registry append into orch-engine.sh SHIP path (after step 5)
- [ ] Wire registry append into ralph-loop.sh SHIP path (after commit)
- [ ] Backfill existing completed plans into the registry

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Shared helper in orch-state.sh | Duplicate logic in both scripts | Single source of truth, less drift |
| Append on SHIP only | Also track FAILED/ABANDONED | Start simple — only track shipped plans. Add failure tracking later. |
| Link slug to completed/ plan.md | Plain text slug | Clickable links are more useful for navigation |

## Completion criteria

- [ ] `docs/exec-plans/REGISTRY.md` exists with header and backfilled rows
- [ ] Running an orch plan to SHIP appends a row to the registry
- [ ] `shellcheck scripts/orch-state.sh scripts/orch-engine.sh scripts/ralph-loop.sh` clean

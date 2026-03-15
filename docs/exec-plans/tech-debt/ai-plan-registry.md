# AI-driven development plan registry

**Discovered:** 2026-03-15
**Severity:** Low

## Problem

There's no single view of all plans executed by the AI development system —
what was planned, whether it shipped or failed, how many iterations it took,
and when. The data exists across `docs/exec-plans/active/` and
`docs/exec-plans/completed/` but requires manual directory scanning.

Over time this history becomes valuable for:
- Understanding what the system has built
- Tracking success/failure rates and iteration counts
- Identifying patterns (which types of plans stagnate, which ship fast)
- Onboarding — quick overview of project evolution

## Proposed fix

Add `docs/exec-plans/REGISTRY.md` — a table auto-maintained by the orch/ralph
SHIP path:

```markdown
# Plan Registry

| Date | Slug | Status | Iterations | Method |
|------|------|--------|------------|--------|
| 2026-03-15 | orch-quick-fixes | SHIP | 1 | orch |
| 2026-03-14 | orch-dashboard-viewport | SHIP | 2 | orch |
| 2026-03-13 | orch-stale-worker-detection | SHIP | 1 | ralph |
| ... | ... | ... | ... | ... |
```

Columns:
- **Date**: completion date
- **Slug**: plan slug (links to `completed/<dated-slug>/plan.md`)
- **Status**: SHIP, STAGNATED, FAILED, ABANDONED
- **Iterations**: how many worker/reviewer cycles before completion
- **Method**: `orch` (orchestrator) or `ralph` (ralph loop) or `manual`

Implementation: append a row in both `scripts/orch-engine.sh` (SHIP path) and
`scripts/ralph-loop.sh` (SHIP path). Backfill existing completed plans from
directory listing.

## Files involved

| File | Role |
|------|------|
| `docs/exec-plans/REGISTRY.md` | New — plan registry table |
| `scripts/orch-engine.sh` | Append row on SHIP |
| `scripts/ralph-loop.sh` | Append row on SHIP |

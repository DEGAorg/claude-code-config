# Orch: completion criteria never verified

**Discovered:** 2026-03-14
**Severity:** Medium

## Problem

The orchestrator's structural check only looks at `## Progress log` checkboxes.
The `## Completion criteria` section is never gated — plans get SHIP'd with all
completion criteria unchecked. This defeats the purpose of having acceptance criteria.

5 recent orch plans were shipped with unchecked completion criteria:
- `20260314-orch-parallel-review` (9 unchecked)
- `20260314-orch-fire-and-forget` (9 unchecked)
- `20260314-orch-reviewer-dashboard-visibility` (4 unchecked)
- `20260314-orch-dashboard-rendering` (4 unchecked)
- `20260314-orch-dashboard-terminal-viewport` (5 unchecked)

## Proposed fix

Option A: Have `orch-engine.sh` (or the reviewer prompt) parse `## Completion criteria`
and treat unchecked items as blockers before declaring SHIP.

Option B: Merge completion criteria into the progress log so one parser covers both.

Needs design work — the reviewer agent would need to verify each criterion (run tests,
check linting, etc.) which may require tool access the reviewer doesn't currently have.

## Files involved

| File | Role |
|------|------|
| `scripts/orch-engine.sh` | SHIP decision point |
| `scripts/orch-review.sh` | Reviewer prompt construction |
| `agents/orch-worker.md` | Worker prompt — could be told to verify criteria |

# Plan: Orch completion criteria gate

**Status:** In progress
**Created:** 2026-03-15

## Requirements

- After per-item reviews all PASS, the engine verifies `## Completion criteria` checkboxes in plan.md before declaring SHIP
- If any completion criteria are unchecked, a verifier agent spawns in a tmux window to execute and check them off
- The verifier runs in the worktree with full tool access (can run tests, linters, shellcheck, etc.)
- If the verifier checks all criteria, the engine declares SHIP
- If criteria remain unchecked after the verifier, the engine declares REVISE and re-runs from the worker phase
- The verifier respects max-iterations (doesn't loop forever)
- The verifier is visible in the dashboard (tmux window named `verifier`)
- State tracks verification status: `pending`, `running`, `passed`, `failed`

## Approach

Three changes, layered:

### 1. Structural gate in orch-engine.sh

After `orch-review.sh` returns SHIP, add a gate before the actual SHIP path:

```bash
# Parse ## Completion criteria section, count unchecked [ ] items
CC_UNCHECKED=$(awk '
  /^```/ { fence = !fence; next }
  fence { next }
  /^## Completion criteria/ { capturing = 1; next }
  capturing && /^## / { capturing = 0; next }
  capturing && /^- \[ \]/ { count++ }
  END { print count+0 }
' "${PLAN_DIR}/plan.md")
```

If `CC_UNCHECKED == 0` → proceed to SHIP as before.
If `CC_UNCHECKED > 0` → run the verifier.

Note: parse from `PLAN_DIR` (the exec-plan in the main repo), not the worktree.
Workers check boxes in plan.md which lives in the main repo, not the worktree.

### 2. Verifier agent (orch-verify.sh)

New script that:
1. Reads `## Completion criteria` from plan.md, extracts unchecked items as text
2. Spawns a single `claude -p` in a tmux window named `verifier`
3. The verifier agent gets a prompt with the unchecked criteria and instructions to:
   - Execute each criterion (run tests, run linters, etc.)
   - Check off `[x]` each criterion it verifies passing
   - Write a `verify-result.txt` with PASS or FAIL
4. Polls for `verify-result.txt` (same pattern as review polling)
5. Returns exit code: 0 for all criteria verified, 1 for failures

The verifier prompt template goes in `agents/orch-verifier.md`.

### 3. State tracking

Add `verification` field to state.json alongside `finalReview`:
```json
{
  "verification": {
    "status": "pending|running|passed|failed",
    "uncheckedCount": 0,
    "iteration": 0
  }
}
```

The dashboard already shows `finalReview` status; the verification status appears
in the engine log output and is visible by selecting the `verifier` window with j/k.

### Flow after changes

```
workers complete → per-item review → all PASS?
  ├─ NO → REVISE (re-run failed items)
  └─ YES → completion criteria gate
       ├─ all [x] → SHIP
       └─ unchecked → spawn verifier agent
            ├─ verifier checks all → re-gate → SHIP
            └─ verifier can't check all → REVISE (full re-run)
```

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-engine.sh` | Add completion criteria gate between review SHIP and actual SHIP |
| `scripts/orch-verify.sh` | New — spawns verifier agent, polls for result |
| `agents/orch-verifier.md` | New — verifier agent prompt template |
| `scripts/orch-state.sh` | Add `orch_count_unchecked_criteria()` helper |

## Risks and open questions

- **P2:** If completion criteria reference things the agent can't check (e.g., "manual QA"), the verifier will fail. Mitigation: the plan skill's rule already says "completion criteria must only contain steps the worker agent can complete autonomously." Plans that violate this will correctly fail the gate — fixing the plan is the right response, not bypassing the gate.

## Progress log

- [x] Add `orch_count_unchecked_criteria()` helper to `orch-state.sh` — awk parser for `## Completion criteria` section
- [x] Create `agents/orch-verifier.md` — verifier agent prompt template
- [x] Create `scripts/orch-verify.sh` — spawns verifier in tmux, polls for result, returns pass/fail
- [x] Add completion criteria gate to `orch-engine.sh` — between review SHIP and actual SHIP, call verifier if unchecked criteria exist

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Separate verifier agent | Workers check criteria themselves | Workers are per-item; criteria are cross-cutting (tests pass, linting clean). A dedicated verifier owns the full-plan check. |
| Structural awk parse | AI agent parses the section | Deterministic, zero-cost, same pattern as Progress log gate. AI parses ambiguously. |
| Parse from PLAN_DIR not worktree | Parse from worktree | Workers check boxes in plan.md in the main repo exec-plan dir, not the worktree copy. |
| Single verifier, not parallel | Parallel verifiers per criterion | Criteria are often sequential (run tests, then lint). One agent, one tmux window, simple. |

## Completion criteria

- [ ] Plans with unchecked `## Completion criteria` items do not get SHIP'd
- [ ] Verifier agent spawns in tmux window visible in dashboard
- [ ] Verifier that successfully checks all criteria leads to SHIP
- [ ] Verifier failure leads to REVISE (not infinite loop)
- [ ] `shellcheck scripts/orch-engine.sh scripts/orch-verify.sh scripts/orch-state.sh` clean

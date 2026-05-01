# Decision: Completion-criteria verification is advisory by default

**Date:** 2026-04-27
**Status:** Accepted
**Forensics:** Issue #241 (verify loop, 2026-04-25)
**Related:** Plan A — runaway safeguards (iteration guard); this decision removes the cause that the safeguards were catching.

## Context

The orchestrator runs two independent quality gates after workers complete a plan:

- **Reviewer** — reads each item's done-file and asks "does this match the item description and clauses?" Per-item, narrative, decides SHIP vs REVISE per item.
- **Verifier** — runs the shell predicates in the plan's `## Completion criteria` block and asks "does each one exit 0?" Whole-plan, binary, runs in the worktree.

On 2026-04-25, issue #241 produced a divergence the orchestrator could not resolve: the reviewer SHIP'd 8/8 items while the verifier FAIL'd repeatedly, sending the plan into a REVISE loop that the workers could not satisfy. Forensics showed the verifier predicates failed for reasons unrelated to whether the work was correct:

- Tooling missing in the worktree env (e.g., `yq`, `fd` not always present)
- TDD-induced transient failures — a typecheck predicate fails because the implementation arrives in a later item
- Path mismatches — `cd canon/templates && …` failing the first run because the directory was created mid-plan
- Tests that hit external services or networks unavailable in the worktree

The reviewer was reading what shipped; the verifier was running predicates that answer a different question. Both signals are useful, but coupling SHIP to the verifier makes the orchestrator brittle in proportion to how thoroughly a planner writes their criteria — a perverse incentive that punishes good plans.

## Decision

**Make completion-criteria verification advisory by default.**

The verifier still runs. It still records `verification.status` in `state.json`. It still posts a per-criterion results comment to the issue. It no longer flips `REVIEW_RESULT=REVISE` when a predicate fails.

Behavior is controlled by a new `verify:` block in `dega-core.yaml`:

```yaml
verify:
  mode: advisory   # default — verify runs, reports, does not gate SHIP
  # mode: enforce  # opt-in — preserves prior behavior (REVISE on verify failure)
```

`enforce` mode preserves today's behavior bit-for-bit, bounded by the iteration guard from Plan A.

## Why not alternatives

| Alternative | Problem |
|-------------|---------|
| Default = enforce | Reproduces the issue #241 loop. Punishes thorough planners. |
| Delete verify entirely | Loses the per-criterion checkbox surfacing that operators wanted; harder to reverse if we change our minds. |
| Global env var (`ORCH_VERIFY_MODE`) | Doesn't match the existing per-project config pattern (`provider`, `github`, harness blocks all live in `dega-core.yaml`). |
| Per-plan override | Premature — no operator has asked for it. Can be added later as `verify.mode` in plan frontmatter without breaking the project default. |
| Suppress verify comments in advisory mode | The per-criterion data is the whole point of keeping verify around. Comment stays. |

## Consequences

- **Default behavior changes.** Existing operators who relied on REVISE-on-verify-failure must opt in by setting `verify.mode: enforce`. Documented in this decision and in the rules update accompanying it.
- **Advisory mode can mask real regressions.** A plan that breaks the test suite would still SHIP. Mitigation: the verify comment still posts findings; reviewers and per-item `check_command` are the appropriate gating layer for hard failures.
- **Plan A's iteration guard remains the universal safety belt.** It protects `enforce` users from re-encountering the issue #241 loop pattern, even with thorough criteria.
- **Reversible.** Flipping the default back is a one-line change to `dega-core.yaml` and the engine default.

## References

- Issue #241 — verify loop forensics (2026-04-25)
- Plan A — runaway safeguards (PR #245, merged 2026-04-27)
- `scripts/orch-engine.sh` — verify gate dispatch
- `scripts/orch-state.sh` — `orch_get_verify_mode`, `orch_verify_should_gate`
- `rules/exec-plans.md` — "Shell-verifiable completion criteria" (advisory by default)

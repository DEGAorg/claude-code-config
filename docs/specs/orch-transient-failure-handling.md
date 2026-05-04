# Orchestrator Transient Failure Handling — Discussion + Options

**Status:** Discussion captured, no plan filed yet
**Owner:** Alberto
**Reference:** [`Canon_Orchestrator_Transient_Failure_Patterns.md`](https://github.com/DEGAorg/canon-docs) (canon-docs repo)
**Related:**
- Issue #258 / PR #260 — agent-bump notification mechanism (the run that surfaced this incident)
- `docs/specs/canon-tui-plan-completion.md` — TUI panel state spec

---

## The incident

Plan #258 ran via `orch-run.sh`. Workers 1-6 spawned; workers 1, 2, 3, 5
produced and committed their artifacts cleanly on the orch branch. Then mid-run,
Claude Code returned `out of extra usage · resets 6pm (America/Tegucigalpa)`.

The engine treated the rate-limit message as a review failure, consumed
review iteration slots re-spawning workers that exited instantly with the
same message, and eventually marked all 6 items `failed` / `review-max-retries`.
state.json said "all red"; the worktree had a clean working branch with
4/4 bats tests passing.

Salvaged by killing the engine, manually verifying the artifacts, pushing
the branch, opening PR #260. But the harness shouldn't need a human to do that.

## The root cause (per canon)

Canon already defines a layered **agentic fallback chain**:

```
auth rotation → multi-account round-robin → model swap →
thinking downgrade → auto-compaction → coder fallback (Codex↔Claude) →
Oracle escalation (Gemini) → human (last resort)
```

The chain triggers on **iteration count**, **review verdict (NEEDS_WORK)**,
and **spiral signals** (regression %, lint errors, etc.). It does NOT
trigger on **transient infrastructure errors** from CLI subprocesses — rate
limits, capacity, auth expiry. Those slip through, get classified as
review-failed-on-merits, and burn iterations against a wall.

**The fix is wiring, not new design.** Add transient-error detection at the
worker exit boundary, route detected transients into the existing chain,
exempt them from iteration counting.

## Options discussed

| Option | Steps from canon doc | Effort | What it does |
|--------|----------------------|--------|--------------|
| A — Full canon path | 1 + 2 + 3 + 4 | ~4.5 days | Adopt CLIProxyAPI as worker substrate; full cascade. Needs ≥2 accounts to round-robin and CLIProxyAPI installed. |
| B — No-proxy cascade | 1 + 3 + 4 | ~3.5 days | Classifier + cascade routing built directly in orch; no proxy dep. Layers 4-7 wire to existing model switches. Single-account-with-wait at the front. |
| **B-minus** — pragmatic cascade | 1 + 3 (partial) + 4 | **~2 days** | Classifier + model swap + thinking downgrade + wait. Skip Codex/Oracle integrations for now. Covers 80% of real rate-limit incidents. **Recommended.** |
| C — Minimum viable | 1 + 4 | ~1.5 days | Classifier + wait-and-retry. Won't dodge rate limit (no swapping), but stops burning iterations and resumes cleanly after cooldown. |
| D — Reconcile-only | 5 | ~1 day | Don't prevent the issue, just give us a clean recovery command (`orch reconcile <slug>`). Useful regardless of which other option ships. |

### What canon-doc step numbers refer to

1. **Failure classifier** — regex match on worker stdout/exit, structured tag
   in state.json (`{class, subclass, provider, reset_hint}`). Foundation.
2. **Point worker subprocesses at CLIProxyAPI** — Layers 1, 2, 3 of the cascade
   become free (auth rotation, account round-robin, model mapping handled by
   the proxy).
3. **Wire transient tag → cascade** — `transient` exits skip iteration counter;
   existing cascade engages.
4. **`reset_hint` countdown wait** — small primitive; only useful when
   `max_wait_ms` is short.
5. **`orch reconcile <slug>`** — state ↔ worktree healing; independent of the
   above.

### Difference between B and C in concrete terms

**Under C** the engine has one lever: time. If your account is rate-limited
at 6pm, the engine waits until 6pm, then retries the same worker (same model,
same agent). If quota didn't refill, sleeps again.

**Under B (or B-minus)** the engine has multiple levers: model, thinking
depth, context size, optionally coder/judge identity. Most rate-limit
incidents resolve at layer 1 (Opus → Sonnet) or layer 2 (drop extended
thinking) without sleeping. Tonight's incident under B-minus would have
recovered in ~30 seconds instead of waiting 3 hours.

## Decision direction (not yet committed)

Lean toward **C now + D bundled**, then **B-minus as a follow-up** —
ship the iteration-burn fix this week, layer in the smart cascade after.
OR jump straight to **B-minus** if 2 days is acceptable, since it's the
sweet spot on cost/value.

## What's deterministic vs agentic

Worth being explicit because the orch is a deterministic flow today, and we
want to keep it that way:

**Deterministic (shell):**
- Classifier — regex match, no judgment
- Cooldown sleep — parse `reset_hint`, sleep with floor/ceiling/jitter
- Cascade routing — table-driven (`subclass → next layer`)
- Reconcile — read state.json + walk worktree, emit diff, atomic rewrite

**Agentic (only when invoked, only by the cascade's later layers):**
- Coder fallback — re-spawn worker with a different agent
- Oracle escalation — Gemini for fresh perspective on stuck states

The first three layers (model swap, thinking downgrade, auto-compact) are
config-only in the existing worker invocation — no agent decision-making
added.

## Configuration shape (proposed, from canon doc)

```yaml
# dega-core.yaml addition
transient_handling:
  enabled: true
  detect_signatures:
    - "out of extra usage"
    - "resets \\d+(am|pm)"
    - "rate_limit"
    - "429"
    - "529"
    - "quota.*exceeded"
  on_transient:
    consume_iteration: false           # do not burn review iterations
    cascade:
      - auth_rotation
      - account_round_robin            # via CLIProxyAPI (B/A only)
      - model_swap                     # B-minus and up
      - thinking_downgrade             # B-minus and up
      - wait_for_reset                 # all options
      - coder_fallback                 # B and up
      - oracle_escalation              # B and up
    max_wait_ms: 300000                # 5min — beyond this, swap if available
    max_cascade_attempts: 3
```

## Open questions before planning

1. **CLIProxyAPI** — installed/usable in our setup, or a separate prerequisite?
   If prerequisite, A balloons in cost; B/B-minus stay flat.
2. **Account pool** — multiple Claude accounts available for round-robin, or
   single-account? Single-account makes A's main payoff (Layer 2) moot.
3. **Time horizon** — "ship soon, iterate later" (C → D → B-minus) or "build
   the right thing now" (jump to B-minus or B).
4. **Codex / Gemini availability** — do we have working CLI paths for these,
   or are layers 6-7 future work? B-minus deliberately punts on this.
5. **Reconcile auto-trigger** — canon doc suggests reconcile could run at
   engine startup automatically; if so, the `orch reconcile` command becomes
   internal-only. Worth deciding if/when we build D.

## What I salvaged from the older revision of the canon doc

The earlier version of `Canon_Orchestrator_Transient_Failure_Patterns.md`
proposed operator commands (`orch resume`, `--rerun-review`,
`--skip-review`, `held` and `needs_human_review` terminal statuses). The
updated version drops these in favor of the agentic-cascade frame —
correctly, since the orch is meant to be agent-native, not human-in-the-loop.

The one operator surface that survived: `orch reconcile` as a last-resort
state↔worktree healer, and even that can be auto-triggered.

Don't bring the operator-command shape back unless we have a strong reason.

## Files most likely to change (when we do plan it)

- `scripts/orch-run.sh` — worker spawn boundary, exit handling
- `scripts/orch-engine.sh` — iteration counter, cascade dispatch
- `scripts/orch-review.sh` — review status enum, transient tag awareness
- `scripts/orch-classifier.sh` — new, the regex match + tag write
- `scripts/orch-reconcile.sh` — new, only for option D
- `dega-core.yaml` — `transient_handling` block
- `tests/orch/test_classifier.bats` — pattern match cases
- `tests/orch/test_reconcile.bats` — diff and apply cases (D only)

## Decision log (running)

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-04-29 | Drop operator commands (`orch resume`, `--rerun-review`) from scope | Agent-native design; canon doc updated to remove them. |
| 2026-04-29 | Drop `needs_human_review` terminal status | Resume agent / cascade always has a next action. Adding a terminal state for "human go look" reintroduces the human-in-loop frame. |
| 2026-04-29 | Single-provider-with-pause is NOT the canonical default | Earlier doc said this; updated doc says cascade engages first, wait is a last layer. |
| pending | Which option (A / B / B-minus / C / D, or composition) | Awaits answers to the 5 open questions above. |

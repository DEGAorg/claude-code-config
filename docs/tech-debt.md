# Tech Debt

Single index of known debt. Severity is P1 (blocks something soon), P2
(annoys but works), P3 (cosmetic). Append; don't reorder. When fixed,
delete the entry.

---

## Stale `docs/exec-plans/` references

**Severity:** P2
**Area:** harness docs + config
**Logged:** 2026-05-03
**Context:** Plans now live as GitHub issues with `plan:draft`; the
orchestrator fetches them at run time. The `docs/exec-plans/` directory
is fully deprecated, but several files still point at it as the
canonical location.

**Live references to remove or rewrite:**

- `README.md:537` — `orch-run.sh` example uses `docs/exec-plans/active/...` as the plan path.
- `AGENTS.md:101` — directory map row: `` `docs/exec-plans/` | Execution plans: `active/` (in progress), `completed/` (archived), `tech-debt.md` ``.
- `AGENTS.md:174` — milestones table row referencing `docs/exec-plans/`.
- `AGENTS.md:215` — "Versioned specs at Stage 2 (`docs/exec-plans/active/`)".
- `AGENTS.md:259` — "log follow-ups to `docs/exec-plans/tech-debt.md`" — also points at this file's old home.
- `docs/conductor-agent-design.md:38` — table row: `` Active plans | `docs/exec-plans/active/` ``.
- `docs/self-development.md:31,42,76,85` — describes a flow that `mv`s plans between `active/` and `completed/`.
- `canon/AGENTS.md:67-69` — canon harness inheritance line listing `docs/exec-plans/`.
- `dega-core.yaml:50-53` — `success_criteria` `exec-plan-dirs` checks `docs/exec-plans/active/` (passes vacuously today; remove).
- `skills/tech-debt-tracking.md:11,17` — points debt index + per-item files at `docs/exec-plans/tech-debt.md` and `docs/exec-plans/tech-debt/`. Should point at `docs/tech-debt.md`.

**Fix:** one PR rewrites every reference to either drop the path or point
at the GitHub-issue flow / `docs/tech-debt.md`. No code changes.

---

## Missing `docs/agent-operating-mode.md`

**Severity:** P3
**Area:** harness docs
**Logged:** 2026-05-03
**Context:** `AGENTS.md:259` instructs agents to read
`docs/agent-operating-mode.md` for default operating rules. The file
does not exist in the repo.

**Fix:** either write the doc (canonising the rules already in `AGENTS.md`)
or remove the broken pointer. Bundle with the `docs/exec-plans/` cleanup
above.

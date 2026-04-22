# Canon Natural-Language UX Intent

Inside a canon-bootstrapped repo, users should interact with the agent in
natural language. Slash commands remain a bootstrap-only affordance for
the very first install step. This document tracks the three-plan rollout
that shifts `/canon-*` flows to NL-triggered skills.

## Plan status

- **Plan #1 — `canon-new` skill (pre-init NL intent capture):** implemented
  (`.orchestrator/plans/20260422-canon-new-skill/plan.md`). Adds
  `canon/skills/canon-new.md` and `canon/scripts/bootstrap-check.sh` with
  phase-based dispatch to `/apply-core` or the init flow.
- **Plan #2 — umbrella skill + `/canon-init` alias:** implemented
  (`.orchestrator/plans/20260422-canon-umbrella-state/plan.md`). Adds
  `canon/skills/canon.md` umbrella, `canon/scripts/phase-detect.sh`
  with full-phase detection (including `running` via
  `.canon/state.json`), converts `canon/commands/*.md` to skills
  under `canon/skills/` with NL `@description`, and reduces
  `commands/canon-init.md` to a thin alias of `canon-new`.
- **Plan #3 — `apply-core` manifest + install wiring:** pending.

## Why

Inside a canon repo, slash commands feel like a mode switch away from the
agent. NL-triggered skills keep the conversation natural and let the agent
choose the right action based on phase (not-bootstrapped vs bootstrapped).
The bootstrap-check script makes the phase explicit and reusable across
skills.

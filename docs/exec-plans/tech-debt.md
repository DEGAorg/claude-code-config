# Tech debt

## P2 — Core host parity beyond Canon entry points (2026-09-17)

`commands/apply-core.md` still distributes several Core workflows only as flat
Markdown commands, and the Codex settings/rules/hook adapters need a separate
compatibility audit. The Canon entry-point fix does not establish full Core parity.
Add native discovery and host-level smoke tests for the remaining workflows before
claiming the entire Core harness works in Codex.

## P2 — Shared Canon start workflow drift (2026-09-17)

`commands/canon-start.md` refers to `.canon/templates/<name>/plan.md`, although
bundled strategies live under `strategies/`. Its phase-6 introduction says
orchestrator while the actual instructions build directly. Bootstrap-only `.canon`
state routes through scaffold verification and can skip dependency/wallet setup.
The Codex adapter handles the bootstrap and plan-path cases. Reconcile the shared
procedure and the duplicate `canon/commands/canon-start.md` in a separate change,
with Claude and Codex pipeline tests before removing those host adaptations.

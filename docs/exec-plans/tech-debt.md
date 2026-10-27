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

## 2026-10-26 — P2: cryptographic dependency and SDK migration

CLI, templates and the PMXT proof of concept retain elliptic 6.6.1 through ethers 5
and vendor SDKs. GHSA-848j-6mx2-7j84 has no patched npm release. The inspected ethers
wrapper fixes secp256k1, rejects non-32-byte digests and does not accept a custom
nonce; the reported triggers are not reachable through those inspected paths.
This is a bounded source assessment, not a fix or a claim about every transitive
consumer. Keep the alert open. Validate a supported SDK/ethers migration with
signature vectors, offline transaction compatibility and existing dry-run guards
before replacing these interfaces. Polymarket's current SDK packages and a
transitive glob package also report deprecation notices; retain those notices in
validation evidence until this migration is completed.

## 2026-10-26 — P3: full-tree shell formatting baseline

`prek run --all-files` reports pre-existing formatting differences in
scripts/providers/provider.sh, scripts/providers/github.sh,
scripts/adapters/gemini-settings.sh, scripts/adapters/claude-settings.sh and
scripts/terminal-ui/test-reviewer-dashboard.sh. None is modified by the dependency
maintenance. Normalize these files in a focused formatting change. The scoped
pre-commit run and CI's top-level shell checks remain the gates for this change.

# Security dependency maintenance — 2026-10-26

CLI, templates, PMXT proof of concept and terminal UI receive refreshed lockfiles.
Both npm and pnpm locks remain supported where already present. In particular,
the templates npm lock now matches the PMXT and CLOB dependencies in its manifest.
No installed global files or existing user projects are rewritten by this change.

Persistent overrides in both package managers fix legacy Axios (0.34.0), ethers
provider WebSockets (8.22.0), and the Solana Jayson browser client (5.0.0). Jayson 5
removes old stream-json and uuid dependencies; the changed TCP/TLS protocol is not
used by Solana's browser client. Regression tests cover successful and failed
Solana JSON-RPC responses without a network request and reject ambiguous proxy
trust subnets. Vite 8.3.5, Vitest 4.1.12 and tsx 4.23.15 update the test/build tools.
utf-8-validate 5.0.10 satisfies both WebSocket 7 and 8 optional peer ranges.

Keep the unresolved elliptic advisory and SDK migration follow-up in
`docs/exec-plans/tech-debt.md`. Do not dismiss its alert or describe the package as
patched. npm may count its affected dependants as separate low-severity entries;
pnpm may omit a linked local package from the parent's audit, so audit the
templates independently as well as the CLI.

All validation unsets wallet keys and CANON_LIVE_TEST. No authenticated market
operation, order, wallet creation or globally installed tool update is part of
this maintenance. The PMXT proof of concept's authenticated/order scripts are
not suitable smoke tests for a dependency update.

# Orchestrator Verifier — DEPRECATED

This agent prompt is no longer used. Verify now runs directly in-engine
via `scripts/orch-verify.sh`, which executes each `## Completion criteria`
command under `timeout`, mutates plan.md checkboxes on pass, and returns
exit 0/1 for the engine to treat as SHIP/REVISE.

The agent-spawn verify path (tmux window, prompt template, poll loop)
has been removed entirely — not gated behind a flag.

See `scripts/orch-verify.sh` and `scripts/orch-engine.sh`
(`ORCH_VERIFY_PHASE_TIMEOUT` watchdog) for the current implementation.

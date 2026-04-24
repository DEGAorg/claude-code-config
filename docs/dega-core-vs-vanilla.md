# DEGA Core vs Vanilla Claude Code

| Capability | Vanilla Claude Code | DEGA Core |
|---|---|---|
| Single interactive session | Yes | Yes |
| Execution plans as versioned artifacts | No (plan mode is ephemeral) | `/plan` creates tracked plans in git |
| Parallel workers on one task | No | Orchestrator spawns N workers in isolated worktrees |
| Agent-to-agent review loop | No | Reviewer agent gates each item (SHIP/REVISE, up to 3 rounds) |
| Completion criteria verification | No | `orch-verify.sh` checks criteria after review passes |
| AFK/unattended execution | No (needs human in the loop) | `orch-run.sh` runs to completion in tmux |
| GitHub Issues as plan backend | No | Plans sync to/from GitHub Issues automatically |
| Guardrail hooks | Basic permission model | Lifecycle hooks: block `rm -rf`, enforce package managers, structured logging |
| Reusable harness across projects | Per-project AGENTS.md | `/apply-core` installs globally, works on any repo |
| Quality tracking | No | `/cleanup` scans + `quality.md` grades by area |
| Sound notifications | No | Audio cues on task completion |
| 9-stage dev pipeline | No | Codified in `dev-flow.md`, enforced by tooling |

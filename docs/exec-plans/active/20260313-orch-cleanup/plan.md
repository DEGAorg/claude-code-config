# Orchestrator Cleanup

Remove Claude-specific code, gitignore runtime state, close stale exec-plans.
This unblocks the tmux execution engine rewrite.

## Acceptance criteria

- No Agent Teams or TeamCreate references remain in the codebase
- `.orchestrator/` is gitignored
- Untracked runtime artifacts cleaned from working tree

## Progress log

- [ ] Add `.orchestrator/` to `.gitignore`
- [ ] Delete `agents/orch-lead.md` (Agent Teams specific, bash script replaces it)
- [ ] Remove Claude-specific refs from `agents/orch-worker.md` (TeamCreate, Agent Teams)
- [ ] Remove Agent Teams code from `scripts/orch-run.sh` (env var, launch block) — leave state init logic intact
- [ ] Clean untracked runtime files: `.ralph-state.json`, `.terminal-ui-state.json`, `context-handoff.txt`

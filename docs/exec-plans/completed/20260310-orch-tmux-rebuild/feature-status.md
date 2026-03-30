# Orchestrator Feature Status

Reference: `ace/notes/quick feature set.md`

| # | Feature | Status | Notes |
|---|---|---|---|
| 1 | AI Plan Generation | Done | `/plan` command + `create-exec-plan.sh` |
| 2 | Plan Execution Management | Partial | Single plan works (Ralph Loop). Orchestrator supports multiple tasks at once. Multi-plan sequential/parallel not built. |
| 3 | Orchestrator Runtime | Partial | State layer clean. Execution engine needs tmux rewrite (last commit replaced tmux with Claude Agent Teams). |
| 4 | Worker Agents | Partial | `orch-worker.md` exists, needs Claude-specific refs removed for agnostic support. |
| 5 | Visual Execution Environment | Partial | Ralph Loop has tmux pane splitting. Orchestrator needs the same. |
| 6 | Dedicated Execution Window | Partial | Dashboard exists (`scripts/terminal-ui/`). Needs verification and adjustments for orchestrator use. |
| 7 | Dashboard | Partial | Ink-based `scripts/terminal-ui/` exists. Needs orchestrator state integration. |
| 8 | Real-Time Observability | Not built | Depends on 5 + 7. |
| 9 | Autonomous Startup | Partial | `orch-run.sh` launcher exists, needs tmux rewrite. |

## Key decisions

- Provider-agnostic: no Claude-specific features (Agent Teams, TeamCreate)
- Execution: tmux (portable across macOS, WSL, Linux)
- Display: pluggable, optional per platform
- Dashboard: Ink, 30s polling, configurable via `ralph.yaml`
- Worker isolation: single worktree per plan, dependencies prevent conflicts
- Ralph Loop integration: reuse convergence patterns where possible
- `.orchestrator/` is runtime state, gitignored

## Work sequence

1. **Cleanup** — gitignore, close old plans, remove Agent Teams code
2. **Execution engine** — rewrite `orch-run.sh` with tmux wave-based spawning
3. **Dashboard integration** — verify and adjust Ink dashboard for orchestrator
4. **Smoke test** — end-to-end with existing smoke test plan
5. **Display layer** — `orch-display.sh` for optional per-worker terminal windows (follow-up)

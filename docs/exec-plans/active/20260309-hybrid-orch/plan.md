# Hybrid Orchestrator: State Layer + Agent Teams Execution

Slim down the orchestrator to two concerns: (1) persistent state management
for resumability, and (2) a thin launcher that delegates execution to Claude
Code Agent Teams or subagents. Delete the ~600 lines of tmux pane management,
polling loops, and worker launching that Agent Teams handles natively.

## Context

The current orchestrator (`orch-loop.sh`, `orch-start.sh`, `orch-grid.sh`,
`orch-worker.sh`, etc.) is ~800 lines of bash reimplementing features that
Claude Code Agent Teams ships natively: tmux auto-splitting, task dependency
tracking, worker spawning, inter-agent messaging.

What we keep: persistent state (state.json, done-files, plan checkboxes) for
cross-session resumability — Agent Teams doesn't have this.

What we replace: the execution engine. Instead of raw `claude -p` calls and
manual tmux pane routing, we use Agent Teams (or subagents as fallback).

## Acceptance criteria

- `orch-run.sh` is a single-command launcher: parses plan, inits state,
  spawns Claude with Agent Teams enabled, passes remaining items as tasks
- State persists across crashes — restart picks up from last completed item
- Workers write done-files; state.json updated on completion
- Plan checkboxes get marked as items complete
- Old scripts (`orch-grid.sh`, `orch-watch.sh`, `orch-list.sh`) deleted
- Smoke test plan runs end-to-end with the new slim orchestrator

## Progress log

- [x] Rewrite orch-run.sh as thin launcher: read state.json for incomplete items, enable CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS, launch claude with orchestrator agent prompt that creates a team for remaining items
- [x] Rewrite orch-state.sh to only keep: orch_write_state, orch_ensure_done_dir, orch_sync_done_files, orch_count_by_status, orch_update_item_status — delete all tmux/worktree/pane functions
- [x] Create agents/orch-lead.md subagent definition: reads plan.md + state.json, creates team, assigns items as tasks with deps, ensures done-files are written on completion (deps: 1)
- [x] Create agents/orch-worker.md subagent definition: receives single item, does the work, writes done-file, marks plan checkbox (deps: 1)
- [x] Add TaskCompleted hook in settings.json: on item completion, run orch-state.sh to sync done-file and update state.json (deps: 2, 3, 4)
- [x] Delete obsolete scripts: orch-grid.sh, orch-loop.sh, orch-start.sh, orch-stop.sh, orch-watch.sh, orch-worker.sh, orch-status.sh, orch-list.sh, orch-dash.sh (deps: 1, 2, 3, 4, 5)
- [ ] Reset smoke test plan and run end-to-end with new slim orchestrator (deps: 6)
- [x] Update apply-core.md install manifest: remove deleted scripts, add new agent definitions (deps: 6)

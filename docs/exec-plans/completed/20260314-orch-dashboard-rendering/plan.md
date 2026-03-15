# Plan: Dashboard Rendering Fixes

**Status:** In progress
**Created:** 2026-03-14

## Requirements

The Ink dashboard has rendering issues:
1. Worker output in the detail panel may not display (log watcher or pipe-pane not working)
2. Status colors in the header and table are too dim — need more prominent colors for running workers and review status
3. The header bar needs clearer visual distinction for orchestrator state (idle, running, reviewing, done)

## Current state

- `session-detail.tsx`: reads `outputLines` prop, strips ANSI, renders tail. Shows "No output captured" when empty.
- `orchestrator-app.tsx`: watches `logs/worker-{id}.log` via chokidar, reads last 200 lines on change.
- `session-table.tsx`: status colors defined but subtle (green for running, gray for queued, dimColor for counts).
- `orch-engine.sh`: uses `tmux pipe-pane` to stream worker output to log files.
- The dashboard header shows "ORCHESTRATOR" in bold white, review status in dim text.

## Approach

1. Diagnose: write a test script that creates a fake plan with a log file, launches the dashboard pointing at it, and writes to the log file to confirm rendering works end-to-end.
2. Fix the header: make running/review/done status use bright, bold colors. Add a prominent status badge.
3. Fix the table: make running items visually pop (bold green), done items clearly marked, failed items bright red.
4. Rebuild the terminal-ui after changes.

## Files to touch

| File | Change |
|------|--------|
| `scripts/terminal-ui/src/session-table.tsx` | Bolder status colors, bold running rows |
| `scripts/terminal-ui/src/session-detail.tsx` | Verify rendering, improve empty state |
| `scripts/terminal-ui/src/orchestrator-app.tsx` | Improve header colors and status badge |
| `tests/test-dashboard-rendering.sh` | End-to-end rendering verification script |

## Progress log

- [x] Create `tests/test-dashboard-rendering.sh`: sets up fake state.json + log file, launches dashboard in tmux, writes log lines, captures pane output, asserts log lines appear in the dashboard. (deps: none)
- [x] Improve header in `orchestrator-app.tsx`: bold colored status badge — bright green "RUNNING" when workers active, bright cyan "REVIEWING" during review, bright green "SHIP" or bright red "REVISE" for results. Add running/done/failed counts with color. (deps: none)
- [x] Improve table in `session-table.tsx`: running rows get bold bright green text, failed rows get bold red, done rows get dimmed green. Status column wider to fit icons. (deps: none)
- [x] Rebuild terminal-ui: `cd scripts/terminal-ui && pnpm build && tsc --noEmit`. (deps: 1, 2, 3)
- [x] Manual verification: launch dashboard against a live or fake plan, navigate with j/k, confirm worker output renders in detail panel, confirm colors are visible and distinct. (deps: 4)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Fake plan test script | Manual testing only | Reproducible, catches regressions, runs in CI |
| Bold+bright colors | Subtle status indicators | Dashboard is for quick glances at a distance, needs to pop |

## Completion criteria

- [ ] Test script passes: log lines written to file appear in dashboard pane
- [ ] Header shows colored status badge visible from across a room
- [ ] Running workers clearly distinguishable from queued/done at a glance
- [ ] `tsc --noEmit` and build pass clean

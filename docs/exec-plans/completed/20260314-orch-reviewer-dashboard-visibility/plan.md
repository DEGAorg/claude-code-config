# Plan: Reviewer Dashboard Visibility

**Status:** In progress
**Created:** 2026-03-14

## Requirements

- Dashboard detail panel shows reviewer output when an item is in review phase (currently only shows worker output)
- When navigating with j/k to an item being reviewed, the detail panel reads `reviewer-{id}.log` instead of `worker-{id}.log`
- The detail panel header changes to indicate reviewer vs worker context
- Dashboard must rebuild cleanly after changes

## Current state

The parallel review plan already implemented:
- Reviewers spawn as tmux windows (`reviewer-N`) with `pipe-pane` to `reviewer-{id}.log`
- `reviewStatus` field tracks per-item review state (pending/reviewing/passed/failed)
- `session-table.tsx` shows a REV column with status icons

What's missing:
- `orchestrator-app.tsx` line 81: log path is hardcoded to `worker-${selectedId}.log`
- `session-detail.tsx`: header always says "worker" regardless of phase
- During review phase, selecting an item shows "No output captured" because the reviewer log has a different filename

## Approach

Update the log watcher in `orchestrator-app.tsx` to pick the correct log file based on `reviewStatus`. When `reviewStatus` is `"reviewing"`, read `reviewer-{id}.log`. Otherwise read `worker-{id}.log`. Update `session-detail.tsx` header to show "reviewer" when in review phase.

## Files to touch

| File | Change |
|------|--------|
| `scripts/terminal-ui/src/orchestrator-app.tsx` | Log watcher picks `reviewer-{id}.log` or `worker-{id}.log` based on `reviewStatus` |
| `scripts/terminal-ui/src/session-detail.tsx` | Header shows "reviewer" when item is in review phase |
| `scripts/terminal-ui/dist/` | Rebuild |

## Progress log

- [x] Update `orchestrator-app.tsx`: derive log filename from `reviewStatus` — use `reviewer-{id}.log` when reviewing, `worker-{id}.log` otherwise. Pass `reviewStatus` to `SessionDetail`. (deps: none)
- [x] Update `session-detail.tsx`: accept `reviewStatus` prop, show "reviewer" in header when reviewing, show "worker" otherwise. (deps: none)
- [x] Rebuild terminal-ui: `cd scripts/terminal-ui && pnpm build`. Verify `tsc` passes. (deps: 1, 2)
- [x] Test: create fake state with `reviewStatus: "reviewing"` and a `reviewer-1.log` file, launch dashboard, select item 1 with j, verify reviewer log content appears in detail panel. (deps: 3)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Switch log file based on reviewStatus | Watch both files simultaneously | Simpler, one file at a time is sufficient since an item is either being worked or reviewed |

## Completion criteria

- [ ] Selecting a reviewing item shows reviewer log output in detail panel
- [ ] Header shows "reviewer" vs "worker" appropriately
- [ ] `tsc --noEmit` passes
- [ ] Dashboard renders correctly with both worker and reviewer states

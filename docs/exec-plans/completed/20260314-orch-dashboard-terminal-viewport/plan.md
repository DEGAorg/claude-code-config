# Plan: Dashboard Terminal Viewport

**Status:** In progress
**Created:** 2026-03-14

## Requirements

- Dashboard detail panel must show clean, readable worker/reviewer output
- No garbled escape sequences, cursor positioning artifacts, or TUI frame fragments
- Output should look like you're seeing the actual terminal pane content
- Works for both interactive `claude` (TUI) and headless `claude -p` workers

## Current state

`pipe-pane` streams raw terminal bytes to `logs/worker-{id}.log`. For headless
`claude -p` workers this is clean text. For interactive `claude` workers, this
includes cursor positioning (`\e[H`, `\e[2J`), box-drawing characters, screen
redraws, and partial line overwrites. `strip-ansi` only removes color codes,
not cursor/screen control sequences. Result: garbled output in the dashboard.

## Approach

Replace `pipe-pane` log file reading with `tmux capture-pane` for live output.
`tmux capture-pane -t <pane> -p` renders the terminal's screen buffer as clean
text — exactly what you'd see if you switched to that tmux window. This handles
all terminal emulation correctly because tmux itself is the terminal emulator.

### Implementation

1. Remove `pipe-pane` from worker/reviewer spawning (no more log files for
   dashboard reading — log files can stay for archival via pipe-pane but
   dashboard doesn't read them)
2. In `orchestrator-app.tsx`, replace the chokidar log file watcher with a
   polling interval that runs `tmux capture-pane -t orch-<slug>:worker-<id> -p`
   via `child_process.execFile` and sets the output lines from the result
3. The capture approach works for both worker and reviewer windows — just
   change the window name prefix
4. Poll every 1-2 seconds (capture-pane is fast, <10ms)

### Why this works

- `tmux capture-pane` is the terminal emulator's own screen buffer dump
- It handles all escape sequences, cursor movement, screen redraws correctly
- Works identically for TUI (`claude`) and headless (`claude -p`) modes
- No dependency on log file writing or strip-ansi hacks
- If the window doesn't exist (worker finished), capture fails gracefully

### Fallback

Keep `pipe-pane` log files as archival (useful for post-mortem debugging),
but the dashboard reads from `tmux capture-pane` for live display.

## Files to touch

| File | Change |
|------|--------|
| `scripts/terminal-ui/src/orchestrator-app.tsx` | Replace chokidar log watcher with `tmux capture-pane` polling via `child_process.execFile` |
| `scripts/terminal-ui/src/session-detail.tsx` | No functional changes needed — it receives lines, doesn't care about source |

## Risks and open questions

- **Node `execFile` in Ink render loop:** Running `tmux capture-pane` every 1-2s
  from a React effect is fine — it's async, fast (<10ms), and non-blocking.
- **Window naming:** Must match the naming convention in orch-engine.sh
  (`worker-{id}`) and orch-review.sh (`reviewer-{id}`).
- **Session name:** Need the tmux session name. Can derive from the state file
  path (it's under `plans/<slug>/state.json`, session is `orch-<slug>`).

## Progress log

- [x] Update `orchestrator-app.tsx`: replace chokidar log file watcher with a `setInterval` that calls `tmux capture-pane -t orch-<slug>:worker-<id> -p` (or `reviewer-<id>` during review phase) via `execFile`. Parse output into lines and set state. Derive tmux session name from the plan slug in state.json. Clean up interval on unmount or selection change. (deps: none)
- [x] Remove `strip-ansi` usage from `session-detail.tsx` — `capture-pane` output is already clean text, no stripping needed. (deps: none)
- [x] Rebuild terminal-ui: `cd scripts/terminal-ui && pnpm build`. (deps: 1, 2)
- [x] Test: launch a worker in interactive `claude` mode, verify dashboard shows clean readable output without garbled escape sequences. Compare with headless `claude -p` output. (deps: 3)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| `tmux capture-pane` polling | xterm-headless VT emulator in Node, pipe-pane with better stripping | tmux IS the terminal emulator — use its own screen buffer instead of re-implementing terminal parsing. Zero new dependencies. |
| Keep pipe-pane for archival | Remove pipe-pane entirely | Log files are useful for post-mortem debugging even if dashboard doesn't read them |
| 1-2s poll interval | chokidar file watching, WebSocket | Simple, fast enough for human eyes, no complexity |

## Completion criteria

- [ ] Interactive `claude` TUI worker output renders cleanly in dashboard (no escape artifacts)
- [ ] Headless `claude -p` worker output continues to render cleanly
- [ ] Reviewer output renders cleanly during review phase
- [ ] `tsc --noEmit` passes
- [ ] No new dependencies added

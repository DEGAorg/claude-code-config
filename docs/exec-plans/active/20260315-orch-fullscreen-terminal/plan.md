# Plan: Orch fullscreen terminal window

**Status:** In progress
**Created:** 2026-03-15

## Requirements

- The terminal window opened by `orch-display.sh` on macOS should be maximized/fullscreen so the dashboard has room
- The `.command` file should use `exec` so the terminal window closes cleanly when tmux detaches

## Approach

Modify `open_command_file()` in `orch-display.sh`:

1. Add `printf '\e[9;1t'` before `exec tmux attach` — this is the xterm maximize escape sequence, works in Terminal.app and iTerm2
2. Change `tmux attach-session` to `exec tmux attach-session` — when tmux exits, the shell process is replaced, so the terminal window closes automatically instead of leaving a dead shell

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-display.sh` | Add maximize escape and exec to .command file |

## Risks and open questions

- None — maximize escape is best-effort, falls back to default size on unsupported terminals

## Progress log

- [ ] Add maximize escape and exec to .command file in orch-display.sh

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| xterm escape `\e[9;1t]` | AppleScript resize | Works cross-platform, no permissions needed |
| `exec tmux attach` | trap EXIT | exec replaces shell — terminal closes when tmux exits, zero cleanup |

## Completion criteria

- [ ] Terminal window opens maximized on macOS
- [ ] Terminal window closes cleanly when tmux session ends
- [ ] `shellcheck scripts/orch-display.sh` clean

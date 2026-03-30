# Plan: tmux Session Launcher

**Status:** In progress
**Created:** 2026-03-03
**Parent:** `docs/research/terminal-ui-action-plan.md` (Plan 3)

## Requirements

- Shell script that creates a named tmux session with two-pane layout
- Left pane (60%): user's shell — they run `claude` or any command here
- Right pane (40%): runs `terminal-ui --state <path>` (Ink dashboard)
- If `terminal-ui` is not installed, falls back to `watch -n1 cat <state-file>`
- Idempotent: if session already exists, attaches to it
- tmux status bar shows session name and current time
- Reusable by Canon (`--name canon --state .canon/state.json`) and Ralph Loop
- Installed globally by `/apply-core` to `~/.claude/scripts/terminal-session.sh`
- Passes shellcheck and shfmt
- Under 50 lines

## Approach

### Interface

```bash
terminal-session.sh --name <session-name> --state <state-file-path>
```

Both flags required. No positional args — explicit is better for a script that
multiple commands and agents will call.

### Session lifecycle

1. Check if tmux session `<name>` already exists (`tmux has-session`)
2. If exists: attach (`tmux attach-session`) and exit
3. If not: create new detached session, split, configure, then attach

### Pane setup

```
┌──────────────────────┬──────────────────┐
│                      │                  │
│   Left pane (60%)    │  Right pane (40%)│
│   User shell         │  terminal-ui     │
│                      │  --state <path>  │
│                      │                  │
└──────────────────────┴──────────────────┘
```

- Create session with default shell in left pane
- Split horizontally: `tmux split-window -h -p 40`
- Right pane runs: `terminal-ui --state <path>` if available,
  otherwise `watch -n1 jq . <path>` as fallback

### Fallback detection

Check if `terminal-ui` is on PATH or if the built package exists at
`~/.claude/scripts/terminal-ui/dist/cli.js`. If neither, use the `watch` fallback.
This lets the script work before Plan 2 (Ink dashboard) is complete.

### Status bar

```bash
tmux set-option -t <name> status-left " #S "
tmux set-option -t <name> status-right " %H:%M "
```

Minimal — session name on the left, time on the right. The Ink dashboard
in the right pane handles detailed status display.

### Integration points

- `/canon-start` (Plan 4) calls this script with `--name canon --state .canon/state.json`
- Ralph Loop could call it with `--name ralph --state <task-dir>/.ralph-ui-state.json`
- Any future automation calls it the same way

## Files to touch

| File | Change |
|------|--------|
| `scripts/terminal-session.sh` | Create — tmux session launcher |

## Risks and open questions

- **P2:** Should the script accept a command for the left pane (e.g., `--cmd "claude"`)?
  → No. Keep it simple — left pane gets the user's default shell. They type whatever
  they want. Adding `--cmd` adds complexity and edge cases (shell quoting, exit handling).
- **P2:** Should the right pane auto-restart if `terminal-ui` crashes? → No. If the
  dashboard crashes, the pane shows the exit status. User can re-run manually or
  restart the session. Auto-restart adds complexity for an unlikely failure.

## Progress log

- [x] Write `scripts/terminal-session.sh` with arg parsing, session creation, pane split
- [x] Add terminal-ui fallback detection (PATH check, dist/cli.js check, watch fallback)
- [x] Add tmux status bar configuration
- [x] shellcheck and shfmt pass
- [x] Manual test: `bash scripts/terminal-session.sh --name test --state /tmp/test-state.json`

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Named flags (`--name`, `--state`) | Positional args | Multiple callers (canon-start, ralph, manual). Named flags are self-documenting and order-independent. |
| Attach if session exists | Kill and recreate | Idempotent. User may have work in the left pane. Destroying it would lose context. |
| `watch` fallback for right pane | Blank pane, error message | Useful even before Ink dashboard is built. Shows state file contents updating in real time. |
| Minimal status bar (name + time) | Rich status bar with phase/metrics | Ink dashboard handles detail display. tmux status bar is just for orientation. |
| No `--cmd` flag for left pane | Accept arbitrary command | YAGNI. Left pane is the user's shell. They decide what to run. Adding quoting/exec logic for one flag isn't worth it. |

## Completion criteria

- [x] `bash scripts/terminal-session.sh --name test --state /tmp/s.json` opens a tmux session
- [x] Session has two panes: left (shell) and right (dashboard or watch fallback)
- [x] Running the same command again attaches to existing session
- [x] shellcheck and shfmt clean

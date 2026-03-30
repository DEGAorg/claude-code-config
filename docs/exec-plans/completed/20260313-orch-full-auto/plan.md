# Plan: Orchestrator Full Auto — One Command Does Everything

**Status:** In progress
**Created:** 2026-03-13

## Requirements

- Single command runs the full orchestrator lifecycle: tmux session, dashboard, workers, display windows
- `orch-run.sh <slug>` opens terminal windows automatically (no manual `tmux attach`)
- Dashboard window shows live state.json progress
- Worker windows show each `claude -p` running in its own pane
- Main user terminal stays free — orchestrator runs in separate windows
- macOS support required (Darwin), WSL/Linux best-effort
- `--background` flag available for headless/AFK runs (tmux only, no windows)

## Approach

Two scripts, three changes:

### 1. `scripts/orch-display.sh` — platform-aware terminal opener

Detects platform and opens terminal windows attached to tmux session.

```
macOS + iTerm2  → osascript: new iTerm2 tab, run tmux attach
macOS + Terminal → osascript: new Terminal.app window, run tmux attach
WSL             → wt.exe new-tab with wsl tmux attach
Linux           → xterm/gnome-terminal/konsole with tmux attach
Fallback        → prints tmux attach command
```

Read-only attach (`tmux attach -r`) so display windows can't interfere.

### 2. Wire into `orch-run.sh`

Default behavior becomes foreground (opens windows). Add `--background` flag
for headless runs. After creating tmux session and spawning first wave,
call `orch-display.sh` to open windows.

### 3. Ink dashboard in tmux pane

Replace `watch jq` placeholder with the Ink orchestrator dashboard.
Add `--orch <state-path>` mode to `cli.tsx` that renders `orchestrator-app.tsx`.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-display.sh` | New — platform detection + terminal window opener |
| `scripts/orch-run.sh` | Add `--background` flag, call `orch-display.sh` by default, replace `watch jq` with Ink |
| `scripts/terminal-ui/src/cli.tsx` | Add `--orch <state-path>` mode |
| `commands/apply-core.md` | Add `orch-display.sh` to manifest |

## Risks and open questions

- **macOS permissions**: Terminal.app/iTerm2 automation may need accessibility permissions on first run. Fallback prints the command.
- **Ink build required**: `pnpm install && pnpm run build` in terminal-ui/ after changing cli.tsx. Worker can do this.

## Progress log

- [x] Create `scripts/orch-display.sh`: detect platform, open terminal window(s) attached to tmux session (read-only)
- [x] Add `--orch <state-path>` entry point to `scripts/terminal-ui/src/cli.tsx` that renders `orchestrator-app.tsx`
- [x] Build terminal-ui: `cd scripts/terminal-ui && pnpm install && pnpm run build` (deps: 2)
- [x] Replace `watch jq` dashboard in `orch-run.sh` with Ink dashboard command (deps: 3)
- [x] Add `--background` flag to `orch-run.sh`, make foreground (auto-open windows) the default (deps: 1, 4)
- [x] Test: `orch-run.sh <slug>` opens terminal windows with dashboard and workers visible on macOS (deps: 5)
- [x] Update `commands/apply-core.md` manifest with `orch-display.sh` (deps: 5)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Foreground by default | Background by default with `--foreground` | User wants to see what's happening. AFK is the exception, not the rule. |
| Read-only tmux attach | Full attach | Display windows are for watching. Prevents accidental keystrokes in worker panes. |
| Platform detection in single script | Separate scripts per OS | One entry point. Detection is ~20 lines. Easier to maintain. |

## Completion criteria

- [ ] `orch-run.sh <slug>` opens dashboard and worker windows automatically on macOS
- [ ] `orch-run.sh <slug> --background` runs headless (tmux only, no windows)
- [ ] Dashboard shows live item states from state.json
- [ ] Closing a display window does not kill the worker
- [ ] shellcheck and shfmt clean

# Plan: Orchestrator Visibility Layer

**Status:** In progress
**Created:** 2026-03-13

## Requirements

- Orchestrator opens a dedicated terminal window automatically on startup (feature 6)
- Dashboard pane shows live plan progress, task states, worker activity (feature 7)
- Worker panes are visible in real time — user can watch agents operate (features 5, 8)
- Main user terminal remains free — orchestrator runs in separate window
- macOS: open native Terminal.app or iTerm2 windows
- WSL: best-effort via Windows Terminal (`wt.exe`)
- Fallback: `tmux attach` in any terminal (always works)

## Approach

Three deliverables, built in order:

### 1. `orch-display.sh` — terminal window opener

Opens terminal windows attached read-only to the orchestrator's tmux session.
Platform detection picks the right method:

- **macOS + iTerm2**: AppleScript to open new iTerm2 tab with `tmux attach -t orch-<slug> -r`
- **macOS + Terminal.app**: `open -a Terminal` with a temp script that attaches
- **WSL**: `wt.exe -w 0 new-tab wsl.exe -d $WSL_DISTRO_NAME -- tmux attach -t orch-<slug> -r`
- **Linux native**: `xterm -e tmux attach -t orch-<slug> -r` or equivalent (`gnome-terminal`, `konsole`)
- **Fallback**: prints the `tmux attach` command for manual use

Options:
- `orch-display.sh <slug>` — opens full session view (dashboard + workers)
- `orch-display.sh <slug> --worker <id>` — opens single worker pane
- `orch-display.sh <slug> --dashboard` — opens dashboard only

### 2. Ink dashboard integration

The Ink dashboard (`scripts/terminal-ui/`) already has orchestrator components
(`orchestrator-app.tsx`, `session-table.tsx`, `session-detail.tsx`). Wire it
into the orchestrator's tmux dashboard pane instead of the current `watch jq`
placeholder.

Dashboard shows:
- Plan slug, progress (N/M items done)
- Item table: ID, description, status, wave, worker PID
- Selected item detail: deps, done-file content, review result
- Polling indicator (last updated timestamp)

### 3. Auto-open on `orch-run.sh` startup

Add `--foreground` flag to `orch-run.sh` that calls `orch-display.sh` after
creating the tmux session. Default behavior stays background (tmux only).

```bash
# Background (default) — tmux session only
orch-run.sh 20260309-orch-smoke-test

# Foreground — also opens terminal windows
orch-run.sh 20260309-orch-smoke-test --foreground
```

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-display.sh` | New — platform-aware terminal window opener |
| `scripts/orch-run.sh` | Add `--foreground` flag, replace `watch jq` with Ink dashboard |
| `scripts/terminal-ui/src/orchestrator-app.tsx` | Verify it works with current state.json schema |
| `scripts/terminal-ui/src/cli.tsx` | Add `--orch` mode entry point |
| `commands/apply-core.md` | Add `orch-display.sh` to install manifest |

## Risks and open questions

- **iTerm2 AppleScript**: may need accessibility permissions on macOS. Fallback to Terminal.app.
- **WSL `wt.exe` path**: may differ across Windows versions. Best-effort, with clear error message.
- **Ink dashboard build**: needs `pnpm install && pnpm run build` after changes. CI should catch build failures.

## Progress log

- [ ] Create `scripts/orch-display.sh` with platform detection (macOS iTerm2, macOS Terminal, WSL, Linux xterm, fallback)
- [ ] Add `--dashboard` and `--worker <id>` flags to `orch-display.sh`
- [ ] Replace `watch jq` dashboard pane in `orch-run.sh` with Ink dashboard (`terminal-ui` in `--orch` mode)
- [ ] Add `--orch <state-path>` entry point to `scripts/terminal-ui/src/cli.tsx`
- [ ] Verify `orchestrator-app.tsx` renders correctly with current state.json schema
- [ ] Add `--foreground` flag to `orch-run.sh` that calls `orch-display.sh` after tmux session creation
- [ ] Test on macOS: `orch-run.sh <slug> --foreground` opens terminal windows with dashboard and workers visible
- [ ] Update `commands/apply-core.md` install manifest with `orch-display.sh`

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Platform detection in shell | Separate scripts per platform | Single entry point, simpler for users. Detection logic is ~20 lines. |
| Read-only tmux attach (`-r`) | Full attach | Display windows observe only. Prevents accidental input in worker panes. |
| `--foreground` opt-in | Auto-open always | Background is the common case (AFK runs). Foreground is for when you want to watch. |
| Ink over `watch jq` | Keep `watch jq` | Ink dashboard already exists, shows structured state, supports navigation. |

## Completion criteria

- [ ] `orch-display.sh <slug>` opens a terminal window on macOS
- [ ] Dashboard shows live item states from state.json
- [ ] `orch-run.sh <slug> --foreground` launches orchestrator with visible windows
- [ ] Fallback prints `tmux attach` command when platform detection fails
- [ ] shellcheck and shfmt clean

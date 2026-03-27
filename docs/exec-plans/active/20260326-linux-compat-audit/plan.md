# Linux compatibility audit — orchestrator scripts

**Source:** `ace/notes/linux-issues.md` (general Q5.3)
**Analysis:** `ace/notes/linux-issues-analysis.md`

## Problem

The orchestrator was developed and tested exclusively on macOS. First Linux
run (SSH into VPS, headless, no display server) exposed multiple failures.
A systematic audit is needed to find and fix all platform assumptions.

## Known platform-specific code

| File | Issue | macOS command | Linux equivalent |
|------|-------|---------------|------------------|
| `orch-display.sh` | Window opening | `open`, `osascript` | `gnome-terminal`, `xterm` — but SSH/headless has NONE |
| `play-sound.sh` | Audio playback | `afplay` | `mpv`, `ffplay`, `paplay` — headless has NONE |
| `orch-engine.sh:605` | Date parsing | `date -jf` (BSD) | `date -d` (GNU) — has `||` fallback |
| `settings.json` | macOS-specific deny paths | `~/Library/Keychains/**` etc. | No equivalent on Linux |

## Approach

1. Audit every `.sh` file in `scripts/` and `hooks/` for platform-specific
   commands using a checklist of known macOS-only commands.
2. For each finding: add Linux fallback or skip gracefully on unsupported
   platforms.
3. Special attention to headless/SSH environments where there is no display
   server, no audio, and no GUI terminal emulator.
4. Add a platform detection helper function to `orch-state.sh` that other
   scripts can source.

## Requirements

1. All orchestrator scripts must work on headless Linux (SSH + tmux, no X11).
2. Features that require a display (dashboard window, sound) must degrade
   gracefully — log a message and continue, never crash.
3. BSD vs GNU command differences must be handled (date, sed, stat, etc.).
4. No regressions on macOS.

## Progress log

- [ ] Create platform detection helper: `orch_platform()` returning `macos|linux|wsl` — add to `orch-state.sh`
- [x] Audit `orch-display.sh`: add headless detection (no DISPLAY, no TERM_PROGRAM) — skip window opening with log message (deps: 1)
- [x] Audit `play-sound.sh`: add headless detection — skip audio with log message (deps: 1)
- [x] Audit `orch-engine.sh`: verify all `date` commands have GNU fallbacks (deps: 1)
- [x] Audit `orch-run.sh`: check for macOS assumptions in session creation, worktree setup (deps: 1)
- [x] Audit `orch-review.sh` and `orch-verify.sh`: same sweep (deps: 1)
- [x] Audit `scripts/gh-plan-sync.sh`, `scripts/gh-plan-fetch.sh`: check `sed`, `date`, path assumptions (deps: 1)
- [ ] Audit `settings.json`: document that `~/Library/` deny paths are macOS-only, add Linux equivalents (deps: 1)
- [ ] Run shellcheck on all modified scripts (deps: 2, 3, 4, 5, 6, 7, 8)
- [ ] Integration test: dry-run orchestrator startup on Linux (or simulate with OSTYPE=linux-gnu) (deps: 9)

## Completion criteria

- [ ] No macOS-only commands without Linux fallbacks in any orchestrator script
- [ ] Headless SSH+tmux environment handled gracefully (no crashes, informative logs)
- [ ] All date/sed/stat commands handle both BSD and GNU variants
- [ ] shellcheck clean on all modified files
- [ ] Platform detection helper available for future scripts

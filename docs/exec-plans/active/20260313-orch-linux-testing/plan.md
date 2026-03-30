# Plan: Orchestrator Linux Testing and Platform Fixes

**Status:** In progress
**Created:** 2026-03-13

## Requirements

- Orchestrator runs on Linux (Ubuntu/WSL) with same behavior as macOS
- Display window opens via appropriate Linux terminal emulator
- Ink dashboard renders correctly in Linux tmux
- `.command` file fallback replaced with Linux-native approach on Linux
- Document platform-specific behavior

## Approach

The orchestrator core (tmux + polling + workers) is already portable bash. The
platform-specific pieces are:

1. **Display window (`orch-display.sh`)**: macOS uses `.command` files. Linux
   needs `gnome-terminal`, `konsole`, `xterm`, or WSL's `wt.exe`. These paths
   already exist in the script but are untested.

2. **Ink dashboard**: Uses `node` + React. Should work anywhere node runs. The
   `isRawModeSupported` guard handles non-TTY environments. Needs verification
   in Linux tmux.

3. **`sleep 2147483647`**: Portable — works on both GNU and macOS `sleep`.

4. **`jq`, `tmux`, `node`**: Required dependencies. Add dependency check at
   script startup with clear error messages.

Test on WSL (Windows Subsystem for Linux) as the primary Linux target, since
that's the most common non-macOS dev environment.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-run.sh` | Add dependency check (jq, tmux, node) at startup |
| `scripts/orch-display.sh` | Verify and fix Linux terminal detection paths |
| `scripts/orch-display.sh` | Add WSL `wt.exe` testing |
| `README.md` | Document platform requirements and known issues |

## Risks and open questions

- **No Linux test environment available in this session.** Plans must be tested
  manually by the user on their Linux/WSL machine. The plan produces the code
  changes; user validates them.
- **WSL tmux interaction:** WSL2 runs its own tmux inside the Linux subsystem.
  `wt.exe` opens a Windows Terminal tab that runs `wsl bash -c "tmux attach..."`.
  This should work but may have PATH or session isolation issues.
- **gnome-terminal `--` flag:** Some older versions don't support `--` separator.
  Need to test or use `-e` fallback.

## Progress log

- [ ] Add dependency check to `orch-run.sh` (jq, tmux, node — exit with clear message if missing)
- [ ] Test `orch-display.sh` Linux paths: verify gnome-terminal, konsole, xterm commands are correct
- [ ] Test WSL path: verify `wt.exe new-tab -- wsl bash -c "tmux attach..."` works
- [ ] Verify Ink dashboard renders in Linux tmux (node + React + chokidar)
- [ ] Add platform requirements to README.md
- [ ] Run full smoke test on Linux/WSL

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Test on WSL first | VM, Docker, native Linux | WSL is the most common non-macOS dev environment for the team |
| Dependency check at startup | Assume deps exist | Clear error messages save debugging time; deps are easy to install |

## Completion criteria

- [ ] `orch-run.sh` includes dependency check with actionable error messages
- [ ] `orch-display.sh` Linux paths verified or fixed
- [ ] README documents platform requirements
- [ ] shellcheck clean on all modified scripts

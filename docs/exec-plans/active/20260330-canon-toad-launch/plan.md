# Plan: Canon launches via Toad TUI

## Context

The canon demo needs to run through Toad (conductor-view) instead of
the old tmux + terminal-ui layout. Toad now has full Canon integration:
CanonStateWidget, Builder section, Automation section, auto-show logic,
and `--project-dir` flag. The `toad acp` command auto-executes an
initial prompt when the agent connects — equivalent to the tmux
`send-keys "/canon-start"` pattern.

Safety: keep the tmux path as fallback for environments without Toad.

## Requirements

1. `canon.sh` launches Toad when available, tmux when not
2. `/canon-start` works in both Toad (ACP) and tmux environments
3. `canon-init.md` generates the updated `canon.sh`
4. Demo-ready: `./canon.sh` opens Toad with `/canon-start` prefilled

## Approach

### canon.sh — two launch modes

```bash
if command -v toad >/dev/null 2>&1; then
  # Toad mode: single process, no tmux
  # Init state, then launch Toad with /canon-start as initial prompt
  toad acp "/canon-start" --project-dir "$(pwd)"
else
  # Fallback: existing tmux layout (agent left, dashboard right)
  # ... current tmux code unchanged ...
fi
```

In Toad mode:
- Init `.canon/state.json` before launching (same as now)
- `toad acp` spawns Claude as ACP agent, auto-sends `/canon-start`
- Builder section auto-shows when state.json appears with build phase
- Automation section auto-shows when phase transitions to run
- No tmux, no terminal-ui, no split panes — Toad handles everything

### canon-start.md — relax tmux requirement

Step 1 currently refuses if `$TMUX` is not set. Change to:

- If `$TMUX` is set → current behavior (check session name)
- If `$TOAD_CWD` is set → running under Toad ACP, proceed normally
- If neither → refuse with updated message mentioning both options

State writes stay the same — `terminal-ui-write.sh` writes to
`.canon/state.json`, Toad watches that file automatically.

### canon-init.md — update generated script

Update the `canon.sh` template written by `/canon-init` to match
the new dual-mode launcher. Add `toad` as optional prerequisite
(not required — tmux fallback exists).

## Progress log

- [ ] Update `scripts/canon.sh` — add Toad-native launch mode with `toad acp "/canon-start"`, keep tmux as fallback
- [ ] Update `canon/commands/canon-start.md` step 1 — accept `$TOAD_CWD` as valid environment alongside tmux (deps: 1)
- [ ] Update `commands/canon-init.md` — new prerequisites list, updated canon.sh template (deps: 1)
- [ ] Test: run `./canon.sh` with toad installed — verify Toad launches, /canon-start auto-executes, Builder section appears (deps: 2, 3)

## Completion criteria

- [ ] `./canon.sh` launches Toad with `/canon-start` prefilled when toad is installed
- [ ] `./canon.sh` falls back to tmux layout when toad is not installed
- [ ] `/canon-start` proceeds without error in both Toad and tmux environments
- [ ] `.canon/state.json` updates trigger Builder/Automation sections in Toad
- [ ] `commands/canon-init.md` generates the correct dual-mode canon.sh
- [ ] shellcheck passes on canon.sh

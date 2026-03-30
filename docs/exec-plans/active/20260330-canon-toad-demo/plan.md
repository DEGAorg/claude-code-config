# Plan: Canon Demo with Toad TUI

## Context

The March 5 demo used a 2-pane tmux layout: Claude (left) + Node.js Ink
terminal-ui (right) watching `.canon/state.json`. For the new demo, the
right pane should be **Toad** (conductor-view TUI) instead of the Ink
dashboard.

Canon does not use the orchestrator. It drives builds via Ralph Loop and
runs automations directly, writing all state to `.canon/state.json`.
The Toad TUI needs to consume this state format — see the companion spec
`docs/toad-canon-sections-spec.md` for the conductor-view work.

## Requirements

1. Rewrite `scripts/canon.sh` to launch Toad as the dashboard instead of
   terminal-ui
2. Update `commands/canon-init.md` to match the new launcher
3. Toad receives the project directory path so it can find `.canon/state.json`
4. Preserve agent-agnostic shim usage (works with Claude, Gemini, Codex)
5. Graceful fallback if Toad is not installed (keep terminal-ui as fallback)

## Approach

### canon.sh rewrite

Replace the dashboard renderer selection with Toad as primary:

```
Priority:
1. toad CLI (if installed) — full TUI with Builder + Automation sections
2. terminal-ui CLI (if installed) — legacy Ink dashboard
3. Node.js Ink app (if dist/cli.js exists) — legacy fallback
4. cat loop — bare minimum
```

Toad launch: `toad --project "$(pwd)"` (or whatever the conductor-view
CLI flag ends up being — coordinate with the Toad spec).

The tmux layout stays the same: left=agent (60%), right=dashboard (40%).

### canon-init.md update

Update the prerequisite check to look for `toad` in PATH. Update the
generated `canon.sh` template to match the new script.

## Progress log

- [ ] Rewrite `scripts/canon.sh` — replace terminal-ui with Toad as primary dashboard renderer, keep fallbacks
- [ ] Update `commands/canon-init.md` — new prerequisites (toad), updated canon.sh template (deps: 1)
- [ ] Test: run `canon.sh` with Toad installed — verify tmux layout, Toad receives project path (deps: 2)
- [ ] Test: run `canon.sh` without Toad — verify fallback to terminal-ui or cat loop (deps: 2)

## Completion criteria

- [ ] `scripts/canon.sh` launches Toad as primary dashboard when available
- [ ] Falls back gracefully to terminal-ui or cat loop
- [ ] `commands/canon-init.md` checks for toad and writes updated canon.sh
- [ ] Agent shim still works (provider-agnostic)
- [ ] shellcheck passes on canon.sh

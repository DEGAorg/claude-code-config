# Plan: Toad Agent Selector — First-Boot Pick + Direct Boot

**Status:** Completed
**Created:** 2026-03-21
**Completed:** 2026-03-22
**Repo:** DEGAorg/conductor-view (AGPL-3.0)

> **Note:** Executed manually by Claude without the orchestrator. The work
> targeted conductor-view (a separate repo), which the orchestrator cannot
> manage yet due to multi-repo support not being implemented. All items
> were completed in interactive sessions.

## Requirements

- First boot: show a simplified store screen with only 3 coding agents (Claude, Gemini, Codex) using existing card style, theming, and install buttons
- Selection saves to a `default_agent` setting in `~/.config/toad/toad.json`
- Subsequent boots: skip home screen, launch directly to conversation with saved agent (same behavior as current `--conductor` flag)
- User can change default agent via settings (a "switch agent" or "reset" option)
- All other agents remain in TOML files but are filtered out of the picker UI
- Remove `--conductor` CLI flag — replaced by persistent `default_agent` setting
- Existing theme compatibility and card appearance preserved

## Approach

Reuse the existing store screen (StoreScreen) with a filtered agent list. Add `default_agent` to the settings schema following the same pattern as `launcher.agents`. On boot, check `default_agent` — if set, skip store and launch directly; if empty, show the filtered picker.

Working directory: `/Users/cerratoa/dega/conductor-view`

## Files to touch

| File | Change |
|------|--------|
| `src/toad/settings_schema.py` | Add `default_agent` setting (string, empty default) |
| `src/toad/screens/store.py` | Filter `compose_agents()` to show only Claude/Gemini/Codex; fix grid nesting for consistent card alignment |
| `src/toad/cli.py` | Remove `--conductor` flag; read `default_agent` from settings to decide boot mode |
| `src/toad/app.py` | On mount, check `default_agent` setting — if set, skip store mode and launch agent directly |
| `src/toad/screens/main.py` | Add "Switch Agent" action accessible from settings/keybinding that clears `default_agent` and returns to store |

## Risks and open questions

- Grid nesting fix (heading inside/outside VerticalGroup) may affect other sections — test visually after change.

## Progress log

- [ ] Add `default_agent` setting to `settings_schema.py` following `launcher.agents` pattern
- [ ] Update `cli.py` — remove `--conductor` flag, use `default_agent` setting to determine boot mode (deps: 1)
- [ ] Update `app.py` — on mount, if `default_agent` is set, skip store and launch agent directly (deps: 2)
- [ ] Update `store.py` — filter `compose_agents()` to only show Claude, Gemini, Codex; fix grid heading nesting; save selection to `default_agent` setting (deps: 1)
- [ ] Update `main.py` — add "Switch Agent" option that clears `default_agent` and navigates back to store screen (deps: 3)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Reuse store screen, filter agents | New minimal screen | Preserves theming, install buttons, card style; less code to maintain |
| Filter agents in UI, keep TOML files | Delete unused TOML files | Preserves upstream rebase compatibility with batrachianai/toad |
| Remove `--conductor` flag | Keep as override | Redundant once `default_agent` is persistent; simpler CLI surface |
| `default_agent` in settings JSON | SQLite, env var, CLI config | Matches existing `launcher.agents` pattern in settings_schema.py |
| Switch agent via settings | Keybinding, CLI `--reset` flag | Settings is the established place for user preferences in Toad |

## Completion criteria

- [ ] First boot (no `default_agent` set) shows store screen with only Claude, Gemini, Codex cards
- [ ] Selecting an agent saves it to `default_agent` in settings and launches conversation
- [ ] Subsequent boots skip store screen and launch saved agent directly
- [ ] "Switch Agent" option exists and works — clears `default_agent`, returns to store
- [ ] `--conductor` flag is removed from CLI
- [ ] All 3 agent cards display correctly with consistent grid alignment, install buttons, and theme
- [ ] Other agent TOML files still exist but do not appear in the picker

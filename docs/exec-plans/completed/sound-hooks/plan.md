# Plan: Sound Hooks on Task Completion

**Status:** In progress
**Created:** 2026-03-02

## Requirements

- Copy 4 MP3 sound files from `~/Downloads/` into `sounds/` in this repo so they ship with the codebase
- Clean filenames: `unstoppable.mp3`, `super-mario-bros.mp3`, `yeahoo.mp3`, `warzone-level-up.mp3`
- Create a `hooks/play-sound.sh` script that plays the configured sound via `afplay` (macOS built-in)
- Default sound is `unstoppable` — configurable via `CLAUDE_SOUND` env var in `settings.json`
- Wire the hook into the Stop event in `settings.json` (alongside the existing `ralph-check.sh`)
- `/apply-core` installs sounds to `~/.claude/dega/sounds/` and the hook to `~/.claude/hooks/`
- Sound plays asynchronously (background `afplay`) so it never blocks Claude's stop sequence

## Approach

### Sound storage

Add `sounds/` directory at repo root with the 4 MP3 files. Rename `unstoppable_5.mp3` → `unstoppable.mp3` for clean naming. Total size is ~140KB — acceptable for a repo asset.

Global install path: `~/.claude/dega/sounds/`. The `dega/` namespace prevents collision with Claude Code internals or other tools that may use `~/.claude/`.

### Hook script (`hooks/play-sound.sh`)

Simple bash script:
1. Read `CLAUDE_SOUND` env var (default: `unstoppable`)
2. Resolve path: `~/.claude/dega/sounds/${CLAUDE_SOUND}.mp3`
3. If file exists, play with `afplay` in background (`&` with `disown`)
4. Exit 0 immediately — never block

### Configuration via env var

Add `"CLAUDE_SOUND": "unstoppable"` to the `env` section in `settings.json`. Users change the value to switch sounds. Available values: `unstoppable`, `super-mario-bros`, `yeahoo`, `warzone-level-up`. Set to empty string to disable.

### Stop hook wiring

Add a second Stop hook entry in `settings.json` that runs `bash ~/.claude/hooks/play-sound.sh`. This runs alongside (not replacing) the existing `ralph-check.sh` Stop hook.

### `/apply-core` update

Add a **Sounds** component to the install menu:
- Creates `~/.claude/dega/sounds/` directory
- Copies all 4 MP3 files
- Installs `hooks/play-sound.sh` to `~/.claude/hooks/`
- Adds `CLAUDE_SOUND` env var if not present in user's `settings.json`

## Files to touch

| File | Change |
|------|--------|
| `sounds/unstoppable.mp3` | New — copy from `~/Downloads/unstoppable_5.mp3` |
| `sounds/super-mario-bros.mp3` | New — copy from `~/Downloads/super-mario-bros.mp3` |
| `sounds/yeahoo.mp3` | New — copy from `~/Downloads/yeahoo.mp3` |
| `sounds/warzone-level-up.mp3` | New — copy from `~/Downloads/warzone-level-up.mp3` |
| `hooks/play-sound.sh` | New — sound player hook script |
| `settings.json` | Add `CLAUDE_SOUND` env var, add Stop hook entry for play-sound |
| `commands/apply-core.md` | Add Sounds component to source list, install steps, and post-install summary |
| `CLAUDE.md` | Add `sounds/` to repo map |

## Risks and open questions

- **P2**: `afplay` is macOS-only. Linux users would need `aplay` or `paplay`. Since the current user is on macOS, ship macOS-only for now and note the limitation in the script.
- **P2**: Git LFS for MP3s? At ~140KB total, not worth the complexity. Standard git is fine.

## Progress log

- [x] Copy 4 MP3 files to `sounds/` with clean names
- [x] Create `hooks/play-sound.sh`
- [x] Update `settings.json` — add `CLAUDE_SOUND` env var and Stop hook
- [x] Update `commands/apply-core.md` — add Sounds component
- [x] Update `CLAUDE.md` repo map — add `sounds/` entry
- [x] Test: verify `afplay` plays the default sound from `~/.claude/dega/sounds/`

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Env var `CLAUDE_SOUND` for config | Symlink `~/.claude/sounds/active`, separate config file | Env var is simplest — already a pattern in settings.json, no extra files |
| `~/.claude/dega/sounds/` for global path | `~/.claude/sounds/`, `~/.config/dega/sounds/` | Namespaced under `dega/` avoids collision with Claude Code internals while staying inside `~/.claude/` |
| Rename `unstoppable_5.mp3` → `unstoppable.mp3` | Keep original name | Clean names match the env var values without suffix noise |
| Background `afplay` with `disown` | Foreground play, `nohup` | `afplay &` + `disown` is lightest — exits instantly, sound keeps playing |
| macOS-only (`afplay`) | Cross-platform with `aplay`/`paplay` fallback | User is on macOS; Linux support can be added later if needed |

## Completion criteria

- [x] All requirements met
- [x] `hooks/play-sound.sh` runs without errors and plays configured sound
- [x] `settings.json` has `CLAUDE_SOUND` env var and Stop hook wired
- [x] `commands/apply-core.md` includes Sounds in install flow
- [x] `CLAUDE.md` repo map updated

## Follow-up (post-loop, human action)

- Commit and push branch for PR
- Test `/apply-core` end-to-end in a fresh environment

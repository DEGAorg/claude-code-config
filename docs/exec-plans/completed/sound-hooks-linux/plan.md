# Plan: Cross-Platform Sound Hooks (WSL2 + Linux)

**Status:** Pending
**Created:** 2026-03-02
**Predecessor:** `docs/exec-plans/completed/sound-hooks/plan.md` (macOS-only)

## Requirements

- Extend `hooks/play-sound.sh` to detect the platform and use the appropriate audio player
- Support three environments: macOS (`afplay`), pure Linux, and WSL2 (Windows)
- On Linux/WSL2, try players in priority order: `mpv`, `ffplay`, `paplay`, `aplay`
- If no player is found, skip silently — never block, never error
- Support `CLAUDE_SOUND=none` to explicitly disable sound (for users who need audio on but don't want task-completion noise)
- Support `CLAUDE_SOUND_VOLUME` env var (0–100, default 50) for per-playback volume control without touching system audio
- Convert MP3 sounds to OGG at install time so `paplay` works without extra dependencies
- Update `/apply-core` Sounds description to remove "macOS only" label
- Document required/recommended packages per platform

## Background

The macOS implementation uses `afplay`, which is built-in and handles MP3 natively.
Linux audio is fragmented:

| Player | Handles MP3 | Handles OGG | Typically installed | Notes |
|--------|-------------|-------------|---------------------|-------|
| `mpv` | yes | yes | no (but common) | Best option — lightweight, handles everything |
| `ffplay` | yes | yes | sometimes (ffmpeg) | Part of ffmpeg, often available |
| `paplay` | no | yes | yes (PulseAudio) | PulseAudio/PipeWire — ubiquitous on desktop Linux |
| `aplay` | no | PCM/WAV only | yes (ALSA) | Bare minimum, no compressed formats |

**WSL2 specifics:** WSL2 with WSLg (Windows 11 22H2+) runs a PulseAudio server
automatically, so `paplay` works if `pulseaudio-utils` is installed. Without WSLg,
there is no audio server — the script falls through to `powershell.exe` as a last
resort to play via Windows audio.

## Approach

### 1. Dual-format sounds: add OGG alongside MP3

Ship OGG versions of all 4 sounds in `sounds/`. OGG is natively supported by
`paplay` (PulseAudio/PipeWire), which is the most commonly pre-installed audio
tool on Linux desktops.

Convert during `/apply-core` install using `ffmpeg` if available, or ship
pre-converted OGG files in the repo. Pre-shipping is simpler and removes the
`ffmpeg` dependency at install time.

New files: `sounds/*.ogg` (4 files, ~100KB total estimated).

### 2. Rewrite `hooks/play-sound.sh` with platform detection

```
#!/bin/bash
set -euo pipefail

sound_name="${CLAUDE_SOUND:-unstoppable}"

# Empty string or "none" disables sound
[[ -z "$sound_name" || "$sound_name" == "none" ]] && exit 0

sounds_dir="$HOME/.claude/dega/sounds"

# Volume: 0-100 scale, default 50
vol="${CLAUDE_SOUND_VOLUME:-50}"

# Normalize volume to each player's native range
# afplay: 0.0-1.0 (float)   — vol/100
# mpv:    0-100 (int)        — passthrough
# ffplay: 0-100 (int)        — passthrough
# paplay: 0-65536 (int)      — vol*65536/100
# powershell: 0.0-1.0 (float) — vol/100
afplay_vol=$(awk "BEGIN {printf \"%.2f\", ${vol}/100}")
paplay_vol=$(( vol * 65536 / 100 ))
ps_vol="$afplay_vol"

# Detect platform
case "$(uname -s)" in
  Darwin)
    sound_file="${sounds_dir}/${sound_name}.mp3"
    [[ -f "$sound_file" ]] && { afplay -v "$afplay_vol" "$sound_file" & disown; }
    ;;
  Linux)
    # Try players in priority order
    # mpv and ffplay handle MP3 natively
    # paplay needs OGG format
    if command -v mpv &>/dev/null; then
      sound_file="${sounds_dir}/${sound_name}.mp3"
      [[ -f "$sound_file" ]] && { mpv --no-video --really-quiet --volume="$vol" "$sound_file" & disown; }
    elif command -v ffplay &>/dev/null; then
      sound_file="${sounds_dir}/${sound_name}.mp3"
      [[ -f "$sound_file" ]] && { ffplay -nodisp -autoexit -loglevel quiet -volume "$vol" "$sound_file" & disown; }
    elif command -v paplay &>/dev/null; then
      sound_file="${sounds_dir}/${sound_name}.ogg"
      [[ -f "$sound_file" ]] && { paplay --volume="$paplay_vol" "$sound_file" & disown; }
    elif grep -qi microsoft /proc/version 2>/dev/null; then
      # WSL2 without WSLg — use PowerShell as last resort
      sound_file="${sounds_dir}/${sound_name}.mp3"
      if [[ -f "$sound_file" ]]; then
        win_path=$(wslpath -w "$sound_file")
        powershell.exe -NoProfile -Command \
          "Add-Type -AssemblyName PresentationCore; \$p = New-Object System.Windows.Media.MediaPlayer; \$p.Open([Uri]'${win_path}'); \$p.Volume = ${ps_vol}; Start-Sleep -Milliseconds 100; \$p.Play(); Start-Sleep -Seconds 5" &
        disown
      fi
    fi
    # No player found — skip silently
    ;;
esac

exit 0
```

Key design decisions:
- **Priority order**: `mpv` > `ffplay` > `paplay` > WSL2 PowerShell fallback
- **OGG for paplay**: `paplay` can't decode MP3, so we try the `.ogg` version
- **WSL2 detection**: `grep microsoft /proc/version` — standard WSL2 fingerprint
- **WSL2 PowerShell fallback**: Uses WPF MediaPlayer which handles MP3. The `Start-Sleep` keeps the process alive long enough to play. Only reached if no Linux player is available and we're on WSL2.
- **Silent skip**: If nothing works, exit 0 — matches existing behavior
- **Volume normalization**: Single 0–100 scale (`CLAUDE_SOUND_VOLUME`) mapped to each player's native range. `awk` for float division (afplay/powershell), shell arithmetic for integer scaling (paplay). Default 50 — audible but not jarring.

### 3. Update `/apply-core` install flow

- Install both `.mp3` and `.ogg` files to `~/.claude/dega/sounds/`
- Remove "macOS only" from the Sounds component description
- Add platform note: "Works on macOS, Linux, and WSL2. Linux needs one of: mpv, ffplay, or paplay (PulseAudio)."
- Update available values to include `none`: `unstoppable`, `super-mario-bros`, `yeahoo`, `warzone-level-up`, `none`. Set to `none` to disable.
- Add `CLAUDE_SOUND_VOLUME` env var (default `50`) to `settings.json`

### 4. Create `skills/sound-notifications.md` — global skill

This skill gets installed to `~/.claude/skills/sound-notifications.md` via
`/apply-core`, so Claude in **any project** knows how to help users configure sounds.

Contents:

- What the feature does (Stop hook plays a sound when Claude finishes a task)
- Env vars: `CLAUDE_SOUND` (sound name or `none`), `CLAUDE_SOUND_VOLUME` (0–100, default 50)
- Available sounds: `unstoppable` (default), `super-mario-bros`, `yeahoo`, `warzone-level-up`
- Where sounds live: `~/.claude/dega/sounds/` (MP3 + OGG)
- Platform support: macOS (afplay), Linux (mpv/ffplay/paplay), WSL2
- How to add custom sounds: drop `.mp3` + `.ogg` in `~/.claude/dega/sounds/`, set `CLAUDE_SOUND` to the filename without extension
- OGG requirement: new sounds need both `.mp3` (macOS/mpv/ffplay) and `.ogg` (paplay on Linux). Convert with `ffmpeg -i sound.mp3 sound.ogg`
- Troubleshooting: no sound on Linux → install `mpv` or `ffmpeg`

This is knowledge, not a procedure — it shapes how Claude answers "how do I change
my notification sound?" or "how do I turn off sounds?" from any project.

### 5. Wire skill into `/apply-core`

Add `skills/sound-notifications.md` to the apply-core source list and the Skills
install section. The skill installs alongside `custom-linter-authoring.md` and
`app-legibility.md` — same pattern, no special handling.

## Files to touch

| File | Change |
|------|--------|
| `sounds/unstoppable.ogg` | New — OGG version of the MP3 |
| `sounds/super-mario-bros.ogg` | New — OGG version of the MP3 |
| `sounds/yeahoo.ogg` | New — OGG version of the MP3 |
| `sounds/warzone-level-up.ogg` | New — OGG version of the MP3 |
| `hooks/play-sound.sh` | Rewrite — add platform detection, Linux/WSL2 player chain, volume control |
| `skills/sound-notifications.md` | New — global skill so Claude knows sound config in any project |
| `settings.json` | Add `CLAUDE_SOUND_VOLUME` env var (default `50`) |
| `commands/apply-core.md` | Update — install OGG files, add skill, remove macOS-only label, add platform + volume notes |

## Risks and open questions

- **P1**: OGG conversion — need `ffmpeg` to create the OGG files. This is a one-time build step, not a runtime dependency. If `ffmpeg` is not available on the current machine, we can convert elsewhere or find pre-existing OGG versions.
- **P2**: WSL2 PowerShell fallback is untested — the WPF `MediaPlayer` approach works in theory but needs validation on a real WSL2 instance. Acceptable risk since it's the last-resort path.
- **P2**: `paplay` on PipeWire — modern distros (Fedora 34+, Ubuntu 22.10+) use PipeWire with PulseAudio compatibility. `paplay` should work via `pipewire-pulse` but needs validation.
- **P3**: Sound playback on headless Linux servers — no audio device, all players will fail silently. This is fine — sound hooks are for interactive use.

## Progress log

- [x] Convert 4 MP3 sounds to OGG using ffmpeg
- [x] Rewrite `hooks/play-sound.sh` with platform detection, `none` disable, and volume control
- [x] Shellcheck and shfmt the new script
- [x] Add `CLAUDE_SOUND_VOLUME=50` to `settings.json` env block
- [x] Create `skills/sound-notifications.md` global skill
- [x] Update `commands/apply-core.md` — add OGG files to source list, add skill, update Sounds description
- [x] Test on macOS — verify `afplay` path still works
- [x] Test on Linux or WSL2 if available — verify at least one player path works

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Ship pre-converted OGG files in repo | Convert at install time with ffmpeg | Removes ffmpeg as install-time dependency; OGG files are small (~100KB total) |
| Player priority: mpv > ffplay > paplay > powershell | paplay first since it's most common | mpv/ffplay handle MP3 natively (no format conversion needed); paplay needs OGG. Prefer the path that uses the original MP3 |
| WSL2 detection via `/proc/version` | Check for `WSL_DISTRO_NAME` env var | `/proc/version` is the canonical method; env var may not be set in all contexts |
| WPF MediaPlayer for WSL2 fallback | `SoundPlayer` (.NET), `cmd.exe /c start wmplayer` | SoundPlayer only handles WAV; wmplayer opens a visible window. WPF MediaPlayer handles MP3 headlessly |
| Silent skip when no player found | Print warning to stderr | Matches existing macOS behavior (silent skip when file missing). Warnings in Stop hook could confuse users |
| `none` as explicit disable value | Only support empty string | `none` is discoverable and intentional — users can see it in the values list. Empty string still works but is less obvious when reading config |
| 0–100 volume scale, default 50 | 0.0–1.0 float scale; per-player native units | 0–100 is intuitive (percentages). Single env var, normalized per-player in the script. Default 50 — audible notification without being startling |
| `awk` for float conversion | `bc`, bash arithmetic | `awk` is POSIX, universally available. `bc` may not be installed. Bash can't do float math natively |

## Completion criteria

- [x] `hooks/play-sound.sh` handles macOS, pure Linux, and WSL2
- [x] `CLAUDE_SOUND=none` exits immediately without playing
- [x] OGG versions of all 4 sounds exist in `sounds/`
- [x] `commands/apply-core.md` installs OGG files and describes cross-platform support
- [x] `CLAUDE_SOUND_VOLUME` controls playback volume across all players
- [x] `settings.json` has `CLAUDE_SOUND_VOLUME` env var defaulting to `50`
- [x] `skills/sound-notifications.md` installed globally via `/apply-core`
- [x] Script passes shellcheck and shfmt
- [x] macOS playback still works (regression check)

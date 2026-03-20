#!/bin/bash
set -euo pipefail
# Stop hook — plays a sound when Claude finishes a response.
# Cross-platform: macOS (afplay), Linux (mpv/ffplay/paplay), WSL2 (PowerShell).
# Runs asynchronously so it never blocks.
#
# Environment variables:
#   CLAUDE_SOUND         Sound name (default: super-mario-bros). Set to "none" to disable.
#   CLAUDE_SOUND_VOLUME  Playback volume 0–100 (default: 50).
#   RALPH_LOOP           Set to "1" by ralph-loop.sh — plays tick at 15% volume.

sound_name="${CLAUDE_SOUND:-super-mario-bros}"

# Empty string or "none" disables sound
[[ -z "$sound_name" || "$sound_name" == "none" ]] && exit 0

sounds_dir="$HOME/.claude/dega/sounds"

# Volume: 0-100 scale, default 50
vol="${CLAUDE_SOUND_VOLUME:-50}"

# Ralph loop mode: play tick at low volume instead of configured sound
if [[ "${RALPH_LOOP:-}" == "1" ]]; then
	sound_name="tick"
	vol=15
fi

# Normalize volume to each player's native range
# afplay:      0.0–1.0 (float)  — vol/100
# mpv:         0–100 (int)      — passthrough
# ffplay:      0–100 (int)      — passthrough
# paplay:      0–65536 (int)    — vol*65536/100
# powershell:  0.0–1.0 (float)  — vol/100
afplay_vol=$(awk "BEGIN {printf \"%.2f\", ${vol}/100}")
paplay_vol=$((vol * 65536 / 100))
ps_vol="$afplay_vol"

# Detect platform
case "$(uname -s)" in
Darwin)
	sound_file="${sounds_dir}/${sound_name}.mp3"
	[[ -f "$sound_file" ]] && {
		afplay -v "$afplay_vol" "$sound_file" &
		disown
	}
	;;
Linux)
	# Try players in priority order
	# mpv and ffplay handle MP3 natively
	# paplay needs OGG format (Vorbis or Opus)
	if command -v mpv &>/dev/null; then
		sound_file="${sounds_dir}/${sound_name}.mp3"
		[[ -f "$sound_file" ]] && {
			mpv --no-video --really-quiet --volume="$vol" "$sound_file" &
			disown
		}
	elif command -v ffplay &>/dev/null; then
		sound_file="${sounds_dir}/${sound_name}.mp3"
		[[ -f "$sound_file" ]] && {
			ffplay -nodisp -autoexit -loglevel quiet -volume "$vol" "$sound_file" &
			disown
		}
	elif command -v paplay &>/dev/null; then
		sound_file="${sounds_dir}/${sound_name}.ogg"
		[[ -f "$sound_file" ]] && {
			paplay --volume="$paplay_vol" "$sound_file" &
			disown
		}
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

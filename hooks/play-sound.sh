#!/bin/bash
set -euo pipefail
# Stop hook — plays a sound when Claude finishes a response.
# macOS only (afplay). Runs asynchronously so it never blocks.

sound_name="${CLAUDE_SOUND:-unstoppable}"

# Empty string disables sound
[[ -z "$sound_name" ]] && exit 0

sound_file="$HOME/.claude/dega/sounds/${sound_name}.mp3"

if [[ -f "$sound_file" ]]; then
	afplay "$sound_file" &
	disown
fi

exit 0

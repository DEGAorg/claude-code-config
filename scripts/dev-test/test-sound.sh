#!/bin/bash
set -euo pipefail
# Quick test: play the configured sound at a given volume.
# Usage: bash scripts/test-sound.sh [volume 0-100] [sound-name]

vol="${1:-50}"
sound="${2:-unstoppable}"

CLAUDE_SOUND="$sound" CLAUDE_SOUND_VOLUME="$vol" \
  bash ~/.claude/hooks/play-sound.sh

echo "Played '${sound}' at ${vol}%"

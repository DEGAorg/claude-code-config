---
name: transcribe-yt
description: Transcribe a YouTube video to text. Use when the user asks to transcribe, get captions, or extract text from a YouTube video.
argument-hint: <youtube-url-or-video-id> [output-file] [--format text|json|srt] [--languages en es ...]
allowed-tools: Bash Read Write
user-invocable: true
---

# YouTube Video Transcription

Transcribe a YouTube video using the `youtube-transcript-api` Python library.

## Setup

The script requires `youtube-transcript-api` in a Python environment. Prefer a
project-local `.venv` when available; otherwise use any Python that can import
the package.

## Usage

Run the transcription script:

```bash
# Find a working Python environment with youtube-transcript-api.
PYTHON_BIN=""
for candidate in .venv/bin/python3 python3; do
  if command -v "$candidate" >/dev/null 2>&1 || [ -x "$candidate" ]; then
    if "$candidate" -c "import youtube_transcript_api" 2>/dev/null; then
      PYTHON_BIN="$candidate"
      break
    fi
  fi
done

if [ -z "$PYTHON_BIN" ]; then
  python3 -m pip install youtube-transcript-api
  PYTHON_BIN=python3
fi

SKILL_DIR="${CLAUDE_HOME:-$HOME/.claude}/skills/transcribe-yt"
"$PYTHON_BIN" "$SKILL_DIR/scripts/transcribe.py" <URL_OR_ID> [OPTIONS]
```

## Arguments from user

Parse `$ARGUMENTS` as: `<youtube-url-or-id> [output-file] [--format text|json|srt] [--languages ...]`

- If the user provides an output file path, use `-o <path>`
- If no output file is specified, save to the current directory as `<video_id>_transcript.txt`
- Default format is `text`. Use `--format json` for timestamped data, `--format srt` for subtitle format

## Steps

1. Extract the YouTube URL or video ID from `$ARGUMENTS`
2. Determine the output file path (from args or default to `<video_id>_transcript.txt` in the current directory)
3. Run the transcription script with the appropriate arguments
4. Report the result to the user (file path, snippet count, character count)

## Error handling

- If `youtube-transcript-api` is not installed, install it in a virtual environment when possible.
- If the video has no captions available, inform the user and suggest alternatives (e.g., downloading audio + Whisper)
- If a specific language is not available, try without language filter to get whatever is available

## Task

$ARGUMENTS

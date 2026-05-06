---
name: transcribe-yt
description: Transcribe a YouTube video to text. Use when the user asks to transcribe, get captions, or extract text from a YouTube video.
---

# YouTube Video Transcription

Transcribe a YouTube video with `youtube-transcript-api`.

## Helper script

```bash
SKILL_DIR="${CODEX_HOME:-$HOME/.codex}/skills/transcribe-yt"
PYTHON_BIN=""
for p in .venv/bin/python3 python3; do
  if command -v "$p" >/dev/null 2>&1 || [ -x "$p" ]; then
    if "$p" -c "import youtube_transcript_api" 2>/dev/null; then
      PYTHON_BIN="$p"
      break
    fi
  fi
done

if [ -z "$PYTHON_BIN" ]; then
  python3 -m pip install youtube-transcript-api
  PYTHON_BIN=python3
fi

"$PYTHON_BIN" "$SKILL_DIR/scripts/transcribe.py" <URL_OR_ID> [OPTIONS]
```

## Arguments

Parse the request as:

```text
<youtube-url-or-id> [output-file] [--format text|json|srt] [--languages en es ...]
```

- If the user provides an output path, pass `-o <path>`.
- Otherwise save to `<video_id>_transcript.txt` in the current directory.
- Default format is `text`.

## Steps

1. Extract the YouTube URL or video ID.
2. Determine the output path.
3. Run the script.
4. Report the saved file path, snippet count, and character count.

## Error Handling

- If `youtube-transcript-api` is missing, install it in a usable Python environment.
- If the video has no captions, say so and suggest audio-plus-Whisper as a fallback.
- If a requested language is unavailable, retry without the language filter.

---
name: transcribe-ig
description: Transcribe an Instagram video such as a Reel, post, or story to text. Use when the user asks to transcribe, get captions, or extract text from an Instagram video.
---

# Instagram Video Transcription

Transcribe an Instagram video using `yt-dlp`, `ffmpeg`, and `openai-whisper`.

## Setup

Use a dedicated venv inside the Codex skill directory:

```bash
SKILL_DIR="${CODEX_HOME:-$HOME/.codex}/skills/transcribe-ig"
if [ ! -d "$SKILL_DIR/.venv" ]; then
  python3 -m venv "$SKILL_DIR/.venv"
  "$SKILL_DIR/.venv/bin/pip" install --upgrade pip
  "$SKILL_DIR/.venv/bin/pip" install openai-whisper
fi
```

Required system tools:
- `yt-dlp`
- `ffmpeg`

Supported wherever `yt-dlp` can read Chrome cookies: macOS, Linux, and Windows.

Instagram auth:
- `yt-dlp` uses Chrome cookies
- the user must be logged into Instagram in Chrome
- macOS may prompt for Keychain access on first run

## Usage

```bash
SKILL_DIR="${CODEX_HOME:-$HOME/.codex}/skills/transcribe-ig"
"$SKILL_DIR/.venv/bin/python3" "$SKILL_DIR/scripts/transcribe.py" <URL> [OPTIONS]
```

## Arguments

Parse the request as:

```text
<instagram-url> [output-file] [--format text|json|srt] [--model tiny|base|small|medium|large] [--language en]
```

- If the user provides an output path, pass `-o <path>`.
- Otherwise save to `ig_transcript.txt` in the current directory.
- Default format is `text`.
- Default model is `base`.

## Steps

1. Ensure the venv and `openai-whisper` are available.
2. Extract the Instagram URL.
3. Determine the output path.
4. Run the script.
5. Report the output path, segment count, character count, and detected language.

## Error Handling

- If the venv or package is missing, create it and install `openai-whisper`.
- If `yt-dlp` says login is required, remind the user to log into Instagram in Chrome.
- If `yt-dlp` fails for other reasons, suggest updating it with `yt-dlp -U`.
- If Whisper is too slow, suggest using `tiny` or `base`.

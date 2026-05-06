---
name: transcribe-ig
description: Transcribe an Instagram video (Reel, post, story) to text. Use when the user asks to transcribe, get captions, or extract text from an Instagram video.
argument-hint: <instagram-url> [output-file] [--format text|json|srt] [--model tiny|base|small|medium|large] [--language en]
allowed-tools: Bash Read Write
user-invocable: true
---

# Instagram Video Transcription

Transcribe an Instagram video using only trusted, audited tools: yt-dlp (download), ffmpeg (audio extraction), and openai-whisper (transcription). No third-party Instagram scrapers.

## Setup

The script requires `openai-whisper` installed in a Python environment. Use a
dedicated virtual environment inside the installed skill directory.

### First-time setup (run once if venv doesn't exist):

```bash
SKILL_DIR="${CLAUDE_HOME:-$HOME/.claude}/skills/transcribe-ig"
if [ ! -d "$SKILL_DIR/.venv" ]; then
  python3 -m venv "$SKILL_DIR/.venv"
  "$SKILL_DIR/.venv/bin/pip" install --upgrade pip
  "$SKILL_DIR/.venv/bin/pip" install openai-whisper
fi
```

### Required system tools (must already be installed):
- `yt-dlp`
- `ffmpeg`

Supported wherever `yt-dlp` can read Chrome cookies: macOS, Linux, and Windows.

### Instagram authentication:
- yt-dlp uses `--cookies-from-browser chrome` to read Instagram session cookies from Chrome
- The user must be logged into Instagram in Chrome
- Cookie extraction depends on browser and OS support in `yt-dlp`
- On first run, macOS may prompt for Keychain access

## Usage

```bash
SKILL_DIR="${CLAUDE_HOME:-$HOME/.claude}/skills/transcribe-ig"
"$SKILL_DIR/.venv/bin/python3" "$SKILL_DIR/scripts/transcribe.py" <URL> [OPTIONS]
```

## Arguments from user

Parse `$ARGUMENTS` as: `<instagram-url> [output-file] [--format text|json|srt] [--model tiny|base|small|medium|large] [--language <code>]`

- If the user provides an output file path, use `-o <path>`
- If no output file is specified, save to the current directory as `ig_transcript.txt`
- Default format is `text`. Use `--format json` for timestamped segments, `--format srt` for subtitles
- Default model is `base`. For better accuracy use `small` or `medium` (slower but more accurate)
- Use `--language` to force a language (e.g., `en`, `es`). If omitted, Whisper auto-detects

## Steps

1. Check if the venv exists; if not, create it and install `openai-whisper`
2. Extract the Instagram URL from `$ARGUMENTS`
3. Determine the output file path (from args or default to `ig_transcript.txt`)
4. Run the transcription script with the appropriate arguments
5. Report the result to the user (file path, segment count, character count, detected language)

## Error handling

- If the venv or `openai-whisper` is missing, run the setup commands above
- If yt-dlp fails with "login required", remind the user to log into Instagram in Chrome
- If yt-dlp fails with other errors, suggest updating yt-dlp: `yt-dlp -U`
- If Whisper is slow, suggest using a smaller model (`tiny` or `base`)

## Task

$ARGUMENTS

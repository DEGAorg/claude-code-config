#!/usr/bin/env python3
"""Transcribe an Instagram video using yt-dlp + ffmpeg + whisper.

Uses only trusted, widely-audited tools:
- yt-dlp: downloads video with Chrome cookies for IG auth
- ffmpeg: extracts audio
- whisper: transcribes audio to text
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile


def _export_ig_cookies(cookie_file: str) -> None:
    """Export only .instagram.com cookies from Chrome to a Netscape cookie file."""
    # yt-dlp's own cookie decryption handles the encryption, so we use yt-dlp
    # to dump cookies then filter. This avoids reimplementing Chrome's keychain decryption.
    dump_cmd = [
        "yt-dlp",
        "--cookies-from-browser", "chrome",
        "--cookies", cookie_file,
        "--skip-download",
        "https://www.instagram.com",
    ]
    result = subprocess.run(dump_cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Cookie export warning: {result.stderr}", file=sys.stderr)
        return

    # Now filter the cookie file to only .instagram.com domains
    if os.path.exists(cookie_file):
        with open(cookie_file, "r") as f:
            lines = f.readlines()

        with open(cookie_file, "w") as f:
            for line in lines:
                if line.startswith("#") or line.strip() == "":
                    f.write(line)
                    continue
                if "\t" not in line:
                    continue
                domain = line.split("\t", 1)[0]
                if domain == ".instagram.com" or domain.endswith(".instagram.com"):
                    f.write(line)


def download_video(url: str, output_path: str) -> str:
    """Download Instagram video using yt-dlp with filtered IG-only cookies."""
    # Create a filtered cookie file containing only .instagram.com cookies
    cookie_file = os.path.join(os.path.dirname(output_path), "ig_cookies.txt")
    _export_ig_cookies(cookie_file)

    if os.path.exists(cookie_file) and os.path.getsize(cookie_file) > 0:
        cmd = [
            "yt-dlp",
            "--cookies", cookie_file,
            "--no-playlist",
            "--merge-output-format", "mp4",
            "-o", output_path,
            url,
        ]
    else:
        # Fallback if cookie export failed
        print("Warning: filtered cookie export failed, falling back to --cookies-from-browser", file=sys.stderr)
        cmd = [
            "yt-dlp",
            "--cookies-from-browser", "chrome",
            "--no-playlist",
            "--merge-output-format", "mp4",
            "-o", output_path,
            url,
        ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"yt-dlp error:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)

    # Clean up cookie file immediately after use
    if os.path.exists(cookie_file):
        os.remove(cookie_file)

    return output_path


def extract_audio(video_path: str, audio_path: str) -> str:
    """Extract audio from video using ffmpeg."""
    cmd = [
        "ffmpeg", "-y",
        "-i", video_path,
        "-vn",
        "-acodec", "pcm_s16le",
        "-ar", "16000",
        "-ac", "1",
        audio_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"ffmpeg error:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    return audio_path


def transcribe_audio(audio_path: str, model_name: str = "base", language: str | None = None) -> dict:
    """Transcribe audio using openai-whisper."""
    import whisper

    model = whisper.load_model(model_name)
    options = {}
    if language:
        options["language"] = language

    result = model.transcribe(audio_path, **options)

    segments = []
    for seg in result.get("segments", []):
        segments.append({
            "text": seg["text"].strip(),
            "start": seg["start"],
            "end": seg["end"],
        })

    full_text = " ".join(s["text"] for s in segments)

    return {
        "text": full_text,
        "segment_count": len(segments),
        "char_count": len(full_text),
        "language": result.get("language", "unknown"),
        "segments": segments,
    }


def main():
    parser = argparse.ArgumentParser(description="Transcribe an Instagram video")
    parser.add_argument("url", help="Instagram URL (reel, post, story)")
    parser.add_argument("-o", "--output", help="Output file path (default: stdout)")
    parser.add_argument("-f", "--format", choices=["text", "json", "srt"], default="text",
                        help="Output format (default: text)")
    parser.add_argument("-m", "--model", default="base",
                        choices=["tiny", "base", "small", "medium", "large"],
                        help="Whisper model size (default: base)")
    parser.add_argument("-l", "--language", default=None,
                        help="Language code (e.g., en, es)")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as tmpdir:
        video_path = os.path.join(tmpdir, "video.mp4")
        audio_path = os.path.join(tmpdir, "audio.wav")

        print("Downloading Instagram video...", file=sys.stderr)
        download_video(args.url, video_path)

        print("Extracting audio...", file=sys.stderr)
        extract_audio(video_path, audio_path)

        print(f"Transcribing with Whisper ({args.model} model)...", file=sys.stderr)
        result = transcribe_audio(audio_path, model_name=args.model, language=args.language)

    print(f"Detected language: {result['language']}", file=sys.stderr)

    if args.format == "json":
        output = json.dumps(result, indent=2, ensure_ascii=False)
    elif args.format == "srt":
        lines = []
        for i, s in enumerate(result["segments"], 1):
            def fmt(t):
                h = int(t // 3600)
                m = int((t % 3600) // 60)
                sec = int(t % 60)
                ms = int((t % 1) * 1000)
                return f"{h:02d}:{m:02d}:{sec:02d},{ms:03d}"
            lines.append(f"{i}")
            lines.append(f"{fmt(s['start'])} --> {fmt(s['end'])}")
            lines.append(s["text"])
            lines.append("")
        output = "\n".join(lines)
    else:
        output = result["text"]

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(output)
        print(f"Saved {result['segment_count']} segments ({result['char_count']} chars) to {args.output}",
              file=sys.stderr)
    else:
        print(output)


if __name__ == "__main__":
    main()

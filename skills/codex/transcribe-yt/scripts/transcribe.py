#!/usr/bin/env python3
"""Transcribe a YouTube video using youtube-transcript-api."""

import argparse
import json
import re
import sys


def extract_video_id(url_or_id: str) -> str:
    """Extract video ID from a YouTube URL or return as-is if already an ID."""
    patterns = [
        r'(?:youtu\.be/|youtube\.com/watch\?v=|youtube\.com/embed/|youtube\.com/v/)([a-zA-Z0-9_-]{11})',
        r'^([a-zA-Z0-9_-]{11})$',
    ]
    for pattern in patterns:
        match = re.search(pattern, url_or_id)
        if match:
            return match.group(1)
    return url_or_id


def transcribe(video_id: str, languages: list[str] | None = None) -> dict:
    """Fetch transcript and return structured data."""
    from youtube_transcript_api import YouTubeTranscriptApi

    api = YouTubeTranscriptApi()
    kwargs = {}
    if languages:
        kwargs["languages"] = languages

    transcript = api.fetch(video_id, **kwargs)

    snippets = []
    for entry in transcript.snippets:
        snippets.append({
            'text': entry.text,
            'start': entry.start,
            'duration': entry.duration,
        })

    full_text = '\n'.join(s['text'] for s in snippets)

    return {
        'video_id': video_id,
        'snippet_count': len(snippets),
        'char_count': len(full_text),
        'text': full_text,
        'snippets': snippets,
    }


def main():
    parser = argparse.ArgumentParser(description='Transcribe a YouTube video')
    parser.add_argument('url', help='YouTube URL or video ID')
    parser.add_argument('-o', '--output', help='Output file path (default: stdout)')
    parser.add_argument('-f', '--format', choices=['text', 'json', 'srt'], default='text',
                        help='Output format (default: text)')
    parser.add_argument('-l', '--languages', nargs='+', default=None,
                        help='Preferred languages (e.g., en es)')
    args = parser.parse_args()

    video_id = extract_video_id(args.url)
    result = transcribe(video_id, args.languages)

    if args.format == 'json':
        output = json.dumps(result, indent=2, ensure_ascii=False)
    elif args.format == 'srt':
        lines = []
        for i, s in enumerate(result['snippets'], 1):
            start = s['start']
            end = start + s['duration']
            def fmt(t):
                h = int(t // 3600)
                m = int((t % 3600) // 60)
                sec = int(t % 60)
                ms = int((t % 1) * 1000)
                return f'{h:02d}:{m:02d}:{sec:02d},{ms:03d}'
            lines.append(f'{i}')
            lines.append(f'{fmt(start)} --> {fmt(end)}')
            lines.append(s['text'])
            lines.append('')
        output = '\n'.join(lines)
    else:
        output = result['text']

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(output)
        print(f"Saved {result['snippet_count']} snippets ({result['char_count']} chars) to {args.output}",
              file=sys.stderr)
    else:
        print(output)


if __name__ == '__main__':
    main()

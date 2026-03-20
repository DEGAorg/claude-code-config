# Sound Notifications

How Claude Code plays audio cues when a task completes. Use this skill when
a user asks about notification sounds, wants to change or disable them, add
custom sounds, or troubleshoot missing audio.

The Stop hook (`~/.claude/hooks/play-sound.sh`) plays a short sound after
every Claude response. Playback is backgrounded and never blocks.

---

## Configuration

Two environment variables control sound behavior. Both are set in
`settings.json` under the `env` block.

| Variable | Values | Default |
|----------|--------|---------|
| `CLAUDE_SOUND` | Sound name, or `none` to disable | `super-mario-bros` |
| `CLAUDE_SOUND_VOLUME` | `0`–`100` (percentage) | `50` |

Setting `CLAUDE_SOUND` to `none` or an empty string disables playback
entirely — the hook exits immediately without launching a player.

### Available sounds

| Name | Description |
|------|-------------|
| `unstoppable` | Default — short motivational clip |
| `super-mario-bros` | Classic game sound |
| `yeahoo` | Short celebration |
| `warzone-level-up` | Level-up chime |
| `tick` | 100ms 880Hz sine tone — used automatically during orchestrator runs |

Sound files live in `~/.claude/dega/sounds/` in both MP3 and OGG formats.

---

## Platform support

| Platform | Player | Format | Notes |
|----------|--------|--------|-------|
| macOS | `afplay` (built-in) | MP3 | No extra install needed |
| Linux | `mpv` | MP3 | Best option — lightweight, handles everything |
| Linux | `ffplay` | MP3 | Part of ffmpeg, often already installed |
| Linux | `paplay` | OGG (Opus) | PulseAudio/PipeWire — pre-installed on most desktops |
| WSL2 | PowerShell `MediaPlayer` | MP3 | Last resort when no Linux player is available |

On Linux, the script tries players in priority order: `mpv` > `ffplay` >
`paplay` > WSL2 PowerShell. The first available player is used. If none is
found, playback is silently skipped.

---

## Orchestrator behavior

When running inside the orchestrator (`scripts/orch-engine.sh`), sound
behavior changes automatically — no user configuration needed.

| Event | Sound | Volume | Mechanism |
|-------|-------|--------|-----------|
| Per-item completion (worker/reviewer) | `tick` | 15% | `RALPH_LOOP=1` env var |
| Plan SHIP (all items pass review) | User's configured sound | User's configured volume | `orch-engine.sh` calls `play-sound.sh` directly |

**How it works:** `orch-engine.sh` exports `RALPH_LOOP=1` when spawning
worker and reviewer agents. The Stop hook's `play-sound.sh` detects this
variable and overrides the sound to `tick` at 15% volume. Since
`RALPH_LOOP` is not in `settings.json`, it survives the env clobber that
`claude -p` applies from settings. On SHIP, the engine reads the user's
`CLAUDE_SOUND` and `CLAUDE_SOUND_VOLUME` from `settings.json` and calls
`play-sound.sh` without `RALPH_LOOP`, so the full configured sound plays
once.

Setting `CLAUDE_SOUND=none` disables all sounds, including ticks during
orchestrator runs. The `none` check runs before the `RALPH_LOOP` check.

---

## Adding custom sounds

1. Place both `.mp3` and `.ogg` versions in `~/.claude/dega/sounds/`:

   ```bash
   cp my-sound.mp3 ~/.claude/dega/sounds/
   ffmpeg -i my-sound.mp3 -c:a libopus -b:a 64k ~/.claude/dega/sounds/my-sound.ogg
   ```

2. Set `CLAUDE_SOUND` to the filename without extension:

   ```jsonc
   // settings.json
   "env": {
     "CLAUDE_SOUND": "my-sound"
   }
   ```

Both formats are required: MP3 for macOS/mpv/ffplay, OGG for paplay on Linux.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| No sound on Linux | No supported player installed | Install `mpv` (`sudo apt install mpv`) or `ffmpeg` (`sudo apt install ffmpeg`) |
| No sound on WSL2 | No Linux player and WSLg not active | Install `pulseaudio-utils` (`sudo apt install pulseaudio-utils`) for paplay via WSLg |
| Sound too loud/quiet | Volume default is 50% | Set `CLAUDE_SOUND_VOLUME` to desired 0–100 value |
| Sound plays but want silence | Sound is enabled | Set `CLAUDE_SOUND` to `none` |
| Custom sound doesn't play | Missing OGG version | Convert with `ffmpeg -i sound.mp3 -c:a libopus -b:a 64k sound.ogg` |
| paplay fails with format error | MP3 file used instead of OGG | Ensure `.ogg` file exists — paplay cannot decode MP3 |

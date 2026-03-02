# Plan: Ralph Loop Sound Behavior

**Status:** In progress
**Created:** 2026-03-02
**Predecessor:** `docs/exec-plans/active/sound-hooks-linux/` (cross-platform, skill, volume — all done, move to completed)

## Requirements

- During ralph loop: play a short, quiet "tick" sound per item instead of the full completion sound
- On ralph loop SHIP: play the user's configured completion sound once at configured volume
- Keep the existing Stop hook unchanged for interactive sessions
- Add a `tick` sound (short synthetic tone) shipped in `sounds/` as MP3 + OGG
- Update `skills/sound-notifications.md` to document ralph loop sound behavior
- Document OGG conversion requirement for any new sound added in the future

## Background

The Stop hook fires every time a `claude -p` invocation ends. In a ralph loop,
that's once per item (worker) plus once per reviewer per iteration. A 3-iteration
loop with 4 items each = (4 + 1) x 3 = **15 sounds**. That's obnoxious for AFK runs.

The fix: differentiate interactive sessions from ralph loop runs. Interactive
sessions keep the current behavior. Ralph loop items get a subtle tick. Loop
completion (SHIP) gets the full sound once.

### Env var passthrough problem

`ralph-loop.sh` spawns `claude -p` which loads `settings.json` env vars. Any
`CLAUDE_SOUND` override in the parent env gets clobbered by settings.json.
Solution: use `RALPH_LOOP=1` — an env var NOT in settings.json — so it survives
the spawn. `play-sound.sh` checks for it and switches to tick mode.

## Approach

### 1. Generate `tick` sound

Use ffmpeg's tone generator to create a 100ms 880Hz (A5) sine wave with fade-out.
No external audio sourcing needed.

```bash
ffmpeg -f lavfi -i "sine=frequency=880:duration=0.1" \
  -af "afade=t=out:st=0.05:d=0.05" sounds/tick.mp3
ffmpeg -f lavfi -i "sine=frequency=880:duration=0.1" \
  -af "afade=t=out:st=0.05:d=0.05" -c:a libopus -b:a 64k sounds/tick.ogg
```

Ships in repo as `sounds/tick.mp3` + `sounds/tick.ogg`. Tiny files (~5KB each).

### 2. Update `hooks/play-sound.sh` — ralph loop detection

Add a check near the top, after the `none` check:

```bash
# Ralph loop mode: play tick at low volume instead of configured sound
if [[ "${RALPH_LOOP:-}" == "1" ]]; then
  sound_name="tick"
  vol=15
fi
```

This overrides both the sound and volume when `RALPH_LOOP=1` is in the env.
The rest of the script (platform detection, player chain) works unchanged.

### 3. Update `scripts/ralph-loop.sh` — suppress per-item, play on SHIP

**Per-item suppression:** Export `RALPH_LOOP=1` before spawning worker and
reviewer agents. Since `RALPH_LOOP` is not in settings.json, it passes through
to the claude process and its hooks without being overridden.

Change line 175 (worker):
```bash
env -u CLAUDECODE RALPH_LOOP=1 claude -p --dangerously-skip-permissions "${WORKER_CONTEXT}"
```

Change line 204 (reviewer):
```bash
env -u CLAUDECODE RALPH_LOOP=1 claude -p --dangerously-skip-permissions "${REVIEWER_CONTEXT}"
```

**Completion sound:** After SHIP + health check + commit (around line 244),
read the user's configured sound from settings.json and call play-sound.sh
directly:

```bash
# Play completion sound — read config from settings.json since ralph-loop.sh
# runs outside Claude Code and doesn't have settings.json env vars
_settings="${HOME}/.claude/settings.json"
if [[ -f "$_settings" ]]; then
  CLAUDE_SOUND=$(jq -r '.env.CLAUDE_SOUND // "unstoppable"' "$_settings")
  CLAUDE_SOUND_VOLUME=$(jq -r '.env.CLAUDE_SOUND_VOLUME // "50"' "$_settings")
  export CLAUDE_SOUND CLAUDE_SOUND_VOLUME
fi
bash "${HOME}/.claude/hooks/play-sound.sh"
```

Note: `RALPH_LOOP` is NOT exported here, so play-sound.sh uses the full
configured sound, not the tick.

### 4. Update `skills/sound-notifications.md`

Add a "Ralph Loop behavior" section documenting:
- Per-item: automatic tick at 15% volume (no user config needed)
- SHIP: full configured sound plays once
- Mechanism: `RALPH_LOOP=1` env var detected by play-sound.sh
- User can still set `CLAUDE_SOUND=none` to disable all sounds including ticks

### 5. Update `commands/apply-core.md`

Add `sounds/tick.mp3` and `sounds/tick.ogg` to the source list and install
section.

### 6. Move predecessor plan to completed

Move `docs/exec-plans/active/sound-hooks-linux/` to
`docs/exec-plans/completed/sound-hooks-linux/` — all work items are done.

## Files to touch

| File | Change |
|------|--------|
| `sounds/tick.mp3` | New — generated 100ms sine tone |
| `sounds/tick.ogg` | New — OGG version of tick |
| `hooks/play-sound.sh` | Add `RALPH_LOOP` detection at top |
| `scripts/ralph-loop.sh` | Add `RALPH_LOOP=1` to worker/reviewer env, add completion sound after SHIP |
| `skills/sound-notifications.md` | Add Ralph Loop behavior section |
| `commands/apply-core.md` | Add tick sound files to source list |

## Risks and open questions

- **P2**: Tick tone characteristics (880Hz, 100ms) are a guess. May need tuning after hearing it. Easy to regenerate.
- **P2**: `RALPH_LOOP` env var name could collide if another tool uses it. Low risk — namespaced to our workflow.

## Progress log

- [x] Generate `tick.mp3` and `tick.ogg` using ffmpeg
- [x] Update `hooks/play-sound.sh` — add `RALPH_LOOP` detection
- [x] Update `scripts/ralph-loop.sh` — add `RALPH_LOOP=1` to spawns, add completion sound
- [x] Shellcheck and shfmt modified scripts
- [x] Update `skills/sound-notifications.md` — add Ralph Loop section
- [x] Update `commands/apply-core.md` — add tick sounds to source list
- [x] Move `sound-hooks-linux` plan to completed

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| `RALPH_LOOP=1` env var for detection | Override `CLAUDE_SOUND` in env; file-based flag | Env vars in `settings.json` clobber inherited env. `RALPH_LOOP` isn't in settings.json so it survives. File flags have race conditions |
| Synthetic tick via ffmpeg tone generator | Source a click sound file; reuse existing sound at low volume | No external sourcing needed, reproducible, tiny file. A distinct sound is clearer than the same sound quieter |
| 880Hz 100ms sine with fade-out | Lower pitch, longer duration, square wave | 880Hz (A5) is audible but not harsh. 100ms is perceptible as a tick without being distracting. Fade-out prevents click artifacts |
| Tick at 15% volume hardcoded | Configurable tick volume via `RALPH_LOOP_VOLUME` | Over-engineering. 15% is quiet enough. Users who want silence set `CLAUDE_SOUND=none` |
| Read settings.json for completion sound | Hardcode sound name; add new env var | settings.json is the source of truth. Reading it respects user config without adding new knobs |
| Sound only on SHIP, not EXHAUSTED/STAGNATED | Sound on all exit paths | SHIP is the success signal. Failure modes print clear messages. A sound on failure could be confusing |

## Completion criteria

- [x] `tick.mp3` and `tick.ogg` exist in `sounds/`
- [x] During ralph loop, per-item Stop hook plays tick at low volume
- [x] On SHIP, ralph-loop.sh plays the configured completion sound once
- [x] Interactive sessions (no RALPH_LOOP) are unaffected
- [x] `skills/sound-notifications.md` documents ralph loop behavior
- [x] `commands/apply-core.md` includes tick sound files
- [x] Modified scripts pass shellcheck and shfmt
- [x] `sound-hooks-linux` plan moved to completed

## Follow-up (post-loop, human action)

- Listen to the tick sound and tune frequency/duration if needed
- Test ralph loop end-to-end to verify sound plays once on SHIP

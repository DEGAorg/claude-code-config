# Plan: Fix sound interface bug in orch-engine.sh

**Status:** In progress
**Created:** 2026-03-24

## Requirements

- `play-sound.sh` plays the completion sound when the orchestrator SHIPs a plan
- The hook reads `CLAUDE_SOUND` env var, not a positional argument
- `orch-engine.sh` must pass the sound name via env var, matching how `planner-loop.sh` already does it correctly

## Approach

`orch-engine.sh` line 431 calls `bash play-sound.sh "success"` — but `play-sound.sh` reads `$CLAUDE_SOUND` env var and ignores positional args. The fix is to match the pattern from `planner-loop.sh`: `CLAUDE_SOUND=success bash play-sound.sh`.

Also check `ralph-loop.sh` — it calls `play-sound.sh` without setting `CLAUDE_SOUND`, relying on the default (`super-mario-bros`). That's fine but worth noting.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-engine.sh` | Change `bash play-sound.sh "success"` to `CLAUDE_SOUND=success bash play-sound.sh` |

## Risks and open questions

- None. One-line fix matching an existing correct pattern.

## Questions for reviewer

No blocking questions.

## Progress log

- [ ] Fix the `play-sound.sh` invocation in `orch-engine.sh` to pass sound name via `CLAUDE_SOUND` env var

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Pass via env var | Modify play-sound.sh to accept positional arg | Env var is the established interface; planner-loop.sh already uses it correctly |

## Completion criteria

- [ ] `rg 'play-sound.sh' scripts/orch-engine.sh` shows `CLAUDE_SOUND=` prefix
- [ ] `shellcheck -e SC1091 -S warning scripts/orch-engine.sh` passes
- [ ] `shfmt -d scripts/orch-engine.sh` passes

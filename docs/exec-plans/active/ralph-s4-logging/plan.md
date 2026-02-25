# Plan: Ralph S4 — Structured Logging

**Status:** In progress
**Created:** 2026-02-25
**Sequence:** Step 4 of 4 — can run after S1; does not depend on S2 or S3

## Context

Ralph runs leave no searchable audit trail. When a session fails at iteration 3,
there is no log to diagnose. This step adds structured JSONL logging: a session-start
hook selects the backend, and a PostToolUse hook appends one line per tool call.

## Requirements

- `hooks/session-start-logging.sh` prompts for logging backend on first use in a
  session; writes `~/.claude/.session-log-config`
- Prompt is skipped when `RALPH_MODE` is set (non-interactive loop context)
- Prompt is skipped if config file already exists for this session
- `hooks/structured-log.sh` appends one JSONL entry per tool call to
  `~/.claude/logs/sessions/YYYY-MM-DD.jsonl` when config exists
- Log entries include: timestamp, tool name, exit code
- `settings.json` wires both hooks at the correct lifecycle events

## Approach

### session-start-logging.sh

Fires on `UserPromptSubmit` (first human message in a session). Writes a config
file so the log hook knows where to write.

```bash
#!/usr/bin/env bash
# Skip in non-interactive (loop) contexts
[[ -n "${RALPH_MODE:-}" ]] && exit 0

CONFIG="${HOME}/.claude/.session-log-config"
[[ -f "$CONFIG" ]] && exit 0  # already configured this session

# In UserPromptSubmit, can write to stdout to surface a message
# but cannot read stdin — use a default of "local" silently
# (interactive prompt not feasible in hook context)
mkdir -p "$(dirname "$CONFIG")"
printf '{"backend":"local","configured_at":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$CONFIG"
```

**Note:** Claude Code hooks cannot read stdin interactively. The "prompt for
local/gcp/skip" design from the MVP doc is not feasible in a hook. Default to
`local` silently. GCP backend can be added by manually writing the config file
with `{"backend":"gcp"}` — document this in a comment in the script.

### structured-log.sh

Fires on PostToolUse for all tools. Appends JSONL:

```bash
#!/usr/bin/env bash
CONFIG="${HOME}/.claude/.session-log-config"
[[ ! -f "$CONFIG" ]] && exit 0

BACKEND=$(jq -r '.backend' "$CONFIG")
[[ "$BACKEND" != "local" ]] && exit 0

TOOL=$(jq -r '.tool_name // "unknown"' <<< "${CLAUDE_TOOL_USE_INPUT:-{\}}")
STATUS=$(jq -r '.exit_code // 0' <<< "${CLAUDE_TOOL_USE_RESULT:-{\}}")

LOG_DIR="${HOME}/.claude/logs/sessions"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%d).jsonl"

printf '{"ts":"%s","tool":"%s","exit_code":%s}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TOOL" "$STATUS" >> "$LOG_FILE"
```

**Note:** Verify the actual env var names Claude Code injects into PostToolUse
hooks before implementing. Check `claude --help` or test with an echo hook.

### settings.json changes

Add to `PostToolUse` matchers:
```json
{
  "matcher": ".*",
  "hooks": [{ "type": "command", "command": "bash hooks/structured-log.sh" }]
}
```

Add to `UserPromptSubmit` (if supported) or `PreSession`:
```json
{ "type": "command", "command": "bash hooks/session-start-logging.sh" }
```

Verify which lifecycle event is available in `settings.json` before wiring.

## Files to touch

| File | Change |
|------|--------|
| `hooks/session-start-logging.sh` | New: write `~/.claude/.session-log-config` with local backend; skip in RALPH_MODE |
| `hooks/structured-log.sh` | New: PostToolUse JSONL appender; noop if no config |
| `settings.json` | Wire `session-start-logging.sh` at session start event; wire `structured-log.sh` at PostToolUse |

## Risks and open questions

- **Open:** Claude Code hook env vars for tool name and exit code in PostToolUse —
  verify actual names. Hook receives JSON on stdin (`jq -r '.tool_name'` from stdin,
  not env var). Test before committing to the implementation.
- **Open:** Which `settings.json` lifecycle event fires at session start?
  `UserPromptSubmit` is documented; `PreSession` may not exist. Check available events.
- **Resolved:** No interactive prompt for backend selection — hooks cannot read stdin.
  Default to `local`; document how to override to `gcp`.

## Progress log

- [ ] Verify PostToolUse hook input format (stdin JSON schema) with a test echo hook
- [ ] `hooks/session-start-logging.sh` — new script; shellcheck + shfmt clean
- [ ] `hooks/structured-log.sh` — new script; shellcheck + shfmt clean
- [ ] `settings.json` — wire both hooks at correct lifecycle events
- [ ] Verify `shellcheck hooks/session-start-logging.sh hooks/structured-log.sh` exits 0
- [ ] Verify `shfmt -d hooks/session-start-logging.sh hooks/structured-log.sh` exits 0
- [ ] Verify `bash scripts/ralph-check.sh` exits 0

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Default backend = local silently | Interactive prompt | Hooks cannot read stdin; interactive prompt is not feasible |
| GCP backend = manual config override | Auto-detect credentials | Avoids credential probing in hook; user sets `{"backend":"gcp"}` explicitly |
| One JSONL file per day | One file per session, one global file | Per-day is searchable with `rg` without loading everything; session ID in each entry allows filtering |
| PostToolUse fires on all tools | Only Edit/Write/Bash | Full audit trail; the log is append-only so noise is acceptable |

## Completion criteria

- [ ] All progress log items checked
- [ ] `hooks/session-start-logging.sh` writes `~/.claude/.session-log-config` on first session use
- [ ] `hooks/structured-log.sh` appends JSONL to `~/.claude/logs/sessions/YYYY-MM-DD.jsonl`
- [ ] Neither hook runs when `RALPH_MODE` is set
- [ ] `bash scripts/ralph-check.sh` exits 0

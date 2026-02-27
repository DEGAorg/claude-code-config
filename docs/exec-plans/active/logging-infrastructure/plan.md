# Plan: Logging Infrastructure — Persistent Server + Ralph Event Logging

**Status:** In progress
**Created:** 2026-02-27

## Requirements

- A persistent Python log server runs as a background daemon for the lifetime of a session
  or ralph-loop run
- The server listens on a Unix socket (`~/.claude/logs/log.sock`) for newline-delimited JSON
- Every event is written to `~/.claude/logs/ralph/YYYY-MM-DD.jsonl` (local)
- Events are optionally forwarded to GCP Cloud Logging asynchronously — no hard failure if
  credentials are absent; emits a startup warning and continues local-only
- A bash client helper (`scripts/log-client.sh`) provides a `log_event` function that any
  script can use; it fails silently if the server is not running
- `ralph-loop.sh` emits structured events at: LOOP_START, WORKER_DONE, REVIEWER_DECISION,
  SHIP, BLOCKED, EXHAUSTED
- `hooks/session-start-logging.sh` starts the server on session begin; cleans up on end
- Per-tool-call logging in `hooks/structured-log.sh` is unchanged
- `ralph-loop.sh` ensures the server is running at startup (supports AFK runs with no
  prior session hook)
- All shell scripts pass `shellcheck` and `shfmt`
- `log-server.py` passes `ruff check`, `ruff format`, and `ty check`

## Approach

### Architecture

```
session-start-logging.sh  ──┐
ralph-loop.sh               ├──► log-server.py (daemon, Unix socket)
any future script           ─┘         │
         │                             ├──► ~/.claude/logs/ralph/YYYY-MM-DD.jsonl
         └── log-client.sh (socat) ───►│
                                       └──► GCP Cloud Logging (async, optional)
```

Three new/modified artifacts:

1. **`scripts/log-server.py`** — Python daemon using `uv` inline script deps
   (`google-cloud-logging`). Opens Unix socket, processes newline-delimited JSON,
   writes local JSONL, spawns a background thread per event for GCP. Writes PID to
   `~/.claude/logs/log-server.pid`. Installs SIGTERM handler to clean up socket.
   Loads GCP credentials once at startup; silently skips GCP if absent.

2. **`scripts/log-client.sh`** — sourceable bash helper. Exports `log_event()` which
   accepts an event name and optional payload JSON, builds the envelope with `ts`,
   `session`, and `script` fields, then sends via `socat`. Falls back silently if
   socat is absent or the server is not running (`|| true`).

3. **`hooks/session-start-logging.sh`** — extended to start the log server as a
   background process (`uv run scripts/log-server.py &`). Waits up to 2 s for the
   socket to appear. Saves PID. Existing session-config write logic is preserved.
   The `RALPH_MODE` early-exit is removed from the server-start code path (ralph
   runs need the server too). The session-config write retains the idempotency guard.

4. **`scripts/ralph-loop.sh`** — sources `scripts/log-client.sh` and calls
   `log_event` at key points. Also starts the server if not already running (for AFK
   ralph runs started without a prior interactive session). Emits SIGTERM on exit via
   `trap`.

### Event schema

```json
{
  "ts": "2026-02-27T10:45:01Z",
  "session": "$SESSION_ID",
  "script": "ralph-loop.sh",
  "event": "LOOP_START",
  "payload": {}
}
```

Events emitted by ralph-loop.sh:

| Event | Payload |
|-------|---------|
| `LOOP_START` | `{"task_slug":"…","max_iterations":N}` |
| `WORKER_DONE` | `{"iteration":N,"exit_code":N}` |
| `REVIEWER_DECISION` | `{"iteration":N,"decision":"SHIP\|REVISE\|BLOCKED","reason":"…"}` |
| `SHIP` | `{"iteration":N}` |
| `BLOCKED` | `{"iteration":N}` |
| `EXHAUSTED` | `{"iterations_used":N}` |

### GCP setup (optional — no-op if absent)

- Credentials file: `~/.claude/gcp-sa.json` (primary) or `$GOOGLE_APPLICATION_CREDENTIALS`
- Log name: `ralph`
- If file not found at startup → warning printed, GCP writes silently disabled

### socat dependency

`log-client.sh` checks for `socat` at load time and sets a `LOG_AVAILABLE` flag.
`log_event` is a no-op when `LOG_AVAILABLE=0`. No hard error.

## Files to touch

| File | Change |
|------|--------|
| `scripts/log-server.py` | **Create** — Python daemon: Unix socket, local JSONL, async GCP |
| `scripts/log-client.sh` | **Create** — bash helper: `log_event` function via socat |
| `hooks/session-start-logging.sh` | **Modify** — add server start/stop; remove RALPH_MODE block for server path |
| `scripts/ralph-loop.sh` | **Modify** — source log-client.sh, emit 6 event types, start server if absent |

## Risks and open questions

- **socat not installed on target machine** — handled: `LOG_AVAILABLE=0` fallback, no crash
- **GCP credentials absent** — handled: startup warning, local-only mode
- **Session-end cleanup** — the logging.md mentions a companion `session-end.sh` that
  doesn't exist yet. For now: `ralph-loop.sh` traps EXIT and sends SIGTERM to the PID it
  started. Interactive session server lifecycle (started by `session-start-logging.sh`)
  will leak the process on session end until a session-end hook is added. Acceptable for
  Phase I — the server is lightweight and self-cleans on next session start.
- **Multiple ralph runs** — if a server is already running (from a prior session),
  `ralph-loop.sh` detects the socket and skips starting a new one.

## Progress log

- [ ] Create `scripts/log-server.py`
- [ ] Create `scripts/log-client.sh`
- [ ] Update `hooks/session-start-logging.sh` — server start/stop
- [ ] Update `scripts/ralph-loop.sh` — source client, emit events
- [ ] Run `shellcheck scripts/log-client.sh hooks/session-start-logging.sh scripts/ralph-loop.sh`
- [ ] Run `shfmt -d scripts/log-client.sh hooks/session-start-logging.sh scripts/ralph-loop.sh`
- [ ] Run `ruff check scripts/log-server.py && ruff format --check scripts/log-server.py`
- [ ] Run `ty check scripts/log-server.py`
- [ ] Smoke test: start server, send a test event, verify JSONL entry written

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Unix socket over named pipe | Named pipe, TCP | Bidirectional, connection-oriented, cleaner for concurrent writers |
| `socat` on bash side | Python client, `nc` | Standard on Linux/macOS, one-liner write, no Python required client-side |
| `uv` inline deps for server | virtualenv, system Python | Zero install friction, self-contained single file |
| Async GCP via background thread | asyncio, fire-and-forget process | Simple, no event loop complexity, server never blocks |
| ralph-loop.sh starts server if absent | Require session hook first | Supports AFK runs; idempotent socket check prevents double-start |
| Session-end cleanup deferred (leak acceptable) | Add session-end hook now | Out of scope for Phase I; server is lightweight, self-cleans next start |
| Remove RALPH_MODE early-exit in server start | Keep skip, ralph starts its own | Ralph needs the same server; unified lifecycle simpler |

## Completion criteria

- [ ] All requirements met (local + GCP paths work, ralph events emitted)
- [ ] `shellcheck` reports zero errors on all touched shell scripts
- [ ] `shfmt -d` reports no diffs on all touched shell scripts
- [ ] `ruff check` and `ruff format --check` pass on `log-server.py`
- [ ] `ty check` passes on `log-server.py`
- [ ] Smoke test passes: `~/.claude/logs/ralph/YYYY-MM-DD.jsonl` contains the test event

# logging-integration

Make `apply-core` install the full logging stack with zero manual steps.
After running `/apply-core`, any project has structured local logs and optional
GCP Cloud Logging via service account — no manual socat install, no path fixes,
no shell debugging.

---

## Problem statement

`ralph-loop.sh` calls `log_event` (from `log-client.sh`) at every lifecycle point
(LOOP_START, WORKER_DONE, REVIEWER_DECISION, SHIP, BLOCKED, EXHAUSTED). But none
of these events ever reached `~/.claude/logs/ralph/` because of three compounding
bugs and a missing install:

| # | Bug | Root cause |
|---|-----|------------|
| 1 | `socat` not installed | no fallback, `log_event` silently no-ops |
| 2 | `${2:-{}}` parsing | bash appends a literal `}` to every payload argument |
| 3 | jq pretty-print | multi-line payload breaks JSONL framing; server discards |
| 4 | Not in apply-core | logging artifacts not installed in new projects |

Bugs 1–3 are fixed in `log-client.sh` this session. This plan fixes bug 4 and
the architectural issues that would cause the same problems in any new project.

---

## Architecture

```
Global (~/.claude/)                   Per-repo (project root)
─────────────────────────────────     ────────────────────────────────────
scripts/log-server.py                 scripts/ralph-loop.sh   (sources log-client)
hooks/session-start-logging.sh ──┐   scripts/log-client.sh   (transport to socket)
hooks/structured-log.sh           │   scripts/plan-advance.sh
hooks/enforce-loop-mode.sh        │   scripts/task-complete.sh
logs/ralph/YYYY-MM-DD.jsonl  ◄───┘   hooks/enforce-loop-mode.sh (per-repo variant)
logs/log.sock  ◄─────────────────────── ralph-loop.sh starts log-server if absent
gcp-sa.json   (optional, user places)
```

**Key design decisions:**
- `log-server.py` is **global** (`~/.claude/scripts/`) — one server per machine,
  shared by all projects. Both `session-start-logging.sh` and `ralph-loop.sh`
  reference it via `${HOME}/.claude/scripts/log-server.py`.
- `log-client.sh` is **per-repo** — sourced by `ralph-loop.sh`, ships with Ralph Loop.
- Global hooks use absolute `~/.claude/hooks/` paths in `settings.json` so they
  work from any project directory.
- GCP is zero-config: drop `~/.claude/gcp-sa.json` and the server auto-enables it.

---

## Progress

### Phase 1 — Fix log-client.sh bugs (done this session)
- [x] Add `nc -U` fallback so socat is not required
- [x] Fix `${2:-{}}` payload parsing (extra `}` appended to every payload)
- [x] Compact payload with `tr -d '\n'` to handle jq pretty-print output
- [x] Warn explicitly at source time when neither socat nor nc is available

### Phase 2 — Fix path references to log-server.py
- [x] Update `hooks/session-start-logging.sh` to reference
      `${HOME}/.claude/scripts/log-server.py` instead of `${SCRIPT_DIR}/../scripts/`
- [x] Update `scripts/ralph-loop.sh` to reference
      `${HOME}/.claude/scripts/log-server.py` instead of `${SCRIPT_DIR}/log-server.py`

### Phase 3 — Update settings.json for global hook paths
- [x] Change `bash hooks/session-start-logging.sh` →
      `bash ~/.claude/hooks/session-start-logging.sh`
- [x] Change `bash hooks/structured-log.sh` →
      `bash ~/.claude/hooks/structured-log.sh`
- [x] Keep `bash hooks/enforce-loop-mode.sh` relative (per-repo behavior is correct)
- [x] Keep `bash scripts/ralph-check.sh` relative (per-repo Stop hook)

### Phase 4 — Update apply-core.md
- [x] Add to **Global scripts** section (install to `~/.claude/scripts/`):
      `scripts/log-server.py`
- [x] Add to **Global hooks** section (install to `~/.claude/hooks/`):
      `hooks/session-start-logging.sh`, `hooks/structured-log.sh`
- [x] Add to **Ralph Loop** per-repo section:
      `scripts/log-client.sh`, `scripts/plan-advance.sh`, `scripts/task-complete.sh`
- [x] Add **GCP setup step** (Step 5, before post-install):
      Check if `~/.claude/gcp-sa.json` exists. If not, tell the user how to place it.
      Do not copy keys — only instruct. GCP is optional; local logging works without it.
- [x] Update **post-install summary** to show logging status (local vs gcp)

### Phase 5 — Verify end-to-end
- [x] Kill any running log server: `rm -f ~/.claude/logs/log.sock`
- [x] Start fresh: `uv run ~/.claude/scripts/log-server.py &`
- [x] Source log-client.sh and fire a LOOP_START event with jq payload
- [x] Confirm entry appears in `~/.claude/logs/ralph/YYYY-MM-DD.jsonl`
- [x] Shellcheck and shfmt all modified shell files
- [x] Run `bash scripts/ralph-check.sh` — must pass

---

## Files changed

| File | Change |
|------|--------|
| `scripts/log-client.sh` | Bugs fixed (done) |
| `hooks/session-start-logging.sh` | Use global log-server path |
| `scripts/ralph-loop.sh` | Use global log-server path |
| `settings.json` | Absolute paths for global hooks |
| `commands/apply-core.md` | Add logging artifacts + GCP step |

---

## Out of scope

- GCP project creation or service account provisioning (user responsibility)
- `structured-log.sh` GCP backend (per-tool-call events are too noisy for GCP;
  ralph events are the high-value signal)
- Log viewer UI (use `rg` / `jq` queries on the JSONL files)
- Log rotation (daily files; manual cleanup if needed)

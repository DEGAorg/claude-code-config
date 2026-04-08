#!/usr/bin/env bash
# SessionStart / UserPromptSubmit hook — start the persistent log server and
# initialise structured logging config.
#
# Server:
#   Starts scripts/log-server.py (via uv) if the socket is not already present.
#   Waits up to 2 s for the socket to appear, then continues regardless.
#   Always runs — RALPH_MODE does not skip the server-start path.
#
# Session config:
#   Writes $DEGA_CORE_HOME/state/.session-log-config on the first prompt of a session so
#   that structured-log.sh knows where to append JSONL entries.
#   Skipped in RALPH_MODE (ralph manages its own server start via ralph-loop.sh).
#   Idempotent: one write per session.
#
# To override the backend, write the config manually before starting Claude Code:
#   printf '{"backend":"gcp"}\n' > ~/.degacore/state/.session-log-config
# Supported backends: "local" (default), "gcp" (future; no-op until implemented).

set -euo pipefail

# ── Log server start (always — ralph runs need the server too) ────────────────

DEGA_CORE_HOME="${DEGA_CORE_HOME:-${HOME}/.degacore}"

SOCK="${DEGA_CORE_HOME}/state/logs/log.sock"

if [[ ! -S "$SOCK" ]]; then
  SERVER="${DEGA_CORE_HOME}/scripts/log-server.py"

  mkdir -p "${DEGA_CORE_HOME}/state/logs/ralph"
  uv run "$SERVER" >>"${DEGA_CORE_HOME}/state/logs/log-server.log" 2>&1 &
  disown

  # Wait up to 2 s (20 × 0.1 s) for the socket to appear.
  _waited=0
  while [[ ! -S "$SOCK" && $_waited -lt 20 ]]; do
    sleep 0.1
    _waited=$((_waited + 1))
  done

  if [[ ! -S "$SOCK" ]]; then
    echo "warning: log-server did not start within 2 s" >&2
  fi
fi

# ── Session config (interactive sessions only; idempotent) ────────────────────

[[ -n "${RALPH_MODE:-}" ]] && exit 0

CONFIG="${DEGA_CORE_HOME}/state/.session-log-config"
[[ -f "$CONFIG" ]] && exit 0

mkdir -p "$(dirname "$CONFIG")"
printf '{"backend":"local","configured_at":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$CONFIG"

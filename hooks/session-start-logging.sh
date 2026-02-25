#!/usr/bin/env bash
# SessionStart / UserPromptSubmit hook — initialise structured logging config.
#
# Writes ~/.claude/.session-log-config on the first prompt of a session so that
# structured-log.sh knows where to append JSONL entries.
#
# Skipped when:
#   - RALPH_MODE is set (non-interactive ralph-loop context)
#   - config file already exists (idempotent; one write per session)
#
# To override the backend, write the config manually before starting Claude Code:
#   printf '{"backend":"gcp"}\n' > ~/.claude/.session-log-config
# Supported backends: "local" (default), "gcp" (future; no-op until implemented).

set -euo pipefail

[[ -n "${RALPH_MODE:-}" ]] && exit 0

CONFIG="${HOME}/.claude/.session-log-config"
[[ -f "$CONFIG" ]] && exit 0

mkdir -p "$(dirname "$CONFIG")"
printf '{"backend":"local","configured_at":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$CONFIG"

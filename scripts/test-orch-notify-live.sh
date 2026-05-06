#!/usr/bin/env bash
# test-orch-notify-live.sh — repeatable end-to-end test for the orch
# agent-notification hooks.
#
# Subcommands:
#   unit      Run the bats unit + handshake tests for both hooks.
#   setup     Wire the Stop hook into THIS repo's .claude/settings.local.json
#             (gitignored, scoped to this dir) and seed an unseen notification
#             so the next Claude Code Stop event surfaces it as an agent-bump.
#   teardown  Reverse `setup`: restore .claude/settings.local.json and remove
#             the seeded plan + notification files.
#   status    Show what the script sees: hook entry presence, notification
#             files in flight, settings backup file.
#
# Designed for the manual integration test described in
# docs/orch-agent-notifications.md ("Testing"). The unit subcommand should
# pass on every PR; the setup/teardown pair is for human-in-loop verification
# that Claude Code actually surfaces the Stop-hook output as a system-reminder.

set -euo pipefail

SLUG="20260506-orch-notify-live-test"
REPO_ROOT="$(git rev-parse --show-toplevel)"
SETTINGS_FILE="${REPO_ROOT}/.claude/settings.local.json"
SETTINGS_BACKUP="${SETTINGS_FILE}.test-orch-notify.bak"
PLAN_DIR="${REPO_ROOT}/.orchestrator/plans/${SLUG}"
NOTIF_FILE="${REPO_ROOT}/.orchestrator/notifications/${SLUG}.json"
LIFECYCLE_HOOK="${REPO_ROOT}/hooks/orch-lifecycle/02-agent-notify.sh"

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required" >&2
    exit 1
  fi
}

cmd_unit() {
  if ! command -v bats >/dev/null 2>&1; then
    echo "error: bats is required (brew install bats-core)" >&2
    exit 1
  fi
  cd "${REPO_ROOT}"
  bats tests/orch/test_notify_lifecycle.bats \
    tests/orch/test_notify_stop_hook.bats \
    tests/orch/test_notify_handshake.bats
}

cmd_setup() {
  require_jq

  if [[ -e "${SETTINGS_BACKUP}" ]]; then
    echo "error: backup already exists at ${SETTINGS_BACKUP}" >&2
    echo "       run '$0 teardown' first or delete the backup manually" >&2
    exit 1
  fi

  # Backup current settings (or stub an empty {} if absent).
  if [[ -f "${SETTINGS_FILE}" ]]; then
    cp "${SETTINGS_FILE}" "${SETTINGS_BACKUP}"
  else
    mkdir -p "$(dirname "${SETTINGS_FILE}")"
    echo '{}' >"${SETTINGS_FILE}"
    echo '{}' >"${SETTINGS_BACKUP}"
  fi

  # Add the Stop hook entry. The full path keeps the hook runnable even if
  # CLAUDE_PROJECT_DIR is set to something other than the repo root.
  local hook_cmd="bash ${REPO_ROOT}/hooks/stop/01-orch-notify.sh"
  local tmp="${SETTINGS_FILE}.tmp.$$"
  jq --arg cmd "${hook_cmd}" '
    .hooks //= {} |
    .hooks.Stop //= [] |
    .hooks.Stop += [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": $cmd }]
    }]
  ' "${SETTINGS_FILE}" >"${tmp}"
  mv "${tmp}" "${SETTINGS_FILE}"

  # Seed a fake plan + notification so the next Stop event has something
  # to surface. Use the lifecycle hook itself so the file format is real.
  mkdir -p "${PLAN_DIR}"
  cat >"${PLAN_DIR}/state.json" <<JSON
{
  "slug": "${SLUG}",
  "issueNumber": 0,
  "status": "completed",
  "finalReview": {
    "decision": "SHIP",
    "prUrl": "https://example.invalid/test/pr/0",
    "prNumber": 0
  }
}
JSON

  (cd "${REPO_ROOT}" &&
    bash "${LIFECYCLE_HOOK}" ship "${SLUG}" --items 1 --passed 1 --elapsed 1s)

  cat <<EOF

Setup complete.

Wired:    Stop hook in ${SETTINGS_FILE}
Backup:   ${SETTINGS_BACKUP}
Seeded:   ${NOTIF_FILE}

Next steps to confirm Claude Code surfaces the agent-bump:

  1. Exit this Claude Code session (/exit) and open a new one in:
     ${REPO_ROOT}
  2. Ask anything trivial ("what's 2+2?") and let it answer.
  3. End that turn (just send another message).
  4. The next turn should open with a system-reminder containing
     "${SLUG}" and "PR: https://example.invalid/test/pr/0".

When done, run:
  bash $0 teardown
EOF
}

cmd_teardown() {
  if [[ -f "${SETTINGS_BACKUP}" ]]; then
    mv "${SETTINGS_BACKUP}" "${SETTINGS_FILE}"
    echo "restored: ${SETTINGS_FILE}"
  else
    echo "warn: no backup found at ${SETTINGS_BACKUP} — settings.local.json left as-is" >&2
  fi

  if [[ -f "${NOTIF_FILE}" ]]; then
    rm -f "${NOTIF_FILE}"
    echo "removed:  ${NOTIF_FILE}"
  fi

  if [[ -d "${PLAN_DIR}" ]]; then
    rm -rf "${PLAN_DIR}"
    echo "removed:  ${PLAN_DIR}"
  fi

  echo "teardown complete."
}

cmd_status() {
  echo "settings:  ${SETTINGS_FILE}"
  if [[ -f "${SETTINGS_FILE}" ]] && command -v jq >/dev/null 2>&1; then
    if jq -e '.hooks.Stop // [] | map(.hooks[]?.command // "") | any(. | contains("01-orch-notify.sh"))' \
      "${SETTINGS_FILE}" >/dev/null 2>&1; then
      echo "  Stop hook wired:   yes"
    else
      echo "  Stop hook wired:   no"
    fi
  fi

  if [[ -f "${SETTINGS_BACKUP}" ]]; then
    echo "  backup present:    yes (${SETTINGS_BACKUP})"
  else
    echo "  backup present:    no"
  fi

  echo
  echo "test plan dir: ${PLAN_DIR}"
  [[ -d "${PLAN_DIR}" ]] && echo "  exists" || echo "  absent"

  echo
  echo "notification file: ${NOTIF_FILE}"
  if [[ -f "${NOTIF_FILE}" ]]; then
    echo "  exists, contents:"
    jq . "${NOTIF_FILE}" 2>/dev/null | sed 's/^/    /'
  else
    echo "  absent"
  fi
}

case "${1:-}" in
unit)
  shift
  cmd_unit "$@"
  ;;
setup)
  shift
  cmd_setup "$@"
  ;;
teardown)
  shift
  cmd_teardown "$@"
  ;;
status)
  shift
  cmd_status "$@"
  ;;
-h | --help | "") usage 0 ;;
*)
  echo "error: unknown subcommand '$1'" >&2
  usage 1
  ;;
esac

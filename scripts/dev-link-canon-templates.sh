#!/usr/bin/env bash
# Point the global canon templates install at a local develop checkout so
# agentic flows (canon-cli, Conductor, orchestrator) pick up unreleased
# template changes without merging to main and re-running /apply-core.
#
# Reversible: the existing ~/.degacore/canon/templates/ snapshot is moved
# aside to a timestamped backup; revert restores it.
#
# Subcommands:
#   link    — back up the current install, symlink develop into its place
#   check   — verify the symlink is active and points at this clone
#   revert  — remove the symlink, restore the backup
#
# Usage:
#   scripts/dev-link-canon-templates.sh link
#   scripts/dev-link-canon-templates.sh check
#   scripts/dev-link-canon-templates.sh revert

set -euo pipefail

DEGACORE="${HOME}/.degacore"
INSTALL_DIR="${DEGACORE}/canon/templates"
CANON_CLI_LINK="${DEGACORE}/canon-cli/node_modules/canon-templates"
STATE_FILE="${DEGACORE}/.canon-templates-dev-link.json"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
SOURCE_DIR=""
if [[ -n "${REPO_ROOT}" ]]; then
  SOURCE_DIR="${REPO_ROOT}/canon/templates"
fi

# --- helpers --------------------------------------------------------------

die() {
  echo "error: $*" >&2
  exit 1
}

require_repo() {
  [[ -n "${REPO_ROOT}" ]] || die "run from inside a claude-code-config clone (no git toplevel found)"
  [[ -d "${SOURCE_DIR}" ]] || die "source canon/templates not found at ${SOURCE_DIR}"
  [[ -f "${SOURCE_DIR}/runner.ts" ]] || die "${SOURCE_DIR} does not look like a canon/templates dir (missing runner.ts)"
}

is_symlink_to_source() {
  [[ -L "${INSTALL_DIR}" ]] || return 1
  local target
  target="$(readlink "${INSTALL_DIR}")"
  # readlink may yield a relative path on some platforms; resolve.
  if [[ "${target}" != /* ]]; then
    target="$(cd "$(dirname "${INSTALL_DIR}")" && cd "${target}" && pwd)"
  fi
  [[ "${target}" == "${SOURCE_DIR}" ]]
}

write_state() {
  local backup_dir="$1"
  cat >"${STATE_FILE}" <<EOF
{
  "linked_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "source_dir": "${SOURCE_DIR}",
  "backup_dir": "${backup_dir}",
  "install_dir": "${INSTALL_DIR}"
}
EOF
}

read_state_field() {
  local field="$1"
  [[ -f "${STATE_FILE}" ]] || return 1
  if command -v jq >/dev/null 2>&1; then
    jq -er ".${field}" "${STATE_FILE}"
  else
    # naive fallback — assumes one field per line, no nested objects.
    grep -E "\"${field}\"" "${STATE_FILE}" | sed -E 's/.*: *"([^"]*)".*/\1/'
  fi
}

# --- subcommands ----------------------------------------------------------

cmd_link() {
  require_repo
  mkdir -p "${DEGACORE}/canon"

  if is_symlink_to_source; then
    echo "INFO: already linked — ${INSTALL_DIR} -> ${SOURCE_DIR}"
    return 0
  fi

  if [[ -L "${INSTALL_DIR}" ]]; then
    echo "INFO: removing stale symlink pointing at $(readlink "${INSTALL_DIR}")"
    rm -- "${INSTALL_DIR}"
  fi

  local backup_dir=""
  if [[ -d "${INSTALL_DIR}" ]]; then
    backup_dir="${INSTALL_DIR}.backup-$(date -u +"%Y%m%dT%H%M%SZ")"
    echo "INFO: moving existing install aside → ${backup_dir}"
    mv -- "${INSTALL_DIR}" "${backup_dir}"
  fi

  echo "INFO: linking ${INSTALL_DIR} -> ${SOURCE_DIR}"
  ln -s -- "${SOURCE_DIR}" "${INSTALL_DIR}"

  # canon-cli node_modules symlink already points at INSTALL_DIR, so it
  # auto-follows. Recreate it if missing (e.g. fresh /apply-core never ran).
  if [[ ! -e "${CANON_CLI_LINK}" && ! -L "${CANON_CLI_LINK}" ]]; then
    if [[ -d "$(dirname "${CANON_CLI_LINK}")" ]]; then
      echo "INFO: creating canon-cli node_modules link"
      ln -s -- "${INSTALL_DIR}" "${CANON_CLI_LINK}"
    else
      echo "INFO: canon-cli/node_modules absent — skipping CLI link (run /apply-core if you need it)"
    fi
  fi

  write_state "${backup_dir}"
  echo "OK: develop canon/templates is now the global install"
  echo "    state: ${STATE_FILE}"
  echo "    revert with: scripts/dev-link-canon-templates.sh revert"
}

cmd_check() {
  require_repo
  local fail=0

  if is_symlink_to_source; then
    echo "OK: ${INSTALL_DIR} -> ${SOURCE_DIR}"
  else
    echo "FAIL: ${INSTALL_DIR} is not a symlink to ${SOURCE_DIR}"
    if [[ -L "${INSTALL_DIR}" ]]; then
      echo "      (current target: $(readlink "${INSTALL_DIR}"))"
    elif [[ -d "${INSTALL_DIR}" ]]; then
      echo "      (current: real directory — link has not been run)"
    else
      echo "      (current: missing)"
    fi
    fail=1
  fi

  if [[ -L "${CANON_CLI_LINK}" ]]; then
    local cli_target
    cli_target="$(readlink "${CANON_CLI_LINK}")"
    if [[ "${cli_target}" == "${INSTALL_DIR}" ]]; then
      echo "OK: canon-cli node_modules link → ${INSTALL_DIR}"
    else
      echo "FAIL: canon-cli node_modules link points at ${cli_target} (expected ${INSTALL_DIR})"
      fail=1
    fi
  elif [[ -e "${CANON_CLI_LINK}" ]]; then
    echo "FAIL: ${CANON_CLI_LINK} exists but is not a symlink"
    fail=1
  else
    echo "INFO: canon-cli node_modules link absent (only matters if you use canon-cli)"
  fi

  # Sentinel: develop-only file proves we're seeing the new tree.
  if [[ -f "${INSTALL_DIR}/mint-cycle-helpers.ts" ]]; then
    echo "OK: develop sentinel present — mint-cycle-helpers.ts is visible through the link"
  else
    echo "FAIL: mint-cycle-helpers.ts missing through ${INSTALL_DIR} — link may be broken"
    fail=1
  fi

  if [[ -f "${STATE_FILE}" ]]; then
    echo "INFO: state file: ${STATE_FILE}"
    if command -v jq >/dev/null 2>&1; then
      jq . "${STATE_FILE}"
    else
      cat "${STATE_FILE}"
    fi
  else
    echo "INFO: no state file — link was not created by this script"
  fi

  return "${fail}"
}

cmd_revert() {
  if [[ ! -f "${STATE_FILE}" ]]; then
    if [[ -L "${INSTALL_DIR}" ]]; then
      die "no state file at ${STATE_FILE}; refusing to remove an unowned symlink at ${INSTALL_DIR}"
    fi
    echo "INFO: no state file and no symlink at ${INSTALL_DIR} — nothing to do"
    return 0
  fi

  local backup_dir source_dir install_dir
  backup_dir="$(read_state_field backup_dir || true)"
  source_dir="$(read_state_field source_dir || true)"
  install_dir="$(read_state_field install_dir || true)"

  [[ "${install_dir}" == "${INSTALL_DIR}" ]] ||
    die "state install_dir (${install_dir}) does not match expected (${INSTALL_DIR}) — bailing"

  if [[ -L "${INSTALL_DIR}" ]]; then
    echo "INFO: removing symlink ${INSTALL_DIR} -> $(readlink "${INSTALL_DIR}")"
    rm -- "${INSTALL_DIR}"
  elif [[ -d "${INSTALL_DIR}" ]]; then
    echo "WARN: ${INSTALL_DIR} is a real directory — not removing"
    echo "      inspect manually before retrying revert"
    return 1
  fi

  if [[ -n "${backup_dir}" && -d "${backup_dir}" ]]; then
    echo "INFO: restoring ${backup_dir} → ${INSTALL_DIR}"
    mv -- "${backup_dir}" "${INSTALL_DIR}"
  else
    echo "INFO: no backup directory to restore (was nothing to back up at link time)"
  fi

  rm -- "${STATE_FILE}"
  echo "OK: reverted — ~/.degacore/canon/templates restored from backup"
  echo "    source was: ${source_dir}"
}

# --- dispatch -------------------------------------------------------------

usage() {
  cat <<EOF
usage: $(basename "$0") <link|check|revert>

  link    back up the current ~/.degacore/canon/templates and symlink the
          develop checkout's canon/templates in its place
  check   verify the symlink is active and points at this clone
  revert  remove the symlink, restore the backup
EOF
}

cmd="${1:-}"
case "${cmd}" in
link) cmd_link ;;
check) cmd_check ;;
revert) cmd_revert ;;
-h | --help | "")
  usage
  [[ -z "${cmd}" ]] && exit 1 || exit 0
  ;;
*)
  echo "error: unknown subcommand: ${cmd}" >&2
  usage >&2
  exit 1
  ;;
esac

#!/usr/bin/env bash
# Point the global canon install at a local develop checkout so agentic
# flows (canon-cli, Conductor, orchestrator) pick up unreleased changes
# without merging to main and re-running /apply-core.
#
# Two link surfaces covered:
#   1. ~/.degacore/canon/templates/  → develop clone's canon/templates/
#   2. ~/.degacore/scripts/<canon-script>.sh → develop clone's scripts/<canon-script>.sh
#      (canon.sh, canon-scaffold.sh, canon-runner.sh, canon-live-readiness.sh —
#      the scripts that participate in the canon-start / canon-runner flow)
#
# Reversible: existing real files and directories are moved aside to
# timestamped backups; revert restores them.
#
# Subcommands:
#   link    — back up the current install pieces, symlink develop into place
#   check   — verify the symlinks are active and point at this clone
#   revert  — remove the symlinks, restore the backups
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

# Scripts on the canon test path. Listed by filename relative to
# scripts/ in the source repo and ~/.degacore/scripts/ in the install.
CANON_SCRIPTS=(
  canon.sh
  canon-scaffold.sh
  canon-runner.sh
  canon-live-readiness.sh
)

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
SOURCE_DIR=""
SOURCE_SCRIPTS_DIR=""
if [[ -n "${REPO_ROOT}" ]]; then
  SOURCE_DIR="${REPO_ROOT}/canon/templates"
  SOURCE_SCRIPTS_DIR="${REPO_ROOT}/scripts"
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
  [[ -d "${SOURCE_SCRIPTS_DIR}" ]] || die "source scripts/ not found at ${SOURCE_SCRIPTS_DIR}"
}

is_symlink_to() {
  local link="$1" want="$2"
  [[ -L "${link}" ]] || return 1
  local target
  target="$(readlink "${link}")"
  if [[ "${target}" != /* ]]; then
    target="$(cd "$(dirname "${link}")" && cd "${target}" && pwd)"
  fi
  [[ "${target}" == "${want}" ]]
}

timestamp() { date -u +"%Y%m%dT%H%M%SZ"; }

# Build a JSON object describing the linked state — templates piece +
# one entry per script. Backups (when created) carry timestamped paths
# alongside the link path so revert knows what to restore.
write_state() {
  local ts="$1"
  local templates_backup="$2"
  shift 2
  # remaining args: pairs of "install_path|backup_path" (one per script)
  local scripts_json="[]"
  if [[ $# -gt 0 ]]; then
    scripts_json="["
    local first=true
    for entry in "$@"; do
      local ip="${entry%%|*}"
      local bp="${entry#*|}"
      [[ "${first}" == true ]] && first=false || scripts_json+=","
      scripts_json+="{\"install_path\": \"${ip}\", \"backup_path\": \"${bp}\"}"
    done
    scripts_json+="]"
  fi
  cat >"${STATE_FILE}" <<EOF
{
  "linked_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "source_repo": "${REPO_ROOT}",
  "source_dir": "${SOURCE_DIR}",
  "templates": {
    "install_dir": "${INSTALL_DIR}",
    "backup_dir": "${templates_backup}"
  },
  "scripts": ${scripts_json},
  "stamp": "${ts}"
}
EOF
}

# --- subcommands ----------------------------------------------------------

cmd_link() {
  require_repo

  [[ ! -f "${STATE_FILE}" ]] ||
    die "state file already exists at ${STATE_FILE}; run \`revert\` first"

  mkdir -p "${DEGACORE}/canon" "${DEGACORE}/scripts"
  local ts
  ts="$(timestamp)"

  # --- templates ---
  local templates_backup=""
  if [[ -L "${INSTALL_DIR}" ]]; then
    echo "INFO: removing stale templates symlink → $(readlink "${INSTALL_DIR}")"
    rm -- "${INSTALL_DIR}"
  fi
  if [[ -d "${INSTALL_DIR}" ]]; then
    templates_backup="${INSTALL_DIR}.backup-${ts}"
    echo "INFO: backing up templates → ${templates_backup}"
    mv -- "${INSTALL_DIR}" "${templates_backup}"
  fi
  echo "INFO: linking ${INSTALL_DIR} -> ${SOURCE_DIR}"
  ln -s -- "${SOURCE_DIR}" "${INSTALL_DIR}"

  # canon-cli node_modules symlink — points at INSTALL_DIR, auto-follows
  if [[ ! -e "${CANON_CLI_LINK}" && ! -L "${CANON_CLI_LINK}" ]]; then
    if [[ -d "$(dirname "${CANON_CLI_LINK}")" ]]; then
      echo "INFO: creating canon-cli node_modules link"
      ln -s -- "${INSTALL_DIR}" "${CANON_CLI_LINK}"
    fi
  fi

  # --- canon scripts ---
  local entries=()
  for script in "${CANON_SCRIPTS[@]}"; do
    local install_path="${DEGACORE}/scripts/${script}"
    local source_path="${SOURCE_SCRIPTS_DIR}/${script}"
    [[ -f "${source_path}" ]] ||
      die "missing source script ${source_path} — develop checkout is incomplete?"

    local backup_path=""
    if [[ -L "${install_path}" ]]; then
      echo "INFO: removing stale ${script} symlink → $(readlink "${install_path}")"
      rm -- "${install_path}"
    fi
    if [[ -f "${install_path}" ]]; then
      backup_path="${install_path}.backup-${ts}"
      echo "INFO: backing up ${script} → ${backup_path##*/}"
      mv -- "${install_path}" "${backup_path}"
    fi
    echo "INFO: linking ${install_path##*/} -> ${source_path}"
    ln -s -- "${source_path}" "${install_path}"
    entries+=("${install_path}|${backup_path}")
  done

  write_state "${ts}" "${templates_backup}" "${entries[@]}"
  echo "OK: develop canon templates + scripts are now the global install"
  echo "    state: ${STATE_FILE}"
  echo "    revert with: scripts/dev-link-canon-templates.sh revert"
}

cmd_check() {
  require_repo
  local fail=0

  # Templates link
  if is_symlink_to "${INSTALL_DIR}" "${SOURCE_DIR}"; then
    echo "OK: ${INSTALL_DIR} -> ${SOURCE_DIR}"
  else
    echo "FAIL: ${INSTALL_DIR} is not a symlink to ${SOURCE_DIR}"
    fail=1
  fi

  if is_symlink_to "${CANON_CLI_LINK}" "${INSTALL_DIR}"; then
    echo "OK: canon-cli node_modules link → ${INSTALL_DIR}"
  elif [[ -L "${CANON_CLI_LINK}" ]]; then
    echo "FAIL: canon-cli link → $(readlink "${CANON_CLI_LINK}") (expected ${INSTALL_DIR})"
    fail=1
  else
    echo "INFO: canon-cli link absent (only matters if you use canon-cli)"
  fi

  if [[ -f "${INSTALL_DIR}/mint-cycle-helpers.ts" ]]; then
    echo "OK: develop sentinel present — mint-cycle-helpers.ts is visible through the link"
  else
    echo "FAIL: mint-cycle-helpers.ts missing through ${INSTALL_DIR}"
    fail=1
  fi

  # Scripts
  for script in "${CANON_SCRIPTS[@]}"; do
    local install_path="${DEGACORE}/scripts/${script}"
    local source_path="${SOURCE_SCRIPTS_DIR}/${script}"
    if is_symlink_to "${install_path}" "${source_path}"; then
      echo "OK: scripts/${script} → develop"
    else
      echo "FAIL: ${install_path} is not a symlink to ${source_path}"
      fail=1
    fi
  done

  if [[ -f "${STATE_FILE}" ]]; then
    echo "INFO: state file: ${STATE_FILE}"
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
    echo "INFO: no state file — nothing to do"
    return 0
  fi

  command -v jq >/dev/null 2>&1 || die "jq is required for revert"

  local templates_install templates_backup
  templates_install="$(jq -r '.templates.install_dir' "${STATE_FILE}")"
  templates_backup="$(jq -r '.templates.backup_dir' "${STATE_FILE}")"

  [[ "${templates_install}" == "${INSTALL_DIR}" ]] ||
    die "state templates.install_dir (${templates_install}) does not match expected (${INSTALL_DIR})"

  # --- templates ---
  if [[ -L "${INSTALL_DIR}" ]]; then
    echo "INFO: removing templates symlink → $(readlink "${INSTALL_DIR}")"
    rm -- "${INSTALL_DIR}"
  elif [[ -d "${INSTALL_DIR}" ]]; then
    echo "WARN: ${INSTALL_DIR} is a real directory — inspect manually before retrying revert" >&2
    return 1
  fi
  if [[ -n "${templates_backup}" && -d "${templates_backup}" ]]; then
    echo "INFO: restoring ${templates_backup##*/} → ${INSTALL_DIR}"
    mv -- "${templates_backup}" "${INSTALL_DIR}"
  fi

  # --- canon scripts ---
  local count
  count="$(jq -r '.scripts | length' "${STATE_FILE}")"
  for i in $(seq 0 $((count - 1))); do
    local install_path backup_path
    install_path="$(jq -r ".scripts[${i}].install_path" "${STATE_FILE}")"
    backup_path="$(jq -r ".scripts[${i}].backup_path" "${STATE_FILE}")"
    if [[ -L "${install_path}" ]]; then
      echo "INFO: removing ${install_path##*/} symlink"
      rm -- "${install_path}"
    fi
    if [[ -n "${backup_path}" && -f "${backup_path}" ]]; then
      echo "INFO: restoring ${backup_path##*/} → ${install_path##*/}"
      mv -- "${backup_path}" "${install_path}"
    fi
  done

  rm -- "${STATE_FILE}"
  echo "OK: reverted — templates + scripts restored from backups"
}

# --- dispatch -------------------------------------------------------------

usage() {
  cat <<EOF
usage: $(basename "$0") <link|check|revert>

  link    back up the current install, symlink develop into place
            covers: ~/.degacore/canon/templates/ AND
            ~/.degacore/scripts/{canon,canon-scaffold,canon-runner,canon-live-readiness}.sh
  check   verify the symlinks are active and point at this clone
  revert  remove the symlinks, restore the backups
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

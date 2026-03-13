#!/usr/bin/env bash
# PostToolUse hook: syncs orchestrator state when a done-file is written.
#
# Triggers on Write to .orchestrator/done/*/item-*.txt paths.
# Extracts the item ID and slug, then calls orch_update_item_status
# to mark the item "done" in state.json.
#
# This automates state sync so the orchestrator doesn't have to call
# orch-state.sh manually after each worker completes.

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "${INPUT}" | jq -r '.tool_name // empty')
[[ "${TOOL_NAME}" != "Write" ]] && exit 0

FILE_PATH=$(printf '%s' "${INPUT}" | jq -r '.tool_input.file_path // empty')
[[ -z "${FILE_PATH}" ]] && exit 0

# Only trigger for done-file writes: .orchestrator/done/<slug>/item-<ID>.txt
if ! printf '%s\n' "${FILE_PATH}" | grep -qE '\.orchestrator/done/[^/]+/item-[0-9]+\.txt$'; then
	exit 0
fi

# Extract slug and item ID from path
SLUG=$(printf '%s\n' "${FILE_PATH}" |
	grep -oE '\.orchestrator/done/[^/]+/' |
	sed 's|\.orchestrator/done/||; s|/$||')
ITEM_ID=$(printf '%s\n' "${FILE_PATH}" |
	grep -oE 'item-[0-9]+\.txt' |
	sed 's/item-//; s/\.txt//')

[[ -z "${SLUG}" || -z "${ITEM_ID}" ]] && exit 0

# Find orch-state.sh relative to this hook
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${HOOK_DIR}/../scripts"
STATE_LIB="${SCRIPTS_DIR}/orch-state.sh"

if [[ ! -f "${STATE_LIB}" ]]; then
	echo "orch-done-sync: warning: ${STATE_LIB} not found, skipping state sync" >&2
	exit 0
fi

# Locate state.json — walk up from the written file path to find .orchestrator/
ORCH_DIR=$(printf '%s\n' "${FILE_PATH}" |
	grep -oE '.*/\.orchestrator' |
	head -1)

if [[ -z "${ORCH_DIR}" || ! -f "${ORCH_DIR}/state.json" ]]; then
	echo "orch-done-sync: warning: state.json not found, skipping" >&2
	exit 0
fi

export ORCH_STATE_DIR="${ORCH_DIR}"
export ORCH_STATE_FILE="${ORCH_DIR}/state.json"

# shellcheck source=../scripts/orch-state.sh
source "${STATE_LIB}"

orch_update_item_status "${ITEM_ID}" "done"
echo "orch-done-sync: item ${ITEM_ID} (slug: ${SLUG}) marked done in state.json"

exit 0

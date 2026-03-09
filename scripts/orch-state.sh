#!/usr/bin/env bash
# Shared orchestrator state management library.
# Source this from orch-*.sh scripts — do not execute directly.
#
# Single state file model: all item state lives in .orchestrator/state.json.
# Workers report completion via done-files (.orchestrator/done/<slug>/item-N.txt)
# that the orchestrator reads — no per-item JSON state files.
#
# Provides: atomic writes, item status updates, done-file sync, and state queries.
#
# All functions expect ORCH_STATE_DIR and ORCH_STATE_FILE to be set
# by the sourcing script (defaults provided below).
#
# Requires: jq

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	echo "error: orch-state.sh is a library — source it, don't execute it" >&2
	exit 1
fi

# --- Defaults (sourcing script can override before calling functions) ---

: "${ORCH_REPO_ROOT:="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"}"
: "${ORCH_STATE_DIR:="${ORCH_REPO_ROOT}/.orchestrator"}"
: "${ORCH_STATE_FILE:="${ORCH_STATE_DIR}/state.json"}"

# --- Directory setup ---

orch_ensure_done_dir() {
	local slug="$1"
	mkdir -p "${ORCH_STATE_DIR}/done/${slug}"
}

# --- Atomic writes ---

orch_write_state() {
	local json="$1"
	local tmp
	tmp=$(mktemp "${ORCH_STATE_DIR}/state.XXXXXX.json")
	printf '%s\n' "${json}" >"${tmp}"
	mv "${tmp}" "${ORCH_STATE_FILE}"
}

# --- Item status updates ---

orch_update_item_status() {
	local item_id="$1"
	local new_status="$2"
	local now
	now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

	local updated
	updated=$(jq \
		--argjson id "${item_id}" \
		--arg status "${new_status}" \
		--arg now "${now}" \
		'(.items[] | select(.id == $id)).status = $status |
     .updatedAt = $now' "${ORCH_STATE_FILE}")
	orch_write_state "${updated}"
}

# --- Sync done-files into state ---

orch_sync_done_files() {
	local slug="$1"
	local done_dir="${ORCH_STATE_DIR}/done/${slug}"
	local state
	state=$(cat "${ORCH_STATE_FILE}")
	local changed=false

	local running_ids
	running_ids=$(printf '%s' "${state}" | jq -r \
		'.items[] | select(.status == "running") | .id')

	for item_id in ${running_ids}; do
		local done_file="${done_dir}/item-${item_id}.txt"
		if [[ -f "${done_file}" ]]; then
			local now
			now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
			state=$(printf '%s' "${state}" | jq \
				--argjson id "${item_id}" \
				--arg now "${now}" \
				'(.items[] | select(.id == $id)) |=
          (.status = "done" | .lastResult = "SHIP") |
         .updatedAt = $now')
			changed=true
			echo "orch-state: item ${item_id} done-file found — marked done"
		fi
	done

	if [[ "${changed}" == "true" ]]; then
		orch_write_state "${state}"
	fi
}

# --- Queries ---

orch_count_by_status() {
	local status="$1"
	jq "[.items[] | select(.status == \"${status}\")] | length" \
		"${ORCH_STATE_FILE}"
}

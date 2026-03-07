#!/usr/bin/env bash
# Shared orchestrator state management library.
# Source this from orch-*.sh scripts — do not execute directly.
#
# Provides: directory setup, atomic writes, per-item updates,
# dead worker pruning, and state queries.
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

orch_ensure_dirs() {
	local slug="$1"
	mkdir -p "${ORCH_STATE_DIR}/items/${slug}"
}

# --- Atomic writes ---

orch_write_state() {
	local json="$1"
	local tmp
	tmp=$(mktemp "${ORCH_STATE_DIR}/state.XXXXXX.json")
	printf '%s\n' "${json}" >"${tmp}"
	mv "${tmp}" "${ORCH_STATE_FILE}"
}

orch_write_item() {
	local slug="$1"
	local item_id="$2"
	local json="$3"
	local items_dir="${ORCH_STATE_DIR}/items/${slug}"
	local item_file="${items_dir}/item-${item_id}.json"
	local tmp
	tmp=$(mktemp "${items_dir}/item-${item_id}.XXXXXX.json")
	printf '%s\n' "${json}" >"${tmp}"
	mv "${tmp}" "${item_file}"
}

# --- Item status updates ---

orch_update_item_status() {
	local slug="$1"
	local item_id="$2"
	local new_status="$3"
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

	local item_file="${ORCH_STATE_DIR}/items/${slug}/item-${item_id}.json"
	if [[ -f "${item_file}" ]]; then
		local item_updated
		item_updated=$(jq --arg status "${new_status}" '.status = $status' "${item_file}")
		orch_write_item "${slug}" "${item_id}" "${item_updated}"
	fi
}

orch_mark_item_stopped() {
	local slug="$1"
	local item_id="$2"
	local now
	now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

	local updated
	updated=$(jq \
		--argjson id "${item_id}" \
		--arg now "${now}" \
		'(.items[] | select(.id == $id)) |=
      (.status = "stopped" | .workerPid = null | .tmuxPane = null) |
     .updatedAt = $now' "${ORCH_STATE_FILE}")
	orch_write_state "${updated}"

	local item_file="${ORCH_STATE_DIR}/items/${slug}/item-${item_id}.json"
	if [[ -f "${item_file}" ]]; then
		local item_updated
		item_updated=$(jq \
			'.status = "stopped" | .workerPid = null | .tmuxPane = null' \
			"${item_file}")
		orch_write_item "${slug}" "${item_id}" "${item_updated}"
	fi
}

# --- Sync and prune ---

orch_sync_item_state() {
	local slug="$1"
	local items_dir="${ORCH_STATE_DIR}/items/${slug}"
	local state
	state=$(cat "${ORCH_STATE_FILE}")
	local changed=false

	local item_count
	item_count=$(printf '%s' "${state}" | jq '.items | length')

	for i in $(seq 0 $((item_count - 1))); do
		local item_id
		item_id=$(printf '%s' "${state}" | jq -r ".items[$i].id")
		local item_file="${items_dir}/item-${item_id}.json"

		if [[ ! -f "${item_file}" ]]; then
			continue
		fi

		local file_status state_status
		file_status=$(jq -r '.status' "${item_file}")
		state_status=$(printf '%s' "${state}" | jq -r ".items[$i].status")

		if [[ "${file_status}" != "${state_status}" ]]; then
			state=$(printf '%s' "${state}" | jq \
				--argjson idx "$i" \
				--arg status "${file_status}" \
				'.items[$idx].status = $status')
			changed=true
		fi

		local file_iter state_iter
		file_iter=$(jq -r '.iteration // 0' "${item_file}")
		state_iter=$(printf '%s' "${state}" | jq -r ".items[$i].iteration")

		if [[ "${file_iter}" != "${state_iter}" ]]; then
			state=$(printf '%s' "${state}" | jq \
				--argjson idx "$i" \
				--argjson iter "${file_iter}" \
				'.items[$idx].iteration = $iter')
			changed=true
		fi

		local file_result state_result
		file_result=$(jq -r '.lastResult // "null"' "${item_file}")
		state_result=$(printf '%s' "${state}" | jq -r ".items[$i].lastResult // \"null\"")

		if [[ "${file_result}" != "${state_result}" ]]; then
			state=$(printf '%s' "${state}" | jq \
				--argjson idx "$i" \
				--arg result "${file_result}" \
				'if $result == "null" then .items[$idx].lastResult = null
         else .items[$idx].lastResult = $result end')
			changed=true
		fi
	done

	if [[ "${changed}" == "true" ]]; then
		local now
		now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
		state=$(printf '%s' "${state}" | jq --arg now "${now}" '.updatedAt = $now')
		orch_write_state "${state}"
	fi
}

orch_prune_dead_workers() {
	local slug="$1"
	local state
	state=$(cat "${ORCH_STATE_FILE}")
	local mode
	mode=$(printf '%s' "${state}" | jq -r '.mode')
	local changed=false

	local running_ids
	running_ids=$(printf '%s' "${state}" | jq -r \
		'.items[] | select(.status == "running") | .id')

	for item_id in ${running_ids}; do
		local alive=true

		if [[ "${mode}" == "foreground" ]]; then
			local session="orch-${slug}"
			if ! tmux has-session -t "${session}" 2>/dev/null; then
				alive=false
			fi
		else
			local bg_session="orch-${slug}-item-${item_id}"
			if ! tmux has-session -t "${bg_session}" 2>/dev/null; then
				alive=false
			fi
		fi

		if [[ "${alive}" == "false" ]]; then
			local now
			now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
			state=$(printf '%s' "${state}" | jq \
				--argjson id "${item_id}" \
				--arg now "${now}" \
				'(.items[] | select(.id == $id)) |=
          (.status = "stopped" | .workerPid = null | .tmuxPane = null) |
         .updatedAt = $now')
			changed=true
			echo "orch-state: item ${item_id} worker is dead — marked stopped"
		fi
	done

	if [[ "${changed}" == "true" ]]; then
		orch_write_state "${state}"
	fi
}

# --- Queries ---

orch_get_plan() {
	jq -r '.plan' "${ORCH_STATE_FILE}"
}

orch_get_mode() {
	jq -r '.mode' "${ORCH_STATE_FILE}"
}

orch_count_by_status() {
	local status="$1"
	jq "[.items[] | select(.status == \"${status}\")] | length" \
		"${ORCH_STATE_FILE}"
}

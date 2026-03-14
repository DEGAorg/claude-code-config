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

# --- Promotion (queued → ready when deps satisfied) ---

orch_promote_ready_items() {
	local state
	state=$(cat "${ORCH_STATE_FILE}")

	local before_ready
	before_ready=$(printf '%s' "${state}" | jq \
		'[.items[] | select(.status == "ready")] | length')

	local now
	now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

	local updated
	updated=$(printf '%s' "${state}" | jq --arg now "${now}" '
		.items as $all |
		.items = [
			$all[] | . as $item |
			if $item.status == "queued" then
				if ($item.deps | length) == 0 then
					.status = "ready"
				elif ([$all[] | select(.id == ($item.deps[])) | .status] | all(. == "done")) then
					.status = "ready"
				else .
				end
			else .
			end
		] |
		.updatedAt = $now
	')

	local after_ready
	after_ready=$(printf '%s' "${updated}" | jq \
		'[.items[] | select(.status == "ready")] | length')

	local promoted=$((after_ready - before_ready))

	if ((promoted > 0)); then
		orch_write_state "${updated}"
		echo "orch-state: promoted ${promoted} item(s) from queued to ready"
	fi

	return 0
}

# --- Stale worker detection ---

orch_detect_stale_workers() {
	local slug="$1"
	local tmux_session="orch-${slug}"

	# Bail if tmux session doesn't exist
	if ! tmux has-session -t "${tmux_session}" 2>/dev/null; then
		return 0
	fi

	local state
	state=$(cat "${ORCH_STATE_FILE}")

	local running_ids
	running_ids=$(printf '%s' "${state}" | jq -r \
		'.items[] | select(.status == "running") | .id')

	if [[ -z "${running_ids}" ]]; then
		return 0
	fi

	# Get live (non-dead) worker windows from tmux
	# Format: "worker-N 0" or "worker-N 1" where 1 = pane_dead
	local live_workers
	live_workers=$(tmux list-windows -t "${tmux_session}" \
		-F '#{window_name} #{pane_dead}' 2>/dev/null || true)

	local changed=false
	local now
	now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

	for item_id in ${running_ids}; do
		local pane_name="worker-${item_id}"
		local is_alive=false

		# Check if pane exists and is not dead
		if printf '%s\n' "${live_workers}" | grep -q "^${pane_name} 0$"; then
			is_alive=true
		fi

		if [[ "${is_alive}" == false ]]; then
			# Worker pane is gone or dead — item is stale
			local cur_iter max_iter
			cur_iter=$(printf '%s' "${state}" | jq \
				".items[] | select(.id == ${item_id}) | .iteration // 0")
			max_iter=$(printf '%s' "${state}" | jq \
				".items[] | select(.id == ${item_id}) | .maxIterations // 3")

			local next_iter=$((cur_iter + 1))

			if ((next_iter >= max_iter)); then
				# Exhausted retries — mark failed
				state=$(printf '%s' "${state}" | jq \
					--argjson id "${item_id}" \
					--arg now "${now}" \
					'(.items[] | select(.id == $id)) |=
					  (.status = "failed" | .lastResult = "stale-max-retries") |
					 .updatedAt = $now')
				echo "orch-state: item ${item_id} stale — max retries exhausted, marked failed"
			else
				# Reset to ready for retry
				state=$(printf '%s' "${state}" | jq \
					--argjson id "${item_id}" \
					--argjson iter "${next_iter}" \
					--arg now "${now}" \
					'(.items[] | select(.id == $id)) |=
					  (.status = "ready" | .iteration = $iter | .lastResult = "stale-retry") |
					 .updatedAt = $now')
				echo "orch-state: item ${item_id} stale — reset to ready (iteration ${next_iter})"
			fi
			changed=true
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

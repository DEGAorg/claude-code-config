#!/usr/bin/env bash
# Shared orchestrator state management library.
# Source this from orch-*.sh scripts — do not execute directly.
#
# Multi-plan model: each plan's state lives under .orchestrator/plans/<slug>/.
# A master registry (.orchestrator/master.json) tracks all running plans.
# Workers report completion via done-files (plans/<slug>/done/item-N.txt)
# that the orchestrator reads — no per-item JSON state files.
#
# Provides: atomic writes, item status updates, done-file sync, state queries,
# master state registry, and worktree helpers.
#
# All functions expect ORCH_STATE_DIR to be set by the sourcing script
# (default provided below). Per-plan paths are derived from the slug.
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
: "${ORCH_MASTER_FILE:="${ORCH_STATE_DIR}/master.json"}"

# --- Per-plan path helpers ---

orch_plan_dir() {
	local slug="$1"
	printf '%s/plans/%s' "${ORCH_STATE_DIR}" "${slug}"
}

orch_plan_state_file() {
	local slug="$1"
	printf '%s/state.json' "$(orch_plan_dir "${slug}")"
}

orch_plan_done_dir() {
	local slug="$1"
	printf '%s/done' "$(orch_plan_dir "${slug}")"
}

orch_plan_review_dir() {
	local slug="$1"
	printf '%s/reviews' "$(orch_plan_dir "${slug}")"
}

orch_plan_log_dir() {
	local slug="$1"
	printf '%s/logs' "$(orch_plan_dir "${slug}")"
}

# --- Directory setup ---

orch_ensure_plan_dirs() {
	local slug="$1"
	mkdir -p "$(orch_plan_done_dir "${slug}")"
	mkdir -p "$(orch_plan_review_dir "${slug}")"
	mkdir -p "$(orch_plan_log_dir "${slug}")"
}

# --- Atomic writes ---

orch_write_state() {
	local slug="$1"
	local json="$2"
	local state_file
	state_file=$(orch_plan_state_file "${slug}")
	local plan_dir
	plan_dir=$(orch_plan_dir "${slug}")

	mkdir -p "${plan_dir}"
	local tmp
	tmp=$(mktemp "${plan_dir}/state.XXXXXX.json")
	printf '%s\n' "${json}" >"${tmp}"
	mv "${tmp}" "${state_file}"
}

orch_write_master() {
	local json="$1"
	mkdir -p "${ORCH_STATE_DIR}"
	local tmp
	tmp=$(mktemp "${ORCH_STATE_DIR}/master.XXXXXX.json")
	printf '%s\n' "${json}" >"${tmp}"
	mv "${tmp}" "${ORCH_MASTER_FILE}"
}

# --- Item status updates ---

orch_update_item_status() {
	local slug="$1"
	local item_id="$2"
	local new_status="$3"
	local state_file
	state_file=$(orch_plan_state_file "${slug}")
	local now
	now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

	local updated
	updated=$(jq \
		--argjson id "${item_id}" \
		--arg status "${new_status}" \
		--arg now "${now}" \
		'(.items[] | select(.id == $id)).status = $status |
     .updatedAt = $now' "${state_file}")
	orch_write_state "${slug}" "${updated}"
}

# --- Sync done-files into state ---

orch_sync_done_files() {
	local slug="$1"
	local done_dir
	done_dir=$(orch_plan_done_dir "${slug}")
	local state_file
	state_file=$(orch_plan_state_file "${slug}")
	local state
	state=$(cat "${state_file}")
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
		orch_write_state "${slug}" "${state}"
	fi
}

# --- Promotion (queued → ready when deps satisfied) ---

orch_promote_ready_items() {
	local slug="$1"
	local state_file
	state_file=$(orch_plan_state_file "${slug}")
	local state
	state=$(cat "${state_file}")

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
		orch_write_state "${slug}" "${updated}"
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

	local state_file
	state_file=$(orch_plan_state_file "${slug}")
	local state
	state=$(cat "${state_file}")

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
		orch_write_state "${slug}" "${state}"
	fi
}

# --- Master state registry ---

orch_master_register() {
	local slug="$1"
	local tmux_session="orch-${slug}"
	local now
	now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

	local master
	if [[ -f "${ORCH_MASTER_FILE}" ]]; then
		master=$(cat "${ORCH_MASTER_FILE}")
		# Remove stale entry for same slug if present
		master=$(printf '%s' "${master}" | jq \
			--arg slug "${slug}" \
			'.plans = [.plans[] | select(.slug != $slug)]')
	else
		master='{"version":1,"plans":[],"updatedAt":""}'
	fi

	local state_path="plans/${slug}/state.json"
	local worktree_path="worktrees/${slug}"

	master=$(printf '%s' "${master}" | jq \
		--arg slug "${slug}" \
		--arg status "running" \
		--arg statePath "${state_path}" \
		--arg tmux "${tmux_session}" \
		--arg worktree "${worktree_path}" \
		--arg now "${now}" \
		'.plans += [{
			slug: $slug,
			status: $status,
			statePath: $statePath,
			tmuxSession: $tmux,
			worktree: $worktree,
			startedAt: $now,
			updatedAt: $now,
			progress: { total: 0, done: 0, running: 0, failed: 0 }
		}] |
		.updatedAt = $now')

	orch_write_master "${master}"
	echo "orch-state: registered plan ${slug} in master state"
}

orch_master_deregister() {
	local slug="$1"
	local final_status="${2:-completed}"

	if [[ ! -f "${ORCH_MASTER_FILE}" ]]; then
		return 0
	fi

	local now
	now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

	local master
	master=$(jq \
		--arg slug "${slug}" \
		--arg status "${final_status}" \
		--arg now "${now}" \
		'(.plans[] | select(.slug == $slug)) |=
			(.status = $status | .updatedAt = $now) |
		 .updatedAt = $now' "${ORCH_MASTER_FILE}")

	orch_write_master "${master}"
	echo "orch-state: deregistered plan ${slug} (status: ${final_status})"
}

orch_master_update_progress() {
	local slug="$1"

	if [[ ! -f "${ORCH_MASTER_FILE}" ]]; then
		return 0
	fi

	local state_file
	state_file=$(orch_plan_state_file "${slug}")
	if [[ ! -f "${state_file}" ]]; then
		return 0
	fi

	local cnt_total cnt_done cnt_running cnt_failed
	cnt_total=$(jq '.items | length' "${state_file}")
	cnt_done=$(jq '[.items[] | select(.status == "done")] | length' "${state_file}")
	cnt_running=$(jq '[.items[] | select(.status == "running")] | length' "${state_file}")
	cnt_failed=$(jq '[.items[] | select(.status == "failed")] | length' "${state_file}")

	local now
	now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

	local master
	master=$(jq \
		--arg slug "${slug}" \
		--argjson total "${cnt_total}" \
		--argjson cnt_done "${cnt_done}" \
		--argjson running "${cnt_running}" \
		--argjson failed "${cnt_failed}" \
		--arg now "${now}" \
		'(.plans[] | select(.slug == $slug)) |=
			(.progress = {
				total: $total,
				done: $cnt_done,
				running: $running,
				failed: $failed
			} | .updatedAt = $now) |
		 .updatedAt = $now' "${ORCH_MASTER_FILE}")

	orch_write_master "${master}"
}

# --- Worktree helpers ---

orch_create_worktree() {
	local slug="$1"
	local worktree_dir="${ORCH_STATE_DIR}/worktrees/${slug}"

	if [[ -d "${worktree_dir}" ]]; then
		echo "orch-state: worktree already exists at ${worktree_dir}"
		return 0
	fi

	local branch="orch/${slug}"
	mkdir -p "${ORCH_STATE_DIR}/worktrees"
	git -C "${ORCH_REPO_ROOT}" worktree add "${worktree_dir}" -b "${branch}" HEAD
	echo "orch-state: created worktree at ${worktree_dir} on branch ${branch}"
}

orch_cleanup_worktree() {
	local slug="$1"
	local worktree_dir="${ORCH_STATE_DIR}/worktrees/${slug}"

	if [[ ! -d "${worktree_dir}" ]]; then
		echo "orch-state: no worktree at ${worktree_dir} — nothing to clean up"
		return 0
	fi

	git -C "${ORCH_REPO_ROOT}" worktree remove "${worktree_dir}" --force
	echo "orch-state: removed worktree at ${worktree_dir}"

	local branch="orch/${slug}"
	if git -C "${ORCH_REPO_ROOT}" rev-parse --verify "${branch}" >/dev/null 2>&1; then
		git -C "${ORCH_REPO_ROOT}" branch -D "${branch}"
		echo "orch-state: deleted branch ${branch}"
	fi
}

# --- Kill finished worker windows ---

orch_kill_done_workers() {
	local slug="$1"
	local tmux_session="orch-${slug}"

	if ! tmux has-session -t "${tmux_session}" 2>/dev/null; then
		return 0
	fi

	local state_file
	state_file=$(orch_plan_state_file "${slug}")
	if [[ ! -f "${state_file}" ]]; then
		return 0
	fi

	local done_ids
	done_ids=$(jq -r '.items[] | select(.status == "done") | .id' "${state_file}")

	if [[ -z "${done_ids}" ]]; then
		return 0
	fi

	local live_windows
	live_windows=$(tmux list-windows -t "${tmux_session}" \
		-F '#{window_name}' 2>/dev/null || true)

	for item_id in ${done_ids}; do
		local window_name="worker-${item_id}"
		if printf '%s\n' "${live_windows}" | grep -qx "${window_name}"; then
			tmux kill-window -t "${tmux_session}:${window_name}" 2>/dev/null || true
			echo "orch-state: killed finished worker window ${window_name}"
		fi
	done
}

# --- Queries ---

orch_count_by_status() {
	local slug="$1"
	local status="$2"
	local state_file
	state_file=$(orch_plan_state_file "${slug}")
	jq "[.items[] | select(.status == \"${status}\")] | length" \
		"${state_file}"
}

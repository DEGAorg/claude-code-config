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

: "${ORCH_REPO_ROOT:="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"}"
: "${ORCH_STATE_DIR:="${ORCH_REPO_ROOT}/.orchestrator"}"
: "${ORCH_MASTER_FILE:="${ORCH_STATE_DIR}/master.json"}"

# --- Config file resolution (dega-core.yaml with ralph.yaml fallback) ---

# Resolve the project config file path. Checks dega-core.yaml first,
# falls back to ralph.yaml with a deprecation warning. Returns empty
# string if neither exists.
orch_resolve_config() {
	if [[ -f "${ORCH_REPO_ROOT}/dega-core.yaml" ]]; then
		printf '%s/dega-core.yaml' "${ORCH_REPO_ROOT}"
	elif [[ -f "${ORCH_REPO_ROOT}/ralph.yaml" ]]; then
		echo "orch-state: WARNING — ralph.yaml is deprecated, rename to dega-core.yaml" >&2
		printf '%s/ralph.yaml' "${ORCH_REPO_ROOT}"
	else
		printf ''
	fi
}

# Read a YAML key from the project config file. Returns the value or
# empty string if the key or file is not found.
#   Usage: value=$(orch_read_config "poll_interval_seconds")
orch_read_config() {
	local key="$1"
	local config_file
	config_file=$(orch_resolve_config)

	if [[ -z "${config_file}" ]]; then
		printf ''
		return 0
	fi

	local value
	value=$(grep "${key}:" "${config_file}" 2>/dev/null |
		awk '{print $2}' | tr -d ' ' || true)
	printf '%s' "${value}"
}

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

orch_plan_log_file() {
	local slug="$1"
	printf '%s/engine.log' "$(orch_plan_log_dir "${slug}")"
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

	local worktree_dir="${ORCH_STATE_DIR}/worktrees/${slug}"

	local running_ids
	running_ids=$(printf '%s' "${state}" | jq -r \
		'.items[] | select(.status == "running") | .id')

	for item_id in ${running_ids}; do
		local done_file="${done_dir}/item-${item_id}.txt"
		if [[ -f "${done_file}" ]]; then
			# Warn on done-files smaller than 20 bytes but accept them —
			# the reviewer will catch garbage content
			local file_size
			file_size=$(wc -c <"${done_file}")
			if ((file_size < 20)); then
				echo "orch-state: WARNING — item ${item_id} done-file small (${file_size} bytes < 20), accepting for review"
			fi

			# Check if worker changed files in the worktree
			# Accept with warning if no changes — a sibling worker may have
			# already committed the needed work (common with overlapping items)
			if [[ -d "${worktree_dir}" ]]; then
				local has_changes
				has_changes=$(git -C "${worktree_dir}" \
					diff --stat HEAD 2>/dev/null || true)
				local has_staged
				has_staged=$(git -C "${worktree_dir}" \
					diff --cached --stat HEAD 2>/dev/null || true)
				local has_untracked
				has_untracked=$(git -C "${worktree_dir}" \
					ls-files --others --exclude-standard 2>/dev/null || true)

				if [[ -z "${has_changes}" && -z "${has_staged}" && -z "${has_untracked}" ]]; then
					echo "orch-state: item ${item_id} done-file exists but no new file changes — accepting (sibling may have done the work)"
				fi
			fi

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

			# Fetch description for commit message and checkbox check
			local item_desc
			item_desc=$(printf '%s' "${state}" | jq -r \
				--argjson id "${item_id}" \
				'.items[] | select(.id == $id) | .description // ""')

			# Commit worktree changes for this item (progress resilience)
			if [[ -d "${worktree_dir}" ]]; then
				local wt_changes
				wt_changes=$(git -C "${worktree_dir}" status --porcelain 2>/dev/null || true)
				if [[ -n "${wt_changes}" ]]; then
					git -C "${worktree_dir}" add -A
					if git -C "${worktree_dir}" commit --no-verify \
						-m "orch: item ${item_id} — ${item_desc}"; then
						echo "orch-state: committed item ${item_id} changes in worktree"
					else
						echo "orch-state: WARNING — failed to commit item ${item_id} in worktree (exit $?)" >&2
					fi
				fi
			fi

			# Warn if the plan.md checkbox is still unchecked
			local plan_file="${ORCH_REPO_ROOT}/docs/exec-plans/active/${slug}/plan.md"
			if [[ -f "${plan_file}" ]]; then
				if [[ -n "${item_desc}" ]]; then
					local escaped_desc
					# shellcheck disable=SC2016 # \& is a sed backreference, not shell expansion
					escaped_desc=$(printf '%s' "${item_desc}" | sed 's/[.[\*^$()+?{|]/\\&/g')
					if grep -q "^- \[ \] ${escaped_desc}" "${plan_file}"; then
						echo "orch-state: WARNING — item ${item_id} done but plan.md checkbox is unchecked"
					fi
				fi
			fi
		fi
	done

	if [[ "${changed}" == "true" ]]; then
		orch_write_state "${slug}" "${state}"
	fi
}

# --- Sync review files into state ---

orch_sync_review_files() {
	local slug="$1"
	local review_dir
	review_dir=$(orch_plan_review_dir "${slug}")
	local state_file
	state_file=$(orch_plan_state_file "${slug}")
	local state
	state=$(cat "${state_file}")
	local changed=false

	local reviewing_ids
	reviewing_ids=$(printf '%s' "${state}" | jq -r \
		'.items[] | select(.reviewStatus == "reviewing") | .id')

	if [[ -z "${reviewing_ids}" ]]; then
		return 0
	fi

	local now
	now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

	for item_id in ${reviewing_ids}; do
		local review_file="${review_dir}/item-${item_id}-review.txt"
		if [[ -f "${review_file}" ]]; then
			local decision
			decision=$(head -1 "${review_file}" | tr -d '[:space:]')

			case "${decision}" in
			PASS)
				state=$(printf '%s' "${state}" | jq \
					--argjson id "${item_id}" \
					--arg now "${now}" \
					'(.items[] | select(.id == $id)).reviewStatus = "passed" |
					 .updatedAt = $now')
				echo "orch-state: item ${item_id} review — PASS"
				;;
			FAIL)
				state=$(printf '%s' "${state}" | jq \
					--argjson id "${item_id}" \
					--arg now "${now}" \
					'(.items[] | select(.id == $id)).reviewStatus = "failed" |
					 .updatedAt = $now')
				echo "orch-state: item ${item_id} review — FAIL"
				;;
			*)
				state=$(printf '%s' "${state}" | jq \
					--argjson id "${item_id}" \
					--arg now "${now}" \
					'(.items[] | select(.id == $id)).reviewStatus = "failed" |
					 .updatedAt = $now')
				echo "orch-state: item ${item_id} review — unexpected decision '${decision}', marking failed"
				;;
			esac
			changed=true
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

orch_commit_worktree() {
	local slug="$1"
	local worktree_dir="${ORCH_STATE_DIR}/worktrees/${slug}"

	if [[ ! -d "${worktree_dir}" ]]; then
		echo "orch-state: no worktree to commit"
		return 0
	fi

	# Check for any changes (staged, unstaged, or untracked)
	local has_changes
	has_changes=$(git -C "${worktree_dir}" status --porcelain 2>/dev/null || true)

	if [[ -z "${has_changes}" ]]; then
		echo "orch-state: worktree has no changes to commit"
		return 0
	fi

	# Stage and commit all changes in the worktree
	git -C "${worktree_dir}" add -A
	if git -C "${worktree_dir}" commit --no-verify -m "orch: ${slug} — worker changes

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"; then
		echo "orch-state: committed worker changes in worktree"
	else
		echo "orch-state: WARNING — failed to commit worktree changes for ${slug} (exit $?)" >&2
	fi
}

orch_merge_worktree() {
	local slug="$1"
	local worktree_dir="${ORCH_STATE_DIR}/worktrees/${slug}"
	local branch="orch/${slug}"

	if [[ ! -d "${worktree_dir}" ]]; then
		echo "orch-state: no worktree to merge"
		return 0
	fi

	# Commit any uncommitted changes in the worktree
	orch_commit_worktree "${slug}"

	# Commit any dirty files in the main repo to avoid merge conflicts
	local main_dirty
	main_dirty=$(git -C "${ORCH_REPO_ROOT}" status --porcelain 2>/dev/null || true)
	if [[ -n "${main_dirty}" ]]; then
		git -C "${ORCH_REPO_ROOT}" add -A
		if git -C "${ORCH_REPO_ROOT}" commit --no-verify -m "orch: auto-commit before merging ${slug}

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"; then
			echo "orch-state: committed dirty files in main repo before merge"
		else
			echo "orch-state: WARNING — failed to auto-commit main repo before merging ${slug} (exit $?)" >&2
		fi
	fi

	# Check if the worktree branch has commits ahead of the source
	local source_branch
	source_branch=$(git -C "${ORCH_REPO_ROOT}" rev-parse --abbrev-ref HEAD)
	local ahead
	ahead=$(git -C "${ORCH_REPO_ROOT}" rev-list \
		"${source_branch}..${branch}" --count 2>/dev/null || echo "0")

	if [[ "${ahead}" -eq 0 ]]; then
		echo "orch-state: worktree branch has no new commits to merge"
		return 0
	fi

	# Merge the worktree branch, auto-resolving plan.md conflicts
	if git -C "${ORCH_REPO_ROOT}" merge "${branch}" \
		--no-edit -m "orch: merge ${slug} worker changes"; then
		echo "orch-state: merged ${ahead} commit(s) from ${branch} into ${source_branch}"
	else
		# Resolve conflicts by taking the worktree version (workers have latest state)
		local conflicted
		conflicted=$(git -C "${ORCH_REPO_ROOT}" diff --name-only --diff-filter=U)
		if [[ -n "${conflicted}" ]]; then
			echo "orch-state: resolving merge conflicts (taking worktree version)"
			echo "${conflicted}" | while IFS= read -r f; do
				git -C "${ORCH_REPO_ROOT}" checkout --theirs -- "${f}"
				git -C "${ORCH_REPO_ROOT}" add "${f}"
			done
			git -C "${ORCH_REPO_ROOT}" commit --no-edit
			echo "orch-state: merged ${ahead} commit(s) with conflict resolution"
		else
			echo "orch-state: merge failed for unknown reason" >&2
			git -C "${ORCH_REPO_ROOT}" merge --abort 2>/dev/null || true
			return 1
		fi
	fi
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

# --- Plan registry ---

orch_registry_append() {
	local slug="$1" status="$2" iterations="$3" method="$4"
	local registry="${ORCH_REPO_ROOT}/docs/exec-plans/REGISTRY.md"
	local date
	date=$(date -u +"%Y-%m-%d")

	# Create file with header if missing
	if [[ ! -f "${registry}" ]]; then
		mkdir -p "$(dirname "${registry}")"
		printf '# Plan Registry\n\n' >"${registry}"
		printf '| Date | Slug | Status | Iterations | Method |\n' >>"${registry}"
		printf '|------|------|--------|------------|--------|\n' >>"${registry}"
	fi

	# Build link to plan.md (completed plans live under completed/)
	local link
	if [[ "${status}" == "completed" ]]; then
		link="[${slug}](completed/${slug}/plan.md)"
	else
		link="[${slug}](active/${slug}/plan.md)"
	fi

	printf '| %s | %s | %s | %s | %s |\n' \
		"${date}" "${link}" "${status}" "${iterations}" "${method}" \
		>>"${registry}"
}

# --- Changelog ---

orch_changelog_append() {
	local slug="$1" title="$2" category="${3:-}"
	local changelog="${ORCH_REPO_ROOT}/CHANGELOG.md"

	# Auto-detect category from title keywords if not provided
	if [[ -z "${category}" ]]; then
		local lower_title
		lower_title=$(printf '%s' "${title}" | tr '[:upper:]' '[:lower:]')
		case "${lower_title}" in
		*fix* | *bug* | *patch*) category="Fixed" ;;
		*add* | *new* | *create* | *introduce*) category="Added" ;;
		*remove* | *delete* | *drop*) category="Removed" ;;
		*) category="Changed" ;;
		esac
	fi

	local date
	date=$(date -u +"%Y-%m-%d")

	# Create file with Keep a Changelog header if missing
	if [[ ! -f "${changelog}" ]]; then
		{
			printf '# Changelog\n\n'
			printf 'All notable changes to this project will be documented in this file.\n\n'
			printf 'The format is based on [Keep a Changelog](https://keepachangelog.com/).\n\n'
			printf '## [Unreleased]\n'
		} >"${changelog}"
	fi

	# Insert [Unreleased] section if missing
	if ! grep -q '## \[Unreleased\]' "${changelog}"; then
		local tmp
		tmp=$(mktemp "${changelog}.XXXXXX")
		awk '
			/^# Changelog/ { print; found_header = 1; next }
			found_header && !inserted && /^$/ {
				print ""
				print "## [Unreleased]"
				inserted = 1
			}
			{ print }
		' "${changelog}" >"${tmp}"
		mv "${tmp}" "${changelog}"
	fi

	# Build the entry line
	local entry="- ${title} (\`${slug}\`) — ${date}"

	# Insert entry under the correct category within [Unreleased]
	# If the category heading exists, append after it; otherwise create it
	local tmp
	tmp=$(mktemp "${changelog}.XXXXXX")
	awk -v cat="${category}" -v entry="${entry}" '
		/^## \[Unreleased\]/ { in_unreleased = 1; print; next }
		in_unreleased && $0 == "### " cat {
			print
			getline
			print entry
			if ($0 != "") print ""
			print
			in_unreleased = 0
			found_cat = 1
			next
		}
		in_unreleased && /^## / {
			# Hit next version section — category not found, insert before it
			print ""
			print "### " cat
			print entry
			print ""
			in_unreleased = 0
			found_cat = 1
		}
		{ print }
		END {
			if (!found_cat) {
				# [Unreleased] was last section — append at end
				print ""
				print "### " cat
				print entry
			}
		}
	' "${changelog}" >"${tmp}"
	mv "${tmp}" "${changelog}"
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

# --- Completion criteria helpers ---

orch_count_unchecked_criteria() {
	local plan_file="$1"
	if [[ ! -f "${plan_file}" ]]; then
		echo "0"
		return 0
	fi
	awk '
		/^```/ { fence = !fence; next }
		fence { next }
		/^## Completion criteria/ { capturing = 1; next }
		capturing && /^## / { capturing = 0; next }
		capturing && /^- \[ \]/ { count++ }
		END { print count+0 }
	' "${plan_file}"
}

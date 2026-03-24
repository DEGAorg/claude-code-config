#!/usr/bin/env bash
# Planner loop — autonomous agent that reads focus.yaml, decides what to
# work on, creates execution plans, launches the orchestrator, and repeats
# until budget is exhausted or all focus areas are addressed.
#
# Each Claude invocation is a fresh `claude -p` call. The bash script is
# the long-lived process; Claude instances are short-lived tools.
#
# Usage: scripts/planner-loop.sh [--dry-run] [--background] [--create-plans] [--plan-only]
#
# Options:
#   --dry-run        Run ASSESS phase only, print decision, do not execute
#   --background     Pass --background to orch-run.sh (headless tmux)
#   --create-plans   Enable plan creation (experimental). Without this flag,
#                    the planner only executes existing active plans.
#   --plan-only      Create plans locally without committing or executing.
#                    Generates a review file with consolidated questions.
#                    Implies --create-plans.
#
# Example: scripts/planner-loop.sh                    # execute existing plans only
# Example: scripts/planner-loop.sh --create-plans     # also create new plans
# Example: scripts/planner-loop.sh --plan-only        # create plans for review only
# Example: scripts/planner-loop.sh --dry-run          # assess only, no execution

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"
# shellcheck source=read-github-config.sh
source "${SCRIPT_DIR}/read-github-config.sh"

# --- Constants ---

LOG_DIR="${HOME}/.claude/planner"
FOCUS_FILE="${REPO_ROOT}/focus.yaml"
TECH_DEBT_FILE="${REPO_ROOT}/docs/exec-plans/tech-debt.md"
QUALITY_FILE="${REPO_ROOT}/docs/QUALITY.md"
REGISTRY_FILE="${REPO_ROOT}/docs/exec-plans/REGISTRY.md"
ACTIVE_PLANS_DIR="${REPO_ROOT}/docs/exec-plans/active"
ASSESS_PROMPT="${SCRIPT_DIR}/../agents/planner-assess.md"
WRITER_PROMPT="${SCRIPT_DIR}/../agents/planner-writer.md"

PREFIX="planner"

# --- Parse args ---

DRY_RUN=false
BACKGROUND=false
CREATE_PLANS=false
PLAN_ONLY=false

while [[ $# -gt 0 ]]; do
	case "$1" in
	--dry-run)
		DRY_RUN=true
		shift
		;;
	--background)
		BACKGROUND=true
		shift
		;;
	--create-plans)
		CREATE_PLANS=true
		shift
		;;
	--plan-only)
		PLAN_ONLY=true
		CREATE_PLANS=true
		shift
		;;
	-*)
		echo "error: unknown option: $1" >&2
		echo "usage: planner-loop.sh [--dry-run] [--background] [--create-plans] [--plan-only]" >&2
		exit 1
		;;
	*)
		echo "error: unexpected argument: $1" >&2
		exit 1
		;;
	esac
done

# --- Check dependencies ---

check_deps() {
	local missing=()
	for cmd in jq claude; do
		if ! command -v "${cmd}" >/dev/null 2>&1; then
			missing+=("${cmd}")
		fi
	done
	if [[ ${#missing[@]} -gt 0 ]]; then
		echo "${PREFIX}: error: missing required tools: ${missing[*]}" >&2
		exit 1
	fi
}

check_deps

# --- Logging ---

mkdir -p "${LOG_DIR}"
LOGFILE="${LOG_DIR}/$(date +%Y%m%d-%H%M%S).log"

log() {
	local msg
	msg="[$(date +%H:%M:%S)] ${PREFIX}: $1"
	echo "${msg}"
	echo "${msg}" >>"${LOGFILE}"
}

log_raw() {
	echo "$1" >>"${LOGFILE}"
}

# --- YAML helpers (no yq dependency) ---

# Read a top-level scalar from focus.yaml budget section.
# Usage: val=$(focus_budget_field "max_plans")
focus_budget_field() {
	local key="$1"
	grep "^  ${key}:" "${FOCUS_FILE}" 2>/dev/null |
		awk '{print $2}' | tr -d ' ' || true
}

# Read a top-level scalar from focus.yaml.
# Usage: val=$(focus_field "instructions")
focus_field() {
	local key="$1"
	grep "^${key}:" "${FOCUS_FILE}" 2>/dev/null |
		sed "s/^${key}:[[:space:]]*//" | tr -d ' ' || true
}

# --- Read focus config ---

read_focus() {
	if [[ ! -f "${FOCUS_FILE}" ]]; then
		log "no focus.yaml found — will fall back to tech-debt.md"
		MAX_PLANS=3
		MAX_CONSECUTIVE_FAILURES=2
		COOLDOWN_SECONDS=30
		INSTRUCTIONS_FILE=""
		INSTRUCTIONS_CONTENT=""
		return 0
	fi

	MAX_PLANS=$(focus_budget_field "max_plans")
	MAX_PLANS="${MAX_PLANS:-5}"
	MAX_CONSECUTIVE_FAILURES=$(focus_budget_field "max_consecutive_failures")
	MAX_CONSECUTIVE_FAILURES="${MAX_CONSECUTIVE_FAILURES:-2}"
	COOLDOWN_SECONDS=$(focus_budget_field "cooldown_seconds")
	COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-30}"

	# Read instructions file path
	INSTRUCTIONS_FILE=$(focus_field "instructions")
	INSTRUCTIONS_CONTENT=""
	if [[ -n "${INSTRUCTIONS_FILE}" ]]; then
		local instructions_path="${REPO_ROOT}/${INSTRUCTIONS_FILE}"
		if [[ -f "${instructions_path}" ]]; then
			INSTRUCTIONS_CONTENT=$(cat "${instructions_path}")
			log "instructions loaded from ${INSTRUCTIONS_FILE}"
		else
			log "warning: instructions file not found: ${INSTRUCTIONS_FILE}"
		fi
	fi

	log "focus loaded: max_plans=${MAX_PLANS} max_failures=${MAX_CONSECUTIVE_FAILURES} cooldown=${COOLDOWN_SECONDS}s"
}

# --- Gather context for assessment ---

gather_context() {
	local focus_content="" tech_debt="" quality="" active_plans="" registry=""

	if [[ -f "${FOCUS_FILE}" ]]; then
		focus_content=$(cat "${FOCUS_FILE}")
	else
		focus_content="(no focus.yaml — use tech-debt.md as primary input)"
	fi

	if [[ -f "${TECH_DEBT_FILE}" ]]; then
		tech_debt=$(cat "${TECH_DEBT_FILE}")
	else
		tech_debt="(no tech-debt.md found)"
	fi

	if [[ -f "${QUALITY_FILE}" ]]; then
		quality=$(cat "${QUALITY_FILE}")
	else
		quality="(no QUALITY.md found)"
	fi

	if [[ -d "${ACTIVE_PLANS_DIR}" ]]; then
		active_plans=$(ls -1 "${ACTIVE_PLANS_DIR}" 2>/dev/null || true)
		if [[ -z "${active_plans}" ]]; then
			active_plans="(no active plans)"
		fi
	else
		active_plans="(no active plans directory)"
	fi

	if [[ -f "${REGISTRY_FILE}" ]]; then
		registry=$(cat "${REGISTRY_FILE}")
	else
		registry="(no REGISTRY.md found)"
	fi

	# Build prompt from template, substituting placeholders
	local prompt_template
	prompt_template=$(cat "${ASSESS_PROMPT}")

	prompt_template="${prompt_template//\{FOCUS_YAML\}/${focus_content}}"
	prompt_template="${prompt_template//\{TECH_DEBT\}/${tech_debt}}"
	prompt_template="${prompt_template//\{QUALITY\}/${quality}}"
	prompt_template="${prompt_template//\{ACTIVE_PLANS\}/${active_plans}}"
	prompt_template="${prompt_template//\{REGISTRY\}/${registry}}"

	printf '%s' "${prompt_template}"
}

# --- ASSESS phase ---

run_assess() {
	log "ASSESS — spawning assessment agent"

	local prompt
	prompt=$(gather_context)

	local assess_output
	local assess_exit=0
	assess_output=$(claude -p --output-format json \
		"${prompt}" 2>"${LOGFILE}.assess-stderr") || assess_exit=$?

	if [[ ${assess_exit} -ne 0 ]]; then
		local stderr_content
		stderr_content=$(cat "${LOGFILE}.assess-stderr" 2>/dev/null || true)
		log_raw "assess stderr: ${stderr_content}"

		if echo "${stderr_content}" | grep -qiE 'rate.?limit|credit|billing|quota|exceeded'; then
			log "credit/rate limit detected — exiting"
			return 2
		fi

		log "assess agent failed (exit ${assess_exit}) — counting as failure"
		return 1
	fi

	# claude --output-format json wraps the result — extract the text content
	local text_result
	text_result=$(printf '%s' "${assess_output}" | jq -r '
		if .result then
			(.result | if type == "array" then
				[.[] | select(.type == "text") | .text] | join("")
			elif type == "string" then .
			else tostring end)
		elif .type == "text" then .text
		else tostring end
	' 2>/dev/null || printf '%s' "${assess_output}")

	log_raw "assess raw output: ${text_result}"

	# Parse JSON from the text output
	# The agent outputs a single JSON object — find and extract it
	local json_result
	json_result=$(printf '%s' "${text_result}" | grep -oE '\{[^}]+\}' | head -1 || true)

	if [[ -z "${json_result}" ]]; then
		log "assess agent returned no parseable JSON"
		log_raw "full output: ${text_result}"
		return 1
	fi

	# Validate required fields
	local action
	action=$(printf '%s' "${json_result}" | jq -r '.action // empty' 2>/dev/null || true)

	if [[ -z "${action}" ]]; then
		log "assess agent JSON missing 'action' field"
		return 1
	fi

	ASSESS_RESULT="${json_result}"
	ASSESS_ACTION="${action}"
	log "ASSESS result: action=${action}"

	if [[ "${action}" == "create_plan" ]]; then
		ASSESS_SLUG=$(printf '%s' "${json_result}" | jq -r '.slug // empty')
		ASSESS_TITLE=$(printf '%s' "${json_result}" | jq -r '.title // empty')
		ASSESS_RATIONALE=$(printf '%s' "${json_result}" | jq -r '.rationale // empty')
		ASSESS_FOCUS_AREA=$(printf '%s' "${json_result}" | jq -r '.focus_area // empty')
		log "  slug=${ASSESS_SLUG} title=${ASSESS_TITLE}"
		log "  rationale=${ASSESS_RATIONALE}"
	fi

	return 0
}

# --- PLAN phase ---

run_plan() {
	local slug="$1"
	local title="$2"
	local rationale="$3"
	local focus_area="$4"

	log "PLAN — creating plan for ${slug}"

	# Scaffold the plan directory
	local plan_dir
	plan_dir=$("${SCRIPT_DIR}/create-exec-plan.sh" "${slug}")
	log "  scaffolded ${plan_dir}"

	# Read focus area context from focus.yaml
	local area_context=""
	if [[ -f "${FOCUS_FILE}" ]] && [[ "${focus_area}" != "tech-debt" ]]; then
		# Extract context for this area (best-effort grep)
		area_context=$(awk "/- area: ${focus_area}/,/^  - area:/" "${FOCUS_FILE}" 2>/dev/null || true)
	fi

	# Build writer prompt
	local writer_base
	writer_base=$(cat "${WRITER_PROMPT}")

	# Include instructions if available
	local instructions_block=""
	if [[ -n "${INSTRUCTIONS_CONTENT}" ]]; then
		instructions_block="
---

## Project Instructions

The following instructions define project-specific conventions and constraints.
Follow them when writing the plan.

${INSTRUCTIONS_CONTENT}"
	fi

	# Set status hint based on mode
	local status_hint="In progress"
	if [[ "${PLAN_ONLY}" == true ]]; then
		status_hint="Draft"
	fi

	local writer_prompt
	writer_prompt="${writer_base}
${instructions_block}

---

## Your Assignment

- **Slug**: ${slug}
- **Title**: ${title}
- **Rationale**: ${rationale}
- **Focus area context**: ${area_context:-"(no additional context)"}
- **Repo root**: ${REPO_ROOT}
- **Plan file**: ${REPO_ROOT}/${plan_dir}/plan.md
- **Plan status**: ${status_hint}"

	local plan_exit=0
	claude -p --dangerously-skip-permissions \
		"${writer_prompt}" 2>"${LOGFILE}.plan-stderr" || plan_exit=$?

	if [[ ${plan_exit} -ne 0 ]]; then
		local stderr_content
		stderr_content=$(cat "${LOGFILE}.plan-stderr" 2>/dev/null || true)
		log_raw "plan stderr: ${stderr_content}"

		if echo "${stderr_content}" | grep -qiE 'rate.?limit|credit|billing|quota|exceeded'; then
			log "credit/rate limit detected during PLAN — exiting"
			return 2
		fi

		log "plan agent failed (exit ${plan_exit})"
		return 1
	fi

	# Verify plan.md was written
	if [[ ! -s "${REPO_ROOT}/${plan_dir}/plan.md" ]]; then
		log "plan agent did not write plan.md — marking failure"
		return 1
	fi

	PLAN_DIR_REL="${plan_dir}"
	log "PLAN complete — ${plan_dir}/plan.md written"
	return 0
}

# --- Extract questions from a plan ---

extract_questions() {
	local plan_file="$1"
	local slug="$2"

	if [[ ! -f "${plan_file}" ]]; then
		return
	fi

	# Extract "Questions for reviewer" section
	local questions=""
	questions=$(awk '/^## Questions for reviewer/,/^## [^Q]/' "${plan_file}" |
		head -n -1 | tail -n +2 | sed '/^$/d' || true)

	# Extract "Risks and open questions" section
	local risks=""
	risks=$(awk '/^## Risks and open questions/,/^## [^R]/' "${plan_file}" |
		head -n -1 | tail -n +2 | sed '/^$/d' || true)

	# Build output
	local output=""
	if [[ -n "${questions}" ]] && ! echo "${questions}" | grep -qi "no blocking questions"; then
		output="${output}### Questions

${questions}
"
	fi

	if [[ -n "${risks}" ]]; then
		output="${output}### Risks

${risks}
"
	fi

	if [[ -n "${output}" ]]; then
		printf '## %s\n\nPlan: `%s`\n\n%s\n' "${slug}" \
			"docs/exec-plans/active/${slug}/plan.md" "${output}"
	fi
}

# --- Build review file ---

build_review_file() {
	local review_file="$1"
	shift
	local slugs=("$@")

	{
		cat <<-'HEADER'
			# Plan Review

			Plans created by the planner loop in **plan-only** mode.
			Review each plan, answer questions, then run `plan-upload.sh` to
			commit and push to GitHub.

			## How to use

			1. Read each plan in `docs/exec-plans/active/<slug>/plan.md`
			2. Answer the questions below (edit the plan directly)
			3. Change plan status from `Draft` to `In progress` when ready
			4. Run: `bash scripts/plan-upload.sh` to commit and push all draft plans

			---

		HEADER

		local has_questions=false
		for slug in "${slugs[@]}"; do
			local plan_file="${REPO_ROOT}/docs/exec-plans/active/${slug}/plan.md"
			local section
			section=$(extract_questions "${plan_file}" "${slug}")
			if [[ -n "${section}" ]]; then
				echo "${section}"
				echo "---"
				echo ""
				has_questions=true
			fi
		done

		if [[ "${has_questions}" == false ]]; then
			echo "No blocking questions found. All plans are ready for execution."
			echo ""
		fi

		echo "## Plans created"
		echo ""
		for slug in "${slugs[@]}"; do
			echo "- \`docs/exec-plans/active/${slug}/plan.md\`"
		done
		echo ""
		echo "---"
		echo "Generated: $(date +%Y-%m-%d\ %H:%M:%S)"
	} >"${review_file}"
}

# --- COMMIT phase ---

run_commit() {
	local slug="$1"
	local plan_dir="$2"

	log "COMMIT — committing plan ${slug}"

	git -C "${REPO_ROOT}" add "${plan_dir}"
	if git -C "${REPO_ROOT}" diff --cached --quiet; then
		log "  nothing to commit (plan may already be tracked)"
		return 0
	fi

	git -C "${REPO_ROOT}" commit -m "$(
		cat <<-EOF
			plan: add ${slug} (auto-planner)

			Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
		EOF
	)"

	log "COMMIT complete"
	return 0
}

# --- EXECUTE phase ---

run_execute() {
	local slug="$1"

	log "EXECUTE — launching orchestrator for ${slug}"

	local orch_args=("${slug}" "--background")
	if [[ "${BACKGROUND}" == false ]]; then
		# In non-background mode, still run orch in background
		# so the planner loop can monitor it
		orch_args=("${slug}" "--background")
	fi

	"${SCRIPT_DIR}/orch-run.sh" "${orch_args[@]}" || {
		log "orch-run.sh failed to launch for ${slug}"
		return 1
	}

	log "EXECUTE — orchestrator launched for ${slug}"
	return 0
}

# --- MONITOR phase ---

run_monitor() {
	local slug="$1"

	log "MONITOR — waiting for orchestrator to complete ${slug}"

	local state_file
	state_file=$(orch_plan_state_file "${slug}")
	local poll_interval
	poll_interval=$(orch_read_config "poll_interval_seconds")
	poll_interval="${poll_interval:-30}"

	local monitor_start
	monitor_start=$(date +%s)

	while true; do
		if [[ ! -f "${state_file}" ]]; then
			log "  state file not found — waiting"
			sleep "${poll_interval}"
			continue
		fi

		local status
		status=$(jq -r '.status // "running"' "${state_file}" 2>/dev/null || echo "running")

		if [[ "${status}" == "completed" ]]; then
			local elapsed=$(($(date +%s) - monitor_start))
			log "MONITOR — ${slug} completed (${elapsed}s)"
			return 0
		fi

		if [[ "${status}" == "failed" ]]; then
			local elapsed=$(($(date +%s) - monitor_start))
			log "MONITOR — ${slug} failed (${elapsed}s)"
			return 1
		fi

		# Print progress periodically
		local done_count running_count total_count
		done_count=$(jq '[.items[] | select(.status == "done")] | length' "${state_file}" 2>/dev/null || echo 0)
		running_count=$(jq '[.items[] | select(.status == "running")] | length' "${state_file}" 2>/dev/null || echo 0)
		total_count=$(jq '.items | length' "${state_file}" 2>/dev/null || echo "?")
		log "  progress: ${done_count}/${total_count} done, ${running_count} running"

		sleep "${poll_interval}"
	done
}

# --- Main loop ---

log "planner loop starting"
log "  repo: ${REPO_ROOT}"
log "  log: ${LOGFILE}"
log "  dry-run: ${DRY_RUN}"
log "  create-plans: ${CREATE_PLANS}"
log "  plan-only: ${PLAN_ONLY}"

# --- Find existing active plans ---

find_existing_plans() {
	local plans=()
	if [[ -d "${ACTIVE_PLANS_DIR}" ]]; then
		for dir in "${ACTIVE_PLANS_DIR}"/*/; do
			if [[ -f "${dir}plan.md" ]]; then
				local slug
				slug=$(basename "${dir}")
				plans+=("${slug}")
			fi
		done
	fi
	printf '%s\n' "${plans[@]}"
}

plans_completed=0
consecutive_failures=0

# Track plans created in plan-only mode for the review file
plan_only_slugs=()

while true; do
	# Re-read focus config each iteration (allows mid-run edits)
	read_focus

	# --- In plan-only mode, skip existing plan execution ---
	if [[ "${PLAN_ONLY}" != true ]]; then

		# --- EXECUTE EXISTING PLANS FIRST ---
		# Before creating new plans, execute any active plans that aren't
		# currently running in an orch session.
		existing_plans=$(find_existing_plans)
		ran_existing=false

		if [[ -n "${existing_plans}" ]]; then
			while IFS= read -r slug; do
				[[ -z "${slug}" ]] && continue

				# Skip if already running in a tmux session
				if tmux has-session -t "orch-${slug}" 2>/dev/null; then
					log "existing plan ${slug} already running — skipping"
					continue
				fi

				# Skip if already completed or failed (check top-level status first,
				# then fall back to item-level check for backwards compatibility)
				state_file=$(orch_plan_state_file "${slug}")
				if [[ -f "${state_file}" ]]; then
					top_status=$(jq -r '.status // "running"' "${state_file}" 2>/dev/null || echo "running")
					if [[ "${top_status}" == "completed" ]] || [[ "${top_status}" == "failed" ]]; then
						log "existing plan ${slug} already ${top_status} — skipping"
						continue
					fi
					remaining=$(jq '[.items[] | select(.status != "done")] | length' "${state_file}" 2>/dev/null || echo "1")
					if [[ "${remaining}" -eq 0 ]]; then
						log "existing plan ${slug} already complete — skipping"
						continue
					fi
				fi

				log "found existing active plan: ${slug}"

				if [[ "${DRY_RUN}" == true ]]; then
					log "dry-run — would execute existing plan: ${slug}"
					continue
				fi

				# Execute it
				execute_exit=0
				run_execute "${slug}" || execute_exit=$?

				if [[ ${execute_exit} -ne 0 ]]; then
					consecutive_failures=$((consecutive_failures + 1))
					log "execute failed for existing plan ${slug}"
					continue
				fi

				# Monitor it
				monitor_exit=0
				run_monitor "${slug}" || monitor_exit=$?

				if [[ ${monitor_exit} -ne 0 ]]; then
					consecutive_failures=$((consecutive_failures + 1))
					log "existing plan ${slug} failed execution"
				else
					consecutive_failures=0
					plans_completed=$((plans_completed + 1))
					log "existing plan ${slug} completed (${plans_completed}/${MAX_PLANS})"
				fi

				ran_existing=true

				# Budget check after each plan
				if [[ ${plans_completed} -ge ${MAX_PLANS} ]]; then
					log "budget exhausted after existing plans"
					break 2
				fi

				if [[ ${consecutive_failures} -ge ${MAX_CONSECUTIVE_FAILURES} ]]; then
					log "stopping — max consecutive failures during existing plans"
					break 2
				fi
			done <<<"${existing_plans}"
		fi

		# If we ran existing plans this cycle, loop back to check for more
		if [[ "${ran_existing}" == true ]]; then
			log "cooling down ${COOLDOWN_SECONDS}s after existing plan execution"
			sleep "${COOLDOWN_SECONDS}"
			continue
		fi

	fi # end: skip existing plan execution in plan-only mode

	# --- CREATE NEW PLANS (requires --create-plans flag) ---
	if [[ "${CREATE_PLANS}" != true ]]; then
		log "no existing plans to execute and --create-plans not set — exiting"
		break
	fi

	# --- ASSESS ---
	assess_exit=0
	run_assess || assess_exit=$?

	if [[ ${assess_exit} -eq 2 ]]; then
		log "stopping — credit/rate limit"
		break
	fi

	if [[ ${assess_exit} -ne 0 ]]; then
		consecutive_failures=$((consecutive_failures + 1))
		log "assess failed (${consecutive_failures}/${MAX_CONSECUTIVE_FAILURES} consecutive)"
		if [[ ${consecutive_failures} -ge ${MAX_CONSECUTIVE_FAILURES} ]]; then
			log "stopping — max consecutive failures reached"
			break
		fi
		log "cooling down ${COOLDOWN_SECONDS}s before retry"
		sleep "${COOLDOWN_SECONDS}"
		continue
	fi

	# --- Handle assessment result ---
	if [[ "${ASSESS_ACTION}" == "done" ]]; then
		log "all focus areas addressed — exiting cleanly"
		break
	fi

	if [[ "${ASSESS_ACTION}" == "skip" ]]; then
		log "all candidates in-flight — waiting ${COOLDOWN_SECONDS}s"
		sleep "${COOLDOWN_SECONDS}"
		continue
	fi

	if [[ "${ASSESS_ACTION}" != "create_plan" ]]; then
		log "unexpected action: ${ASSESS_ACTION} — skipping"
		consecutive_failures=$((consecutive_failures + 1))
		continue
	fi

	# --- Dry-run exit ---
	if [[ "${DRY_RUN}" == true ]]; then
		log "dry-run — would create plan: ${ASSESS_SLUG}"
		log "  title: ${ASSESS_TITLE}"
		log "  rationale: ${ASSESS_RATIONALE}"
		echo "${ASSESS_RESULT}"
		break
	fi

	# --- Check for duplicate plan ---
	if [[ -d "${ACTIVE_PLANS_DIR}/${ASSESS_SLUG}" ]]; then
		log "plan ${ASSESS_SLUG} already exists in active/ — skipping"
		consecutive_failures=$((consecutive_failures + 1))
		continue
	fi

	# --- PLAN ---
	plan_exit=0
	run_plan "${ASSESS_SLUG}" "${ASSESS_TITLE}" \
		"${ASSESS_RATIONALE}" "${ASSESS_FOCUS_AREA}" || plan_exit=$?

	if [[ ${plan_exit} -eq 2 ]]; then
		log "stopping — credit/rate limit during plan"
		break
	fi

	if [[ ${plan_exit} -ne 0 ]]; then
		consecutive_failures=$((consecutive_failures + 1))
		log "plan failed (${consecutive_failures}/${MAX_CONSECUTIVE_FAILURES} consecutive)"
		if [[ ${consecutive_failures} -ge ${MAX_CONSECUTIVE_FAILURES} ]]; then
			log "stopping — max consecutive failures reached"
			break
		fi
		sleep "${COOLDOWN_SECONDS}"
		continue
	fi

	# Reset failures on successful plan creation
	consecutive_failures=0

	# --- PLAN-ONLY mode: skip commit and execute ---
	if [[ "${PLAN_ONLY}" == true ]]; then
		plan_only_slugs+=("${ASSESS_SLUG}")
		plans_completed=$((plans_completed + 1))
		log "plan-only — ${ASSESS_SLUG} created locally (${plans_completed}/${MAX_PLANS})"

		if [[ ${plans_completed} -ge ${MAX_PLANS} ]]; then
			log "budget exhausted — created ${plans_completed} plans"
			break
		fi

		sleep "${COOLDOWN_SECONDS}"
		continue
	fi

	# --- CREATE ISSUE (if github.sync enabled) ---
	if gh_config_bool sync; then
		issue_num=$("${SCRIPT_DIR}/plan-issue.sh" "${ASSESS_SLUG}") || {
			log "issue creation failed for ${ASSESS_SLUG} — continuing"
			issue_num=""
		}
		if [[ -n "${issue_num}" ]]; then
			log "created issue #${issue_num} for ${ASSESS_SLUG}"
		fi
	fi

	# --- COMMIT ---
	run_commit "${ASSESS_SLUG}" "${PLAN_DIR_REL}" || {
		log "commit failed — continuing anyway"
	}

	# --- EXECUTE ---
	execute_exit=0
	run_execute "${ASSESS_SLUG}" || execute_exit=$?

	if [[ ${execute_exit} -ne 0 ]]; then
		consecutive_failures=$((consecutive_failures + 1))
		log "execute failed (${consecutive_failures}/${MAX_CONSECUTIVE_FAILURES} consecutive)"
		if [[ ${consecutive_failures} -ge ${MAX_CONSECUTIVE_FAILURES} ]]; then
			log "stopping — max consecutive failures reached"
			break
		fi
		sleep "${COOLDOWN_SECONDS}"
		continue
	fi

	# --- MONITOR ---
	monitor_exit=0
	run_monitor "${ASSESS_SLUG}" || monitor_exit=$?

	if [[ ${monitor_exit} -ne 0 ]]; then
		consecutive_failures=$((consecutive_failures + 1))
		log "plan ${ASSESS_SLUG} failed execution (${consecutive_failures}/${MAX_CONSECUTIVE_FAILURES} consecutive)"
	else
		consecutive_failures=0
		plans_completed=$((plans_completed + 1))
		log "plan ${ASSESS_SLUG} completed successfully (${plans_completed}/${MAX_PLANS})"
	fi

	# --- BUDGET CHECK ---
	if [[ ${plans_completed} -ge ${MAX_PLANS} ]]; then
		log "budget exhausted — completed ${plans_completed} plans"
		break
	fi

	if [[ ${consecutive_failures} -ge ${MAX_CONSECUTIVE_FAILURES} ]]; then
		log "stopping — max consecutive failures reached (${consecutive_failures})"
		break
	fi

	# --- COOLDOWN ---
	log "cooling down ${COOLDOWN_SECONDS}s before next cycle"
	sleep "${COOLDOWN_SECONDS}"
done

# --- Plan-only: build review file ---

if [[ "${PLAN_ONLY}" == true ]] && [[ ${#plan_only_slugs[@]} -gt 0 ]]; then
	REVIEW_FILE="${REPO_ROOT}/docs/exec-plans/plan-review.md"
	build_review_file "${REVIEW_FILE}" "${plan_only_slugs[@]}"
	log ""
	log "========================================="
	log "  PLAN-ONLY COMPLETE"
	log "========================================="
	log "  Plans created: ${#plan_only_slugs[@]}"
	log "  Review file:   docs/exec-plans/plan-review.md"
	log ""
	log "  Next steps:"
	log "  1. Review each plan in docs/exec-plans/active/"
	log "  2. Answer questions in docs/exec-plans/plan-review.md"
	log "  3. Edit plans as needed"
	log "  4. Run: bash scripts/plan-upload.sh"
	log "========================================="
fi

# --- Summary ---

log "planner loop finished: ${plans_completed} plans completed, ${consecutive_failures} consecutive failures"
log "log saved to ${LOGFILE}"

# Play sound on completion
if [[ -x "${SCRIPT_DIR}/../hooks/play-sound.sh" ]]; then
	if [[ ${plans_completed} -gt 0 ]]; then
		CLAUDE_SOUND=success bash "${SCRIPT_DIR}/../hooks/play-sound.sh" || true
	else
		CLAUDE_SOUND=error bash "${SCRIPT_DIR}/../hooks/play-sound.sh" || true
	fi
fi

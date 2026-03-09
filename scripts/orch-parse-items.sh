#!/usr/bin/env bash
# Parse a plan's progress log into a JSON item queue with dependencies.
# Output matches the ParsedPlan interface from orch-types.ts.
#
# Usage: scripts/orch-parse-items.sh <slug>
#   slug: exec-plan directory name (e.g., 20260307-mcp-server)
#
# Output (stdout): JSON object with slug and items array.
# Each item has: id (1-indexed), description, deps (array of ints), checked (bool).
#
# Dependency format in plan.md:
#   - [ ] Some task (deps: 1, 3)
#   - [x] Completed task
#   - [ ] No-dep task

set -euo pipefail

SLUG="${1:-}"

if [[ -z "${SLUG}" ]]; then
	echo "error: usage: orch-parse-items.sh <slug>" >&2
	exit 1
fi

PLAN_DIR="docs/exec-plans/active/${SLUG}"
PLAN_FILE="${PLAN_DIR}/plan.md"

if [[ ! -f "${PLAN_FILE}" ]]; then
	echo "error: plan not found: ${PLAN_FILE}" >&2
	exit 1
fi

# Extract lines between "## Progress log" and the next "##" heading (or EOF).
# Skip content inside fenced code blocks (``` ... ```).
# Only keep lines matching the checkbox pattern: - [ ] or - [x]
in_progress_log=false
in_code_block=false
items_raw=()

while IFS= read -r line; do
	# Toggle code block state on fence lines
	if [[ "${line}" =~ ^\`\`\` ]]; then
		if ${in_code_block}; then
			in_code_block=false
		else
			in_code_block=true
		fi
		continue
	fi
	# Skip everything inside code blocks
	if ${in_code_block}; then
		continue
	fi
	if [[ "${line}" =~ ^##[[:space:]]+Progress[[:space:]]+log ]]; then
		in_progress_log=true
		continue
	fi
	if ${in_progress_log} && [[ "${line}" =~ ^## ]]; then
		break
	fi
	if ${in_progress_log} && [[ "${line}" =~ ^[[:space:]]*-[[:space:]]\[([ xX])\] ]]; then
		items_raw+=("${line}")
	fi
done <"${PLAN_FILE}"

if [[ ${#items_raw[@]} -eq 0 ]]; then
	echo "error: no progress log items found in ${PLAN_FILE}" >&2
	exit 1
fi

# Build JSON array of parsed items
json_items="[]"
id=0

for raw_line in "${items_raw[@]}"; do
	id=$((id + 1))

	# Determine checked status
	checked=false
	if [[ "${raw_line}" =~ \[[xX]\] ]]; then
		checked=true
	fi

	# Extract description: strip leading "- [ ] " or "- [x] ", then strip deps annotation
	description="${raw_line}"
	description="${description#*] }"
	# Remove trailing (deps: ...) if present
	description=$(printf '%s' "${description}" | sed 's/[[:space:]]*(deps:[[:space:]]*[0-9, ]*)$//')

	# Extract deps: look for (deps: N, M, ...) at end of line
	deps="[]"
	if [[ "${raw_line}" =~ \(deps:[[:space:]]*([0-9, ]+)\) ]]; then
		deps_str="${BASH_REMATCH[1]}"
		# Convert "1, 3, 4" to JSON array [1, 3, 4]
		deps=$(printf '%s' "${deps_str}" | tr ',' '\n' | tr -d ' ' | jq -R 'tonumber' | jq -s '.')
	fi

	# Append item to JSON array
	json_items=$(printf '%s' "${json_items}" | jq \
		--argjson id "${id}" \
		--arg desc "${description}" \
		--argjson deps "${deps}" \
		--argjson checked "${checked}" \
		'. + [{"id": $id, "description": $desc, "deps": $deps, "checked": $checked}]')
done

# Output final ParsedPlan JSON
jq -n --arg slug "${SLUG}" --argjson items "${json_items}" \
	'{"slug": $slug, "items": $items}'

#!/usr/bin/env bash
# PreToolUse hook: enforces YYYYMMDD-slug naming for exec-plan directories.
# Blocks both Bash (mkdir) and Write (file creation) targeting exec-plans/active/
# with incorrectly named directories.
# Exit 2 = block the tool call. Exit 0 = allow.

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "${INPUT}" | jq -r '.tool_name // empty')

case "${TOOL_NAME}" in
Bash)
	CMD=$(printf '%s' "${INPUT}" | jq -r '.tool_input.command // empty')
	[[ -z "${CMD}" ]] && exit 0

	# Only intercept mkdir targeting exec-plans/active/
	if ! printf '%s\n' "${CMD}" | grep -qE 'mkdir.*exec-plans/active/'; then
		exit 0
	fi

	DIR_NAME=$(printf '%s\n' "${CMD}" |
		grep -oE 'exec-plans/active/[^/[:space:]"'"'"']+' |
		head -1 |
		sed 's|exec-plans/active/||')
	;;
Write)
	FILE_PATH=$(printf '%s' "${INPUT}" | jq -r '.tool_input.file_path // empty')
	[[ -z "${FILE_PATH}" ]] && exit 0

	if ! printf '%s\n' "${FILE_PATH}" | grep -qE 'exec-plans/active/'; then
		exit 0
	fi

	# First path segment after active/
	DIR_NAME=$(printf '%s\n' "${FILE_PATH}" |
		grep -oE 'exec-plans/active/[^/]+' |
		head -1 |
		sed 's|exec-plans/active/||')
	;;
*)
	exit 0
	;;
esac

[[ -z "${DIR_NAME}" ]] && exit 0

# Validate YYYYMMDD- prefix
if ! printf '%s\n' "${DIR_NAME}" | grep -qE '^[0-9]{8}-'; then
	echo "BLOCKED: exec-plan directory must start with YYYYMMDD- (e.g., 20260303-add-auth)." >&2
	echo "Use: bash scripts/create-exec-plan.sh <slug>" >&2
	exit 2
fi

exit 0

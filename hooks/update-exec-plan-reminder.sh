#!/usr/bin/env bash
# PostToolUse hook — reminds the agent to update the exec-plan progress log
# after completing a work step. Fires after successful non-read-only Bash
# commands when an active plan exists in the project.
set -euo pipefail

INPUT=$(cat)
EXIT_CODE=$(printf '%s' "${INPUT}" | jq -r '.tool_result.exit_code // 0')
COMMAND=$(printf '%s' "${INPUT}" | jq -r '.tool_input.command // empty')

# Only remind on success
[[ "${EXIT_CODE}" != "0" ]] && exit 0

# Skip empty commands
[[ -z "${COMMAND}" ]] && exit 0

# Skip read-only / diagnostic commands where no work step was completed
SKIP_PATTERN='^(cat[ $]|ls[ $]|head |tail |grep |rg |fd |echo[ $]|printf |which |test |true$|false$|\[\[|git (status|log|diff|show)|shfmt -d |wc |sort |uniq )'
if printf '%s' "${COMMAND}" | grep -qE "${SKIP_PATTERN}"; then
  exit 0
fi

# Check for active plans in the project (directory-based: active/*/plan.md)
PLAN_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}/docs/exec-plans/active"
[[ ! -d "${PLAN_DIR}" ]] && exit 0

PLAN_COUNT=$(find "${PLAN_DIR}" -maxdepth 2 -name "plan.md" 2>/dev/null | wc -l | tr -d ' ')
[[ "${PLAN_COUNT}" -eq 0 ]] && exit 0

printf '[exec-plan] Step complete? Mark it [x] in docs/exec-plans/active/*/plan.md before continuing.\n'

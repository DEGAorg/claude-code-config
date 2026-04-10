#!/usr/bin/env bash
# Create a date-prefixed exec-plan directory under docs/exec-plans/active/.
# Usage: scripts/create-exec-plan.sh <slug>
# Example: scripts/create-exec-plan.sh add-auth-endpoint
#   → docs/exec-plans/active/20260303-add-auth-endpoint/
#   → docs/exec-plans/active/20260303-add-auth-endpoint/plan.md (empty)
# If <slug> already starts with YYYYMMDD-, uses it as-is.
# If the directory already exists, prints the path without error.

set -euo pipefail

SLUG="${1:-}"

if [[ -z "${SLUG}" ]]; then
  echo "error: usage: scripts/create-exec-plan.sh <slug>" >&2
  echo "example: scripts/create-exec-plan.sh add-auth-endpoint" >&2
  exit 1
fi

# If slug already has a YYYYMMDD- prefix, use it as-is
if printf '%s\n' "${SLUG}" | grep -qE '^[0-9]{8}-'; then
  DIR_NAME="${SLUG}"
else
  DIR_NAME="$(date +%Y%m%d)-${SLUG}"
fi

PLAN_DIR="docs/exec-plans/active/${DIR_NAME}"

mkdir -p "${PLAN_DIR}"
touch "${PLAN_DIR}/plan.md"

echo "${PLAN_DIR}"

#!/usr/bin/env bash
set -euo pipefail

# Generate Claude Code settings.json from settings-template.json.
# Claude uses the canonical event names, so no translation is needed.
# This adapter strips template metadata and adds Claude-specific fields.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEMPLATE="${REPO_ROOT}/settings-template.json"
DEGACORE_DIR="${HOME}/.degacore"
OUTPUT_DIR="${HOME}/.claude"
OUTPUT_FILE="${OUTPUT_DIR}/settings.json"

if [[ ! -f "${TEMPLATE}" ]]; then
  echo "error: settings-template.json not found at ${TEMPLATE}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required but not installed" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"

# Build Claude settings.json:
# 1. Remove metadata keys (_doc, _event_name_mapping)
# 2. Add Claude-specific fields
# 3. Ensure hook paths point to ~/.degacore/
jq --arg degacore "${DEGACORE_DIR}" '
  # Remove template metadata
  del(._doc, ._event_name_mapping)

  # Add Claude-specific settings
  | {
      "$schema": "https://json.schemastore.org/claude-code-settings.json",
      cleanupPeriodDays: 365,
      env: .env,
      enableAllProjectMcpServers: false,
      alwaysThinkingEnabled: true,
      permissions: .permissions,
      hooks: .hooks,
      mcpServers: .mcpServers,
      statusLine: {
        type: "command",
        command: ($degacore + "/scripts/statusline.sh")
      }
    }
' "${TEMPLATE}" > "${OUTPUT_FILE}.tmp"

mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
echo "Generated ${OUTPUT_FILE}"

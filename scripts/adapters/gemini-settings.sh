#!/usr/bin/env bash
set -euo pipefail

# Gemini settings adapter
# Reads settings-template.json and generates settings.json for ~/.gemini/
# Translates canonical event names to Gemini-specific names:
#   PreToolUse       → BeforeTool
#   PostToolUse      → AfterTool
#   Stop             → SessionEnd
#   UserPromptSubmit → SessionStart

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEMPLATE="${REPO_ROOT}/settings-template.json"

GEMINI_DIR="${HOME}/.gemini"
OUTPUT="${GEMINI_DIR}/settings.json"

if [[ ! -f "${TEMPLATE}" ]]; then
	echo "error: settings-template.json not found at ${TEMPLATE}" >&2
	exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
	echo "error: jq is required but not installed" >&2
	exit 1
fi

mkdir -p "${GEMINI_DIR}"

# Build the Gemini settings.json by:
# 1. Removing internal _doc and _event_name_mapping fields
# 2. Translating hook event names from canonical to Gemini-specific
# 3. Keeping env, permissions, and mcpServers as-is
jq '
  # Translate hook event names
  def gemini_event_name:
    if . == "PreToolUse" then "BeforeTool"
    elif . == "PostToolUse" then "AfterTool"
    elif . == "Stop" then "SessionEnd"
    elif . == "UserPromptSubmit" then "SessionStart"
    else .
    end;

  # Rebuild hooks with translated event names
  (.hooks | to_entries | map({key: (.key | gemini_event_name), value}) | from_entries) as $translated_hooks |

  # Assemble output: env, permissions, translated hooks, mcpServers
  {
    env: .env,
    permissions: .permissions,
    hooks: $translated_hooks,
    mcpServers: .mcpServers
  }
' "${TEMPLATE}" >"${OUTPUT}"

echo "Generated ${OUTPUT}"

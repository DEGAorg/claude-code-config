#!/usr/bin/env bash
# Diagnostic PostToolUse echo hook — captures stdin JSON for schema inspection.
# Wire temporarily in settings.json to observe real tool-call input.
# Run once, inspect /tmp/posttooluse-echo.json, then remove this hook.
#
# Verified PostToolUse stdin schema (official docs + log-gam.sh cross-reference):
#
#   .session_id         — session identifier string
#   .transcript_path    — path to conversation JSONL
#   .cwd                — working directory when hook fires
#   .permission_mode    — "default" | "plan" | "acceptEdits" | "dontAsk" | "bypassPermissions"
#   .hook_event_name    — "PostToolUse"
#   .tool_name          — tool name string (e.g. "Bash", "Write", "Edit", "Read")
#   .tool_input         — tool-specific input object:
#                           Bash:  { "command": "..." }
#                           Write: { "file_path": "...", "content": "..." }
#                           Edit:  { "file_path": "...", "old_string": "...", "new_string": "..." }
#   .tool_response      — tool-specific response object (NOT .tool_result):
#                           Bash:  { "exit_code": N, "stdout": "...", "stderr": "..." }
#                           Write: { "filePath": "...", "success": true }
#   .tool_use_id        — tool use identifier ("toolu_01...")
#
# Key correction: field is .tool_response (not .tool_result as older scripts assumed).
# Use: jq -r '.tool_response.exit_code // 0' for Bash exit codes.

set -euo pipefail

DUMP=/tmp/posttooluse-echo.json
INPUT=$(cat)

printf '%s\n' "$INPUT" >"$DUMP"

# Print summary to stderr — visible in Claude Code verbose mode (Ctrl+O)
jq -r '"[test-echo] tool=\(.tool_name // "?") event=\(.hook_event_name // "?") exit=\(.tool_response.exit_code // "n/a")"' \
	<<<"$INPUT" >&2

exit 0

#!/usr/bin/env bash
# orch-gate-decision-audit.sh
#
# Parses the "Decision log" markdown table from a plan body and emits one
# JSON object per row to stdout. Intended for the orch reviewer's Gate B.
#
# Output schema (one object per line, JSON Lines):
#   { "decision": "...", "alternatives": "...", "rationale": "...",
#     "keywords": ["FOK", "limit"] }
#
# `keywords` is a heuristic: capitalised words and ALL-CAPS acronyms from
# the Decision column, plus any back-tick-quoted token. Gate B uses this
# list to grep the diff for evidence.
#
# Usage: orch-gate-decision-audit.sh <plan-file>

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: orch-gate-decision-audit.sh <plan-file>" >&2
  exit 1
fi

PLAN_FILE="$1"
if [[ ! -f "${PLAN_FILE}" ]]; then
  echo "error: plan file not found: ${PLAN_FILE}" >&2
  exit 1
fi

# Extract the "## Decision log" section up to the next ## heading.
# Then keep only table rows (lines starting with "|") that are not
# the header or the alignment row.
awk '
  /^## *Decision log/ { in_section = 1; next }
  in_section && /^## / { in_section = 0 }
  in_section && /^[[:space:]]*\|/ { print }
' "${PLAN_FILE}" |
  grep -v '^[[:space:]]*|[[:space:]]*-' |
  grep -v '^[[:space:]]*|[[:space:]]*Decision[[:space:]]*|' |
  while IFS= read -r row; do
    # Split on |, trim whitespace from each cell. The leading and
    # trailing | produce empty first/last fields — drop them.
    decision=$(awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2 }' <<<"${row}")
    alternatives=$(awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3 }' <<<"${row}")
    rationale=$(awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $4); print $4 }' <<<"${row}")

    [[ -z "${decision}" ]] && continue

    # Extract heuristic keywords: ALL-CAPS acronyms (≥2 chars), back-tick
    # tokens, and `Capitalized` proper nouns ≥4 chars. Lowercase common
    # English words are skipped.
    keywords=$(printf '%s' "${decision}" | tr -c 'A-Za-z0-9_`' '\n' |
      awk '
          /^[A-Z]{2,}$/ { print; next }
          /^`[^`]+`$/   { gsub(/`/, ""); print; next }
          /^[A-Z][a-zA-Z]{3,}$/ { print; next }
        ' |
      sort -u |
      awk 'BEGIN { printf "[" } { printf "%s\"%s\"", (NR>1 ? "," : ""), $0 } END { print "]" }')

    # Emit JSON line; escape backslashes and double quotes in fields.
    esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
    printf '{"decision":"%s","alternatives":"%s","rationale":"%s","keywords":%s}\n' \
      "$(esc "${decision}")" \
      "$(esc "${alternatives}")" \
      "$(esc "${rationale}")" \
      "${keywords}"
  done

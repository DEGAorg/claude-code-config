#!/usr/bin/env bash
# resolve.sh — NL intent → issue/slug resolver for the orch-invoke skill.
#
# Reads a single natural-language intent string, loads the set of candidate
# plan issues (from `gh issue list` or a fixture via $ORCH_INVOKE_ISSUES_FIXTURE),
# and emits a JSON object on stdout:
#
#   { "status": "exact"|"match"|"ambiguous"|"empty",
#     "issue": <int|null>,
#     "slug":  <string|null>,
#     "candidates": [ {issue, slug, title}, ... ] }
#
# Diagnostics go to stderr. Exit code is 0 on any successful classification
# (including "empty" and "ambiguous"); 2 on usage / environment errors.

set -euo pipefail

die() {
  printf 'resolve.sh: %s\n' "$*" >&2
  exit 2
}

[[ $# -eq 1 ]] || die 'usage: resolve.sh "<user intent>"'

intent="$1"

load_issues() {
  if [[ -n "${ORCH_INVOKE_ISSUES_FIXTURE:-}" ]]; then
    [[ -r "$ORCH_INVOKE_ISSUES_FIXTURE" ]] ||
      die "fixture not readable: $ORCH_INVOKE_ISSUES_FIXTURE"
    cat -- "$ORCH_INVOKE_ISSUES_FIXTURE"
    return
  fi
  if ! command -v gh >/dev/null 2>&1; then
    printf '[]'
    return
  fi
  gh issue list \
    --state open \
    --label plan:draft --label plan:active \
    --json number,title,labels \
    --limit 100 2>/dev/null || printf '[]'
}

command -v jq >/dev/null 2>&1 || die 'jq is required'

issues_json=$(load_issues)
if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$issues_json"; then
  die 'issues source did not produce a JSON array'
fi

emit() {
  # emit <status> <issue-json> <slug-string> <candidates-json>
  local status="$1" issue_json="$2" slug="$3" candidates_json="$4"
  jq -n \
    --arg status "$status" \
    --argjson issue "$issue_json" \
    --arg slug "$slug" \
    --argjson candidates "$candidates_json" \
    '{
       status:     $status,
       issue:      $issue,
       slug:       (if $slug == "" then null else $slug end),
       candidates: $candidates
     }'
}

slug_from_title() {
  local title="$1"
  if [[ "$title" =~ ([0-9]{8}-[a-z0-9-]+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

# ---------------------------------------------------------------------------
# 1. Explicit issue number: "#214", "issue 214", or standalone 2-6 digit token.
# ---------------------------------------------------------------------------
explicit_num=""
if [[ "$intent" =~ \#([0-9]+) ]]; then
  explicit_num="${BASH_REMATCH[1]}"
elif [[ "$intent" =~ [Ii]ssue[[:space:]]+#?([0-9]+) ]]; then
  explicit_num="${BASH_REMATCH[1]}"
elif [[ "$intent" =~ (^|[[:space:]])([0-9]{2,6})([[:space:]]|$) ]]; then
  explicit_num="${BASH_REMATCH[2]}"
fi

# ---------------------------------------------------------------------------
# 2. Explicit slug: YYYYMMDD-token.
# ---------------------------------------------------------------------------
explicit_slug=""
if [[ "$intent" =~ ([0-9]{8}-[a-z0-9-]+) ]]; then
  explicit_slug="${BASH_REMATCH[1]}"
fi

if [[ -n "$explicit_num" ]]; then
  match=$(jq -c --argjson n "$explicit_num" \
    '[.[] | select(.number == $n)] | first // empty' <<<"$issues_json")
  if [[ -n "$match" ]]; then
    title=$(jq -r '.title' <<<"$match")
    slug=$(slug_from_title "$title")
    emit 'exact' "$explicit_num" "$slug" "[$match]"
    exit 0
  fi
  # Number supplied but not found in the candidate set — still treat as exact
  # so launch.sh can decide whether the plan exists on disk.
  emit 'exact' "$explicit_num" "$explicit_slug" '[]'
  exit 0
fi

if [[ -n "$explicit_slug" ]]; then
  match=$(jq -c --arg s "$explicit_slug" \
    '[.[] | select(.title | test($s; "i"))] | first // empty' <<<"$issues_json")
  if [[ -n "$match" ]]; then
    num=$(jq -r '.number' <<<"$match")
    emit 'exact' "$num" "$explicit_slug" "[$match]"
    exit 0
  fi
  emit 'exact' 'null' "$explicit_slug" '[]'
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Keyword match against titles.
# ---------------------------------------------------------------------------
stopwords_re='^(run|runs|running|execute|executes|executing|kick|off|issue|issues|plan|plans|the|start|starts|starting|launch|launches|launching|please|begin|begins|beginning|orchestrator|orch|work|works|working|on|shipping|ship|pick|picks|picking|up|background|in|go|ahead|lets|now|spin|workers|for|a|an|of|with|to|let|s|and|me|my|can|you|that|this|it)$'

raw_tokens=$(printf '%s\n' "$intent" |
  tr '[:upper:]' '[:lower:]' |
  tr -cs 'a-z0-9' '\n' |
  awk 'length($0) >= 2')

filtered=""
while IFS= read -r tok; do
  [[ -z "$tok" ]] && continue
  if [[ ! "$tok" =~ $stopwords_re ]]; then
    filtered+="${tok}"$'\n'
  fi
done <<<"$raw_tokens"

if [[ -z "${filtered//[[:space:]]/}" ]]; then
  emit 'empty' 'null' '' '[]'
  exit 0
fi

tokens_json=$(printf '%s' "$filtered" |
  jq -Rsc 'split("\n") | map(select(length > 0))')

scored=$(jq -c --argjson toks "$tokens_json" '
  map(
    . as $i
    | ($i.title | ascii_downcase) as $t
    | ($toks | map(select(. as $k | $t | contains($k))) | length) as $score
    | {
        issue: $i.number,
        title: $i.title,
        slug:  (try ($i.title | match("[0-9]{8}-[a-z0-9-]+").string) catch null),
        score: $score
      }
  )
  | sort_by(-.score)
' <<<"$issues_json")

top_score=$(jq -r 'if length == 0 then 0 else .[0].score end' <<<"$scored")
if [[ "$top_score" == '0' ]]; then
  emit 'empty' 'null' '' '[]'
  exit 0
fi

top_count=$(jq --argjson s "$top_score" \
  '[.[] | select(.score == $s)] | length' <<<"$scored")
top_candidates=$(jq -c --argjson s "$top_score" \
  '[.[] | select(.score == $s) | {issue, slug, title}]' <<<"$scored")

if [[ "$top_count" -ge 2 ]]; then
  emit 'ambiguous' 'null' '' "$top_candidates"
  exit 0
fi

best=$(jq -c '.[0]' <<<"$scored")
best_issue=$(jq -r '.issue' <<<"$best")
best_slug=$(jq -r '.slug // ""' <<<"$best")
emit 'match' "$best_issue" "$best_slug" "$top_candidates"

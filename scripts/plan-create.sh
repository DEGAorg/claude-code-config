#!/usr/bin/env bash
set -euo pipefail

# Create a GitHub Issue from plan content and apply the plan:draft label.
# Returns the issue number on stdout.
#
# Usage:
#   plan-create.sh --title "Plan title" --body "markdown body"
#   plan-create.sh --title "Plan title" --body-file /path/to/plan.md
#   plan-create.sh --title "Plan title" --body-file -   # read from stdin
#
# Options:
#   --repo OWNER/REPO   Override repo (default: auto-detected from git remote)
#   --label LABEL        Additional label (repeatable, plan:draft always applied)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/ensure-gh.sh
source "${SCRIPT_DIR}/ensure-gh.sh"
# shellcheck source=scripts/read-github-config.sh
source "${SCRIPT_DIR}/read-github-config.sh"

usage() {
	echo "usage: plan-create.sh --title TITLE (--body BODY | --body-file FILE) [--repo OWNER/REPO] [--label LABEL]..." >&2
	exit 1
}

title=""
body=""
body_file=""
repo=""
extra_labels=()

while [[ $# -gt 0 ]]; do
	case "$1" in
	--title)
		title="$2"
		shift 2
		;;
	--body)
		body="$2"
		shift 2
		;;
	--body-file)
		body_file="$2"
		shift 2
		;;
	--repo)
		repo="$2"
		shift 2
		;;
	--label)
		extra_labels+=("$2")
		shift 2
		;;
	*)
		echo "error: unknown option: $1" >&2
		usage
		;;
	esac
done

if [[ -z "${title}" ]]; then
	echo "error: --title is required" >&2
	usage
fi

if [[ -z "${body}" && -z "${body_file}" ]]; then
	echo "error: --body or --body-file is required" >&2
	usage
fi

# Read body from file if specified
if [[ -n "${body_file}" ]]; then
	if [[ "${body_file}" == "-" ]]; then
		body="$(cat)"
	elif [[ -f "${body_file}" ]]; then
		body="$(cat "${body_file}")"
	else
		echo "error: body file not found: ${body_file}" >&2
		exit 1
	fi
fi

# Ensure gh is installed
ensure_gh

# Verify authentication
if ! gh auth status &>/dev/null; then
	echo "error: gh is not authenticated. Run: gh auth login" >&2
	echo "Then re-run this command." >&2
	exit 2
fi

# Resolve repo via fallback chain: --repo flag > dega-core.yaml > git remote
repo="$(gh_resolve_repo "${repo}")"

# Build gh issue create command
gh_args=(issue create --title "${title}" --body "${body}")

# Apply plan:draft label unless labels explicitly disabled in config
if [[ "$(gh_config_value labels)" != "false" ]]; then
	gh_args+=(--label "plan:draft")
fi

for label in "${extra_labels[@]+"${extra_labels[@]}"}"; do
	gh_args+=(--label "${label}")
done

gh_args+=(--repo "${repo}")

# Create the issue and capture the URL
issue_url="$(gh "${gh_args[@]}")"

# Extract issue number from URL (last path segment)
issue_number="${issue_url##*/}"

if [[ ! "${issue_number}" =~ ^[0-9]+$ ]]; then
	echo "error: failed to parse issue number from URL: ${issue_url}" >&2
	exit 1
fi

echo "${issue_number}"

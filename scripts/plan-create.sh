#!/usr/bin/env bash
set -euo pipefail

# Create an issue from plan content and apply the plan:draft label.
# Returns the issue number on stdout.
#
# Usage:
#   plan-create.sh --title "Plan title" --body "markdown body"
#   plan-create.sh --title "Plan title" --body-file /path/to/plan.md
#   plan-create.sh --title "Plan title" --body-file -   # read from stdin
#
# Options:
#   --repo OWNER/REPO   Override repo (default: auto-detected)
#   --label LABEL        Additional label (repeatable, plan:draft always applied)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/providers/provider.sh
source "${SCRIPT_DIR}/providers/provider.sh"

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

# Ensure provider CLI is installed and authenticated
provider_ensure_cli
provider_auth_check

# Build provider_issue_create arguments
create_args=(--title "${title}")

if [[ -n "${body_file}" ]]; then
	create_args+=(--body-file "${body_file}")
else
	create_args+=(--body "${body}")
fi

# Apply plan:draft label unless labels explicitly disabled in config
if [[ "$(provider_config_value labels)" != "false" ]]; then
	create_args+=(--label "plan:draft")
fi

for label in "${extra_labels[@]+"${extra_labels[@]}"}"; do
	create_args+=(--label "${label}")
done

if [[ -n "${repo}" ]]; then
	create_args+=(--repo "${repo}")
fi

# Create the issue and output the number
provider_issue_create "${create_args[@]}"

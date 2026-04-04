#!/usr/bin/env bash
set -euo pipefail

# Fetch a GitHub Issue body by number and write it to a local plan file.
# Usage: gh-plan-fetch.sh <issue-number> <slug> [--repo OWNER/REPO]
#
# Writes to: .orchestrator/plans/<slug>/plan.md
# Requires: gh CLI (auto-installed via ensure-gh.sh), authenticated session

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/providers/provider.sh
source "${SCRIPT_DIR}/providers/provider.sh"

usage() {
	echo "usage: gh-plan-fetch.sh <issue-number> <slug> [--repo OWNER/REPO]" >&2
	echo "" >&2
	echo "Fetches a GitHub Issue body and writes it to:" >&2
	echo "  .orchestrator/plans/<slug>/plan.md" >&2
	exit 1
}

# --- Parse arguments ---

issue_number=""
slug=""
repo=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--repo)
		[[ $# -lt 2 ]] && {
			echo "error: --repo requires a value" >&2
			exit 1
		}
		repo="$2"
		shift 2
		;;
	--help | -h)
		usage
		;;
	*)
		if [[ -z "${issue_number}" ]]; then
			issue_number="$1"
		elif [[ -z "${slug}" ]]; then
			slug="$1"
		else
			echo "error: unexpected argument: $1" >&2
			usage
		fi
		shift
		;;
	esac
done

if [[ -z "${issue_number}" || -z "${slug}" ]]; then
	echo "error: issue number and slug are required." >&2
	usage
fi

if ! [[ "${issue_number}" =~ ^[0-9]+$ ]]; then
	echo "error: issue number must be a positive integer, got: ${issue_number}" >&2
	exit 1
fi

# --- Ensure provider CLI is available ---

provider_ensure_cli || exit 1

# --- Check authentication ---

provider_auth_check || exit $?

# --- Resolve repo ---

if [[ -n "${repo}" ]]; then
	repo="$(provider_repo_resolve --repo "${repo}")"
else
	repo="$(provider_repo_resolve)"
fi

echo "Fetching issue #${issue_number} from ${repo}..." >&2

# --- Fetch issue body ---

body="$(gh issue view "${issue_number}" --repo "${repo}" --json body --jq '.body')" || {
	echo "error: failed to fetch issue #${issue_number} from ${repo}" >&2
	exit 1
}

if [[ -z "${body}" ]]; then
	echo "error: issue #${issue_number} has an empty body." >&2
	exit 1
fi

# --- Write to local plan file ---

plan_dir=".orchestrator/plans/${slug}"
plan_file="${plan_dir}/plan.md"

mkdir -p "${plan_dir}"
printf '%s\n' "${body}" >"${plan_file}"

echo "Plan written to ${plan_file}" >&2
echo "${plan_file}"

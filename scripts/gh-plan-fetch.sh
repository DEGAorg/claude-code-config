#!/usr/bin/env bash
set -euo pipefail

# Fetch a GitHub Issue body by number and write it to a local plan file.
# Usage: gh-plan-fetch.sh <issue-number> <slug> [--repo OWNER/REPO]
#
# Writes to: .orchestrator/plans/<slug>/plan.md
# Requires: gh CLI (auto-installed via ensure-gh.sh), authenticated session

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/ensure-gh.sh
source "${SCRIPT_DIR}/ensure-gh.sh"
# shellcheck source=scripts/read-github-config.sh
source "${SCRIPT_DIR}/read-github-config.sh"

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

# --- Ensure gh is available ---

ensure_gh

# --- Check authentication ---

if ! gh auth status &>/dev/null; then
	echo "error: gh is not authenticated. Run: gh auth login" >&2
	echo "Then re-run this command." >&2
	exit 2
fi

# --- Resolve repo ---

if [[ -z "${repo}" ]]; then
	# Try dega-core.yaml first
	if [[ -f "dega-core.yaml" ]]; then
		yaml_repo="$(grep -E '^\s+repo:' dega-core.yaml | head -1 | sed 's/.*repo:\s*//' | tr -d ' ')" || true
		if [[ -n "${yaml_repo}" ]]; then
			repo="${yaml_repo}"
		fi
	fi

	# Fall back to git remote
	if [[ -z "${repo}" ]]; then
		repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)" || {
			echo "error: could not detect repo. Pass --repo OWNER/REPO or set github.repo in dega-core.yaml" >&2
			exit 1
		}
	fi
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

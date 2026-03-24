#!/usr/bin/env bash
# Upload reviewed plans to GitHub.
#
# Scans docs/exec-plans/active/ for plans with Status: Draft, commits them
# on the current branch, and pushes. Optionally creates GitHub issues.
#
# Usage: scripts/plan-upload.sh [--push] [--issues] [--all]
#
# Options:
#   --push     Push to remote after committing (default: commit only)
#   --issues   Create GitHub issues for each plan (requires gh CLI)
#   --all      Upload all plans, not just Draft ones
#
# Without --push, plans are committed locally so you can inspect before pushing.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ACTIVE_DIR="${REPO_ROOT}/docs/exec-plans/active"

PUSH=false
CREATE_ISSUES=false
UPLOAD_ALL=false

while [[ $# -gt 0 ]]; do
	case "$1" in
	--push)
		PUSH=true
		shift
		;;
	--issues)
		CREATE_ISSUES=true
		shift
		;;
	--all)
		UPLOAD_ALL=true
		shift
		;;
	-*)
		echo "error: unknown option: $1" >&2
		echo "usage: plan-upload.sh [--push] [--issues] [--all]" >&2
		exit 1
		;;
	*)
		echo "error: unexpected argument: $1" >&2
		exit 1
		;;
	esac
done

# Find plans to upload
uploaded=()

for dir in "${ACTIVE_DIR}"/*/; do
	plan_file="${dir}plan.md"
	[[ -f "${plan_file}" ]] || continue

	slug=$(basename "${dir}")

	# Check if already tracked and unchanged
	if git -C "${REPO_ROOT}" diff --quiet -- "${dir}" 2>/dev/null &&
		git -C "${REPO_ROOT}" diff --cached --quiet -- "${dir}" 2>/dev/null &&
		git -C "${REPO_ROOT}" ls-files --error-unmatch "${plan_file}" >/dev/null 2>&1; then
		# File is tracked and has no changes — skip unless --all
		if [[ "${UPLOAD_ALL}" != true ]]; then
			continue
		fi
	fi

	# Check status field (Draft plans are the target)
	if [[ "${UPLOAD_ALL}" != true ]]; then
		status=$(grep -m1 '^\*\*Status:\*\*' "${plan_file}" 2>/dev/null |
			sed 's/.*\*\*Status:\*\*[[:space:]]*//' || true)
		# Skip plans still in Draft — they haven't been reviewed yet
		if echo "${status}" | grep -qi "draft"; then
			echo "skipping ${slug} — still in Draft status (review first, then change to 'In progress')"
			continue
		fi
	fi

	echo "staging ${slug}"
	git -C "${REPO_ROOT}" add "${dir}"
	uploaded+=("${slug}")
done

if [[ ${#uploaded[@]} -eq 0 ]]; then
	echo "no plans to upload"
	echo ""
	echo "Tip: Change plan status from 'Draft' to 'In progress' after review,"
	echo "     then run this script again. Or use --all to upload everything."
	exit 0
fi

# Commit
slug_list=$(printf ', %s' "${uploaded[@]}")
slug_list="${slug_list:2}"

git -C "${REPO_ROOT}" commit -m "$(
	cat <<-EOF
		plan: add reviewed plans (${slug_list})

		Plans created via planner-loop --plan-only, reviewed, and ready
		for orchestrator execution.

		Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
	EOF
)"

echo ""
echo "committed ${#uploaded[@]} plan(s): ${slug_list}"

# Push
if [[ "${PUSH}" == true ]]; then
	branch=$(git -C "${REPO_ROOT}" rev-parse --abbrev-ref HEAD)
	echo "pushing to origin/${branch}"
	git -C "${REPO_ROOT}" push -u origin "${branch}"
	echo "pushed"
fi

# Create GitHub issues via plan-issue.sh (idempotent)
if [[ "${CREATE_ISSUES}" == true ]]; then
	SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	for slug in "${uploaded[@]}"; do
		echo "creating issue for ${slug}"
		issue_num=$("${SCRIPT_DIR}/plan-issue.sh" "${slug}") || {
			echo "warning: failed to create issue for ${slug}" >&2
			continue
		}
		echo "  issue #${issue_num}"
	done
fi

echo ""
echo "done. Next: run the orchestrator on these plans:"
for slug in "${uploaded[@]}"; do
	echo "  bash scripts/orch-run.sh docs/exec-plans/active/${slug}"
done

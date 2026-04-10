#!/usr/bin/env bash
# GitHub provider — implements the provider interface contract
# (_interface.md) using the `gh` CLI.
#
# Source this file via provider.sh — never directly.

set -euo pipefail

# --- Internal: config helpers ---

_gh_find_dega_core_yaml() {
	local dir="$PWD"
	while [[ "${dir}" != "/" ]]; do
		if [[ -f "${dir}/dega-core.yaml" ]]; then
			echo "${dir}/dega-core.yaml"
			return 0
		fi
		dir="$(dirname "${dir}")"
	done
	return 1
}

_GH_DEGA_CORE_YAML=""
_gh_dega_core_yaml() {
	if [[ -z "${_GH_DEGA_CORE_YAML}" ]]; then
		_GH_DEGA_CORE_YAML="$(_gh_find_dega_core_yaml 2>/dev/null)" || true
	fi
	echo "${_GH_DEGA_CORE_YAML}"
}

# Read a value from the github: block in dega-core.yaml.
_gh_config_raw() {
	local key="$1"
	local yaml
	yaml="$(_gh_dega_core_yaml)"
	if [[ -z "${yaml}" ]]; then
		return 0
	fi
	grep -A 20 '^github:' "${yaml}" 2>/dev/null |
		grep -E "^  ${key}:" |
		head -1 |
		sed "s/^  ${key}:[[:space:]]*//" |
		sed 's/[[:space:]]*#.*//' |
		tr -d ' ' || true
}

# --- Authentication ---

provider_ensure_cli() {
	if command -v gh &>/dev/null; then
		return 0
	fi

	echo "gh CLI not found. Attempting to install via Homebrew..." >&2

	if ! command -v brew &>/dev/null; then
		echo "error: gh CLI is not installed and Homebrew is not available." >&2
		echo "" >&2
		echo "Install gh manually:" >&2
		case "$(uname -s)" in
		Darwin)
			echo "  Option 1: Install Homebrew first — https://brew.sh" >&2
			echo "  Option 2: Download gh from https://cli.github.com" >&2
			;;
		Linux)
			echo "  Option 1: Install Homebrew for Linux — https://brew.sh" >&2
			echo "  Option 2: See https://github.com/cli/cli/blob/trunk/docs/install_linux.md" >&2
			;;
		*)
			echo "  See https://cli.github.com for installation instructions." >&2
			;;
		esac
		return 1
	fi

	brew install gh >&2 || {
		echo "error: brew install gh failed." >&2
		return 1
	}

	if ! command -v gh &>/dev/null; then
		echo "error: gh was installed but is not in PATH." >&2
		return 1
	fi

	echo "gh installed successfully." >&2
}

provider_auth_check() {
	if gh auth status &>/dev/null; then
		return 0
	fi
	echo "error: gh is not authenticated. Run: gh auth login" >&2
	return 2
}

# --- Repository resolution ---

# shellcheck disable=SC2120
provider_repo_resolve() {
	local explicit=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--repo)
			explicit="$2"
			shift 2
			;;
		*)
			shift
			;;
		esac
	done

	if [[ -n "${explicit}" ]]; then
		echo "${explicit}"
		return 0
	fi

	local config_repo
	config_repo="$(_gh_config_raw repo)"
	if [[ -n "${config_repo}" ]]; then
		echo "${config_repo}"
		return 0
	fi

	local remote_repo
	remote_repo="$(gh repo view --json nameWithOwner \
		--jq '.nameWithOwner' 2>/dev/null)" || {
		echo "error: could not detect repo. Pass --repo OWNER/REPO or set github.repo in dega-core.yaml" >&2
		return 1
	}
	echo "${remote_repo}"
}

# Resolve repo from an optional argument, falling back to auto-detection.
_gh_resolve_repo_arg() {
	local repo="$1"
	if [[ -n "${repo}" ]]; then
		echo "${repo}"
	else
		# shellcheck disable=SC2119
		provider_repo_resolve
	fi
}

# --- Issues ---

provider_issue_create() {
	local title="" body="" body_file="" repo=""
	local labels=()

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
			labels+=("$2")
			shift 2
			;;
		*)
			echo "error: provider_issue_create: unknown arg: $1" >&2
			return 1
			;;
		esac
	done

	if [[ -z "${title}" ]]; then
		echo "error: provider_issue_create: --title required" >&2
		return 1
	fi

	if [[ -z "${body}" && -z "${body_file}" ]]; then
		echo "error: provider_issue_create: --body or --body-file required" >&2
		return 1
	fi

	if [[ -n "${body_file}" ]]; then
		if [[ "${body_file}" == "-" ]]; then
			body="$(cat)"
		elif [[ -f "${body_file}" ]]; then
			body="$(cat "${body_file}")"
		else
			echo "error: provider_issue_create: body file not found: ${body_file}" >&2
			return 1
		fi
	fi

	repo="$(_gh_resolve_repo_arg "${repo}")"

	local gh_args=(issue create --title "${title}" --body "${body}" --repo "${repo}")
	for label in "${labels[@]+"${labels[@]}"}"; do
		gh_args+=(--label "${label}")
	done

	local issue_url
	issue_url="$(gh "${gh_args[@]}")"

	local issue_number="${issue_url##*/}"
	if [[ ! "${issue_number}" =~ ^[0-9]+$ ]]; then
		echo "error: provider_issue_create: failed to parse issue number from: ${issue_url}" >&2
		return 1
	fi

	echo "${issue_number}"
}

provider_issue_view() {
	local issue="" repo="" fields=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--issue)
			issue="$2"
			shift 2
			;;
		--repo)
			repo="$2"
			shift 2
			;;
		--fields)
			fields="$2"
			shift 2
			;;
		*)
			echo "error: provider_issue_view: unknown arg: $1" >&2
			return 1
			;;
		esac
	done

	if [[ -z "${issue}" ]]; then
		echo "error: provider_issue_view: --issue required" >&2
		return 1
	fi

	repo="$(_gh_resolve_repo_arg "${repo}")"

	# Build jq filter to reshape labels into string array
	local jq_filter
	jq_filter='{body, state, title, assignees, milestone}'
	jq_filter="${jq_filter} + {labels: [.labels[].name]}"

	# If specific fields requested, select only those
	if [[ -n "${fields}" ]]; then
		local keys_jq
		keys_jq="$(echo "${fields}" | tr ',' '\n' | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//')"
		jq_filter="(${jq_filter}) | {${keys_jq}}"
	fi

	gh issue view "${issue}" --repo "${repo}" \
		--json body,state,labels,title,assignees,milestone \
		--jq "${jq_filter}"
}

provider_issue_edit() {
	local issue="" repo="" body=""
	local add_labels=()
	local remove_labels=()

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--issue)
			issue="$2"
			shift 2
			;;
		--repo)
			repo="$2"
			shift 2
			;;
		--body)
			body="$2"
			shift 2
			;;
		--add-label)
			add_labels+=("$2")
			shift 2
			;;
		--remove-label)
			remove_labels+=("$2")
			shift 2
			;;
		*)
			echo "error: provider_issue_edit: unknown arg: $1" >&2
			return 1
			;;
		esac
	done

	if [[ -z "${issue}" ]]; then
		echo "error: provider_issue_edit: --issue required" >&2
		return 1
	fi

	repo="$(_gh_resolve_repo_arg "${repo}")"

	local gh_args=(issue edit "${issue}" --repo "${repo}")

	if [[ -n "${body}" ]]; then
		gh_args+=(--body "${body}")
	fi

	for label in "${add_labels[@]+"${add_labels[@]}"}"; do
		gh_args+=(--add-label "${label}")
	done

	for label in "${remove_labels[@]+"${remove_labels[@]}"}"; do
		gh_args+=(--remove-label "${label}")
	done

	gh "${gh_args[@]}" >/dev/null
}

provider_issue_comment() {
	local issue="" repo="" body=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--issue)
			issue="$2"
			shift 2
			;;
		--repo)
			repo="$2"
			shift 2
			;;
		--body)
			body="$2"
			shift 2
			;;
		*)
			echo "error: provider_issue_comment: unknown arg: $1" >&2
			return 1
			;;
		esac
	done

	if [[ -z "${issue}" ]]; then
		echo "error: provider_issue_comment: --issue required" >&2
		return 1
	fi
	if [[ -z "${body}" ]]; then
		echo "error: provider_issue_comment: --body required" >&2
		return 1
	fi

	repo="$(_gh_resolve_repo_arg "${repo}")"

	gh issue comment "${issue}" --repo "${repo}" --body "${body}"
}

provider_issue_close() {
	local issue="" repo=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--issue)
			issue="$2"
			shift 2
			;;
		--repo)
			repo="$2"
			shift 2
			;;
		*)
			echo "error: provider_issue_close: unknown arg: $1" >&2
			return 1
			;;
		esac
	done

	if [[ -z "${issue}" ]]; then
		echo "error: provider_issue_close: --issue required" >&2
		return 1
	fi

	repo="$(_gh_resolve_repo_arg "${repo}")"

	# Idempotent — check state first
	local state
	state="$(gh issue view "${issue}" --repo "${repo}" \
		--json state --jq '.state')" || {
		echo "error: provider_issue_close: failed to read issue #${issue}" >&2
		return 1
	}

	if [[ "${state}" == "CLOSED" ]]; then
		return 0
	fi

	gh issue close "${issue}" --repo "${repo}" >/dev/null
}

provider_issue_list() {
	local repo="" state="open" limit="100"
	local labels=()

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--repo)
			repo="$2"
			shift 2
			;;
		--state)
			state="$2"
			shift 2
			;;
		--label)
			labels+=("$2")
			shift 2
			;;
		--limit)
			limit="$2"
			shift 2
			;;
		*)
			echo "error: provider_issue_list: unknown arg: $1" >&2
			return 1
			;;
		esac
	done

	repo="$(_gh_resolve_repo_arg "${repo}")"

	local gh_args=(issue list --repo "${repo}" --state "${state}")
	gh_args+=(--limit "${limit}")
	gh_args+=(--json "number,title,state,labels,milestone,assignees")

	for label in "${labels[@]+"${labels[@]}"}"; do
		gh_args+=(--label "${label}")
	done

	gh "${gh_args[@]}" | jq '[.[] | {
    number, title, state,
    labels: [.labels[].name],
    milestone: .milestone,
    assignees: .assignees
  }]'
}

# --- Pull requests ---

provider_pr_create() {
	local title="" body="" base="" head="" repo=""

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
		--base)
			base="$2"
			shift 2
			;;
		--head)
			head="$2"
			shift 2
			;;
		--repo)
			repo="$2"
			shift 2
			;;
		*)
			echo "error: provider_pr_create: unknown arg: $1" >&2
			return 1
			;;
		esac
	done

	if [[ -z "${title}" || -z "${body}" || -z "${base}" || -z "${head}" ]]; then
		echo "error: provider_pr_create: --title, --body, --base, --head required" >&2
		return 1
	fi

	local gh_args=(pr create --title "${title}" --body "${body}")
	gh_args+=(--base "${base}" --head "${head}")

	if [[ -n "${repo}" ]]; then
		repo="$(_gh_resolve_repo_arg "${repo}")"
		gh_args+=(--repo "${repo}")
	fi

	gh "${gh_args[@]}"
}

# --- Labels ---

provider_labels_get() {
	local issue="" repo=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--issue)
			issue="$2"
			shift 2
			;;
		--repo)
			repo="$2"
			shift 2
			;;
		*)
			echo "error: provider_labels_get: unknown arg: $1" >&2
			return 1
			;;
		esac
	done

	if [[ -z "${issue}" ]]; then
		echo "error: provider_labels_get: --issue required" >&2
		return 1
	fi

	repo="$(_gh_resolve_repo_arg "${repo}")"

	gh issue view "${issue}" --repo "${repo}" \
		--json labels --jq '[.labels[].name] | join(",")'
}

provider_labels_set() {
	local issue="" repo="" label="" family="plan:"

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--issue)
			issue="$2"
			shift 2
			;;
		--repo)
			repo="$2"
			shift 2
			;;
		--label)
			label="$2"
			shift 2
			;;
		--family)
			family="$2"
			shift 2
			;;
		*)
			echo "error: provider_labels_set: unknown arg: $1" >&2
			return 1
			;;
		esac
	done

	if [[ -z "${issue}" ]]; then
		echo "error: provider_labels_set: --issue required" >&2
		return 1
	fi
	if [[ -z "${label}" ]]; then
		echo "error: provider_labels_set: --label required" >&2
		return 1
	fi

	repo="$(_gh_resolve_repo_arg "${repo}")"

	# Get current labels and remove any matching the family prefix
	local current_labels
	current_labels="$(provider_labels_get --issue "${issue}" --repo "${repo}")"

	IFS=',' read -ra label_arr <<<"${current_labels}"
	for existing in "${label_arr[@]}"; do
		if [[ "${existing}" == "${family}"* ]]; then
			gh issue edit "${issue}" --repo "${repo}" \
				--remove-label "${existing}" >/dev/null 2>&1 || true
		fi
	done

	# Add the target label
	gh issue edit "${issue}" --repo "${repo}" \
		--add-label "${label}" >/dev/null
}

# --- Milestones ---

provider_milestone_list() {
	local repo="" state="all"

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--repo)
			repo="$2"
			shift 2
			;;
		--state)
			state="$2"
			shift 2
			;;
		*)
			echo "error: provider_milestone_list: unknown arg: $1" >&2
			return 1
			;;
		esac
	done

	repo="$(_gh_resolve_repo_arg "${repo}")"

	gh api "repos/${repo}/milestones?state=${state}&per_page=100" \
		--jq '[.[] | {
      number, title, description, due_on,
      open_issues, closed_issues
    }]'
}

# --- Project boards ---

provider_project_items_list() {
	local project="" owner="" limit="200"

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--project)
			project="$2"
			shift 2
			;;
		--owner)
			owner="$2"
			shift 2
			;;
		--limit)
			limit="$2"
			shift 2
			;;
		*)
			echo "error: provider_project_items_list: unknown arg: $1" >&2
			return 1
			;;
		esac
	done

	if [[ -z "${project}" ]]; then
		echo "error: provider_project_items_list: --project required" >&2
		return 1
	fi
	if [[ -z "${owner}" ]]; then
		echo "error: provider_project_items_list: --owner required" >&2
		return 1
	fi

	gh project item-list "${project}" --owner "${owner}" \
		--format json --limit "${limit}"
}

provider_project_field_edit() {
	local project_id="" item_id="" field_id="" value=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--project-id)
			project_id="$2"
			shift 2
			;;
		--item-id)
			item_id="$2"
			shift 2
			;;
		--field-id)
			field_id="$2"
			shift 2
			;;
		--value)
			value="$2"
			shift 2
			;;
		*)
			echo "error: provider_project_field_edit: unknown arg: $1" >&2
			return 1
			;;
		esac
	done

	if [[ -z "${project_id}" || -z "${item_id}" || -z "${field_id}" || -z "${value}" ]]; then
		echo "error: provider_project_field_edit: --project-id, --item-id, --field-id, --value required" >&2
		return 1
	fi

	gh project item-edit \
		--project-id "${project_id}" \
		--id "${item_id}" \
		--field-id "${field_id}" \
		--single-select-option-id "${value}"
}

# --- Configuration ---

provider_config_value() {
	local key="${1:?provider_config_value requires a key}"
	_gh_config_raw "${key}"
}

provider_config_bool() {
	local key="${1:?provider_config_bool requires a key}"
	local val
	val="$(_gh_config_raw "${key}")"
	[[ "${val}" == "true" ]]
}

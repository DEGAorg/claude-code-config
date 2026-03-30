#!/usr/bin/env bash
# Shared helper to read github: config block from dega-core.yaml.
# Source this file — it provides functions, not a standalone script.
#
# Functions:
#   gh_config_value <key>     — print value for github.<key>, empty if unset
#   gh_config_bool <key>      — exit 0 if github.<key> is true, 1 otherwise
#   gh_config_repo            — print repo from config, empty if unset
#   gh_resolve_repo           — resolve repo: --repo flag > config > git remote

# Find dega-core.yaml by walking up from cwd (supports worktrees)
_find_dega_core_yaml() {
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

_DEGA_CORE_YAML=""
_dega_core_yaml() {
	if [[ -z "${_DEGA_CORE_YAML}" ]]; then
		_DEGA_CORE_YAML="$(_find_dega_core_yaml 2>/dev/null)" || true
	fi
	echo "${_DEGA_CORE_YAML}"
}

# Read a value under the github: block.
# Usage: gh_config_value repo  → prints "DEGAorg/claude-code-config"
gh_config_value() {
	local key="$1"
	local yaml
	yaml="$(_dega_core_yaml)"
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

# Check if a github config boolean is true.
# Usage: if gh_config_bool labels; then ...
gh_config_bool() {
	local val
	val="$(gh_config_value "$1")"
	[[ "${val}" == "true" ]]
}

# Shortcut: get github.repo from config.
gh_config_repo() {
	gh_config_value "repo"
}

# Resolve repo with standard fallback chain:
#   1. Explicit value passed as $1 (from --repo flag)
#   2. github.repo in dega-core.yaml
#   3. git remote auto-detection via gh
# Prints resolved repo or exits 1.
gh_resolve_repo() {
	local explicit="${1:-}"

	if [[ -n "${explicit}" ]]; then
		echo "${explicit}"
		return 0
	fi

	local config_repo
	config_repo="$(gh_config_repo)"
	if [[ -n "${config_repo}" ]]; then
		echo "${config_repo}"
		return 0
	fi

	local remote_repo
	remote_repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)" || {
		echo "error: could not detect repo. Pass --repo OWNER/REPO or set github.repo in dega-core.yaml" >&2
		return 1
	}
	echo "${remote_repo}"
}

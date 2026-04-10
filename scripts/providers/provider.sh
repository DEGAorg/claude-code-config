#!/usr/bin/env bash
# Provider shim — reads `provider:` from dega-core.yaml and sources the
# matching provider script. Callers source this file to get provider_*
# functions; they never source a specific provider directly.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/providers/provider.sh"

set -euo pipefail

# --- Locate dega-core.yaml ---

_provider_find_dega_core_yaml() {
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

# --- Read provider name ---

_provider_read_name() {
	local yaml
	yaml="$(_provider_find_dega_core_yaml)" || {
		echo "error: dega-core.yaml not found" >&2
		return 1
	}
	local name
	name="$(grep -E '^provider:' "${yaml}" | head -1 |
		sed 's/^provider:[[:space:]]*//' |
		sed 's/[[:space:]]*#.*//' |
		tr -d ' ')"
	if [[ -z "${name}" ]]; then
		echo "error: no 'provider:' field in ${yaml}" >&2
		return 1
	fi
	echo "${name}"
}

# --- Source the provider ---

_PROVIDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_provider_name="$(_provider_read_name)" || exit 1
_provider_script="${_PROVIDER_DIR}/${_provider_name}.sh"

if [[ ! -f "${_provider_script}" ]]; then
	echo "error: provider script not found: ${_provider_script}" >&2
	echo "Available providers:" >&2
	for f in "${_PROVIDER_DIR}"/*.sh; do
		local_name="$(basename "${f}" .sh)"
		if [[ "${local_name}" != "provider" ]]; then
			echo "  - ${local_name}" >&2
		fi
	done
	exit 1
fi

# shellcheck source=/dev/null
source "${_provider_script}"

# Clean up variables that callers don't need.
unset _provider_name _provider_script

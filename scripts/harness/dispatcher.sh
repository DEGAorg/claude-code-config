#!/usr/bin/env bash
# Harness dispatcher — reads `harness:` from dega-core.yaml (or the
# DEGA_HARNESS env override) and sources the matching backend. Callers
# source this file to get `harness::*` functions; they never source a
# specific backend directly.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/harness/dispatcher.sh"
#
# Contract: scripts/harness/contract.md

set -euo pipefail

# --- Locate dega-core.yaml ---

_harness_find_dega_core_yaml() {
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

# --- Read backend name ---

_harness_read_name() {
  if [[ -n "${DEGA_HARNESS:-}" ]]; then
    printf '%s\n' "${DEGA_HARNESS}"
    return 0
  fi

  local yaml
  if ! yaml="$(_harness_find_dega_core_yaml)"; then
    # No config found — default to local.
    echo "local"
    return 0
  fi

  local name
  name="$(grep -E '^harness:' "${yaml}" | head -1 |
    sed 's/^harness:[[:space:]]*//' |
    sed 's/[[:space:]]*#.*//' |
    tr -d ' ')"
  if [[ -z "${name}" ]]; then
    name="local"
  fi
  printf '%s\n' "${name}"
}

# --- Source the backend ---

_HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_harness_name="$(_harness_read_name)"
_harness_script="${_HARNESS_DIR}/${_harness_name}.sh"

if [[ ! -f "${_harness_script}" ]]; then
  echo "error: harness backend not found: ${_harness_script}" >&2
  echo "Available backends:" >&2
  for _f in "${_HARNESS_DIR}"/*.sh; do
    [[ -e "${_f}" ]] || continue
    _base="$(basename "${_f}" .sh)"
    if [[ "${_base}" != "dispatcher" ]]; then
      echo "  - ${_base}" >&2
    fi
  done
  exit 1
fi

# shellcheck source=/dev/null
source "${_harness_script}"

unset _harness_name _harness_script _f _base

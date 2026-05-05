#!/usr/bin/env bash
set -euo pipefail

# Print the installed core version, the latest version on the remote,
# and the relative status: up-to-date, behind, or ahead.
#
# Output format:
#   installed=<x.y.z>  latest=<x.y.z>  status=<up-to-date|behind|ahead|unknown>
#
# Sources:
#   installed → ~/.degacore/VERSION (written during /apply-core)
#   latest    → raw VERSION file on the remote default branch
#
# Network or filesystem failures yield the literal "unknown" rather than
# aborting, so the script is safe to call from status banners.

INSTALLED_VERSION_FILE="${DEGACORE_VERSION_FILE:-$HOME/.degacore/VERSION}"
REMOTE_REPO="${DEGACORE_REMOTE_REPO:-DEGAorg/claude-code-config}"

read_installed() {
  if [[ -f "$INSTALLED_VERSION_FILE" ]]; then
    tr -d '[:space:]' <"$INSTALLED_VERSION_FILE"
  else
    printf 'unknown'
  fi
}

read_latest() {
  if ! command -v gh >/dev/null 2>&1; then
    printf 'unknown'
    return
  fi
  local body
  if body=$(gh api -H 'Accept: application/vnd.github.raw' \
    "repos/${REMOTE_REPO}/contents/VERSION" 2>/dev/null); then
    printf '%s' "$body" | tr -d '[:space:]'
  else
    printf 'unknown'
  fi
}

# Compare two semver-ish strings. Echoes one of: up-to-date, behind, ahead, unknown.
compare_versions() {
  local installed=$1 latest=$2
  if [[ "$installed" == "unknown" ]] || [[ "$latest" == "unknown" ]]; then
    printf 'unknown'
    return
  fi
  if [[ "$installed" == "$latest" ]]; then
    printf 'up-to-date'
    return
  fi
  local re='^[0-9]+\.[0-9]+\.[0-9]+$'
  if [[ ! "$installed" =~ $re ]] || [[ ! "$latest" =~ $re ]]; then
    printf 'unknown'
    return
  fi
  local IFS=.
  # shellcheck disable=SC2206
  local i=($installed) l=($latest)
  local idx
  for idx in 0 1 2; do
    if ((i[idx] < l[idx])); then
      printf 'behind'
      return
    fi
    if ((i[idx] > l[idx])); then
      printf 'ahead'
      return
    fi
  done
  printf 'up-to-date'
}

main() {
  local installed latest status
  installed=$(read_installed)
  latest=$(read_latest)
  status=$(compare_versions "$installed" "$latest")
  printf 'installed=%s  latest=%s  status=%s\n' "$installed" "$latest" "$status"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

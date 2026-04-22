#!/usr/bin/env bash
# Print the current canon phase for the working directory.
#
# Phases (first match wins, checked in order):
#   not-bootstrapped          — no dega-core.yaml at cwd
#   bootstrapped-no-strategy  — dega-core.yaml present, canon/strategies/ empty or absent
#   has-strategy              — dega-core.yaml + non-empty canon/strategies/, no active run
#   running                   — has-strategy AND .canon/state.json shows phase != "idle"
#                               AND status != "idle"
#
# The running marker is .canon/state.json (written by scripts/canon.sh).
# Running requires the prior phases as prerequisites — a stale state.json
# without a strategy reports bootstrapped-no-strategy, not running.

set -euo pipefail

# shellcheck source=canon-error.sh
source "$(dirname "${BASH_SOURCE[0]}")/canon-error.sh"

# Convert any unexpected bash-level failure (set -e trigger) into a
# structured canon-error line so the agent can route it per the contract
# in canon/scripts/README.md.
trap 'canon_error 1 phase-detect-failed "unexpected error in phase-detect.sh"' ERR

if [[ ! -f "dega-core.yaml" ]]; then
  echo "not-bootstrapped"
  exit 0
fi

if [[ ! -d "canon/strategies" ]]; then
  echo "bootstrapped-no-strategy"
  exit 0
fi

shopt -s nullglob dotglob
entries=(canon/strategies/*)
shopt -u nullglob dotglob

if ((${#entries[@]} == 0)); then
  echo "bootstrapped-no-strategy"
  exit 0
fi

state_file=".canon/state.json"
if [[ -f "$state_file" ]]; then
  # Extract "phase" and "status" string values with a minimal regex.
  # Accepts the canon.sh writer's compact JSON shape.
  phase="$(sed -n 's/.*"phase"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$state_file" | head -n1)"
  status="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$state_file" | head -n1)"
  if [[ -n "$phase" && "$phase" != "idle" && -n "$status" && "$status" != "idle" ]]; then
    echo "running"
    exit 0
  fi
fi

echo "has-strategy"

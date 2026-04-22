#!/usr/bin/env bash
# Print the current canon bootstrap phase for the working directory.
#
# Phases:
#   not-bootstrapped          — no dega-core.yaml at cwd
#   bootstrapped-no-strategy  — dega-core.yaml present, canon/strategies/ empty or absent
#   has-strategy              — dega-core.yaml present, canon/strategies/ has at least one entry

set -euo pipefail

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
else
  echo "has-strategy"
fi

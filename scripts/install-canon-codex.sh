#!/usr/bin/env bash
# Install the Canon Codex entry points from a repo or Core config cache.
# Usage: install-canon-codex.sh SOURCE_ROOT [SKILLS_DIR]
set -euo pipefail

SOURCE_ROOT="${1:?usage: install-canon-codex.sh SOURCE_ROOT [SKILLS_DIR]}"
SKILLS_DIR="${2:-${CODEX_HOME:-${HOME}/.codex}/skills}"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

verify_existing() {
  local target="$1" path
  [[ ! -L "$target" ]] || fail "skill is a symlink: $target; choose a separate destination"
  [[ -e "$target" ]] || return 0
  for path in SKILL.md references references/workflow.md .dega-core.sha256; do
    [[ ! -L "$target/$path" ]] || fail "managed path is a symlink: $target/$path"
  done
  [[ -f "$target/.dega-core.sha256" ]] ||
    fail "user-owned skill at $target; move it aside before installing Canon"
  (cd "$target" && shasum -a 256 -c .dega-core.sha256 >/dev/null 2>&1) ||
    fail "locally modified skill at $target; preserve your edits before updating Canon"
}

for name in canon-start canon-init; do
  source_skill="$SOURCE_ROOT/skills/codex/$name/SKILL.md"
  workflow="$SOURCE_ROOT/commands/$name.md"
  [[ -s "$source_skill" ]] || fail "missing $source_skill; fetch the complete Codex skills tree"
  [[ -s "$workflow" ]] || fail "missing $workflow; fetch Canon commands from the same release"
  verify_existing "$SKILLS_DIR/$name"
done

for name in canon-start canon-init; do
  target="$SKILLS_DIR/$name"
  mkdir -p "$target/references"
  cp "$SOURCE_ROOT/skills/codex/$name/SKILL.md" "$target/SKILL.md"
  cp "$SOURCE_ROOT/commands/$name.md" "$target/references/workflow.md"
  (
    cd "$target"
    shasum -a 256 SKILL.md references/workflow.md >.dega-core.sha256
    shasum -a 256 -c .dega-core.sha256 >/dev/null
  )
  printf 'installed: %s\n' "$target"
done

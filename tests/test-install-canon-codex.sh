#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'find "$TEST_ROOT" -type f -delete; find "$TEST_ROOT" -type d -empty -delete' EXIT
INSTALLER="$REPO_ROOT/scripts/install-canon-codex.sh"
SOURCE="$TEST_ROOT/source"
DEST="$TEST_ROOT/skills with spaces"
mkdir -p "$SOURCE/skills/codex" "$SOURCE/commands"
for name in canon-start canon-init; do
  cp -R "$REPO_ROOT/skills/codex/$name" "$SOURCE/skills/codex/$name"
  cp "$REPO_ROOT/commands/$name.md" "$SOURCE/commands/$name.md"
done

bash "$INSTALLER" "$SOURCE" "$DEST"
for name in canon-start canon-init; do
  cmp "$SOURCE/skills/codex/$name/SKILL.md" "$DEST/$name/SKILL.md"
  cmp "$SOURCE/commands/$name.md" "$DEST/$name/references/workflow.md"
done
bash "$INSTALLER" "$SOURCE" "$DEST"
printf '\nUpdated workflow\n' >>"$SOURCE/commands/canon-start.md"
bash "$INSTALLER" "$SOURCE" "$DEST"
cmp "$SOURCE/commands/canon-start.md" "$DEST/canon-start/references/workflow.md"

# Existing user skills survive, and all destinations are checked before writing.
mkdir -p "$TEST_ROOT/conflict/canon-init"
printf 'user skill\n' >"$TEST_ROOT/conflict/canon-init/SKILL.md"
if bash "$INSTALLER" "$SOURCE" "$TEST_ROOT/conflict" >"$TEST_ROOT/error" 2>&1; then
  exit 1
fi
[[ ! -e "$TEST_ROOT/conflict/canon-start" ]]
[[ "$(cat "$TEST_ROOT/conflict/canon-init/SKILL.md")" == 'user skill' ]]

printf '\nLocal edit\n' >>"$DEST/canon-start/SKILL.md"
cp "$DEST/canon-start/SKILL.md" "$TEST_ROOT/edited"
if bash "$INSTALLER" "$SOURCE" "$DEST" >"$TEST_ROOT/error" 2>&1; then
  exit 1
fi
cmp "$TEST_ROOT/edited" "$DEST/canon-start/SKILL.md"

# Missing sources cannot produce a partially successful install.
mv "$SOURCE/commands/canon-init.md" "$SOURCE/commands/canon-init.saved"
if bash "$INSTALLER" "$SOURCE" "$TEST_ROOT/missing" >"$TEST_ROOT/error" 2>&1; then
  exit 1
fi
[[ ! -e "$TEST_ROOT/missing" ]]
mv "$SOURCE/commands/canon-init.saved" "$SOURCE/commands/canon-init.md"

# CODEX_HOME can target an isolated host without modifying the user's install.
CODEX_HOME="$TEST_ROOT/custom-codex" bash "$INSTALLER" "$SOURCE"
test -s "$TEST_ROOT/custom-codex/skills/canon-start/references/workflow.md"
mkdir -p "$TEST_ROOT/linked"
ln -s "$DEST/canon-start" "$TEST_ROOT/linked/canon-start"
if bash "$INSTALLER" "$SOURCE" "$TEST_ROOT/linked" >"$TEST_ROOT/error" 2>&1; then
  exit 1
fi
unlink "$TEST_ROOT/linked/canon-start"

mv "$SOURCE/skills/codex/canon-init/SKILL.md" "$SOURCE/skills/codex/canon-init/saved"
if bash "$INSTALLER" "$SOURCE" "$TEST_ROOT/missing-skill" >"$TEST_ROOT/error" 2>&1; then
  exit 1
fi
[[ ! -e "$TEST_ROOT/missing-skill" ]]
mv "$SOURCE/skills/codex/canon-init/saved" "$SOURCE/skills/codex/canon-init/SKILL.md"

printf 'PASS: fresh install, repeat, update, conflicts, missing source, custom Codex home\n'

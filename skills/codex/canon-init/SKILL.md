---
name: canon-init
description: >-
  Bootstrap a Canon project for Codex by checking the Core installation and creating a local
  Codex launcher. Use for canon-init; use canon-start for strategy selection and execution.
---

# Canon Init in Codex

Read `references/workflow.md` beside this skill. It contains the shared
`commands/canon-init.md` procedure. Follow its disclaimer and wrong-directory
guard, with these host-specific replacements for steps 3–6:

1. Check `codex` is on PATH, and that
   `${DEGA_CORE_HOME:-$HOME/.degacore}/scripts/canon-scaffold.sh` and
   `${DEGA_CORE_HOME:-$HOME/.degacore}/canon/templates/package.json` exist.
   Also check the installed sibling `canon-start/SKILL.md` and its
   `references/workflow.md`. Collect missing prerequisites and stop with an
   actionable message. Core scripts/templates require the Canon Bootstrap
   component; missing skill files require re-running the Codex skill installer.
2. Create `.canon` in the strategy project. The global `canon-start` skill is
   already installed; do not fetch a Claude command into `.claude/commands`.
3. Write the following launcher to `canon.sh` and make it executable. If that
   file already contains different content, show the difference and ask before
   replacing it. Re-running with identical content is safe.

   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   cd "${PROJECT_DIR}"
   export DEGA_PROVIDER=codex
   exec codex "\$canon-start"
   ```

4. Report: `Canon bootstrap complete. Use $canon-start in this Codex session,
   or run ./canon.sh from a terminal to open Codex.` Stop here. Initialization
   does not choose a strategy, scaffold templates, create a wallet, or launch
   trading. The `canon-start` workflow handles those next steps.

The launcher targets Codex explicitly. Canon TUI is optional and configured
separately; do not launch its default agent or require Claude/tmux here.

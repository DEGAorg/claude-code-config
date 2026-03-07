# Apply Core

@description Install DEGA Core AI development artifacts globally to ~/.claude/. Ralph Loop engine scripts install globally; only ralph.yaml is per-project.

Install Core harness artifacts from GitHub into `~/.claude/`. Works from any
directory — no need to clone the repo. Ralph Loop engine scripts install
globally to `~/.claude/scripts/`; only `ralph.yaml` is per-project.

## Source

All files are fetched from:

```
https://raw.githubusercontent.com/DEGAorg/claude-code-config/ace-work/
```

Files available:
- `settings.json`
- `claude-md-template.md`
- `commands/fix-issue.md`
- `commands/review-pr.md`
- `commands/plan.md`
- `commands/cleanup.md`
- `commands/doc-garden.md`
- `commands/core-init.md`
- `rules/python.md`
- `rules/node-typescript.md`
- `rules/rust.md`
- `rules/bash.md`
- `rules/github-actions.md`
- `hooks/enforce-package-manager.sh`
- `hooks/log-gam.sh`
- `hooks/update-exec-plan-reminder.sh`
- `hooks/session-start-logging.sh`
- `hooks/structured-log.sh`
- `hooks/ralph-reviewer-stop.sh`
- `skills/custom-linter-authoring.md`
- `skills/app-legibility.md`
- `skills/sound-notifications.md`
- `scripts/log-server.py`
- `ralph.yaml`
- `scripts/ralph-check.sh`
- `scripts/ralph-loop.sh`
- `scripts/ralph-worker-prompt.md`
- `scripts/ralph-reviewer-prompt.md`
- `scripts/log-client.sh`
- `scripts/plan-advance.sh`
- `scripts/task-complete.sh`
- `scripts/canon-runner.sh`
- `scripts/ralph-worktree.sh`
- `scripts/terminal-session.sh`
- `scripts/terminal-ui-write.sh`
- `scripts/terminal-ui/package.json`
- `scripts/terminal-ui/tsconfig.json`
- `scripts/terminal-ui/src/types.ts`
- `scripts/terminal-ui/src/write.ts`
- `scripts/terminal-ui/src/verify-shell-compat.ts`
- `scripts/terminal-ui/src/cli.tsx`
- `scripts/terminal-ui/src/app.tsx`
- `scripts/terminal-ui/src/status-bar.tsx`
- `scripts/terminal-ui/src/log-panel.tsx`
- `scripts/terminal-ui/src/metrics-panel.tsx`
- `scripts/canon-scaffold.sh`
- `scripts/canon.sh`
- `sounds/unstoppable.mp3`
- `sounds/super-mario-bros.mp3`
- `sounds/yeahoo.mp3`
- `sounds/warzone-level-up.mp3`
- `sounds/unstoppable.ogg`
- `sounds/super-mario-bros.ogg`
- `sounds/yeahoo.ogg`
- `sounds/warzone-level-up.ogg`
- `sounds/tick.mp3`
- `sounds/tick.ogg`
- `hooks/play-sound.sh`

---

## Steps

### 1. Inventory what exists

Read and note which of these already exist:
- `~/.claude/settings.json`
- `~/.claude/CLAUDE.md`
- `~/.claude/commands/fix-issue.md`
- `~/.claude/commands/review-pr.md`
- `~/.claude/commands/plan.md`
- `~/.claude/commands/cleanup.md`
- `~/.claude/commands/doc-garden.md`
- `~/.claude/commands/core-init.md`
- `~/.claude/rules/` (any files)
- `~/.claude/hooks/` (any files)
- `~/.claude/skills/` (any files)
- `~/.claude/scripts/` (any files)
- `~/.claude/dega/sounds/` (any files)
- `~/.claude/scripts/terminal-session.sh`
- `~/.claude/scripts/terminal-ui-write.sh`
- `~/.claude/scripts/terminal-ui/` (any files)
- `~/.claude/scripts/canon-scaffold.sh`
- `~/.claude/scripts/canon.sh`

Also check in the current working directory (target project root):
- `ralph.yaml`

---

### 2. Ask the user what to install

Use AskUserQuestion with a single multi-select question. List each component
with a short description. Pre-label as recommended any component that is
missing from `~/.claude/`.

Components:
- **settings.json** — permissions, hooks (rm-rf blocker, push-to-main blocker, doc-reminder), telemetry off
- **CLAUDE.md** — global development standards: philosophy, no speculative features, agent-native by default
- **Commands** — fix-issue, review-pr, plan, cleanup, doc-garden, core-init slash commands
- **Rules** — language-specific standards auto-loaded by file type (python, node-typescript, rust, bash, github-actions)
- **Hooks** — enforce-package-manager and log-gam shell scripts
- **Skills** — custom-linter-authoring, app-legibility, and sound-notifications knowledge files
- **Logging** — `log-server.py` global Python log server; writes structured JSONL to
  `~/.claude/logs/ralph/`. One server per machine, shared by all projects.
  Also installs `session-start-logging.sh` (starts log server on session open) and
  `structured-log.sh` (records every tool call) as global hooks.
  GCP Cloud Logging is zero-config: drop `~/.claude/gcp-sa.json` and it auto-enables.
  (recommended when `~/.claude/scripts/log-server.py` is missing)
- **Ralph Loop** — engine scripts install globally to `~/.claude/scripts/`
  (`ralph-loop.sh`, `ralph-worktree.sh`, `ralph-check.sh`,
  `ralph-worker-prompt.md`, `ralph-reviewer-prompt.md`, `log-client.sh`,
  `plan-advance.sh`, `task-complete.sh`); only `ralph.yaml` is per-project
  (written to cwd). Invoke from any project:
  `~/.claude/scripts/ralph-loop.sh <dated-slug>` (single loop) or
  `~/.claude/scripts/ralph-worktree.sh <dated-slug>` (parallel via worktree)
  (opt-in; recommended when `~/.claude/scripts/ralph-loop.sh` is missing)
- **Sounds** — notification sounds that play when Claude finishes a task.
  Works on macOS, Linux, and WSL2. Linux needs one of: `mpv`, `ffplay`, or
  `paplay` (PulseAudio/PipeWire). Installs MP3 and OGG files to
  `~/.claude/dega/sounds/` and the `play-sound.sh` hook to `~/.claude/hooks/`.
  Configured via `CLAUDE_SOUND` env var in `settings.json`
  (default: `unstoppable`). Available values: `unstoppable`,
  `super-mario-bros`, `yeahoo`, `warzone-level-up`, `none`. Set to `none`
  to disable. Volume controlled via `CLAUDE_SOUND_VOLUME` (0–100, default 50).
  (recommended when `~/.claude/dega/sounds/` is missing)
- **Terminal UI** — visual status dashboard for automation sessions. Includes
  tmux session launcher (`terminal-session.sh`), state file writer
  (`terminal-ui-write.sh`), and Ink status dashboard (`terminal-ui/`).
  Requires Node.js. Installs scripts to `~/.claude/scripts/` and builds
  the Ink app with `pnpm install && pnpm run build`.
  (opt-in; recommended when `~/.claude/scripts/terminal-ui/` is missing)
- **Canon Bootstrap** — launcher and scaffold scripts for Canon prediction
  market projects. Installs `canon-scaffold.sh` (deterministic project
  scaffolder called by `/canon-start`) and `canon.sh` (reference copy of
  the local tmux launcher written by `/canon-init`).
  (opt-in; recommended when `~/.claude/scripts/canon-scaffold.sh` is missing)

---

### 3. Fetch selected files

Use WebFetch to download only the files needed for the user's selections from
the GitHub URLs above. Extract the raw file content from each response.

---

### 4. Install each selected component

#### settings.json

Create `~/.claude/` if it doesn't exist.

- If `~/.claude/settings.json` does **not** exist: write it directly.
- If it **does** exist: read both files and merge the repo's keys into the
  existing file — preserve any user keys that don't conflict. Show the merged
  result and ask for confirmation before writing.

#### CLAUDE.md

- If `~/.claude/CLAUDE.md` does **not** exist: write the fetched
  `claude-md-template.md` content to `~/.claude/CLAUDE.md`.
- If it **already exists**: tell the user it exists and ask whether to
  overwrite, skip, or show a diff. Never silently overwrite — it likely has
  personal customizations.

#### Commands

Create `~/.claude/commands/` if it doesn't exist.

Write each selected command file to `~/.claude/commands/<name>.md`. Safe to
overwrite — commands have no user customization.

#### Rules

Create `~/.claude/rules/` if it doesn't exist.

Write each rule file to `~/.claude/rules/<name>.md`. Safe to overwrite.

#### Hooks

Create `~/.claude/hooks/` if it doesn't exist.

Write each hook file to `~/.claude/hooks/<name>.sh` and `chmod +x` it. Safe
to overwrite.

#### Skills

Create `~/.claude/skills/` if it doesn't exist.

Write each skill file to `~/.claude/skills/<name>.md`. Safe to overwrite.

#### Logging — Global scripts

Create `~/.claude/scripts/` if it doesn't exist.

Write `scripts/log-server.py` to `~/.claude/scripts/log-server.py`. Safe to overwrite.

#### Logging — Global hooks

Create `~/.claude/hooks/` if it doesn't exist.

Write and `chmod +x` each file:
- `hooks/session-start-logging.sh` → `~/.claude/hooks/session-start-logging.sh`
- `hooks/structured-log.sh` → `~/.claude/hooks/structured-log.sh`
- `hooks/ralph-reviewer-stop.sh` → `~/.claude/hooks/ralph-reviewer-stop.sh`

Safe to overwrite. These hooks reference `${HOME}/.claude/scripts/log-server.py`
so they work from any project directory. The reviewer stop hook is scoped
via `RALPH_ROLE` env var — it's a no-op outside ralph loop sessions.

#### Ralph Loop — Global scripts

Create `~/.claude/scripts/` if it doesn't exist.

Write each engine script to `~/.claude/scripts/`:
- `scripts/ralph-loop.sh` → `~/.claude/scripts/ralph-loop.sh`
- `scripts/ralph-worktree.sh` → `~/.claude/scripts/ralph-worktree.sh`
- `scripts/ralph-check.sh` → `~/.claude/scripts/ralph-check.sh`
- `scripts/ralph-worker-prompt.md` → `~/.claude/scripts/ralph-worker-prompt.md`
- `scripts/ralph-reviewer-prompt.md` → `~/.claude/scripts/ralph-reviewer-prompt.md`
- `scripts/log-client.sh` → `~/.claude/scripts/log-client.sh`
- `scripts/plan-advance.sh` → `~/.claude/scripts/plan-advance.sh`
- `scripts/task-complete.sh` → `~/.claude/scripts/task-complete.sh`
- `scripts/canon-runner.sh` → `~/.claude/scripts/canon-runner.sh`

Run `chmod +x ~/.claude/scripts/ralph-loop.sh ~/.claude/scripts/ralph-worktree.sh ~/.claude/scripts/ralph-check.sh ~/.claude/scripts/log-client.sh ~/.claude/scripts/plan-advance.sh ~/.claude/scripts/task-complete.sh ~/.claude/scripts/canon-runner.sh` after writing.
Safe to overwrite — these are engine scripts with no user customization.

#### Ralph Loop — Per-project config

- If `ralph.yaml` does **not** exist in the cwd: write it directly.
- If it **does** exist: tell the user it exists and ask whether to
  overwrite, skip, or show a diff. Never silently overwrite — the user
  may have customized `max_iterations` or `success_criteria`.

No per-project scripts are needed. The global engine at
`~/.claude/scripts/ralph-loop.sh` reads `ralph.yaml` from `$PWD`.

#### Sounds

Create `~/.claude/dega/sounds/` if it doesn't exist.

Write each sound file (MP3 and OGG) to `~/.claude/dega/sounds/`:
- `sounds/unstoppable.mp3` → `~/.claude/dega/sounds/unstoppable.mp3`
- `sounds/super-mario-bros.mp3` → `~/.claude/dega/sounds/super-mario-bros.mp3`
- `sounds/yeahoo.mp3` → `~/.claude/dega/sounds/yeahoo.mp3`
- `sounds/warzone-level-up.mp3` → `~/.claude/dega/sounds/warzone-level-up.mp3`
- `sounds/unstoppable.ogg` → `~/.claude/dega/sounds/unstoppable.ogg`
- `sounds/super-mario-bros.ogg` → `~/.claude/dega/sounds/super-mario-bros.ogg`
- `sounds/yeahoo.ogg` → `~/.claude/dega/sounds/yeahoo.ogg`
- `sounds/warzone-level-up.ogg` → `~/.claude/dega/sounds/warzone-level-up.ogg`
- `sounds/tick.mp3` → `~/.claude/dega/sounds/tick.mp3`
- `sounds/tick.ogg` → `~/.claude/dega/sounds/tick.ogg`

Safe to overwrite — these are static assets with no user customization.
OGG files are needed for `paplay` on Linux (cannot decode MP3).

Write `hooks/play-sound.sh` to `~/.claude/hooks/play-sound.sh` and `chmod +x`
it. Safe to overwrite.

#### Terminal UI

Create `~/.claude/scripts/terminal-ui/src/` if it doesn't exist.

Write each file to its corresponding path under `~/.claude/scripts/`:
- `scripts/terminal-session.sh` → `~/.claude/scripts/terminal-session.sh`
- `scripts/terminal-ui-write.sh` → `~/.claude/scripts/terminal-ui-write.sh`
- `scripts/terminal-ui/package.json` → `~/.claude/scripts/terminal-ui/package.json`
- `scripts/terminal-ui/tsconfig.json` → `~/.claude/scripts/terminal-ui/tsconfig.json`
- `scripts/terminal-ui/src/types.ts` → `~/.claude/scripts/terminal-ui/src/types.ts`
- `scripts/terminal-ui/src/write.ts` → `~/.claude/scripts/terminal-ui/src/write.ts`
- `scripts/terminal-ui/src/verify-shell-compat.ts` → `~/.claude/scripts/terminal-ui/src/verify-shell-compat.ts`
- `scripts/terminal-ui/src/cli.tsx` → `~/.claude/scripts/terminal-ui/src/cli.tsx`
- `scripts/terminal-ui/src/app.tsx` → `~/.claude/scripts/terminal-ui/src/app.tsx`
- `scripts/terminal-ui/src/status-bar.tsx` → `~/.claude/scripts/terminal-ui/src/status-bar.tsx`
- `scripts/terminal-ui/src/log-panel.tsx` → `~/.claude/scripts/terminal-ui/src/log-panel.tsx`
- `scripts/terminal-ui/src/metrics-panel.tsx` → `~/.claude/scripts/terminal-ui/src/metrics-panel.tsx`

Run `chmod +x ~/.claude/scripts/terminal-session.sh ~/.claude/scripts/terminal-ui-write.sh` after writing.

Then build the Ink dashboard:
```bash
cd ~/.claude/scripts/terminal-ui && pnpm install && pnpm run build
```

If `pnpm` is not available, fall back to `npm install && npm run build`.

Safe to overwrite — these are engine scripts and app source with no user customization.

#### Canon Bootstrap

Create `~/.claude/scripts/` if it doesn't exist.

Write each file to its corresponding path under `~/.claude/scripts/`:
- `scripts/canon-scaffold.sh` → `~/.claude/scripts/canon-scaffold.sh`
- `scripts/canon.sh` → `~/.claude/scripts/canon.sh`

Run `chmod +x ~/.claude/scripts/canon-scaffold.sh ~/.claude/scripts/canon.sh` after writing.

Safe to overwrite — these are engine scripts with no user customization.

---

### 5. Self-install

After completing the user's selections, also install this command itself to
`~/.claude/commands/apply-core.md` by fetching:

```
https://raw.githubusercontent.com/DEGAorg/claude-code-config/ace-work/commands/apply-core.md
```

This makes `/apply-core` available from any directory in future without
needing the repo cloned.

---

### 6. GCP setup (optional)

This step only applies if the user selected **Logging**.

Check whether `~/.claude/gcp-sa.json` exists:

- **If it exists**: note that GCP Cloud Logging is configured. The log server
  will auto-enable GCP output when it starts.
- **If it does not exist**: tell the user:

  > GCP Cloud Logging is optional. To enable it, place a GCP service account
  > key at `~/.claude/gcp-sa.json`. The log server detects this file at
  > startup and enables GCP output automatically — no other configuration
  > needed. Local JSONL logging to `~/.claude/logs/ralph/` works without it.
  >
  > To create a service account key:
  > 1. Go to the GCP Console → IAM & Admin → Service Accounts.
  > 2. Create a service account with the **Logs Writer** role
  >    (`roles/logging.logWriter`).
  > 3. Create a JSON key for that service account and download it.
  > 4. Move the downloaded file to `~/.claude/gcp-sa.json`.
  >
  > Do not commit this file — it contains credentials. Add `gcp-sa.json` to
  > your `.gitignore` if you store anything in `~/.claude/` under version
  > control.

Do not copy, read, or transmit the key contents. Only check for its presence.

---

### 7. Post-install

Summarize what was installed or updated. Use a checklist format, one line per
component. Note any manual steps (e.g. CLAUDE.md diff review).

For the **Logging** component, include one of these lines based on the
`~/.claude/gcp-sa.json` check from Step 6:

- If `gcp-sa.json` **found**: `✓ Logging — GCP active (gcp-sa.json detected)`
- If `gcp-sa.json` **absent**: `✓ Logging — local-only (add ~/.claude/gcp-sa.json to enable GCP)`

Example summary:

```
Installed:
✓ settings.json
✓ CLAUDE.md (review diff before next session)
✓ Commands — fix-issue, review-pr, plan, cleanup, doc-garden, core-init
✓ Rules — python, node-typescript, rust, bash, github-actions
✓ Hooks — enforce-package-manager, log-gam
✓ Skills — custom-linter-authoring, app-legibility, sound-notifications
✓ Logging — local-only (add ~/.claude/gcp-sa.json to enable GCP)
✓ Ralph Loop — scripts → ~/.claude/scripts/, ralph.yaml → cwd
✓ Sounds — MP3 + OGG → ~/.claude/dega/sounds/, play-sound.sh → ~/.claude/hooks/
✓ Terminal UI — dashboard + scripts → ~/.claude/scripts/, built with pnpm
✓ Canon Bootstrap — canon-scaffold.sh + canon.sh → ~/.claude/scripts/

Canon layer is separate. Run /apply-canon from a Canon strategy project to add the
prediction-market layer on top of Core.
```

Adapt to what the user actually selected — omit components that were skipped.

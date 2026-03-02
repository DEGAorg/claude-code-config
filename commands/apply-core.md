# Apply Core

@description Install DEGA Core AI development artifacts globally (~/.claude/) or into a specific project (.claude/), with Ralph Loop scripts per-repo.

Install Core harness artifacts from GitHub. Supports two install targets:

- **Global** (`~/.claude/`) — applies to all projects on this machine
- **Project** (`<project>/.claude/`) — applies to a specific project only

Works from any directory — no need to clone the repo.

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
- `skills/custom-linter-authoring/SKILL.md`
- `skills/app-legibility/SKILL.md`
- `scripts/log-server.py`
- `ralph.yaml`
- `scripts/ralph-check.sh`
- `scripts/ralph-loop.sh`
- `scripts/ralph-worker-prompt.md`
- `scripts/ralph-reviewer-prompt.md`
- `scripts/log-client.sh`
- `scripts/plan-advance.sh`
- `scripts/task-complete.sh`

---

## Steps

### 1. Choose install target

Use AskUserQuestion to ask the user where to install:

- **Global** (`~/.claude/`) — applies to all projects on this machine
- **Project** — applies to a specific project only

If the user selects **Project**:

1. Ask for the **absolute path** to the project root.
2. Verify the directory exists. If not, stop and tell the user.
3. Attempt to create `<path>/.claude/` if it doesn't exist. If creation
   fails (permission denied), tell the user to grant edit access for that
   path and stop.

Set two variables used throughout the remaining steps:

| Variable | Global | Project |
|----------|--------|---------|
| `$BASE` | `~/.claude` | `<project-path>/.claude` |
| `$PROJECT_ROOT` | *(not set — Ralph Loop uses cwd)* | `<project-path>` |

---

### 2. Inventory what exists

Read and note which of these already exist under `$BASE`:
- `$BASE/settings.json`
- CLAUDE.md — `~/.claude/CLAUDE.md` (global) or `$PROJECT_ROOT/CLAUDE.md` (project)
- `$BASE/commands/dega/fix-issue.md`
- `$BASE/commands/dega/review-pr.md`
- `$BASE/commands/dega/plan.md`
- `$BASE/commands/dega/cleanup.md`
- `$BASE/commands/dega/doc-garden.md`
- `$BASE/rules/` (any files)
- `$BASE/hooks/` (any files)
- `$BASE/skills/dega/` (any skill directories)
- `$BASE/scripts/` (any files)

Also check the Ralph Loop target directory (`$PROJECT_ROOT` if set, otherwise cwd):
- `ralph.yaml`
- `scripts/ralph-loop.sh`
- `scripts/ralph-check.sh`
- `scripts/ralph-worker-prompt.md`
- `scripts/ralph-reviewer-prompt.md`
- `scripts/log-client.sh`
- `scripts/plan-advance.sh`
- `scripts/task-complete.sh`

---

### 3. Ask the user what to install

Use AskUserQuestion with a single multi-select question. List each component
with a short description. Pre-label as recommended any component that is
missing from `$BASE`.

Components:
- **settings.json** — permissions, hooks (rm-rf blocker, push-to-main blocker, doc-reminder), telemetry off
- **CLAUDE.md** — global development standards: philosophy, no speculative features, agent-native by default
- **Commands** — fix-issue, review-pr, plan, cleanup, doc-garden slash commands
- **Rules** — language-specific standards auto-loaded by file type (python, node-typescript, rust, bash, github-actions)
- **Hooks** — enforce-package-manager and log-gam shell scripts
- **Skills** — custom-linter-authoring and app-legibility knowledge files
- **Logging** — `log-server.py` Python log server; writes structured JSONL to
  `~/.claude/logs/ralph/`. Also installs `session-start-logging.sh` (starts
  log server on session open) and `structured-log.sh` (records every tool
  call) as hooks. GCP Cloud Logging is zero-config: drop
  `~/.claude/gcp-sa.json` and it auto-enables.
  (recommended when `$BASE/scripts/log-server.py` is missing)
- **Ralph Loop** — per-repo install of `ralph.yaml`, `ralph-loop.sh`, `ralph-check.sh`,
  `ralph-worker-prompt.md`, `ralph-reviewer-prompt.md`, `log-client.sh`,
  `plan-advance.sh`, and `task-complete.sh` into the project root
  (opt-in; recommended when Ralph Loop is missing from `$PROJECT_ROOT` or cwd)

---

### 4. Fetch selected files

Use WebFetch to download only the files needed for the user's selections from
the GitHub URLs above. Extract the raw file content from each response.

---

### 5. Install each selected component

All paths below use `$BASE` (set in Step 1). For global installs `$BASE` is
`~/.claude`; for project installs `$BASE` is `<project-path>/.claude`.

#### settings.json

Create `$BASE/` if it doesn't exist.

- If `$BASE/settings.json` does **not** exist: write it directly.
- If it **does** exist: read both files and merge the repo's keys into the
  existing file — preserve any user keys that don't conflict. Show the merged
  result and ask for confirmation before writing.

**Project-level note:** When the install target is project, hook command paths
inside `settings.json` must use project-relative references (e.g.,
`.claude/hooks/enforce-package-manager.sh`) instead of `~/.claude/hooks/`.
Rewrite any `~/.claude/` prefixed hook paths in the fetched template before
writing.

#### CLAUDE.md

- **Global:** If `~/.claude/CLAUDE.md` does **not** exist, write the fetched
  `claude-md-template.md` content to `~/.claude/CLAUDE.md`. If it already
  exists, ask whether to overwrite, skip, or show a diff.
- **Project:** If `$PROJECT_ROOT/CLAUDE.md` does **not** exist, write the
  fetched `claude-md-template.md` content to `$PROJECT_ROOT/CLAUDE.md`. If
  it already exists, ask whether to overwrite, skip, or show a diff.

Never silently overwrite — it likely has customizations.

#### Commands

Create `$BASE/commands/dega/` if it doesn't exist.

Write each selected command file to `$BASE/commands/dega/<name>.md`. Safe to
overwrite — commands have no user customization.

#### Rules

Create `$BASE/rules/` if it doesn't exist.

Write each rule file to `$BASE/rules/<name>.md`. Safe to overwrite.

#### Hooks

Create `$BASE/hooks/` if it doesn't exist.

Write each hook file to `$BASE/hooks/<name>.sh` and `chmod +x` it. Safe
to overwrite.

#### Skills

Skills use the directory format: each skill is a folder with a `SKILL.md` entrypoint.

For each selected skill:
1. Create `$BASE/skills/dega/<name>/` if it doesn't exist.
2. Write the fetched content to `$BASE/skills/dega/<name>/SKILL.md`. Safe to overwrite.

#### Logging — Scripts

Create `$BASE/scripts/` if it doesn't exist.

Write `scripts/log-server.py` to `$BASE/scripts/log-server.py`. Safe to overwrite.

#### Logging — Hooks

Create `$BASE/hooks/` if it doesn't exist.

Write and `chmod +x` each file:
- `hooks/session-start-logging.sh` → `$BASE/hooks/session-start-logging.sh`
- `hooks/structured-log.sh` → `$BASE/hooks/structured-log.sh`

Safe to overwrite. These hooks reference `${HOME}/.claude/scripts/log-server.py`
so they work from any project directory.

#### Ralph Loop

Use `$PROJECT_ROOT` if set (project-level install), otherwise the current
working directory as the target.

Create `scripts/` in the target directory if it doesn't exist.

- If `ralph.yaml` does **not** exist in the target: write it directly.
- If it **does** exist: tell the user it exists and ask whether to
  overwrite, skip, or show a diff. Never silently overwrite — the user
  may have customized `max_iterations` or `success_criteria`.

Write each script file to the target directory:
- `scripts/ralph-loop.sh`
- `scripts/ralph-check.sh`
- `scripts/ralph-worker-prompt.md`
- `scripts/ralph-reviewer-prompt.md`
- `scripts/log-client.sh`
- `scripts/plan-advance.sh`
- `scripts/task-complete.sh`

Run `chmod +x scripts/ralph-loop.sh scripts/ralph-check.sh scripts/log-client.sh` after writing.
Safe to overwrite the scripts — they have no user customization.

---

### 6. Self-install

**Always targets `~/.claude/` regardless of install target** — the command
itself must be available globally.

After completing the user's selections, install this command to
`~/.claude/commands/dega/apply-core.md` by fetching:

```
https://raw.githubusercontent.com/DEGAorg/claude-code-config/ace-work/commands/apply-core.md
```

This makes `/dega:apply-core` available from any directory in future without
needing the repo cloned.

---

### 7. GCP setup (optional)

This step only applies if the user selected **Logging**.

**Project-level note:** The log server and GCP credentials always resolve to
global paths (`~/.claude/gcp-sa.json`, `~/.claude/logs/`), even when Logging
scripts are installed at project level. For project-level installs, ask the user:

> The log server uses `~/.claude/gcp-sa.json` for GCP credentials regardless
> of install target. Would you like to configure GCP Cloud Logging now?

If the user declines, skip the rest of this step.

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

### 8. Post-install

Summarize what was installed or updated. Start with the install target, then
use a checklist format — one line per component. Note any manual steps (e.g.
CLAUDE.md diff review).

For the **Logging** component (global installs only), include one of these
lines based on the `~/.claude/gcp-sa.json` check from Step 7:

- If `gcp-sa.json` **found**: `✓ Logging — GCP active (gcp-sa.json detected)`
- If `gcp-sa.json` **absent**: `✓ Logging — local-only (add ~/.claude/gcp-sa.json to enable GCP)`

**Global install example:**

```
Installed to: ~/.claude/ (global)

✓ settings.json
✓ CLAUDE.md (review diff before next session)
✓ Commands — /dega:fix-issue, /dega:review-pr, /dega:plan, /dega:cleanup, /dega:doc-garden
✓ Rules — python, node-typescript, rust, bash, github-actions
✓ Hooks — enforce-package-manager, log-gam
✓ Skills — custom-linter-authoring, app-legibility
✓ Logging — local-only (add ~/.claude/gcp-sa.json to enable GCP)
✓ Ralph Loop — ralph.yaml, ralph-loop.sh, ralph-check.sh, log-client.sh, ...

Canon is separate. Run /dega:canon-init from a Canon strategy project to add the
prediction-market layer on top of Core.
```

**Project-level install example:**

```
Installed to: /path/to/project/.claude/ (project-level)

✓ settings.json (project-relative hook paths)
✓ CLAUDE.md → /path/to/project/CLAUDE.md
✓ Commands — /dega:fix-issue, /dega:review-pr, /dega:plan, /dega:cleanup, /dega:doc-garden
✓ Rules — python, node-typescript, rust, bash, github-actions
✓ Hooks — enforce-package-manager, log-gam
✓ Skills — custom-linter-authoring, app-legibility
✓ Logging — scripts and hooks installed to project .claude/
✓ Ralph Loop — ralph.yaml, ralph-loop.sh, ralph-check.sh, log-client.sh, ...

Self-install: /dega:apply-core also installed globally to ~/.claude/ for future use.
```

Adapt to what the user actually selected — omit components that were skipped.

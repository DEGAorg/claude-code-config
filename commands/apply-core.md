# Apply Core

@description Install DEGA Core AI development artifacts globally to ~/.claude/.

Install Core harness artifacts from GitHub into `~/.claude/`. Works from any
directory — no need to clone the repo.

## Source

All files are fetched from:

```
https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/
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
- `skills/custom-linter-authoring.md`
- `ralph.yaml`
- `scripts/ralph-check.sh`
- `scripts/ralph-loop.sh`
- `scripts/ralph-worker-prompt.md`
- `scripts/ralph-reviewer-prompt.md`

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
- `~/.claude/rules/` (any files)
- `~/.claude/hooks/` (any files)
- `~/.claude/skills/` (any files)

---

### 2. Ask the user what to install

Use AskUserQuestion with a single multi-select question. List each component
with a short description. Pre-label as recommended any component that is
missing from `~/.claude/`.

Components:
- **settings.json** — permissions, hooks (rm-rf blocker, push-to-main blocker, doc-reminder), telemetry off
- **CLAUDE.md** — global development standards: philosophy, no speculative features, agent-native by default
- **Commands** — fix-issue, review-pr, plan, cleanup, doc-garden slash commands
- **Rules** — language-specific standards auto-loaded by file type (python, node-typescript, rust, bash, github-actions)
- **Hooks** — enforce-package-manager and log-gam shell scripts
- **Skills** — custom-linter-authoring knowledge file

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

---

### 5. Self-install

After completing the user's selections, also install this command itself to
`~/.claude/commands/apply-core.md` by fetching:

```
https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/commands/apply-core.md
```

This makes `/apply-core` available from any directory in future without
needing the repo cloned.

---

### 6. Post-install

Summarize what was installed or updated. Note any manual steps (e.g. CLAUDE.md
diff review). Remind the user that Canon installation is separate — run
`/apply-canon` from a Canon strategy project to scaffold the prediction-market
layer on top of Core.

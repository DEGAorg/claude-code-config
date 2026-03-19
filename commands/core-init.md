# Core Init

@description Bootstrap any repo for DEGA Core — creates dega-core.yaml, exec-plans, .gitignore entries, and minimal CLAUDE.md. Enables Ralph Loop and orchestrator.

Run every step below in order. This command is idempotent — it skips files
that already exist and never overwrites user-customized config.

---

## 1. Guard: wrong directory

Check if the current directory is the `claude-code-config` repo:

```bash
[[ -f "CLAUDE.md" ]] && grep -q "claude-code-config" "CLAUDE.md" 2>/dev/null
```

If that succeeds, stop and print:

> Run `/core-init` from your project directory, not from `claude-code-config`.

Do not continue.

---

## 2. Detect project language

Check for language markers in the current directory to auto-populate
`check_command` in dega-core.yaml. Check in this order, use the first match:

**Language detection table:**

| Marker file | Language | `check_command` |
|-------------|----------|-----------------|
| `package.json` | Node/TypeScript | `<PKG_MGR> test && <PKG_MGR> run lint && <PKG_MGR> run typecheck` |
| `pyproject.toml` | Python | `pytest -q && ruff check . && ty check` |
| `Cargo.toml` | Rust | `cargo test && cargo clippy --all-targets --all-features -- -D warnings && cargo fmt --check` |
| `go.mod` | Go | `go test ./... && golangci-lint run` |

**Node package manager detection:** If `package.json` is found, detect the
package manager by checking for lockfiles (first match wins):

| Lockfile | Package manager |
|----------|----------------|
| `pnpm-lock.yaml` | `pnpm` |
| `yarn.lock` | `yarn` |
| `bun.lockb` or `bun.lock` | `bun` |
| (none of the above) | `npm` |

Substitute `<PKG_MGR>` with the detected package manager in the check_command.

**If no language marker matches**, set `check_command` to:

```yaml
check_command: |
  # TODO: Replace with your project's test/lint/typecheck commands
  echo "No check_command configured — edit dega-core.yaml"
  exit 1
```

Store the detected language name (or "unknown") and package manager for use
in later steps.

---

## 3. Create directory structure

Create all directories. These are no-ops if they already exist:

```bash
mkdir -p docs/exec-plans/active docs/exec-plans/completed .claude/commands
```

Add `.gitkeep` files to empty directories so git tracks them:

```bash
[[ -z "$(ls -A docs/exec-plans/active 2>/dev/null)" ]] && touch docs/exec-plans/active/.gitkeep
[[ -z "$(ls -A docs/exec-plans/completed 2>/dev/null)" ]] && touch docs/exec-plans/completed/.gitkeep
[[ -z "$(ls -A .claude/commands 2>/dev/null)" ]] && touch .claude/commands/.gitkeep
```

### .gitignore entries

Append these lines to `.gitignore` if they aren't already present:

```
# DEGA Core — orchestrator runtime state (ephemeral, not tracked)
/.orchestrator/

# DEGA Core — personal focus config for planner loop
focus.yaml
```

Check each line before appending — skip if already in `.gitignore`. Create
`.gitignore` if it doesn't exist.

---

## 4. Write dega-core.yaml

**If `dega-core.yaml` already exists:** tell the user it exists and skip. Print:

> `dega-core.yaml` already exists — skipping. Delete it and re-run `/core-init` to regenerate.

**If it does not exist:** write it using the detected language from Step 2.

Template (substitute `<CHECK_COMMAND>` with the detected value):

```yaml
# DEGA Core config — edit to match your project
version: 1
max_iterations: 20

budget:
  warn_at_iteration: 15
check_command: |
  <CHECK_COMMAND>
poll_interval_seconds: 30

# Worker and reviewer prompts (global, installed by /apply-core)
worker_prompt: ~/.claude/scripts/ralph-worker-prompt.md
reviewer_prompt: ~/.claude/scripts/ralph-reviewer-prompt.md

success_criteria:
  - "tests pass"
  - "linting clean"
  - "types valid"
```

---

## 5. Write CLAUDE.md

**If `CLAUDE.md` already exists:** tell the user it exists and skip. Print:

> `CLAUDE.md` already exists — skipping. Delete it and re-run `/core-init` to regenerate.

**If it does not exist:** fetch the minimal template from GitHub:

```
https://raw.githubusercontent.com/DEGAorg/claude-code-config/develop/docs/core-init-claude-template.md
```

Write the fetched content to `CLAUDE.md` in the current directory.

If the fetch fails, write this fallback directly:

```markdown
# <Project Name>

Replace this with a one-line description of your project.

## Repo Map

| Path | Purpose |
|------|---------|
| `src/` | Application source code |
| `tests/` | Test files |
| `docs/` | Documentation |
| `docs/exec-plans/` | Execution plans (active + completed) |

## Working Conventions

- Language-specific standards load from `~/.claude/rules/` by file type
- Ralph Loop config: `dega-core.yaml` (edit `check_command` for your toolchain)
- Exec plans: `docs/exec-plans/active/<YYYYMMDD-slug>/plan.md`

## Session Start

Check `docs/exec-plans/active/` for in-progress plans before starting new work.
```

---

## 6. Print completion message

Summarize what was created. Use a checklist format:

```
Core init complete.

Created:
✓ docs/exec-plans/active/       — execution plan directory
✓ docs/exec-plans/completed/    — archived plans
✓ .claude/commands/              — local commands directory
✓ .gitignore                     — added .orchestrator/ and focus.yaml entries
✓ dega-core.yaml                — core config (<LANGUAGE> detected, <PKG_MGR> if Node)
✓ CLAUDE.md                     — minimal project context

Skipped (already existed):
⊘ <list any files that were skipped>

Next steps:
1. Edit CLAUDE.md — add your project's repo map and conventions
2. Edit dega-core.yaml — verify check_command matches your toolchain
3. Run /apply-core to install global tools (if not already installed)
4. Create your first exec plan: /plan
5. Run it: bash ~/.claude/scripts/orch-run.sh <slug>
```

Adapt the summary to what actually happened — only show "Skipped" if
something was skipped, only show "Created" items that were created.

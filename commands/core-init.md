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

### GitHub detection

Before writing the file, detect the GitHub remote and `gh` CLI availability:

1. **Check if `gh` is installed and authenticated:**

   ```bash
   gh auth status 2>/dev/null
   ```

2. **If `gh` is available**, detect the GitHub repo from the git remote:

   ```bash
   gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null
   ```

   If that succeeds, use the returned `owner/repo` value for the `github.repo`
   field and set `sync: true`.

3. **If `gh` is NOT installed, not authenticated, or repo detection fails**,
   write the `github:` block with `sync: false` and a comment explaining why:

   ```yaml
   github:
     # gh CLI not available — install gh and run /core-init again to enable sync
     sync: false
   ```

**The `github:` block must ALWAYS be present in the output.** There is no
scenario where it is omitted.

### Template

Substitute `<CHECK_COMMAND>` with the detected value from Step 2, and
`<GITHUB_BLOCK>` with the result of GitHub detection above:

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

<GITHUB_BLOCK>

success_criteria:
  - "tests pass"
  - "linting clean"
  - "types valid"
```

Where `<GITHUB_BLOCK>` is one of:

**When `gh` detected the repo successfully:**

```yaml
github:
  sync: true
  repo: <OWNER/REPO>
  labels: true
  comments: true
  close_on_ship: true
```

**When `gh` is not installed, not authenticated, or detection failed:**

```yaml
github:
  # gh CLI not available — install gh and run /core-init again to enable sync
  sync: false
```

---

## 5. CRITICAL: github block must NEVER be omitted

**The `github:` block is MANDATORY in every `dega-core.yaml` produced by this
command. There is NO scenario where it may be left out.**

- If `gh` is installed and the repo is detected → write `sync: true` with full config.
- If `gh` is NOT installed, not authenticated, or detection fails → write `sync: false` with a comment.
- **Never skip the `github:` block.** Even if every detection step fails, the block must be present with `sync: false`.

A missing `github:` block breaks the orchestrator's `GH_SYNC` detection and
cascades into plan-path failures. This is the single most common failure mode
on fresh Linux installs.

After writing `dega-core.yaml`, proceed immediately to the validation gate
(Step 6) before continuing.

---

## 6. Validation gate: verify github block exists

After writing `dega-core.yaml`, re-read the file and verify the `github:` key
is present. This is a programmatic check, not a visual one.

```bash
grep -q '^github:' dega-core.yaml
```

**If the check fails** (exit code non-zero):

1. Print an error:

   > **ERROR:** `dega-core.yaml` is missing the `github:` block. Adding fallback.

2. Append the fallback block to the file:

   ```bash
   cat >> dega-core.yaml << 'EOF'

   github:
     # ADDED BY VALIDATION GATE — github block was missing after initial write
     # Install gh and run /core-init again to enable sync
     sync: false
   EOF
   ```

3. Re-run the check to confirm the fix:

   ```bash
   grep -q '^github:' dega-core.yaml || { echo "FATAL: github block still missing after repair"; exit 1; }
   ```

**If the check passes**, print:

> `dega-core.yaml` validated — `github:` block present.

**Do not proceed to the next step until this validation passes.**

---

## 7. Write CLAUDE.md

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

## 8. Print completion message

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

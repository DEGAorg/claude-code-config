# Plan: apply-core + Ralph Loop

**Status:** Completed
**Created:** 2026-02-20
**Updated:** 2026-02-20 — global install done, apply-core redesigned to match ToB pattern

---

## Architecture decision (2026-02-20, Carlos)

- **Core** → `~/.claude/` (global) — harness applies to all projects on the machine
- **Canon** → project-local (`.canon/`) — scaffolded by `canon_init`
- `canon_init` checks for Core pre-installed; does not bundle Core

This resolved the three open questions from `docs/Canon_Installation_Architecture_Analysis.md`.

## apply-core: done + globally installed

`commands/apply-core.md` redesigned to match Trail of Bits pattern:
- Fetches from GitHub (works from any directory, no repo clone needed)
- Interactive multi-select (asks what to install, recommends missing components)
- Merges settings.json keys, never silently overwrites
- Self-installs to `~/.claude/commands/dega/apply-core.md`

**Global install completed 2026-02-20** (from `ace-work` branch, local copy used
since WebFetch summarizes content — GitHub fetch will work correctly post-merge to main).

Installed to `~/.claude/`:
- `settings.json` — merged with existing `skipDangerousModePermissionPrompt` key
- `CLAUDE.md` — fresh install (was missing)
- `commands/` — cleanup, doc-garden, fix-issue, plan, review-pr, apply-core (self)
- `rules/` — bash, github-actions, node-typescript, python, rust
- `hooks/` — enforce-package-manager, log-gam (chmod +x)
- `skills/` — custom-linter-authoring

**Note:** `apply-core.md` source points to `main` branch. After this branch merges,
the GitHub fetch will work correctly from any directory.

---

## What we can do now: Ralph Loop for this repo

The Ralph Loop is entirely repo-local — no installation target question, no
architecture ambiguity. It needs three things:

1. `ralph.yaml` — success criteria for this repo's completeness
2. `scripts/ralph-check.sh` — evaluates each criterion, reports pass/fail
3. One section in `CLAUDE.md` — the instruction that closes the loop

### How it works

```
Agent reads CLAUDE.md
  → sees: "before declaring work complete, run scripts/ralph-check.sh"
  → does work
  → runs the check
  → if any criteria fail → keeps working
  → if all pass → reports done
```

No MCP tool. No Stop hook event. The CLAUDE.md instruction is the loop
mechanism — sufficient for a config/markdown repo where success criteria are
file existence and content assertions.

State persists between sessions via git (what's committed) and
`docs/exec-plans/active/` (plan checkboxes).

---

## Success criteria (repo-local only)

No global deployment checks — those belong to apply-core, which is deferred.
These criteria cover what this repo should contain when complete.

**Harness artifacts:**
- `rules/` has all 5 language files (python, node-typescript, rust, bash, github-actions)
- `commands/` has: fix-issue, review-pr, plan, cleanup, doc-garden
- `skills/custom-linter-authoring.md` exists
- `canon/rules/domain-layering.md` exists
- `docs/exec-plans/active/` and `docs/exec-plans/completed/` exist
- CLAUDE.md gap table: gaps 1–6 all marked Done

**Ralph Loop itself:**
- `ralph.yaml` exists at repo root
- `scripts/ralph-check.sh` exists and is executable
- CLAUDE.md Working Conventions contains the ralph check instruction

---

## Files to create

### `ralph.yaml`

```yaml
# Ralph Loop config for claude-code-config repo
version: 1
max_iterations: 10
check_command: bash scripts/ralph-check.sh

success_criteria:
  # Harness — rules
  - id: rules-files
    description: rules/ has all 5 language files
    check: >
      test -f rules/python.md &&
      test -f rules/node-typescript.md &&
      test -f rules/rust.md &&
      test -f rules/bash.md &&
      test -f rules/github-actions.md

  # Harness — commands
  - id: commands-files
    description: commands/ has all core commands
    check: >
      test -f commands/fix-issue.md &&
      test -f commands/review-pr.md &&
      test -f commands/plan.md &&
      test -f commands/cleanup.md &&
      test -f commands/doc-garden.md

  # Harness — skills and canon rules
  - id: skills-and-canon-rules
    description: custom-linter skill and canon domain-layering rule exist
    check: >
      test -f skills/custom-linter-authoring.md &&
      test -f canon/rules/domain-layering.md

  # Harness — exec-plans structure
  - id: exec-plans-dirs
    description: docs/exec-plans/active/ and completed/ exist
    check: >
      test -d docs/exec-plans/active &&
      test -d docs/exec-plans/completed

  # Harness — gaps marked done in CLAUDE.md
  - id: harness-gaps-done
    description: Gaps 1-6 marked Done in CLAUDE.md
    check: >
      grep -q '| 1 .*Done' CLAUDE.md &&
      grep -q '| 2 .*Done' CLAUDE.md &&
      grep -q '| 3 .*Done' CLAUDE.md &&
      grep -q '| 4 .*Done' CLAUDE.md &&
      grep -q '| 5 .*Done' CLAUDE.md &&
      grep -q '| 6 .*Done' CLAUDE.md

  # Ralph Loop — self-check
  - id: ralph-files
    description: ralph.yaml and ralph-check.sh exist
    check: >
      test -f ralph.yaml &&
      test -x scripts/ralph-check.sh

  - id: ralph-instruction
    description: CLAUDE.md contains ralph check instruction
    check: grep -q 'ralph-check.sh' CLAUDE.md
```

### `scripts/ralph-check.sh`

Hardcoded checks matching the criteria above (no yq dependency — the script
is the source of truth for what passes). Agent-readable output: ✓/✗ per
criterion with a fix hint on failure. Exit 0 if all pass, exit 1 if any fail.

Output format:
```
✓ rules-files: rules/ has all 5 language files
✓ commands-files: commands/ has all core commands
✓ skills-and-canon-rules: custom-linter skill and canon domain-layering rule exist
✓ exec-plans-dirs: docs/exec-plans/active/ and completed/ exist
✓ harness-gaps-done: Gaps 1-6 marked Done in CLAUDE.md
✗ ralph-files: ralph.yaml and ralph-check.sh exist
  → fix: create ralph.yaml and scripts/ralph-check.sh
✗ ralph-instruction: CLAUDE.md contains ralph check instruction
  → fix: add Ralph Loop section to CLAUDE.md Working Conventions

RESULT: 5/7 criteria passing. Keep working.
```

### `CLAUDE.md` update

Add to Working Conventions:

```markdown
### Ralph Loop

Before declaring any session's work complete, run `bash scripts/ralph-check.sh`.
If any criteria fail, address them and run the check again. All criteria must
pass before the session is done.
```

---

## All files at a glance

| File | Action |
|------|--------|
| `ralph.yaml` | Create |
| `scripts/ralph-check.sh` | Create |
| `CLAUDE.md` | Update — add Ralph Loop section to Working Conventions |

---

## Progress log

- [x] Create `ralph.yaml`
- [x] Create `scripts/ralph-check.sh`
- [x] Update `CLAUDE.md` with Ralph Loop instruction
- [x] Run `bash scripts/ralph-check.sh` — all 7 criteria pass
- [x] Create `commands/apply-core.md` (architecture decision unblocked)
- [x] Redesign apply-core to match ToB pattern (GitHub fetch, interactive, merge, self-install)
- [x] Global install to `~/.claude/` — all components installed, settings merged

---

## Verification

Run `bash scripts/ralph-check.sh` from the repo root. All 7 criteria must
show ✓. If any fail, the script output tells you exactly what to fix.

# Plan: Harness Engineering Implementation

**Status:** In progress — see gap table in root `CLAUDE.md` for live status.

---

## Context

Seven harness engineering gaps were identified from OpenAI's methodology (Feb 2026) and mapped to Claude Code equivalents. All seven are currently marked "To do" in root `CLAUDE.md`. This plan implements them in priority order at the **Core (root)** layer, where they belong — Canon inherits them without duplication.

The harness is the static infrastructure that makes every agent session reliable: how agents load context, how errors are communicated, how architectural drift is prevented, and how docs stay fresh. Without it, no loop (Ralph or otherwise) runs reliably.

**Source document:** `git show origin/openai-harness-patterns:docs/harness-engineering-improvements.md`

---

## Does Canon's CLAUDE.md need harness content?

**No — with one exception.**

Canon inherits all Core harness infrastructure automatically. Canon's `CLAUDE.md` should not duplicate any harness setup. The one Canon-specific addition is domain layering enforcement (`Types→Config→Repo→Service→Runtime→UI`), which becomes a Canon-owned rule in `canon/rules/domain-layering.md`.

Canon `CLAUDE.md` gets a single new section: a pointer to Core harness and the domain-layering rule.

---

## Implementation Phases

### Phase 1 — Gaps 1 + 5 (Foundational, no dependencies)

#### Gap 1: CLAUDE.md as Map + `rules/`

**Problem:** `claude-md-template.md` (the global CLAUDE.md template) is a ~10KB monolith. Language toolchains, philosophy, and workflow all in one file. Crowds out task context. Rots because there's no structure to validate or maintain.

**Fix:**

1. **Restructure `claude-md-template.md`** → lean ~100-line map:
   - Keep: core philosophy (short), code quality hard limits (short), CLI tools table, workflow conventions
   - Remove: language-specific sections (Python, Node, Rust, Bash, GitHub Actions) → move to `rules/`
   - Add: golden principles section (from Gap 6, fits naturally here)
   - Add: pointer to `rules/` directory

2. **Create `rules/` directory** at repo root with glob-matched language files:

   | File | Glob trigger | Content |
   |---|---|---|
   | `rules/python.md` | `*.py` | uv, ruff, ty, test conventions |
   | `rules/node-typescript.md` | `*.ts, *.tsx, *.js` | oxlint, vitest, import conventions |
   | `rules/rust.md` | `*.rs, Cargo.toml` | clippy, cargo deny, safety patterns |
   | `rules/bash.md` | `*.sh` | shellcheck, errexit, safety patterns |
   | `rules/github-actions.md` | `.github/workflows/*.yml` | zizmor, actionlint, pinned versions |

   Each file uses Claude Code's native rules glob matching — loads only when Claude is working on files of that type. Progressive disclosure.

3. **Update root `CLAUDE.md`**: add `rules/` to repo map, update gap 1 status.

**Files modified:** `claude-md-template.md`, `CLAUDE.md` (root)
**Files created:** `rules/python.md`, `rules/node-typescript.md`, `rules/rust.md`, `rules/bash.md`, `rules/github-actions.md`

---

#### Gap 5: Agent-to-Agent Review Convergence Loop

**Problem:** `/fix-issue` and `/review-pr` do one round: implement → review → fix → done. No re-review after fixes. Regressions introduced by fixes go undetected.

**Fix:**

Enhance both commands with a convergence loop:
- After fixing findings, re-run a lightweight self-review
- If new P1–P3 findings appear, fix and re-review
- Maximum 3 rounds
- If not converged after 3 rounds → stop and flag for human

Round 1 uses the full multi-agent review. Rounds 2+ use lightweight self-review (cheaper, faster, catches regressions only).

**Files modified:** `commands/fix-issue.md`, `commands/review-pr.md`

---

### Phase 2 — Gaps 2 + 6 (Depends on Phase 1 structure)

#### Gap 2: Execution Plans as First-Class Artifacts

**Problem:** `/fix-issue` writes a plan file to the repo root, then **deletes it** on commit. Plans are ephemeral. Agents in subsequent sessions have no record of what was tried, decided, or why.

**Fix:**

1. **Create `docs/exec-plans/`** directory structure:
   ```
   docs/exec-plans/
   ├── active/        ← live plans in progress
   ├── completed/     ← archived plans
   └── tech-debt.md   ← known debt tracker
   ```

2. **Create `commands/plan.md`** — standalone plan creation command:
   - Writes structured plan to `docs/exec-plans/active/`
   - Schema: requirements, approach, files to touch, progress log (checkboxes), decision log (why X over Y), completion criteria

3. **Enhance `commands/fix-issue.md`**:
   - Write plans to `docs/exec-plans/active/` (not repo root)
   - Move to `docs/exec-plans/completed/` on close (not delete)
   - Simple issues (single-file obvious fix) may still use ephemeral plans — use judgment

**Files created:** `commands/plan.md`, `docs/exec-plans/active/.gitkeep`, `docs/exec-plans/completed/.gitkeep`, `docs/exec-plans/tech-debt.md`
**Files modified:** `commands/fix-issue.md`

---

#### Gap 6: Entropy / Garbage Collection

**Problem:** No recurring process to detect AI-generated drift: duplicated utilities, inconsistent patterns, docs diverging from code, principle violations accumulating.

**Fix:**

1. **Add golden principles** to `claude-md-template.md` (global template):
   - Prefer shared utilities over hand-rolled helpers
   - Validate data at boundaries (parse, don't validate)
   - Structured logging everywhere, no ad-hoc console.log
   - No YOLO-style data probing — use typed interfaces

2. **Create `commands/cleanup.md`** — weekly GC scan:
   - Finds: duplicated utilities, inconsistent error handling, unused imports/dead code, oversized files, TODO/FIXME debt, principle violations
   - Opens a PR with fixes
   - Designed for weekly cron or Friday ritual

3. **Create `docs/QUALITY.md`** — quality grades per domain:
   - Template for grading codebase areas (A–F) with rationale
   - Populated manually at project start or by `/init` (when built)
   - Agents read this to understand where to focus

**Files created:** `commands/cleanup.md`, `docs/QUALITY.md`
**Files modified:** `claude-md-template.md` — golden principles section (done as part of Gap 1 restructure)

---

### Phase 3 — Gaps 3 + 4 (Automation layer, depends on Phase 1–2)

#### Gap 3: Doc-Gardening Automation

**Problem:** No automated validation that `docs/` reflects actual code. Stale references, broken cross-links, outdated instructions accumulate silently.

**Fix:**

1. **Create `commands/doc-garden.md`**:
   - Scans `docs/` and `CLAUDE.md` against codebase
   - Identifies: stale file/function references, broken cross-links, outdated commands
   - Opens PR with fixes or flags items needing human judgment

2. **Add PostToolUse hook** to `settings.json`:
   - After significant file edits, reminds Claude to update any docs that reference those files
   - Lightweight — just a reminder, not a blocker

**Files created:** `commands/doc-garden.md`
**Files modified:** `settings.json` (add PostToolUse hook)

---

#### Gap 4: Custom Linters with Agent-Friendly Error Messages

**Problem:** Off-the-shelf linters produce human-readable errors. No guidance on writing custom structural linters whose error messages inject remediation instructions directly into agent context.

**Fix:**

1. **Create `skills/custom-linter-authoring.md`**:
   - Teaches how to write `ast-grep` rules
   - The "promote rule into code" pattern: correct Claude twice on the same thing → encode as a lint rule, not a CLAUDE.md instruction
   - Error message design: include *what*, *why*, *how to fix*, and a doc pointer
   - Example rules with agent-optimized messages

2. **Create `canon/rules/domain-layering.md`**:
   - Canon-specific rule: enforce `Types→Config→Repo→Service→Runtime→UI` dependency direction
   - Catches violations with actionable error messages pointing to Canon architecture docs
   - This is the one Canon-specific harness contribution

**Files created:** `skills/custom-linter-authoring.md`, `canon/rules/domain-layering.md`

---

### Phase 4 — Gap 7 (Out of scope for Phase I)

App legibility (per-worktree boot, console streaming, observability) is aspirational. Depends on teams adopting Phases 1–3 first. Deferred to Phase II.

---

## Canon CLAUDE.md Change (minimal)

Add one section to `canon/CLAUDE.md`:

```markdown
## Harness

Canon inherits all Core harness infrastructure (CLAUDE.md map, rules/, commands, hooks).
No duplication needed here.

Canon-specific addition: domain layering enforcement
(`Types→Config→Repo→Service→Runtime→UI`) is defined in `canon/rules/domain-layering.md`
and enforced via ast-grep rules with agent-friendly error messages.
```

**File modified:** `canon/CLAUDE.md`

---

## All Files at a Glance

| File | Action | Gap |
|---|---|---|
| `claude-md-template.md` | Restructure → lean map + golden principles | 1, 6 |
| `CLAUDE.md` (root) | Update repo map, gap statuses | 1 |
| `rules/python.md` | Create | 1 |
| `rules/node-typescript.md` | Create | 1 |
| `rules/rust.md` | Create | 1 |
| `rules/bash.md` | Create | 1 |
| `rules/github-actions.md` | Create | 1 |
| `commands/fix-issue.md` | Enhance (convergence loop + exec-plans) | 5, 2 |
| `commands/review-pr.md` | Enhance (convergence loop) | 5 |
| `commands/plan.md` | Create | 2 |
| `commands/cleanup.md` | Create | 6 |
| `commands/doc-garden.md` | Create | 3 |
| `skills/custom-linter-authoring.md` | Create | 4 |
| `docs/exec-plans/active/.gitkeep` | Create | 2 |
| `docs/exec-plans/completed/.gitkeep` | Create | 2 |
| `docs/exec-plans/tech-debt.md` | Create | 2 |
| `docs/QUALITY.md` | Create (template) | 6 |
| `settings.json` | Add PostToolUse hook | 3 |
| `canon/CLAUDE.md` | Add harness inheritance note | — |
| `canon/rules/domain-layering.md` | Create | 4 |

---

## Verification

1. **Gap 1**: `claude-md-template.md` is ≤ 100 lines, no language-specific toolchain content. `rules/` files exist with correct glob metadata at top.
2. **Gap 5**: `/fix-issue` steps show convergence loop section with "up to 3 rounds" language. `/review-pr` matches.
3. **Gap 2**: `docs/exec-plans/active/` and `completed/` exist. `/fix-issue` writes plans there. `/plan` command creates a plan file in `active/`.
4. **Gap 6**: `commands/cleanup.md` exists. `docs/QUALITY.md` exists as template. Golden principles appear in `claude-md-template.md`.
5. **Gap 3**: `commands/doc-garden.md` exists. `settings.json` has a PostToolUse hook entry.
6. **Gap 4**: `skills/custom-linter-authoring.md` exists. `canon/rules/domain-layering.md` exists with example ast-grep rule and agent-friendly error message.
7. **Canon**: `canon/CLAUDE.md` has harness section. `canon/rules/` has domain-layering rule. No Core content duplicated.

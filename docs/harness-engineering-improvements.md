# Harness Engineering Improvements

Actionable improvements for this repo derived from [OpenAI's "Harness Engineering" article](https://openai.com/index/harness-engineering/) (Feb 2026), mapped to Claude Code equivalents. The article documents lessons from building a product with zero manually-written code using Codex agents over five months (~1M lines of code, ~1,500 PRs).

## What we already cover

These patterns from the article are already present in this repo:

| OpenAI Pattern | Our Equivalent |
|---|---|
| AGENTS.md for directing agents | `claude-md-template.md` (global CLAUDE.md) |
| Guardrails via tooling | Hooks: `rm -rf` blocker, push-to-main blocker, package manager enforcer |
| Agent-driven PR review | `/review-pr` command using multi-agent review |
| End-to-end autonomous issue resolution | `/fix-issue` command (plan → implement → test → PR → self-review → fix) |
| Anti-rationalization / force-continue | `Stop` hook pattern (prompt-based cop-out detection) |
| Context management discipline | README section on context management, `/clear` vs `/compact`, checkpoints |
| Worktree-aware parallel agents | `wt` tool in CLAUDE.md, "each subagent MUST work in its own worktree" |

---

## Architecture: Zero-Manual-Steps Automation

All improvements follow a two-command model that eliminates manual setup. No developer should copy files, create directories, or remember to run follow-up steps.

### Layer 1: `/dega:config` (run once per developer machine)

Already exists. Enhanced to install all new artifacts globally:

```
~/.claude/
├── CLAUDE.md                          # Lean ~100-line map (Gap 1)
├── settings.json                      # Enhanced: new hooks (Gaps 3, 4)
├── statusline.sh
├── rules/                             # NEW: modular language rules (Gap 1)
│   ├── python.md                      #   glob: *.py
│   ├── node-typescript.md             #   glob: *.ts, *.tsx, *.js
│   ├── rust.md                        #   glob: *.rs, Cargo.toml
│   ├── bash.md                        #   glob: *.sh
│   └── github-actions.md             #   glob: .github/workflows/*.yml
├── commands/
│   ├── init.md                        # NEW: project scaffolding (Gaps 1, 2, 6)
│   ├── plan.md                        # NEW: execution plans (Gap 2)
│   ├── doc-garden.md                  # NEW: doc freshness scanner (Gap 3)
│   ├── cleanup.md                     # NEW: garbage collection (Gap 6)
│   ├── review-pr.md                   # Enhanced: convergence loop (Gap 5)
│   ├── fix-issue.md                   # Enhanced: convergence loop + plan preservation (Gap 5)
│   └── dega/
│       └── config.md                  # Enhanced: installs all of the above
└── output-styles/
~/.mcp.json                            # MCP servers (unchanged)
```

Language-specific rules use Claude Code's native `.claude/rules/` glob matching for progressive disclosure — they only load when Claude is working on files of that type. The global CLAUDE.md stays small and never crowds out the actual task.

### Layer 2: `/init` (run once per project repo)

A new global command (installed by `/dega:config`) that scaffolds a project. This is an **agent command, not a file copy** — it reads the codebase, detects the stack, and generates tailored project-level artifacts:

1. **Detect** the tech stack (Python, Node, Rust, multi-language, etc.) and build system
2. **Generate** a lean project-level `CLAUDE.md` (~100 lines) serving as a map to `docs/`
3. **Scaffold** the `docs/` directory structure:

```
CLAUDE.md                  # Generated: project map with detected build/test/lint commands
docs/
├── ARCHITECTURE.md        # Generated: domain map based on codebase analysis
├── QUALITY.md             # Generated: initial quality grades per domain
├── PLANS.md               # Index of active/completed execution plans
├── SECURITY.md            # Security invariants (skeleton)
├── exec-plans/
│   ├── active/
│   └── completed/
├── references/            # llms.txt files, API docs
└── design-docs/
    └── index.md
```

4. **Scaffold** project-local `.ast-grep/` rules based on detected stack (Gap 4)
5. **Commit** all scaffolding so other developers get it from git
6. **Run `/plan`** to generate the initial execution plan for the project's immediate work

Step 6 is critical: `/init` chains into `/plan` automatically. Developers never need to remember to run `/plan` separately after init. The project is fully configured and has a working plan before the developer writes a single line of code.

`/plan` also exists as a standalone command for creating execution plans later — but the first plan is always created by `/init`.

### The developer experience

**New developer onboarding (one-time):**
```
git clone dega/claude-code-config && cd claude-code-config
claude
> /dega:config
```

**Starting work on a project (one-time per repo):**
```
cd ~/projects/some-repo
claude
> /init
```

**Ongoing work uses commands naturally:**
```
/fix-issue 42          # Autonomous: plan → implement → test → PR → review loop → done
/review-pr 99          # Review with convergence loop
/plan Add OAuth        # Create a new execution plan
/cleanup               # Weekly drift scan
/doc-garden            # Weekly doc freshness check
```

### Skills (via Dega marketplace)

Two improvements are better suited as **skills** (knowledge that shapes how Claude thinks) rather than commands (procedures that run steps):

- **Custom linter authoring** (Gap 4) — teaches Claude how to write `ast-grep` rules with agent-friendly error messages, the "promote rule into code" pattern
- **Application legibility** (Gap 7) — teaches Claude patterns for making apps observable to agents: per-worktree boot, log piping, health checks

Skills live in the `dega/skills` marketplace and are installed via `/plugin install`. They don't require any per-project setup.

---

## Gap 1: Restructure CLAUDE.md as a Map, Not an Encyclopedia

**Priority: High** — compounds over time in every project that adopts this config.

**Artifact type:** Global config (`/dega:config`) + project scaffolding (`/init`)

### What they learned

They tried "one big AGENTS.md" and it failed:

- Hard to verify — a single blob doesn't lend itself to mechanical checks (coverage, freshness, ownership, cross-links), so drift is inevitable.
- Rots instantly — a monolithic manual turns into a graveyard of stale rules. Agents can't tell what's still true.
- Too much guidance becomes non-guidance — when everything is "important," nothing is.
- Context is scarce — a giant instruction file crowds out the task, the code, and the relevant docs.

Their fix: AGENTS.md is ~100 lines and serves as a **table of contents** pointing to a structured `docs/` directory. They call this **progressive disclosure** — agents start with a small, stable entry point and are taught where to look next.

### Our current state

`claude-md-template.md` is a ~10KB monolith covering philosophy, code quality, language toolchains, and workflow in one file. This is the pattern they abandoned.

### Implementation plan

**Global (installed by `/dega:config`):**

1. Restructure `claude-md-template.md` into a lean ~100-line global CLAUDE.md covering:
   - Core philosophy (keep as-is, it's short)
   - Code quality hard limits (keep as-is, it's short)
   - CLI tools table (keep as-is, it's a reference)
   - Workflow conventions (keep as-is, it's short)
   - Golden principles (new, from Gap 6)
2. Extract language-specific sections into `~/.claude/rules/` with glob matchers for progressive disclosure:
   - `python.md` — activated by `*.py` files
   - `node-typescript.md` — activated by `*.ts`, `*.tsx`, `*.js` files
   - `rust.md` — activated by `*.rs`, `Cargo.toml` files
   - `bash.md` — activated by `*.sh` files
   - `github-actions.md` — activated by `.github/workflows/*.yml` files

**Per-project (scaffolded by `/init`):**

3. `/init` generates a project-level `CLAUDE.md` as a map — not a copy of the global template but a tailored entry point:
   - Detected build/test/lint commands
   - Pointers to `docs/ARCHITECTURE.md`, `docs/QUALITY.md`, etc.
   - Project-specific conventions discovered by reading the codebase
4. `/init` scaffolds the `docs/` directory structure with generated content (not empty skeletons — Claude reads the codebase and writes initial drafts of ARCHITECTURE.md and QUALITY.md)

### Key quote

> "Give Codex a map, not a 1,000-page instruction manual."

---

## Gap 2: Execution Plans as First-Class Artifacts

**Priority: Medium** — high payoff for teams doing complex feature work.

**Artifact type:** New `/plan` command (`/dega:config`) + directory scaffolding (`/init`) + enhanced `/fix-issue`

### What they learned

Plans are treated as first-class artifacts — checked into the repo with progress logs, decision logs, versioned alongside code. Active plans, completed plans, and known technical debt are all versioned and co-located. This lets agents operate without relying on external context (Slack, Google Docs, people's heads).

### Our current state

The `/fix-issue` command writes a `plan-issue-$ISSUE_NUMBER.md` to the repo root, then **deletes it** before committing. Plans are ephemeral working artifacts, not versioned knowledge.

### Implementation plan

1. `/init` scaffolds `docs/exec-plans/active/` and `docs/exec-plans/completed/` with `.gitkeep` files, `docs/PLANS.md` as the index, and `docs/exec-plans/tech-debt-tracker.md` for known debt
2. `/init` chains into `/plan` at the end — the first execution plan is created automatically as part of project setup, covering whatever the immediate work is
3. Create a standalone `/plan` command (installed to `~/.claude/commands/plan.md`) that writes structured execution plans:
   - Requirements summary
   - Approach and key design decisions
   - Files to create or modify
   - Progress log (checkboxes updated as work proceeds)
   - Decision log (why X over Y, with tradeoffs noted)
   - Explicit completion criteria
   - Plans write to `docs/exec-plans/active/`
4. Modify `/fix-issue` to:
   - Write plans to `docs/exec-plans/active/` instead of the repo root
   - Move completed plans to `docs/exec-plans/completed/` instead of deleting
   - For simple issues (single-file, obvious fix), the plan can still be ephemeral — use judgment based on complexity

### Key quote

> "Active plans, completed plans, and known technical debt are all versioned and co-located, allowing agents to operate without relying on external context."

---

## Gap 3: Doc-Gardening Automation

**Priority: Medium** — prevents knowledge base rot, the #1 failure mode of monolithic docs.

**Artifact type:** New `/doc-garden` command (`/dega:config`) + PostToolUse hook in `settings.json`

### What they learned

They enforce documentation mechanically. CI jobs validate that the knowledge base is up-to-date, cross-linked, and structured correctly. A recurring "doc-gardening" agent scans for stale or obsolete documentation that doesn't reflect real code behavior and opens fix-up PRs.

### Our current state

No automation for documentation freshness. The README mentions `/insights` for session analysis, but there's no recurring process that validates project docs against actual code.

### Implementation plan

1. Create a `/doc-garden` command (installed to `~/.claude/commands/doc-garden.md`) that:
   - Scans a project's `docs/` and CLAUDE.md against the actual codebase
   - Identifies stale references (files/functions that no longer exist, APIs that changed, outdated instructions)
   - Checks cross-links between docs are valid
   - Opens a PR with fixes or flags items requiring human judgment
2. Add a `PostToolUse` hook to `settings.json` that reminds Claude to update relevant docs when making significant code changes (e.g., after editing files referenced in ARCHITECTURE.md)
3. Add README guidance on scheduling recurring doc-gardening runs:
   - Weekly cron via `claude --print` piped to the command
   - CI job that runs doc validation on every PR
   - Manual cadence: run `/doc-garden` every Friday

### Key quote

> "Dedicated linters and CI jobs validate that the knowledge base is up to date, cross-linked, and structured correctly."

---

## Gap 4: Custom Linters with Agent-Friendly Error Messages

**Priority: Medium** — advanced but differentiating for agent-first workflows.

**Artifact type:** Skill (Dega marketplace) + PostToolUse hook in `settings.json` + project-local scaffolding (`/init`)

### What they learned

They write custom linters whose error messages are specifically designed to inject remediation instructions into agent context. When documentation falls short, they **promote the rule into code**. They enforce structured logging, naming conventions, file size limits, and dependency direction with custom lints.

The key insight: **error messages are a form of context injection**. Design them as instructions to the agent, not descriptions for humans.

### Our current state

We use off-the-shelf linters (`ruff`, `oxlint`, `clippy`, `shellcheck`, `actionlint`, `zizmor`) and have PreToolUse hooks that block patterns with error messages. But there's no guidance on writing custom project-specific linters or using `ast-grep` rules as structural enforcers with agent-optimized messages.

### Implementation plan

1. Create a **custom-linter-authoring skill** for the `dega/skills` marketplace that teaches Claude:
   - How to write `ast-grep` rules with agent-friendly error messages
   - The "promote rule into code" pattern: when you correct Claude twice on the same thing, encode it as a lint or hook, not a CLAUDE.md instruction
   - Example rules with remediation-as-error-message:
     - Catches direct `console.log` usage → "Use the structured logger from `@app/logger` instead. See `docs/ARCHITECTURE.md#logging` for conventions."
     - Catches relative imports → "Use absolute imports from the package root. See CLAUDE.md#code-quality for the rule."
     - Catches files exceeding size limits → "This file exceeds 300 lines. Split it by responsibility. See `docs/ARCHITECTURE.md` for the domain layout."
2. Add a `PostToolUse` hook to `settings.json` that runs project-local ast-grep rules after file writes and feeds results (with remediation instructions) back into Claude's context
3. `/init` scaffolds a `.ast-grep/` directory with starter rules based on the detected stack

### Key quote

> "Because the lints are custom, we write the error messages to inject remediation instructions into agent context."

---

## Gap 5: Agent-to-Agent Review Convergence Loop

**Priority: High** — directly improves the quality of `/fix-issue` and `/review-pr` output.

**Artifact type:** Enhanced commands (`/dega:config`)

### What they learned

Their workflow is fully autonomous: Codex reviews its own changes, requests additional agent reviews, responds to feedback, and **iterates in a loop** until all reviewers are satisfied. They call this the "Ralph Wiggum Loop." Humans may review but aren't required.

### Our current state

`/fix-issue` does one round: implement → self-review → fix findings → done. `/review-pr` also does one round. There's no iteration loop where the agent re-reviews after fixing, catches new issues introduced by the fixes, and continues until clean.

### Implementation plan

1. Enhance `/fix-issue` step 7 (fix findings) with a convergence loop:
   - After fixing findings, re-run the review
   - If new findings emerge (P1-P3), fix and re-review
   - Repeat up to 3 iterations or until clean
   - If not converging after 3 rounds, stop and flag for human review
2. Enhance `/review-pr` with the same convergence pattern
3. Use a lightweight self-review step (not the full multi-agent review) for rounds 2+ — cheaper and faster for catching regressions introduced by the fixes
4. Document the convergence loop pattern in the README's hooks section as a composable workflow

### Key quote

> "We instruct Codex to review its own changes locally, request additional specific agent reviews both locally and in the cloud, respond to any human or agent given feedback, and iterate in a loop until all agent reviewers are satisfied."

---

## Gap 6: Entropy / Garbage Collection Automation

**Priority: High** — prevents codebase drift, the biggest long-term risk of agent-generated code.

**Artifact type:** New `/cleanup` command (`/dega:config`) + golden principles in global CLAUDE.md + quality scaffolding (`/init`)

### What they learned

They spent 20% of their week (every Friday) cleaning up "AI slop" manually. It didn't scale. Their fix:

1. Encode "golden principles" — opinionated, mechanical rules — directly into the repo
2. Build recurring background Codex tasks that scan for deviations, update quality grades, and open targeted refactoring PRs
3. Most of these PRs can be reviewed in under a minute and automerged

They describe this as **garbage collection**: continuous small cleanups rather than painful periodic bursts. "Technical debt is like a high-interest loan: it's almost always better to pay it down continuously in small increments than to let it compound."

### Our current state

The anti-rationalization `Stop` hook catches incomplete work in real-time, but there's no recurring cleanup process. No quality scoring, no automated drift detection, no "golden principles" enforcement beyond CLAUDE.md.

### Implementation plan

1. Add golden principles to the global CLAUDE.md (installed by `/dega:config`):
   - Prefer shared utility packages over hand-rolled helpers
   - Validate data at boundaries (parse, don't validate)
   - No YOLO-style data probing — use typed interfaces
   - Structured logging everywhere
2. Create a `/cleanup` command (installed to `~/.claude/commands/cleanup.md`) that scans a project for common agent-generated drift:
   - Duplicated utility code that should be consolidated
   - Inconsistent error handling patterns
   - Unused imports, variables, dead code
   - Files exceeding size limits
   - Code that violates the project's stated conventions
   - TODOs and FIXMEs that have been sitting too long
   - Deviations from `docs/QUALITY.md` grades
   - Opens a PR with fixes
3. `/init` scaffolds `docs/QUALITY.md` with initial quality grades per domain/layer:
   - Claude reads the codebase and grades each area (A-F) with brief rationale
   - Tracks gap history over time
   - Agents read this to understand what needs attention
4. Add README guidance on scheduling recurring cleanup:
   - Weekly automated runs via `claude --print`
   - As part of CI on every PR (lightweight version)
   - As a Friday ritual replacing manual cleanup

### Key quote

> "Human taste is captured once, then enforced continuously on every line of code."

---

## Gap 7: Application Legibility to Agents

**Priority: Low** — aspirational, most valuable for full-stack / web app work.

**Artifact type:** Skill (Dega marketplace)

### What they learned

They made the app bootable per git worktree so Codex could launch and drive one instance per change. They wired Chrome DevTools Protocol into the agent runtime and created skills for working with DOM snapshots, screenshots, and navigation. They exposed logs, metrics, and traces via a local observability stack that's ephemeral per worktree. Agents can query logs with LogQL and metrics with PromQL.

This enabled prompts like "ensure service startup completes in under 800ms" or "no span in these four critical user journeys exceeds two seconds."

### Our current state

We have `agent-browser` for browser automation and Chrome DevTools support. But there's no guidance on making app logs, metrics, or runtime state accessible to Claude Code agents. No patterns for per-worktree app instances or ephemeral observability stacks.

### Implementation plan

1. Create an **app-legibility skill** for the `dega/skills` marketplace that teaches Claude:
   - How to make apps bootable per-worktree (isolated instances for parallel agent work)
   - How to pipe app logs to files agents can read (e.g., `dev-server.log` in the worktree root)
   - How to expose health checks or structured logs agents can query
   - Pattern: `PostToolUse` hook that captures app startup logs after server-start commands
2. Include example configurations for common setups:
   - Next.js / Node server: redirect stdout to a log file, expose `/health` endpoint
   - Python / FastAPI: structured JSON logging to file, startup probe
3. Document how `agent-browser` + per-worktree app instances enable parallel agent QA

### Key quote

> "From the agent's point of view, anything it can't access in-context while running effectively doesn't exist."

---

## Implementation order

Recommended sequence based on impact and dependency:

| Phase | Gaps | Artifacts | Rationale |
|-------|------|-----------|-----------|
| **Phase 1** | #1 (CLAUDE.md restructure), #5 (review loop) | Restructured CLAUDE.md, `~/.claude/rules/`, enhanced `/fix-issue` and `/review-pr` | Highest impact, no dependencies. #1 is foundational. #5 is a small change to existing commands with immediate quality improvement. |
| **Phase 2** | #2 (execution plans), #6 (garbage collection) | `/init` command, `/plan` command, `/cleanup` command, golden principles in CLAUDE.md | `/init` depends on the `docs/` structure from Phase 1. `/init` chains into `/plan` to eliminate manual follow-up. Garbage collection needs the quality scoring template that `/init` scaffolds. |
| **Phase 3** | #3 (doc-gardening), #4 (custom linters) | `/doc-garden` command, PostToolUse hooks, custom-linter-authoring skill | Automation layer. Doc-gardening validates the structure from Phase 1-2. Custom linters encode lessons learned from Phase 1-2. |
| **Phase 4** | #7 (app legibility) | App-legibility skill | Aspirational. Depends on teams adopting the other patterns first. |

After each phase, update `/dega:config` to install the new artifacts. Developers re-run `/dega:config` to pick up changes — no manual file copying.

## Source

- Article: [Harness engineering: leveraging Codex in an agent-first world](https://openai.com/index/harness-engineering/) (OpenAI, Feb 11 2026)
- Author: Ryan Lopopolo, Member of the Technical Staff
- Related: [Execution plans cookbook](https://cookbook.openai.com/articles/codex_exec_plans), [Ralph Wiggum Loop](https://ghuntley.com/loop/), [Parse, don't validate](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/)

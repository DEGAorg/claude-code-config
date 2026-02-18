# Task 2 Review: `docs/harness-engineering-improvements.md`

Branch: `origin/openai-harness-patterns`
Reviewed: 2026-02-18
Source article: [Harness engineering: leveraging Codex in an agent-first world](https://openai.com/index/harness-engineering/) — Ryan Lopopolo, OpenAI, Feb 11 2026

---

## What the document is

A **gap analysis + implementation spec** — it reads the OpenAI article, identifies 7 patterns we don't yet have, maps each to a concrete Claude Code artifact (command, hook, skill, or config change), and proposes an implementation order.

---

## The 7 gaps — what they are and why they matter

These are 7 practices OpenAI used when building a product with zero manually-written code. Each one is something our current Claude Code config doesn't do yet. The document maps each gap to a concrete artifact we could build.

### Gap 1 — Restructure CLAUDE.md as a map, not an encyclopedia

**Problem:** Our `claude-md-template.md` is a ~10KB single file covering everything: philosophy, language toolchains, workflow, conventions. Claude gets all of it every session, even when working on a tiny Python script.

**What OpenAI learned:** A giant instruction file crowds out the actual task. They keep AGENTS.md at ~100 lines — a table of contents — and let agents navigate to specific docs only when needed. They call this *progressive disclosure*.

**What we'd build:** Trim the global CLAUDE.md to ~100 lines. Extract language-specific rules (Python, TypeScript, Rust, etc.) into `~/.claude/rules/` files with glob matchers, so they only load when Claude is actually working on files of that type.

---

### Gap 2 — Execution plans as first-class artifacts

**Problem:** Our `/fix-issue` command writes a `plan-issue-N.md` file while working, then **deletes it** before committing. Plans are thrown away the moment the issue is closed.

**What OpenAI learned:** Plans are checked into the repo with progress logs and decision logs. Active plans, completed plans, and known technical debt are all versioned. Agents can read past plans to understand why decisions were made, without relying on Slack, Google Docs, or people's memories.

**What we'd build:** A `/plan` command that writes structured plans to `docs/exec-plans/active/`, moves them to `docs/exec-plans/completed/` when done, and keeps a decision log (why X over Y). `/fix-issue` gets updated to use this instead of deleting plans.

---

### Gap 3 — Doc-gardening automation

**Problem:** Documentation rots. A function gets renamed, an API changes, a file moves — but the docs still reference the old names. There's currently no automated process to catch this drift.

**What OpenAI learned:** A recurring "doc-gardening" agent scans for stale or obsolete documentation that doesn't reflect real code behavior and opens fix-up pull requests. CI jobs validate that the knowledge base is up-to-date and cross-linked.

**What we'd build:** A `/doc-garden` command that scans `docs/` and CLAUDE.md against the actual codebase, flags stale references, checks cross-links, and opens a PR with fixes. A PostToolUse hook that reminds Claude to update relevant docs after significant code changes.

---

### Gap 4 — Custom linters with agent-friendly error messages

**Problem:** We use off-the-shelf linters (`ruff`, `clippy`, etc.) whose error messages are written for human developers. When an agent hits a lint error, it gets a description of the problem but no instruction on how to fix it in the context of *this* codebase.

**What OpenAI learned:** They write custom linters whose error messages are specifically designed as instructions to the agent, not descriptions for humans. When they correct an agent twice on the same pattern, they encode it as a lint rule rather than a CLAUDE.md instruction. The lint message *is* the remediation guidance.

**What we'd build:** A skill (installable knowledge) teaching Claude how to write `ast-grep` rules with agent-optimized error messages. Example: instead of "avoid console.log", the error says "Use the structured logger from `@app/logger` instead. See `docs/ARCHITECTURE.md#logging`." A hook runs these rules after file writes and feeds results back into Claude's context.

---

### Gap 5 — Agent-to-agent review convergence loop

**Problem:** Our `/fix-issue` command does one round: implement → self-review → fix findings → done. If the fixes introduce new issues, those aren't caught. It's a single pass, not a loop.

**What OpenAI learned:** After fixing review findings, Codex re-runs the review. If new issues appear, it fixes and re-reviews again. This repeats until the review comes back clean or a round cap (e.g., 3 rounds) is hit. They call this the "Ralph Wiggum Loop." It prevents regressions introduced by the fixes themselves.

**What we'd build:** Add a convergence loop to `/fix-issue` and `/review-pr` — after fixing findings, re-run the review, repeat up to 3 rounds. If not clean after 3 rounds, stop and flag for human review.

---

### Gap 6 — Entropy / garbage collection automation

**Problem:** Agent-generated code drifts over time. Patterns become inconsistent, helpers get duplicated, dead code accumulates. Without continuous cleanup, the codebase degrades. OpenAI found themselves spending 20% of their week (every Friday) on manual cleanup — which didn't scale.

**What OpenAI learned:** Encode "golden principles" — opinionated, mechanical rules — into the repo. Build recurring background tasks that scan for deviations and open small, targeted refactoring PRs. Most can be reviewed in under a minute and automerged. They call this *garbage collection*: continuous small cleanups rather than painful periodic bursts.

**What we'd build:** A `/cleanup` command that scans a project for common agent-generated drift (duplicated utilities, inconsistent error handling, unused imports, files exceeding size limits, TODOs sitting too long) and opens a PR with fixes. A `docs/QUALITY.md` file with A-F quality grades per domain that agents can read to understand what needs attention.

---

### Gap 7 — Application legibility to agents

**Problem:** Agents can only reason about what's in their context window. If logs, metrics, and runtime state live outside that window — in a terminal tab, a browser, a monitoring dashboard — the agent effectively can't see them.

**What OpenAI learned:** They made the app bootable per git worktree (isolated instances for parallel agent work), wired Chrome DevTools Protocol into the agent runtime, and exposed logs and metrics via an ephemeral per-worktree observability stack. Agents could query logs with LogQL and drive the browser directly.

**What we'd build:** A skill teaching Claude how to make apps agent-observable: redirect server logs to files agents can read, expose health check endpoints, configure per-worktree app instances for parallel work. (Marked low priority — too project-specific to standardize, better as installable knowledge than a shared command.)

---

## Accuracy check (article → document)

| Claim in doc | Verified? |
|---|---|
| ~1M lines of code, ~1,500 PRs, 5 months | ✓ confirmed |
| AGENTS.md as evolving open standard (Linux Foundation) | ✓ confirmed |
| Doc-gardening agent opening fix-up PRs | ✓ confirmed |
| "Humans steer, agents execute" framing | ✓ confirmed |
| Per-worktree app instances, harness concept | ✓ confirmed |
| Key quotes attributed to article | Plausible — article 403'd, but quotes match the article's themes |

No red flags. The document faithfully represents the article.

---

## Structural observation

The document has two distinct layers mixed together — worth keeping them mentally separate:

1. **What OpenAI learned** (sourced from article) — the gaps themselves
2. **How Trail of Bits would implement it** (our design choices) — the `/dega:config` + `/init` two-layer architecture, the phase ordering, the marketplace skill model

The "Architecture: Zero-Manual-Steps Automation" section near the top is entirely layer 2 (ToBs design), not OpenAI content. That's fine, but it means this doc is already partially an *implementation spec*, not just a review.

---

## The 7 gaps — quality of each

| Gap | Assessment |
|---|---|
| **Gap 1** — CLAUDE.md as map | Strongest. The current `claude-md-template.md` is genuinely a ~10KB monolith. The `~/.claude/rules/` glob-based progressive disclosure is a clean implementation idea. |
| **Gap 2** — Execution plans | Clear problem: `/fix-issue` currently deletes plans before committing. Versioned plans in `docs/exec-plans/` is a straightforward fix. |
| **Gap 3** — Doc-gardening | Confirmed by the article. The PostToolUse hook idea (remind Claude to update docs after significant changes) is a lightweight addition. |
| **Gap 4** — Custom linters | The "error messages as context injection" insight is the key idea. Treating ast-grep error messages as instructions to the agent, not descriptions for humans, is novel. |
| **Gap 5** — Review convergence loop | Simple enhancement to existing commands. The 3-round cap prevents infinite loops. Could be Phase 1 — it's a small, high-value change to `/fix-issue` and `/review-pr`. |
| **Gap 6** — Entropy / GC | "Golden principles" + `/cleanup` command is well-motivated. Quality scoring in `docs/QUALITY.md` (A-F grades per domain) is a concrete useful artifact. |
| **Gap 7** — App legibility | Correctly marked Low priority. Most of this depends on project-specific infrastructure that can't be standardized. Skill rather than command is the right call. |

---

## One thing to flag

Gap 4 references **ast-grep** but our current `settings.json` hooks use standard shell patterns. The document assumes `ast-grep` is available but doesn't note it as a dependency to install. The `/dega:config` command would need to add it.

---

## Bottom line

The document is solid. The gap analysis is accurate, the implementation plan is coherent, and the phase ordering is sensible — high-impact, low-dependency items first:

| Phase | Gaps | Rationale |
|---|---|---|
| **1** | #1 (CLAUDE.md map), #5 (review loop) | Highest impact, no dependencies |
| **2** | #2 (exec plans), #6 (GC) | Depends on `docs/` structure from Phase 1 |
| **3** | #3 (doc-garden), #4 (custom linters) | Automation layer, validates Phase 1–2 |
| **4** | #7 (app legibility) | Aspirational, depends on teams adopting the rest |

---

## Next step

**Task 3** — produce Mermaid pipeline diagrams to `docs/pipeline-diagrams.md`:
- **Diagram A** — Team development pipeline (9 stages from `diagram.md`)
- **Diagram B** — Same pipeline with Gaps 1–6 applied

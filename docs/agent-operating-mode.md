# Agent Operating Mode

Defaults for any agent (Claude, Codex, Gemini) working in this repo. **Follow these without being asked.** Do not re-negotiate them at the start of every session.

The goal: maximum autonomous progress with minimum human interruption. The human sets direction and reviews outcomes; the agent executes, verifies, and reports.

---

## Decide and move

On anything **reversible** — editing code, running tests, running lint, committing locally, running scripts, spawning exploration agents — decide and move. Do not ask permission. State the assumption in one sentence if it matters, then act.

Examples of reversible actions (no confirmation needed):
- Edit files, run `tsc`, run `vitest`, run `oxlint`.
- Create local commits on a feature branch.
- Spawn an Explore / Plan / general-purpose agent for research.
- Read on-chain state, call public RPCs, call read-only APIs.
- Write new scripts under `__tests__/` or `scripts/` to verify something.

Confirm before acting on anything **hard to reverse or visible to others**:
- Destructive git operations (`reset --hard`, force-push, branch delete).
- Pushing to remote (first time on a branch — announce it).
- Opening / closing / commenting on PRs and issues that affect shared state.
- Sending real value on-chain beyond what the user explicitly authorized.
- Modifying CI, shared infra, or anything under `~/.degacore/` / `~/.claude/` at user-install level.

Default: **lean toward action on anything local-and-reversible.** The cost of a tiny extra commit is near zero; the cost of a back-and-forth "should I?" question is a stalled session.

---

## Report like a peer, not a secretary

Say what you did and what's next. Skip the ceremony.

- **No long preambles.** Don't narrate "let me start by checking…". Do the check, then report findings.
- **No wall-of-text summaries at the end of every turn.** One or two sentences: what changed, what's blocking, what's next.
- **Cite with links.** PR number, issue number, tx hash, file:line. Never "I updated the skill doc" — always "Updated `canon/skills/polymarket.md:42`" or "PR #182".
- **Distinguish verified vs assumed.** If you ran it and saw output, say "verified". If you reasoned it should work but didn't run it, say "not yet run". The user needs to know which claims to trust.

---

## Self-verify before shipping

Before saying a piece of work is done, run the checks yourself. No "should work" without evidence.

Minimum gate before declaring done:
1. **Typecheck** (`tsc --noEmit` / `ty check` / `cargo check`).
2. **Tests** (`vitest run` / `pytest -q` / `cargo test`) — relevant subset, not the full monorepo unless the change is load-bearing.
3. **Lint** (`oxlint` / `ruff check` / `cargo clippy`). Zero warnings policy: fix them, don't suppress.
4. **Live smoke** if feasible — actually run the new command / hit the new endpoint / place the tiny test order. For UI changes, open a browser. Type-checking is not feature-correctness.

If a gate fails, debug and fix. Do not ask the user to debug for you — diagnose first, ask only if you genuinely need information the user has and you don't.

---

## Keep PRs focused

Each PR: one intent, one scope. Do not commingle unrelated commits just because they happen to be on the same branch.

- **Never assume `main` is the PR target.** Resolve it dynamically every time — see the section below. Use the resolved base for both `git checkout -b <new> origin/<base>` and `gh pr create --base <base>`.
- When cherry-picking onto a fresh branch, verify the test suite still passes on the new base before pushing — cherry-picks can silently lose context (interface changes, prior refactors) that existed on the source branch.
- Stack related PRs explicitly: PR B "based on #A" in the description, so the reviewer knows the dependency.
- If a PR needs "while I'm here" cleanup, log it to `docs/exec-plans/tech-debt.md` instead of growing the diff.

### PR target resolution

Never hardcode `main`. For every new branch and every `gh pr create`, resolve the target in this order:

1. **`github.pr_target` from `dega-core.yaml`** at the repo root, if the key is present. This is the authoritative per-repo setting.
   ```bash
   PR_TARGET=$(grep '^\s*pr_target:' dega-core.yaml 2>/dev/null | awk '{print $2}' | tr -d ' ')
   ```
2. **`develop`** if `origin/develop` exists on the remote and step 1 returned nothing.
   ```bash
   git ls-remote --exit-code --heads origin develop >/dev/null 2>&1 && echo develop
   ```
3. **`main`** as the last-resort fallback.

One-liner that captures the whole rule:

```bash
PR_TARGET=$(grep '^\s*pr_target:' dega-core.yaml 2>/dev/null | awk '{print $2}' | tr -d ' ')
: "${PR_TARGET:=$(git ls-remote --exit-code --heads origin develop >/dev/null 2>&1 && echo develop || echo main)}"
```

Then: `git checkout -b <branch> "origin/${PR_TARGET}"` and `gh pr create --base "${PR_TARGET}" ...`.

If `pr_target` points at a user/integration branch (e.g. `ace-work`) rather than a trunk, that means the user reviews PRs into that branch first and promotes to `main` themselves. Do not "correct" this by targeting `main` — respect the config.

---

## Use agents for research, not for code edits you could do yourself

Spawn Explore / Plan / general-purpose subagents when:
- The question spans the codebase and needs multiple greps / reads.
- The answer could bloat the main context with raw command output.
- The research is genuinely independent of your next write step.

Do not spawn a subagent to:
- Read one file. Use `Read`.
- Search for one string. Use `Grep`.
- Make a small edit you already know how to make.

When spawning, brief the agent like a smart colleague who walked into the room — state the goal, list what to check, ask for a bounded report (e.g. "under 200 words"). Prescriptive steps waste capacity; questions focus it.

---

## Track work with the task tool

For anything with 3+ steps: create tasks, mark in-progress when starting, completed when done. Not for trivial 1-2 step work.

Tasks are for the current session. **Persistent decisions, follow-ups, and tech debt go in the repo** — either in `docs/exec-plans/tech-debt.md` or as GitHub issues.

Never describe ongoing work in prose-only form ("I'll also need to do X later"). Either do it now or log it where someone can find it later.

---

## Log follow-ups as tech debt

If you notice something adjacent that's worth fixing but out of scope: add an entry to `docs/exec-plans/tech-debt.md` with the format already established there. Include severity (P1/P2/P3), area, date, context, and a concrete fix sketch.

Do not leave follow-ups buried in PR descriptions, commit messages, or conversation logs. They rot there.

---

## Memory and persistence

This file and `canon/docs/tui-wiring.md` are the permanent behavior spec. **Do not re-derive this from scratch in future sessions.** Read it at session start if needed, then apply.

`~/.claude/projects/.../memory/` is for user-level and temporary context (current work, user preferences, references). Repo-level behavior rules live here in the repo.

---

## When to break these rules

- The user explicitly overrides one in the current session ("just do it, no PR").
- A rule is clearly wrong for the specific situation — in which case say so, explain why, and suggest updating this doc.

The goal is maximum leverage per minute of the human's attention. If following a rule is blocking that, surface it.

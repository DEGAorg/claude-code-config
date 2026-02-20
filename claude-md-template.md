# Global Development Standards

Global instructions for all projects. Project-specific CLAUDE.md files override these defaults.
Language-specific standards load automatically from `~/.claude/rules/` by file type.

- Prefer Exa AI (`mcp__exa__web_search_exa`) over `WebSearch` for all web searches
- Use skills proactively when they match the task — suggest relevant ones, don't block on them

## Philosophy

- **No speculative features** — Don't add features, flags, or configuration unless users actively need them
- **No premature abstraction** — Don't create utilities until you've written the same code three times
- **Clarity over cleverness** — Prefer explicit, readable code over dense one-liners
- **Justify new dependencies** — Each dependency is attack surface and maintenance burden
- **No phantom features** — Don't document or validate features that aren't implemented
- **Replace, don't deprecate** — When a new implementation replaces an old one, remove the old one entirely. No backward-compatible shims, dual config formats, or migration paths. Proactively flag dead code.
- **Verify at every level** — Set up automated guardrails (linters, type checkers, pre-commit hooks, tests) as the first step. Prefer structure-aware tools (ast-grep, LSPs, compilers) over text pattern matching.
- **Bias toward action** — Decide and move for anything easily reversed; state your assumption so the reasoning is visible. Ask before committing to interfaces, data models, architecture, or destructive operations on external services.
- **Finish the job** — Handle the edge cases you can see. Clean up what you touched. Flag adjacent breakage. Don't invent new scope.
- **Agent-native by default** — Design so agents can achieve any outcome users can. Prefer file-based state for transparency and portability. When adding UI capability, ask: can an agent achieve this too?

## Golden Principles

- **Shared utilities first** — Prefer shared utilities over hand-rolled helpers. Write it twice, extract on the third.
- **Parse, don't validate** — Validate data at system boundaries only. Trust internal code and framework guarantees.
- **Structured logging** — Structured logging everywhere; no ad-hoc `console.log` or `print` statements.
- **Typed interfaces** — No YOLO-style data probing. Always use typed interfaces and explicit contracts.

## Code Quality

### Hard limits

1. ≤100 lines/function, cyclomatic complexity ≤8
2. ≤5 positional params
3. 100-char line length
4. Absolute imports only — no relative (`..`) paths
5. Google-style docstrings on non-trivial public APIs

### Zero warnings policy

Fix every warning from every tool — linters, type checkers, compilers, tests. If a warning truly can't be fixed, add an inline ignore with a justification comment. Never leave warnings unaddressed.

### Comments

Code should be self-documenting. No commented-out code — delete it. If you need a comment to explain WHAT the code does, refactor instead.

### Error handling

- Fail fast with clear, actionable messages
- Never swallow exceptions silently
- Include context (what operation, what input, suggested fix)

### Reviewing code

Evaluate in order: architecture → code quality → tests → performance. Before reviewing, sync to latest remote (`git fetch origin`).

For each issue: describe concretely with file:line references, present options with tradeoffs when the fix isn't obvious, recommend one, and ask before proceeding.

### Testing

**Test behavior, not implementation.** Tests should verify what code does, not how. If a refactor breaks your tests but not your code, the tests were wrong.

**Test edges and errors, not just the happy path.** Empty inputs, boundaries, malformed data, missing files, network failures — bugs live in edges. Every error path the code handles should have a test that triggers it.

**Mock boundaries, not logic.** Only mock things that are slow (network, filesystem), non-deterministic (time, randomness), or external services you don't control.

**Verify tests catch failures.** Break the code, confirm the test fails, then fix. Use mutation testing (`cargo-mutants`, `mutmut`) and property-based testing (`proptest`, `hypothesis`) for parsers and algorithms.

## CLI Tools

| tool | replaces | usage |
|------|----------|-------|
| `rg` (ripgrep) | grep | `rg "pattern"` — fast regex search |
| `fd` | find | `fd "*.py"` — fast file finder |
| `ast-grep` | — | `ast-grep --pattern '$FUNC($$$)' --lang py` — AST-based code search |
| `shellcheck` | — | `shellcheck script.sh` — shell script linter |
| `shfmt` | — | `shfmt -i 2 -w script.sh` — shell formatter |
| `actionlint` | — | `actionlint .github/workflows/` — GitHub Actions linter |
| `zizmor` | — | `zizmor .github/workflows/` — Actions security audit |
| `prek` | pre-commit | `prek run` — fast git hooks (Rust, no Python) |
| `wt` | git worktree | `wt switch branch` — manage parallel worktrees |
| `trash` | rm | `trash file` — moves to macOS Trash (recoverable). **Never use `rm -rf`** |

Prefer `ast-grep` over ripgrep when searching for code structure (function calls, class definitions, imports). Use ripgrep for literal strings and log messages.

When adding dependencies, CI actions, or tool versions, always look up the current stable version — never assume from memory unless the user provides one.

## Workflow

**Before committing:**
1. Re-read your changes for unnecessary complexity, redundant code, and unclear naming
2. Run relevant tests — not the full suite
3. Run linters and type checker — fix everything before committing

**Commits:**
- Imperative mood, ≤72 char subject line, one logical change per commit
- Never amend/rebase commits already pushed to shared branches
- Never push directly to main — use feature branches and PRs
- Never commit secrets, API keys, or credentials — use `.env` files (gitignored) and environment variables

**Hooks and worktrees:**
- Install prek in every repo (`prek install`). Run `prek run` before committing. Configure auto-updates: `prek auto-update --cooldown-days 7`
- Parallel subagents require worktrees. Each subagent MUST work in its own worktree (`wt switch <branch>`), not the main repo. Never share working directories.

**Pull requests:**
Describe what the code does now — not discarded approaches, prior iterations, or alternatives. Only describe what's in the diff.

Use plain, factual language. A bug fix is a bug fix, not a "critical stability improvement." Avoid: critical, crucial, essential, significant, comprehensive, robust, elegant.

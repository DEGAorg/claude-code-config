# Garbage Collection Scan

@description Weekly entropy scan: find AI-generated drift, duplicated utilities, stale docs, and principle violations. Opens a PR with fixes.

Perform a structured garbage collection scan of the codebase. This command
is designed to run weekly (or before a sprint boundary) to prevent
AI-generated drift from accumulating.

Execute every step below sequentially. Do not stop or ask for confirmation
at any step unless a finding requires a judgment call.

## 1. Load quality baseline

Read `docs/QUALITY.md` to understand the current quality grades by area.
This tells you where to look harder and sets context for what "better"
means in each module.

## 2. Scan for entropy

Run the following checks. For each finding, record it with: area, severity
(P1/P2/P3), description, and suggested fix.

### 2a. Duplicated utilities

Search for hand-rolled helpers that duplicate shared utilities:

- String manipulation, date formatting, error wrapping, logging wrappers
  that appear in more than one place
- Fetch/HTTP client wrappers when a shared one exists
- Configuration loaders, environment parsers written multiple times
- Use `ast-grep` for structural patterns, `rg` for literal copies

### 2b. Inconsistent patterns

- Error handling: mixed `try/catch` styles, inconsistent error types, swallowed
  exceptions, missing context in error messages
- Logging: ad-hoc `console.log`/`print` mixed with structured logging calls
- Data validation: some paths validate at boundaries, others don't

### 2c. Dead code

- Unused imports, unexported functions never called, commented-out blocks
- Feature flags or A/B switches where one branch is always taken
- Unresolved work-in-progress comments (`todo`, `fixme`, `hack`) older than 30 days (check git blame)

### 2d. Oversized files

- Files > 400 lines: candidates for splitting
- Functions > 100 lines: violate hard limits (AGENTS.md)
- Modules with cyclomatic complexity > 8

### 2e. Docs drift

- References in `docs/` to files, functions, or commands that no longer exist
- `README` sections describing features not yet implemented (phantom features)
- `AGENTS.md` instructions that contradict current code structure

### 2f. Principle violations

Check against the Golden Principles in the global CLAUDE.md:

- Hand-rolled helpers where a shared utility exists
- Validation inside business logic (should be at boundaries)
- Unstructured logging
- Untyped data structures passed through layers

### 2g. Supply chain hygiene

- Unpinned versions (`^` or `~`) in package.json, `>=` in pyproject.toml
- Actions not pinned to SHA hashes in GitHub workflows
- Dependencies flagged by `pip-audit` or `pnpm audit`

## 3. Prioritize findings

Rank all findings:

- **P1** — violates a hard limit or creates a security/correctness risk. Fix now.
- **P2** — meaningful drift or tech debt. Fix in this PR.
- **P3** — minor inconsistency or style issue. Fix if trivial; otherwise log to `docs/exec-plans/tech-debt.md`.

## 4. Fix P1 and P2 findings

For each P1-P2 finding:

- Apply the fix
- Verify tests still pass after each change
- Do not fix P3 unless trivial (< 5 min); log them to tech-debt.md instead

## 5. Update docs/QUALITY.md

After fixing, update the quality grades for any area that improved or
regressed. Record the date and what changed.

## 6. Create PR

- Branch: `chore/cleanup-YYYY-MM-DD`
- Commit: `chore: weekly entropy scan — [summary of main findings]`
- PR title: `chore: weekly GC scan YYYY-MM-DD`
- PR body: total findings by severity, how many fixed vs deferred, updated quality grades

# Exec Plan Authoring Rules

Standards for writing execution plans that run correctly under the orch orchestrator.

---

## Progress Log — Dependency Annotations

**Always add `(deps: N)` annotations to every item in the Progress log.**

The orch treats any item with no deps as `ready` and launches it immediately in
parallel with all other dep-free items. Without annotations, every step in the plan
runs simultaneously — workers conflict on the same files and produce broken output.

### Sequential plan (most plans)

When steps must run in order, chain each item to the previous one:

```markdown
## Progress log

- [ ] Step 1
- [ ] Step 2 (deps: 1)
- [ ] Step 3 (deps: 2)
- [ ] Step 4 (deps: 3)
```

### Parallel plan (intentional parallelism)

When steps are truly independent, omit deps or use a common root:

```markdown
## Progress log

- [ ] Setup root (deps: none needed — first item always starts)
- [ ] Task A (deps: 1)
- [ ] Task B (deps: 1)
- [ ] Task C (deps: 1)
- [ ] Merge and verify (deps: 2, 3, 4)
```

### Mixed plan

```markdown
## Progress log

- [ ] Step 1
- [ ] Step 2 (deps: 1)
- [ ] Step 3a — parallel branch A (deps: 2)
- [ ] Step 3b — parallel branch B (deps: 2)
- [ ] Step 4 — join (deps: 3, 4)
```

---

## Rules

1. **Every item in the Progress log must have a `(deps: N)` annotation** unless it is
   the first item and has no dependencies.

2. **Sequential plans must form a chain** — each item depends on the one before it.
   Do not leave items without deps unless parallel execution is intentional.

3. **The `/plan` skill does not add dep annotations automatically** — you must add
   them manually after the plan is written, or ask Claude to add them before running
   the orch.

4. **All plans must be committed** before running `orch-run.sh`. The orch will refuse
   to start if the plan directory has uncommitted changes.

5. **First item never needs a dep** — it is implicitly the root. No need to write
   `(deps: none)` or `(deps: 0)`.

---

## Scope Guardrails

Hard limits enforced during plan creation. Plans that violate these limits
must be rewritten before the issue is created.

### Hard limits

| Guardrail | Limit | Why |
|-----------|-------|-----|
| Progress log items | **≤10** (4-8 recommended) | Plans with 4-8 items ship in 0-1 review iterations; larger plans need more. |
| Files per item | **≤3** | Each worker runs in isolation. Touching >3 files increases merge conflict risk and review complexity. |
| Completion criteria | **Shell-verifiable** | Every criterion must be a concrete command that returns 0 on success. No vague "tests pass" or "code is clean." |
| Dependency chain depth | **≤5** | Depth >5 means a long sequential chain — restructure for parallelism or split into phases. |
| TDD ordering | **Tests before implementation** | When a plan touches application code, test items must run before or alongside implementation items — never after. |

### Shell-verifiable completion criteria

Every completion criterion must be a shell command a reviewer can run.

```markdown
# WRONG — vague, not verifiable
- [ ] Tests pass
- [ ] Code is clean
- [ ] Feature works correctly

# CORRECT — concrete shell commands
- [ ] `vitest run tests/auth.test.ts` exits 0
- [ ] `ruff check src/` exits 0
- [ ] `grep -c 'export function createUser' src/users.ts` returns 1
```

### TDD ordering for application code

When a plan touches application code (`.ts`, `.tsx`, `.py`, `.rs`, `.go`),
test-writing items must appear as dependencies of implementation items —
not the reverse. Tests come first; implementation satisfies them.

**Shell scripts (`.sh`) are exempt.** Use `shellcheck`/`shfmt` as the
quality gate instead.

```markdown
# CORRECT — test first, then implement, then verify
- [ ] Write tests for auth middleware (`tests/auth.test.ts`)
- [ ] Implement auth middleware (`src/middleware/auth.ts`) (deps: 1)
- [ ] Verify: `vitest run tests/auth.test.ts` passes (deps: 2)

# CORRECT — test and implement in parallel (shared dependency)
- [ ] Set up project scaffolding
- [ ] Write tests for parser (`tests/parser.test.ts`) (deps: 1)
- [ ] Implement parser (`src/parser.ts`) (deps: 1)
- [ ] Verify: all parser tests pass (deps: 2, 3)
```

```markdown
# WRONG — tests depend on implementation (tests as afterthought)
- [ ] Implement auth middleware (`src/middleware/auth.ts`)
- [ ] Write tests for auth middleware (deps: 1)  ← tests after impl

# WRONG — tests tacked on at the end
- [ ] Implement feature A
- [ ] Implement feature B (deps: 1)
- [ ] Implement feature C (deps: 2)
- [ ] Write tests for A, B, and C (deps: 3)  ← all tests last
```

### Split into phases when exceeding 10 items

Plans with more than 10 progress items must be split into phases. Each
phase becomes its own GitHub issue with its own progress log.

```markdown
# WRONG — 14-item monolith plan
- [ ] Step 1
- [ ] Step 2 (deps: 1)
  ...
- [ ] Step 14 (deps: 13)

# CORRECT — split into phases, each its own issue
## Phase 1: Foundation (Issue #42)
- [ ] Set up project structure
- [ ] Add core types and interfaces (deps: 1)
- [ ] Write tests for core module (deps: 2)
- [ ] Implement core module (deps: 3)

## Phase 2: Features (Issue #43, blocked by #42)
- [ ] Add feature A tests
- [ ] Implement feature A (deps: 1)
- [ ] Add feature B tests (deps: 1)
- [ ] Implement feature B (deps: 3)
- [ ] Integration tests (deps: 2, 4)
```

Each phase should be independently shippable. Phase 2 blocks on Phase 1
via GitHub issue dependencies, not dep annotations within a single plan.

---

## Checklist before running orch-run.sh

- [ ] Every progress log item (except the first) has `(deps: N)`
- [ ] Dep numbers reference valid item IDs (1-indexed, sequential)
- [ ] Plan is committed to git
- [ ] `dega-core.yaml` has a valid `check_command` for the project's toolchain

---

## Common mistake

```markdown
# WRONG — all items are "ready" and run in parallel
- [ ] Install dependencies
- [ ] Configure TypeScript
- [ ] Set up linting
- [ ] Run dev server

# CORRECT — sequential chain
- [ ] Install dependencies
- [ ] Configure TypeScript (deps: 1)
- [ ] Set up linting (deps: 2)
- [ ] Run dev server (deps: 3)
```

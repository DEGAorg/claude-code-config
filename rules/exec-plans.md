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

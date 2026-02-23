# Create Execution Plan

@description Create a structured execution plan in docs/exec-plans/active/ before starting work.
@arguments $TASK: Brief description of the task to plan (used as filename slug)

Create a versioned execution plan for the task described in $TASK. Plans are
first-class artifacts — they persist through completion and inform future work.

Execute every step below sequentially.

## 1. Understand the scope

Before writing anything:

- If a GitHub issue number is available, read it with `gh issue view`
- Read every file that will be touched — don't plan against memory
- Identify the acceptance criteria: what does "done" look like?
- Identify risks and open questions that need a decision before work starts

## 2. Write the plan

Create a plan directory at `docs/exec-plans/active/$SLUG/` where `$SLUG`
is a short kebab-case slug derived from $TASK (e.g. `add-auth-endpoint`).
Write the plan to `docs/exec-plans/active/$SLUG/plan.md`.

The plan must include every section below:

```markdown
# Plan: [Task Title]

**Status:** In progress
**Created:** YYYY-MM-DD
**Issue:** #N (if applicable)

## Requirements

[What must be true when this is done. Use bullet points. Be concrete.]

## Approach

[How you will implement it. Architecture decisions go here, not in commit messages.]

## Files to touch

| File | Change |
|------|--------|
| `path/to/file.ts` | Add X, modify Y |

## Risks and open questions

- [Question or risk — resolve before implementing if P1]

## Progress log

- [ ] [Step 1]
- [ ] [Step 2]
- [ ] ...

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Use X | Y, Z | [Why X] |

## Completion criteria

- [ ] All requirements met
- [ ] Tests pass
- [ ] Linting clean
- [ ] PR created and reviewed
```

## 3. Resolve open questions

If there are P1 open questions (blocking decisions), resolve them before
implementing. Ask the user or investigate the codebase as needed. Record
the decision in the Decision log.

## 4. Implement

The plan file is the source of truth. Follow this discipline for every step:

1. Complete the work for one step.
2. **Immediately mark it `[x]` in the plan file** — before starting the next step.
3. Repeat until done.

This is what makes plans resumable. If the session ends mid-task, the next
session reads the plan and picks up from the first unchecked box. Skipping
the file update means the next session has no idea what was done.

When all steps are complete, move the whole plan directory from `active/$SLUG/`
to `completed/$SLUG/`. Do not delete it.

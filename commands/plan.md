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

Create a plan directory at `docs/exec-plans/active/$DATED_SLUG/` where
`$DATED_SLUG` is `YYYYMMDD-$SLUG` — today's date (8 digits) followed by a
short kebab-case slug derived from $TASK (e.g. `20260302-add-auth-endpoint`).
Write the plan to `docs/exec-plans/active/$DATED_SLUG/plan.md`.

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
```

**Rule:** Completion criteria must only contain steps the worker agent can complete
autonomously. Do not add steps that require human action (browser OAuth, manual
approvals, external credentials, PR creation via authenticated CLI, etc.) unless
the user explicitly asks for them. Post-loop human steps (opening a PR, deploying,
granting access) belong in a follow-up note, not in the completion criteria.

## 3. Resolve open questions

If there are P1 open questions (blocking decisions), resolve them before
implementing. Ask the user or investigate the codebase as needed. Record
the decision in the Decision log.

## 4. Hand off

Once the plan is written and open questions resolved, **stop**. Do not begin
implementation.

The plan file is now the source of truth for the next session. Implementation
starts by reading `docs/exec-plans/active/$DATED_SLUG/plan.md`, finding the first
unchecked `[ ]` in the Progress log, and continuing from there.

When all steps are complete, move the whole plan directory from
`active/$DATED_SLUG/` to `completed/$DATED_SLUG/`. Do not delete it.

Output the following to the user as part of the hand-off:

```
To run the ralph loop for this plan:

    bash scripts/ralph-loop.sh <dated-slug>
```

Replace `<dated-slug>` with the `YYYYMMDD-slug` derived in Step 2
(e.g. `20260302-add-auth-endpoint`).

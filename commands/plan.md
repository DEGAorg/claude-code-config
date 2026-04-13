# Create Execution Plan

@description Create a structured execution plan as a GitHub Issue for orchestrator execution.
@arguments $TASK: Brief description of the task to plan. Prefix with `--from-issue #N` to attach a plan to an existing issue.

Create a versioned execution plan for the task described in $TASK. The plan is
stored as a GitHub Issue — no local plan files are committed to git.

Execute every step below sequentially.

## 1. Parse arguments

Check if $TASK starts with `--from-issue #N` (where N is an issue number):

- **With `--from-issue #N`:** Read the existing issue with `gh issue view N --json title,body`.
  Use the issue title and body as context for generating the plan. The plan body
  will be set on this existing issue (via `gh issue edit N --body`), not a new one.
- **Without `--from-issue`:** The full $TASK string is the task description. A new
  issue will be created.

## 2. Understand the scope

Before writing anything:

- If working from an existing issue, read its body for requirements and context
- Read every file that will be touched — don't plan against memory
- Identify the acceptance criteria: what does "done" look like?
- Identify risks and open questions that need a decision before work starts

## 3. Write the plan

Generate the plan body as markdown with every section below. This content
becomes the GitHub Issue body.

```markdown
# Plan: [Task Title]

**Status:** Draft
**Created:** YYYY-MM-DD

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
- [ ] [Step 2] (deps: 1)
- [ ] [Step 3] (deps: 2)
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
the user explicitly asks for them.

**Rule:** Every Progress log item (except the first) MUST have a `(deps: N)`
annotation. The orchestrator runs all dep-free items in parallel — without
annotations, every step launches simultaneously and workers conflict on the same
files. Use `(deps: none)` for the first item or truly independent items. Chain
sequential items: `(deps: 1)`, `(deps: 2)`, etc. For parallel branches that
rejoin, use multiple deps: `(deps: 3, 4)`.

## 4. Validate scope

Before creating the issue, validate the plan against the scope guardrails
in `rules/exec-plans.md`. Run every check below. If any check fails,
rewrite the failing section in place — do not prompt the user.

### Checks

1. **Item count:** Count progress log items. If >10, split into phases —
   each phase becomes its own issue with ≤10 items. Create a parent issue
   linking the phases.
2. **Files per item:** For each progress item, count backtick-quoted file
   paths in its description. If any item references >3 files, split it
   into smaller items scoped to ≤3 files each.
3. **Shell-verifiable criteria:** Each completion criterion must contain a
   concrete shell command (backtick-quoted) that returns 0 on success.
   Rewrite vague criteria like "tests pass" into specific commands
   (e.g., `` `vitest run tests/auth.test.ts` exits 0 ``).
4. **Dependency chain depth:** Compute the longest path through the
   dependency DAG. If depth >5, restructure the progress log for more
   parallelism or split into phases.
5. **TDD ordering:** Scan the "Files to touch" table for application code
   extensions (`.ts`, `.tsx`, `.py`, `.rs`, `.go`). If found, verify the
   progress log contains test-writing items that are dependencies of (or
   run alongside) the implementation items — not after them. If tests are
   missing or misordered, rewrite the progress log to follow TDD ordering:
   write test → implement → verify. Shell-only plans (`.sh` files) are
   exempt.
6. **Single retry:** If any check triggered a rewrite, re-run all five
   checks once. If the plan still fails validation after the retry,
   stop and report the failing checks to the user — do not loop.

## 5. Resolve open questions

If there are P1 open questions (blocking decisions), resolve them before
proceeding. Ask the user or investigate the codebase as needed. Record
the decision in the Decision log section of the plan.

## 6. Create or update the GitHub Issue

Write the plan body to a temporary file, then call the appropriate script.

### New issue (no `--from-issue`)

Derive a short kebab-case slug from $TASK (e.g. `add-auth-endpoint`).
Set the title to `Plan: [Task Title]`.

```bash
plan_body_file="$(mktemp)"
# Write the generated plan markdown to $plan_body_file

issue_number="$(bash scripts/plan-create.sh \
  --title "Plan: [Task Title]" \
  --body-file "${plan_body_file}")"

rm -f "${plan_body_file}"
```

The script creates the issue with the `plan:draft` label and prints the
issue number to stdout.

### Existing issue (`--from-issue #N`)

Update the existing issue body with the plan content and add the `plan:draft` label:

```bash
plan_body_file="$(mktemp)"
# Write the generated plan markdown to $plan_body_file

gh issue edit N --body-file "${plan_body_file}"
gh issue edit N --add-label "plan:draft"

rm -f "${plan_body_file}"
```

## 7. Hand off

Once the issue is created or updated, **stop**. Do not begin implementation.

The GitHub Issue is now the source of truth. Implementation starts by running
the orchestrator, which fetches the issue body, parses the progress log, and
spawns worker agents.

Output the following to the user:

```
Plan created: <issue_url>

To run with the orchestrator:

    bash ~/.degacore/scripts/orch-run.sh --issue N
```

Replace `N` with the issue number and `<issue_url>` with the full GitHub issue URL.

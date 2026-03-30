# Fix GitHub Issue

@description End-to-end: plan, implement, test, PR, review, fix findings, and comment on a GitHub issue.
@arguments $ISSUE_NUMBER: GitHub issue number to fix

Read GitHub Issue #$ISSUE_NUMBER thoroughly. Understand the full
context: problem description, acceptance criteria, linked PRs,
and any discussion. Follow linked issues, referenced PRs, and
external documentation to build complete understanding before
planning.

Execute every step below sequentially. Do not stop or ask for
confirmation at any step.

## 1. Plan

Create a plan directory at `docs/exec-plans/active/YYYYMMDD-issue-$ISSUE_NUMBER/`
where `YYYYMMDD` is today's date (8 digits), e.g. `20260302-issue-42/`.
Write the plan to `docs/exec-plans/active/YYYYMMDD-issue-$ISSUE_NUMBER/plan.md`.
The plan must:

- Summarize the issue requirements
- List every file to create or modify
- Describe the approach and key design decisions
- Call out risks or open questions
- Reference relevant code paths by file:line

For simple single-file obvious fixes, an ephemeral plan in the root is
acceptable — use judgment. Non-trivial work always goes in `exec-plans/`.

## 2. Implement

Implement the plan across all necessary files. Follow the
project's AGENTS.md standards. Keep changes minimal and focused
on the issue requirements -- no speculative features.

## 3. Build, test, lint

Run the project's full quality pipeline in this order:

1. Build (compile/bundle if the project has a build step)
2. Run the full test suite -- iterate on failures until green
3. Add new tests for the changed behavior
4. Run linting, formatting, and type-checking -- fix any issues

Refer to the project's AGENTS.md or package.json/Makefile/etc.
for the correct commands.

## 4. Branch, commit, and push

- Determine the branch prefix from the issue type: `fix/` for
  bugs, `feat/` for features, `refactor/` for refactors, `docs/`
  for documentation. When ambiguous, use `fix/`.
- Create a branch named `{prefix}issue-$ISSUE_NUMBER`
- Move the plan directory from `docs/exec-plans/active/YYYYMMDD-issue-$ISSUE_NUMBER/`
  to `docs/exec-plans/completed/YYYYMMDD-issue-$ISSUE_NUMBER/` — do not delete it.
  Plans are permanent artifacts and inform future work.
- Commit all changes with a conventional commit message referencing
  the issue
- Push the branch

## 5. Create PR

Create a PR with:

- A concise title (under 70 chars)
- A description that maps changes back to the issue requirements
- Link to the issue with "Closes #$ISSUE_NUMBER" (or "Refs" if it
  doesn't fully close it)

## 6. Self-review

Use `/compound-engineering:workflows:review` to perform a full
multi-agent code review of the PR. Produce a list of findings
ranked by severity (P1 = blocks merge, P2 = important, P3 = nice
to have).

## 7. Fix findings and converge

Address all P1-P3 findings. For each finding, either:

- **Fix it** -- apply the change, or
- **Dismiss it** -- explain why it's a false positive or not worth
  the churn (e.g. a stylistic disagreement or an impossible edge
  case). Document the reasoning inline.

### Convergence loop (up to 3 rounds)

After addressing all findings from the previous review, run a
lightweight self-review before committing:

1. Re-read every changed file end-to-end
2. Check for regressions introduced by the fixes: broken types,
   missed edge cases, inconsistent behavior, new dead code
3. Identify any new P1-P3 issues

**If new P1-P3 issues are found:** fix them, then repeat from
step 1 of this loop.

**If clean (no new P1-P3 issues):** proceed to verification.

**Maximum 3 rounds.** If P1-P3 findings are still present after
round 3, stop immediately and surface the open issues for human
review -- do not proceed to commit.

### Verification (after loop converges)

1. Re-run the full quality pipeline (build, test, lint)
2. Commit the fixes as a separate commit (do not squash into the
   original -- preserve review history)
3. Push the branch (regular push, not force-push)
4. Delete any todo files in `todos/` that were created by the
   review and are now resolved

## 8. Comment on issue

Post a summary comment on Issue #$ISSUE_NUMBER linking to the PR.
Include:

- What was implemented (1-3 bullet points)
- Key design decisions
- Link to the PR

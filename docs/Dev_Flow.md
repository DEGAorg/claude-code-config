# Development Flow

Extracted from a team meeting transcript (16 Feb 2026).
This describes the expected end-to-end process for every feature or fix.

---

## Overview

Every unit of work flows through nine stages. Eight involve a human decision;
one fires automatically via CI. The goal is to set a quality floor so that
even the worst-case delivery clears a minimum acceptable bar.

---

## Stage 1 — Create Task

**Who:** Team lead / PM
**Where:** GitHub Issues

- Start from a user story.
- Break it into micro-tasks beneath the story.
- Each micro-task must include:
  - A clear description of what must be done.
  - Specific acceptance criteria for verifying it.
- Link related tasks to the parent story so the PR can later be tied to the issue.

---

## Stage 2 — Create Spec

**Who:** Developer (supported by Claude Code)
**Where:** GitHub Issue task body

- Before touching code, the developer generates an implementation plan with AI.
- The plan must cover:
  - Which patterns will be used (e.g., connection pools, caching, behavior trees).
  - Why those patterns are appropriate for this context.
  - Any relevant design decisions.
- The plan is stored permanently in the GitHub issue task — not as a throwaway
  artifact — so there is always a traceable record of how an implementation was
  designed.
- For complex systems, Claude Code should be in plan mode before writing a single
  line of code.

---

## Stage 3 — Review Spec

**Who:** Lead or designated reviewer (Daniel / Vlad)
**Where:** GitHub Issue comment / async review

- The spec is reviewed before implementation starts.
- The reviewer checks:
  - Correct patterns are proposed for the context.
  - Nothing critical is missing (e.g., caching where needed, connection pooling, etc.).
  - The plan aligns with the user story acceptance criteria.
- The developer may not begin Stage 4 until the spec is approved.

---

## Stage 4 — Implement Locally

**Who:** Developer
**Tools:** Claude Code, TDD

- Implementation follows the approved spec.
- Test-Driven Development (TDD) is required: write tests first, then code.
- The developer runs all services locally and verifies they start and communicate
  correctly before moving on.
- Fixing one file must not break another — the developer is responsible for
  checking integration, not just the changed file.

---

## Stage 5 — Dev Runs AI Code Review Locally

**Who:** Developer
**Tools:** Claude Code `review-pr` command (or equivalent)

- Before submitting the PR, the developer runs the AI code-review command locally.
- The developer reads the issues found and validates each one against the spec and
  business logic — not every flagged issue is necessarily valid.
- If issues are legitimate, they are fixed before the PR is opened.
- This step is human-judged: the developer decides what to act on.

---

## Stage 6 — Record Walkthrough Video

**Who:** Developer

- A short screen recording that shows the feature or fix running end-to-end.
- Purpose: proof that the developer actually tested what they built.
- For small changes a smoke test (happy path) is sufficient.
- For larger or riskier changes, demonstrate full regression coverage.
- Also capture a screenshot of the local test run so reviewers can compare with CI.
- Submitting a fake or untested recording is treated the same as not testing at all.

---

## Stage 7 — Submit PR

**Who:** Developer
**Where:** GitHub Pull Request, linked to the issue

- PR must include:
  - The code changes.
  - The walkthrough video attached.
  - Screenshot of local test run.
- The PR description should reference the GitHub issue so the full chain is
  traceable: issue → spec → implementation → PR.
- The developer is **100% responsible** for the code in the PR.
  AI assistance is an accelerator, not an excuse. No exceptions.

---

## Stage 8 — Automated AI Code Review

**Who:** Claude Code (CI trigger, no human touch)
**Trigger:** PR opened

- The AI code-review command runs automatically on every new PR.
- It posts review comments directly on the PR.
- When all AI-flagged issues are resolved, a human reviewer steps in.
- This stage acts as the quality floor: issues that reach a human reviewer should
  be substantive, not mechanical.

---

## Stage 9 — Human Review & Ownership Sign-off

**Who:** Lead / reviewer
**Where:** GitHub PR

- The reviewer verifies that the delivered code matches the approved spec from
  Stage 3 and satisfies the acceptance criteria from Stage 1.
- Checks that the video and test screenshot are present and credible.
- Confirms human interaction points and owners are documented for the feature.
- Merges or requests changes.

---

## Responsibilities Summary

| Stage | Actor | Human? |
|---|---|---|
| 1 — Create Task | Team Lead / PM | Yes |
| 2 — Create Spec | Developer + AI | Yes |
| 3 — Review Spec | Lead / Reviewer | Yes |
| 4 — Implement (TDD) | Developer + Claude Code | Yes |
| 5 — Local AI Review | Developer + Claude Code | Yes (judgment call) |
| 6 — Record Video | Developer | Yes |
| 7 — Submit PR | Developer | Yes |
| 8 — Automated AI Review | CI / Claude Code | No |
| 9 — Human Review & Sign-off | Lead / Reviewer | Yes |

---

## Quality Floor Principle

The point of this pipeline is not to hand off responsibility to AI — it is to make
the worst-case delivery acceptable. Layers stack: TDD → local AI review → personal
QA video → automated CI review → human review. By the time a bug escapes all five
layers it should be an edge case affecting a small fraction of users, not a
systematic failure.

The developer owns the code. The AI tools own nothing.

# Tech Debt: Planning Command Improvements

Captured from session 2026-03-21. Patterns discovered during plan creation
that should feed back into the `/plan` skill and orchestrator.

## 1. Research step before implementation

The `/plan` command jumps straight to "create files." For plans that extract
or synthesize from source material, a research step should come first:
read sources → extract findings → organize → then create artifacts.

**Current behavior:** Plan hardcodes file list and counts upfront.
**Better:** Plan includes a discovery step that determines the shape of work.

## 2. Avoid hard-coding artifact counts in completion criteria

Plans should not say "exactly 4 files." If the research step discovers 3 or 6
groupings, the completion criteria should accommodate that. Use `≥1` or
"all groups from research step covered" instead of exact counts.

## 3. Confirmation questions before execution

Before running a plan, the planner should ask the user 3 targeted questions
to verify they read and understood the plan. This caught two issues in this
session (hard-coded file count, missing research step).

## 4. Pattern sourcing as a plan concern

When a plan touches an unfamiliar codebase (fork, dependency, protocol), the
first step should be "study upstream patterns" — not "implement the fix."
This was discovered when modifying Toad's ACP protocol: the initial approach
invented a new mechanism instead of extending the existing one.

## 5. Multi-repo plan architecture

Decisions from this session:
- Plans live in the orchestration repo (Core), even when work touches other repos
- Labels (e.g., `repo:conductor-view`) indicate which repo the work lands in
- The orch worker's `cwd` can point to any repo
- Cross-repo data flows through GitHub API (issues), not filesystem imports
- This avoids license contamination (Apache 2.0 Core vs AGPL-3.0 Toad)

## 6. Relative paths for external doc references

When plans reference external spec repos (canon-docs), use sibling-relative
paths (`../canon-docs`) not absolute paths. Instruct users to clone the
reference repo at that location. This is portable across machines.

## 7. Canon-docs as pattern source

The growth rule pattern: when encountering an unsolved design decision,
search spec documents for methodology sections, extract the generic version,
and add it to the patterns skill. Plans should encode this as a sourcing
instruction, not assume the planner already knows all patterns.

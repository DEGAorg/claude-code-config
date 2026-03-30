<!-- Sources: SAS_AIDD_Pipeline.md (Risk Contract & Merge Policy, Preflight gate ordering, Current-Head SHA Discipline, Local PR System, Cross-Model Review Gate) -->

# Quality Gates

Patterns for automated, risk-proportional code review and merge policies.

## Risk contract

A machine-readable policy (JSON/YAML) governing which checks run before
merge, based on which files changed. High-risk paths get more gates;
low-risk paths get fast checks.

## Risk-tiered file paths

Classify files by risk tier. Core logic, schemas, and critical paths are
high tier. Everything else is low tier. High tier gets full review;
low tier gets automated checks only.

## Preflight gate ordering

Run cheap/fast checks first (policy, lint). Only trigger expensive checks
(security scan, cross-model review) after preflight passes. Fail fast,
save cost.

## Current-head SHA discipline

Review state is only valid when it matches the current commit SHA. Stale
reviews from earlier iterations are rejected. Every push invalidates
prior review state.

## Parallel review agents

Multiple specialized review agents run in parallel: linting, security,
testing, types, architecture. Results are aggregated and presented together
rather than sequentially blocking each other.

## Cross-model review

A different model reviews the coder's work. Self-testing is
self-consistency, not falsification. Cross-model review catches different
blind spots than the implementing model has.

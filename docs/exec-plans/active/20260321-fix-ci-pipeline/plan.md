# Plan: Fix CI pipeline — shellcheck severity and excluded codes

**Status:** In progress
**Created:** 2026-03-21

## Requirements

- CI shellcheck step should not fail on info-level messages (SC1091, SC2015, SC2317)
- Match the local shellcheck config: exclude SC1091 (source not followed) which is expected for sourced libraries
- Fail only on warning and error severity, not info
- Fix any real warnings or errors that are currently masked by the info-level noise
- Optionally: fix the underlying SC2015 and SC2317 issues in the scripts so CI is fully clean even at info level

## Approach

The CI workflow (`.github/workflows/ci.yml`) runs `shellcheck hooks/*.sh scripts/*.sh tests/*.sh` with no flags. This fails on info-level messages.

Fix: change to `shellcheck -e SC1091 -S warning hooks/*.sh scripts/*.sh tests/*.sh`

- `-e SC1091` excludes "source not followed" — standard for dynamic source paths
- `-S warning` sets minimum severity to warning — info messages don't fail the build

Also audit each SC2015 and SC2317 to determine if they're real issues or false positives, and fix or suppress with inline comments.

## Files to touch

| File | Change |
|------|--------|
| `.github/workflows/ci.yml` | Add `-e SC1091 -S warning` to shellcheck step |
| `scripts/canon-runner.sh` | Fix SC2015: A && B \|\| C pattern (if applicable) |
| `scripts/canon-scaffold.sh` | Fix SC2015: A && B \|\| C pattern (if applicable) |
| `scripts/ralph-loop.sh` | Fix SC2015 and SC2317 (if applicable) |

## Progress log

- [x] Update `.github/workflows/ci.yml` — add `-e SC1091 -S warning` to shellcheck step
- [x] Audit and fix SC2015 in `scripts/canon-runner.sh`, `scripts/canon-scaffold.sh`, `scripts/ralph-loop.sh` — replace `A && B || C` with proper if/then/else where it matters (deps: 1)
- [ ] Audit and fix SC2317 in `scripts/ralph-loop.sh` — unreachable command warning (deps: 1)
- [ ] Test: run shellcheck locally with the same flags as CI, verify zero exit code (deps: 1, 2, 3)

## Completion criteria

- [ ] CI shellcheck step passes (exit 0)
- [ ] No real warnings or errors suppressed — only info-level exclusions
- [ ] shellcheck and shfmt clean locally with same flags as CI

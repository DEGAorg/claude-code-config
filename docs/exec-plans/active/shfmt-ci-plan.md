# Plan: Add shfmt Formatting Check to CI

**Status:** In progress
**Created:** 2026-02-20

## Requirements

- All shell scripts in `hooks/`, `scripts/`, and `tests/` pass `shfmt -d` (no diff = correctly formatted)
- CI enforces this on every push and PR — formatting drift is caught automatically
- shfmt version is pinned so local and CI results are identical
- `lint-hooks` CI job runs both shellcheck and shfmt in a single job

## Approach

Three-phase: audit → fix → wire CI.

1. Install shfmt locally (`brew install shfmt`), run `shfmt -d` across all scripts to
   identify formatting drift.
2. Apply `shfmt -i 2 -w` to fix any issues in-place.
3. Add a shfmt install step and format-check step to `.github/workflows/ci.yml`
   alongside the existing shellcheck step. Pin to v3.12.0 via binary download so
   the version is explicit and reproducible.

shfmt is added to `lint-hooks` (not a new job) — it's the same concern as shellcheck.

## Files to touch

| File | Change |
|------|--------|
| `.github/workflows/ci.yml` | Add shfmt install + `shfmt -d` check step |
| `hooks/enforce-package-manager.sh` | Fix formatting if `shfmt -d` reports drift |
| `hooks/log-gam.sh` | Fix formatting if `shfmt -d` reports drift |
| `scripts/ralph-check.sh` | Fix formatting if `shfmt -d` reports drift |
| `scripts/statusline.sh` | Fix formatting if `shfmt -d` reports drift |
| `tests/test-enforce-package-manager.sh` | Fix formatting if `shfmt -d` reports drift |

## Risks and open questions

- **shfmt not installed locally** (non-blocking): devs need to install it before
  committing bash changes. Document in README or CLAUDE.md. `brew install shfmt` on macOS.
- **shfmt version drift** (mitigated): pinning to v3.12.0 in CI via binary download.
  Local `brew install shfmt` may drift over time — acceptable for now.

## Progress log

- [x] Install shfmt locally — v3.12.0 installed, matches pinned CI version
- [ ] Run `shfmt -d hooks/*.sh scripts/*.sh tests/*.sh` — note any drift
- [ ] Fix formatting issues with `shfmt -i 2 -w hooks/*.sh scripts/*.sh tests/*.sh`
- [ ] Add shfmt install + check step to `.github/workflows/ci.yml`
- [ ] Run `bash scripts/ralph-check.sh` — all criteria pass
- [ ] Commit and push

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Pin shfmt v3.12.0 via binary download | `apt-get install shfmt` (unpinned), `go install` (requires Go) | Pinned version ensures local/CI parity; binary download has no extra runtime deps |
| Add shfmt to `lint-hooks` job (not new job) | Separate `format-check` job | Same concern category as shellcheck; keeps CI config lean |

## Completion criteria

- [ ] `shfmt -d hooks/*.sh scripts/*.sh tests/*.sh` exits 0 locally
- [ ] CI `lint-hooks` job passes with shfmt step included
- [ ] `bash scripts/ralph-check.sh` exits 0 (7/7)
- [ ] Changes committed and pushed

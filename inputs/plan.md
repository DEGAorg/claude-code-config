# Plan: Update CHANGELOG Unreleased section with latest Kalshi commits

## Requirements

The `CHANGELOG.md` `[Unreleased]` section documents only the Kalshi PoC
(`20260515-kalshi-poc`) but is missing two commits that landed on `develop`
afterward:

- `66c0b822` — fix(kalshi): map TIF to snake_case + use dollar-string prices (2026-05-15)
- `92b103d5` — docs(kalshi): add adapter integration guide for partner share (2026-05-22)

Bring the `[Unreleased]` section up to date so it reflects all merged Kalshi work.

## Approach

Add two concise entries to the `[Unreleased]` section, following the existing
Keep a Changelog format and the `— YYYY-MM-DD` date-suffix style already used
in the file. Place the order-mapping fix under a `### Fixed` subsection and the
integration-guide doc under a `### Docs` subsection (create the subsections if
absent). Documentation-only change — touch `CHANGELOG.md` only.

## Progress log

- [x] Add the two missing Kalshi entries to the `CHANGELOG.md` `[Unreleased]` section

## Completion criteria

- [ ] `rg -qi 'tif|snake_case|dollar' CHANGELOG.md` exits 0
- [ ] `rg -qi 'integration guide|adapter.*guide|KALSHI\.md' CHANGELOG.md` exits 0
- [ ] `git diff --name-only HEAD | grep -qx CHANGELOG.md` (only the changelog changed)

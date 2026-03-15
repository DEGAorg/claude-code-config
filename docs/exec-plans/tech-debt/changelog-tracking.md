# Feature changelog tracking

**Discovered:** 2026-03-15
**Severity:** Low

## Problem

No changelog exists for the project. Features, fixes, and improvements are only
discoverable by reading git log or exec-plan directories. There's no user-facing
summary of what changed and when.

## Proposed fix

Add a `CHANGELOG.md` at repo root following Keep a Changelog format:

```markdown
# Changelog

## [Unreleased]

### Added
- ...

### Fixed
- ...

### Changed
- ...
```

Update it as part of every shipped plan — either manually or via a hook that
appends an entry when a plan moves from `active/` to `completed/`.

Consider: auto-generate changelog entries from exec-plan titles and completion
dates. The data is already there in `docs/exec-plans/completed/*/plan.md`.

## Files involved

| File | Role |
|------|------|
| `CHANGELOG.md` | New — feature changelog |
| `scripts/orch-engine.sh` | Could append entry on SHIP |
| `scripts/ralph-loop.sh` | Could append entry on SHIP |

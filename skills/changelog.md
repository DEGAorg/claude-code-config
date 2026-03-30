# Changelog

How the project changelog works and how to update it. Use this skill when
completing a plan, releasing a version, or checking what changed on a date.

---

## File

`CHANGELOG.md` at repo root. Follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Structure

```markdown
## [Unreleased]
### Added
### Changed
### Fixed

## YYYY-MM-DD
### Added / Changed / Fixed / Removed
- Entry text (`plan-slug`)
```

Each entry is one line: a short description of what changed, with the plan
slug in parentheses for traceability. Entries are grouped by category
(Added, Changed, Fixed, Removed) within each date section.

**[Unreleased]** holds entries that haven't been cut into a dated release yet.
When a dated section is created (manually or by the orchestrator on SHIP),
entries move from Unreleased to the new section.

---

## Automatic updates

The orchestrator (`orch-engine.sh`) calls `orch_changelog_append()` on
SHIP. This function:

1. Extracts the plan title from `# Plan: <title>` in `plan.md`
2. Appends a `- <title> (\`slug\`)` line under `### Changed` in the
   `[Unreleased]` section
3. The engine then commits the change

No manual changelog entry is needed for orchestrator-driven work.

---

## Manual updates

For work done outside the orchestrator (manual commits, hotfixes), add an
entry to the appropriate category under `[Unreleased]`:

```markdown
### Fixed
- Fix auth token refresh on 401 responses (`20260315-auth-fix`)
```

Use imperative mood. Include the plan slug or PR number for traceability.

---

## Querying the changelog

To find what changed on a specific date or in a date range, read
`CHANGELOG.md` and look for the date header. Each dated section lists
every plan that shipped that day.

To find when a specific feature shipped, search for the plan slug:
```
rg "plan-slug" CHANGELOG.md
```

---

## Categories

| Category | Use when |
|----------|----------|
| Added | New feature or capability that didn't exist before |
| Changed | Enhancement to existing feature, refactor, update |
| Fixed | Bug fix |
| Removed | Deleted feature, removed dead code |

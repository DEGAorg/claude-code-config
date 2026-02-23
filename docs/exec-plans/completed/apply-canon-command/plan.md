# Plan: Build /apply-canon Command

**Status:** In progress
**Created:** 2026-02-23

## Requirements

- `/apply-canon` is a slash command that installs Canon layer artifacts globally to `~/.claude/`
- Mirrors the structure and style of `/apply-core` (fetches from GitHub, inventories existing
  files, multi-select what to install, writes to `~/.claude/`)
- Requires Core to be installed first; checks for a Core marker before proceeding
- Installs the one artifact that currently exists: `canon/rules/domain-layering.md`
- Structured so future Canon artifacts (skills, hooks, agents, commands) can be added by listing
  new paths — no structural changes to the command needed
- Self-installs as `~/.claude/commands/apply-canon.md` so it is available from any directory
- Post-install summary tells the user what was installed and what to do next (`canon_init`)

## Approach

Write `commands/apply-canon.md` as a prose slash command (same format as `apply-core.md`).

**Core pre-check:** Test for `~/.claude/commands/fix-issue.md` as the Core marker. If absent,
abort with a clear message: "Run `/apply-core` first."

**Source URL base:**
```
https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/canon/
```

**Artifact categories and files (at time of writing):**

| Category | Source path | Install target |
|----------|-------------|----------------|
| Rules | `canon/rules/domain-layering.md` | `~/.claude/rules/domain-layering.md` |

The command is forward-compatible: each new Canon artifact simply adds a row to each category's
file list. No structural refactor needed.

**Install strategy:** Safe to overwrite for all Canon artifacts (rules, skills, hooks,
commands). Unlike Core's `CLAUDE.md`, Canon injects domain knowledge — no user customization
expected.

**Self-install:** After user selections, fetch and write
`canon/commands/apply-canon.md` → `~/.claude/commands/apply-canon.md` unconditionally.

## Files to touch

| File | Change |
|------|--------|
| `commands/apply-canon.md` | Create — the slash command |
| `canon/CLAUDE.md` | Update Active Work section: mark `/apply-canon` as built |

## Risks and open questions

- **Q1 (resolved):** Does `/apply-canon` bundle Core installation or require it as a
  prerequisite? → **Prerequisite.** `canon/CLAUDE.md` documents sequential order:
  `/apply-core` then `/apply-canon`. The command checks and aborts if Core is missing.
- **Q2 (resolved):** Where do Canon artifacts install? → `~/.claude/` (same global location
  as Core). Commands → `~/.claude/commands/`, rules → `~/.claude/rules/`, etc.
- **Q3 (resolved):** Does the `canon/CLAUDE.md` project context file get installed globally?
  → No. It is a project-local context file for canon/ subdirectory work, not a user-level
  global artifact. It has no install target.
- **Q4 (open, non-blocking):** Canon has no skills, hooks, agent files, or Canon-specific
  commands yet. The apply-canon command should list these categories with empty file lists
  and note they are "coming soon." This is honest and keeps the structure ready for future
  artifacts without advertising phantom features.

## Progress log

- [x] Write `commands/apply-canon.md`
- [x] Update `canon/CLAUDE.md` — mark Active Work item 4 complete

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Require Core pre-installed | Bundle Core install in apply-canon | Sequential model matches `canon/CLAUDE.md` docs; simpler; avoids duplication |
| Install to `~/.claude/` | Install to project `.agents/` | Global install = available everywhere; `apply-core` sets this precedent |
| Overwrite Canon artifacts without prompt | Ask on every overwrite | Canon artifacts have no user customization; Core pattern already skips prompt for commands/rules |
| Domain-layering rule is only current artifact | Scaffold stub dirs with .gitkeep | Command should install real artifacts only; stub dirs are separate scaffolding work |

## Completion criteria

- [ ] `commands/apply-canon.md` created and follows apply-core.md style
- [ ] Pre-check for Core presence documented in the command
- [ ] At least one artifact installs (domain-layering rule)
- [ ] Self-install step included
- [ ] Post-install next steps mention `canon_init`
- [ ] `canon/CLAUDE.md` updated to reflect command exists

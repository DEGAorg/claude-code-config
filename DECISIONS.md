# Architecture Decisions

Settled decisions for Core + Canon config layer. Updated as decisions are made.

---

## Layer separation

- **Harness** → Core (repo root). Generic AI development infrastructure.
- **Ralph Loop hook mechanism** (`ralph-stop-hook.sh`, `ralph.yaml` template) → Core. Generic enough for any project.
- **Ralph Loop implementation** (`ralph-loop.ts`, `canon_ralph` MCP tool) → Canon application repo (separate repo, not this one).
- **`canon/` in this repo** → Canon's Claude Code config only (skills, hooks, commands, rules). Not Canon application code.
- **Canon application code** → lives in a separate Canon app repo. Developed using the config installed from this repo.

## Install model

- `/apply-core` and `/apply-canon` install additive artifacts only: `commands/`, `rules/`, `skills/`, `hooks/`.
- `~/.claude/CLAUDE.md` is **personal space** — never auto-overwritten. Template install is optional and prompted.
- If `~/.claude/CLAUDE.md` already exists: skip it, remind user that `claude-md-template.md` is available as a project-level starter.
- `settings.json` is mergeable — show diff, ask: merge / overwrite / skip.
- `/apply-canon` requires Core to be installed first.
- `canon/CLAUDE.md` is a **project-level starter**, not a global install. Offered when scaffolding a Canon project.

## Build order

1. Build Core artifacts (rules/, skills/, commands/, hooks/) — harness implementation
2. Build Canon config artifacts (canon/rules/, canon/skills/, canon/commands/, canon/hooks/)
3. Write `/apply-core` and `/apply-canon` last — they enumerate what exists and copy it

## Planning repo

- Team planning repo (docs, specs, decisions) stays separate.
- Do not import wholesale. Pull specific docs only when a decision point requires them.

## Naming (from Feb 18 meeting)

- Branding: "dega core" / "dega canon" (or just "core" / "canon" in commands)
- Commands prefix: `/dega` (replacing "slash trailer bits")
- Apply canon must require core and say "run core first" if core is not installed

---

*Last updated: 2026-02-19*

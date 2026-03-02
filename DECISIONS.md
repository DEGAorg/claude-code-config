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

- `/dega:apply-core` and `/dega:canon-init` install additive artifacts only: `commands/`, `rules/`, `skills/`, `hooks/`.
- `/dega:apply-core` supports two install targets: **global** (`~/.claude/`) or **project** (`<project>/.claude/`). The user always picks the target first, and provides an explicit project path when choosing project-level. Self-install always goes to `~/.claude/` (global) so the command stays available everywhere.
- `~/.claude/CLAUDE.md` is **personal space** — never auto-overwritten. Template install is optional and prompted. For project-level installs, CLAUDE.md goes to `<project>/CLAUDE.md` (project root).
- `settings.json` is mergeable — show diff, ask: merge / overwrite / skip. For project-level installs, hook paths inside settings.json are rewritten to project-relative (e.g., `.claude/hooks/` instead of `~/.claude/hooks/`).
- `/dega:canon-init` requires Core to be installed first.
- `canon/CLAUDE.md` is a **project-level starter**, not a global install. Offered when scaffolding a Canon project.

## Build order

1. Build Core artifacts (rules/, skills/, commands/, hooks/) — harness implementation
2. Build Canon config artifacts (canon/rules/, canon/skills/, canon/commands/, canon/hooks/)
3. Write `/dega:apply-core` and `/dega:canon-init` last — they enumerate what exists and copy it

## Planning repo

- Team planning repo (docs, specs, decisions) stays separate.
- Do not import wholesale. Pull specific docs only when a decision point requires them.

## Naming (from Feb 18 meeting)

- Branding: "dega core" / "dega canon" (or just "core" / "canon" in commands)
- Commands prefix: `/dega` (replacing "slash trailer bits")
- Apply canon must require core and say "run core first" if core is not installed

---

*Last updated: 2026-03-02*

# Plan: Provider-Agnostic Agent Configuration

**Status:** Draft
**Created:** 2026-03-27

## Requirements

- All core configuration, project maps, and personas live in `AGENTS.md` at the project root — single source of truth
- Lightweight provider-specific shim files (`CLAUDE.md`, `GEMINI.md`, `.cursorrules`) instruct agents to read `AGENTS.md`
- `claude-md-template.md` renamed to `agent-template.md` to remove provider branding from the harness core
- All scripts (`/apply-core`, `/core-init`), commands, and documentation reference `AGENTS.md` instead of `CLAUDE.md` at the project level
- **Global config (`~/.claude/CLAUDE.md`) remains provider-specific** — other providers have their own global config paths and won't discover files in `~/.claude/`
- System works out-of-the-box on `git clone` for Claude Code, Gemini, Cursor/Codex — no manual configuration
- Canon subdirectory follows the same pattern: `canon/AGENTS.md` (truth) + `canon/CLAUDE.md` (shim)

## Approach

**Project-level pattern:**
- `AGENTS.md` — full configuration (repo map, conventions, active work, etc.)
- `CLAUDE.md` — 3-line shim: "Read and follow all instructions in AGENTS.md"
- `GEMINI.md` — same shim content
- `.cursorrules` — same shim content

**Global level (`~/.claude/`) — unchanged:**
- `~/.claude/CLAUDE.md` stays as the full global standards file (provider-specific)
- No `~/.claude/AGENTS.md` — other providers don't discover files in `~/.claude/`
- `agent-template.md` in the repo is still installed as `~/.claude/CLAUDE.md` (the template content is provider-agnostic, the install target is provider-specific)

**Migration scope:**
- 43 files reference `CLAUDE.md` or `claude-md-template` — most are completed exec plans (historical, leave as-is). Active artifacts that need updating: commands, scripts, README, INSTALL, DECISIONS, canon layer, and the templates themselves.

## Files to touch

| File | Change |
|------|--------|
| `CLAUDE.md` | Replace 310-line config with 3-line shim pointing to AGENTS.md |
| `AGENTS.md` (new) | Move full content from old CLAUDE.md here |
| `GEMINI.md` (new) | Shim pointing to AGENTS.md |
| `.cursorrules` (new) | Shim pointing to AGENTS.md |
| `claude-md-template.md` → `agent-template.md` | Rename; content stays provider-agnostic (global standards) |
| `docs/core-init-claude-template.md` → `docs/core-init-agent-template.md` | Rename; update references inside |
| `commands/apply-core.md` | Update `claude-md-template.md` → `agent-template.md`; install target remains `~/.claude/CLAUDE.md` |
| `commands/core-init.md` | Update Step 6 to write `AGENTS.md` + shims instead of just `CLAUDE.md` |
| `canon/CLAUDE.md` | Replace with shim pointing to `canon/AGENTS.md` |
| `canon/AGENTS.md` (new) | Move full content from old `canon/CLAUDE.md` here |
| `scripts/canon-scaffold.sh` | Update to generate shims alongside `AGENTS.md` |
| `README.md` | Update "Global CLAUDE.md" section name, "Project-level CLAUDE.md" → "Project-level AGENTS.md", file structure tables |
| `INSTALL.md` | Update references |
| `DECISIONS.md` | Update references |
| `docs/Self_Development.md` | Update references |
| `docs/QUALITY.md` | Update references |
| `docs/core-init-claude-template.md` | Update internal references |
| `skills/custom-linter-authoring.md` | Update project-level CLAUDE.md references to AGENTS.md |
| `commands/cleanup.md` | Update project-level CLAUDE.md references to AGENTS.md |
| `commands/doc-garden.md` | Update project-level CLAUDE.md references to AGENTS.md |
| `commands/fix-issue.md` | Update project-level CLAUDE.md references to AGENTS.md |
| `commands/review-pr.md` | Update project-level CLAUDE.md references to AGENTS.md |
| `commands/canon-init.md` | Update project-level CLAUDE.md references to AGENTS.md |

## Risks and open questions

- **Claude Code auto-discovery**: Claude Code only auto-loads `CLAUDE.md` — the shim approach preserves this. Verify that Claude Code follows "read AGENTS.md" instructions reliably. (P2 — test after implementation)
- **Gemini auto-discovery**: Confirm `GEMINI.md` is the correct filename for Google's Gemini CLI/agent. (P2 — verify current convention)
- **Cursor auto-discovery**: Confirm `.cursorrules` is still the convention vs `.cursor/rules` or other patterns. (P2 — verify current convention)
- ~~**Global AGENTS.md path**~~ **Resolved**: Global config remains provider-specific. `~/.claude/CLAUDE.md` stays as the full global standards file. The repo template is renamed to `agent-template.md` but installs to `~/.claude/CLAUDE.md`.

## Progress log

- [x] Create `AGENTS.md` at repo root with full content from current `CLAUDE.md`; replace `CLAUDE.md` with shim; create `GEMINI.md` and `.cursorrules` shims
- [ ] Migrate `canon/CLAUDE.md` → `canon/AGENTS.md` + shim (deps: 1)
- [ ] Rename `claude-md-template.md` → `agent-template.md`; rename `docs/core-init-claude-template.md` → `docs/core-init-agent-template.md`; update internal references in both (deps: 1)
- [ ] Update `commands/apply-core.md` — change `claude-md-template.md` refs to `agent-template.md`; install target remains `~/.claude/CLAUDE.md` (global config is provider-specific) (deps: 3)
- [ ] Update `commands/core-init.md` — Step 6 writes `AGENTS.md` + shims (`CLAUDE.md`, `GEMINI.md`, `.cursorrules`) instead of just `CLAUDE.md` (deps: 3)
- [ ] Update `scripts/canon-scaffold.sh` — generate `CLAUDE.md`, `GEMINI.md`, `.cursorrules` shims alongside the existing `AGENTS.md` write (deps: 2)
- [ ] Update `README.md` and `INSTALL.md` — update project-level references to AGENTS.md; keep global `~/.claude/CLAUDE.md` references accurate (deps: 1)
- [ ] Update remaining commands (`cleanup.md`, `doc-garden.md`, `fix-issue.md`, `review-pr.md`, `canon-init.md`) — replace project-level CLAUDE.md references with AGENTS.md (deps: 1)
- [ ] Update remaining docs and skills (`DECISIONS.md`, `docs/Self_Development.md`, `docs/QUALITY.md`, `skills/custom-linter-authoring.md`) — replace project-level CLAUDE.md references with AGENTS.md (deps: 1)
- [ ] Verify: grep entire repo for stale `claude-md-template` references; verify project-level `CLAUDE.md` refs are shim-aware; run `shellcheck` on modified scripts (deps: 4, 5, 6, 7, 8, 9)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Shim pattern (CLAUDE.md points to AGENTS.md) | Symlinks, includes, single AGENTS.md with no CLAUDE.md | Claude Code requires CLAUDE.md to exist for auto-discovery; shims are the simplest approach that preserves native behavior |
| **Global config stays provider-specific** (`~/.claude/CLAUDE.md` is the full file, not a shim) | Global AGENTS.md + shim | Other providers don't discover files in `~/.claude/`; there's no shared global config dir. The template source is agnostic (`agent-template.md`) but the install target is provider-specific. |
| Leave completed exec plans unchanged | Update all 43 files | Historical plans describe what existed at the time; updating them adds churn with no value |
| Rename template files (not just content) | Keep old names, change content only | "Replace, don't deprecate" — old names with new content creates confusion |

## Completion criteria

- [ ] `AGENTS.md` exists at repo root with full project configuration
- [ ] `CLAUDE.md` at repo root is a shim (under 10 lines) pointing to `AGENTS.md`
- [ ] `GEMINI.md` and `.cursorrules` exist as shims at repo root
- [ ] `claude-md-template.md` no longer exists; `agent-template.md` exists in its place
- [ ] `commands/apply-core.md` references `agent-template.md` and installs to `~/.claude/CLAUDE.md` (not AGENTS.md)
- [ ] `commands/core-init.md` generates project-level `AGENTS.md` + all three shims
- [ ] Global `~/.claude/CLAUDE.md` remains the full standards file (no shim at global level)
- [ ] `grep -r "claude-md-template" .` returns zero hits (excluding completed exec plans and git history)
- [ ] `shellcheck` passes on all modified `.sh` files

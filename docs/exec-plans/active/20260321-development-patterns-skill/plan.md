# Plan: Development Patterns Skill System

**Status:** In progress
**Created:** 2026-03-21

## Requirements

- `skills/development-patterns.md` — core skill, ≤100 lines, with pattern index, sourcing methodology, and growth rule
- `skills/patterns/*.md` — extension files, each ≤80 lines, grouped by topic. Number determined by research step.
- Every pattern traces to a canon-docs source (file + section in a comment header per extension)
- Zero domain content: no prediction markets, Polymarket, strategies, Arena, or Canon-specific terms
- `CLAUDE.md` skills table updated with `development-patterns` entry
- `claude-md-template.md` references the skill for third-party users

## Approach

First, read the four canon-docs specs and extract a flat list of generic development methodology patterns. Then group them by topic — each group becomes an extension file. Finally, build the core skill as an index over the extensions.

Source specs (read-only, at `../canon-docs/specs/` relative to this repo):
- `SAS_Agent_Framework.md` — agent-as-code, progressive disclosure, composable skills, standards injection, context routing
- `SAS_AIDD_Pipeline.md` — risk contracts, SHA discipline, preflight gates, convergence loops, cross-model review
- `SAS_Automation_Model.md` — `.agents/` conventions, SKILL.md manifest, interoperability, deferred decisions
- `Canon_MVP_Technical_Roadmap.md` — open core boundary, dogfooding, spec-grounded implementation

Each pattern is stripped of Canon/prediction-market terminology and generalized for any AI-driven project. The core skill is a lean index; extensions hold full pattern descriptions.

## Files to touch

| File | Change |
|------|--------|
| `skills/development-patterns.md` | Create — core skill with index, sourcing rules, growth rule |
| `skills/patterns/*.md` | Create — extension files grouped by topic (count determined by step 1) |
| `CLAUDE.md` | Update skills table entry (line ~63) and tree diagram (line ~122) |
| `claude-md-template.md` | Add patterns reference in Philosophy or Skills section |

## Risks and open questions

- Canon-docs must be cloned at `../canon-docs` relative to this repo (already documented in CLAUDE.md).

## Progress log

- [x] Read all 4 canon-docs specs, extract a flat list of generic patterns, and write `skills/patterns/_research.md` — a temporary working doc with every pattern found, its source, and a proposed topic group
- [x] Review the research list, decide topic groups, create one extension file per group under `skills/patterns/` (deps: 1)
- [x] Create `skills/development-patterns.md` — core skill indexing all extensions (deps: 2)
- [x] Update `CLAUDE.md` — add `development-patterns` to skills table and tree diagram (deps: 3)
- [x] Update `claude-md-template.md` — add patterns reference for third-party users (deps: 3)
- [x] Delete `skills/patterns/_research.md` working doc (deps: 2)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Skill + extensions vs monolithic skill | Single large skill, CLAUDE.md section, rules/ file | Skills are composable and load on demand; extensions prevent context bloat while keeping deep patterns accessible |
| Topic-based extension files | Per-source-doc files, single catch-all extension | Topic-based organization matches how patterns are used (working on a fork? load upstream-integration) |
| Research step first | Hardcode 4 extension files upfront | Let the source material determine the groupings; avoids forcing patterns into predetermined buckets |
| Canon-docs as source, not target | Copy canon-docs patterns verbatim, reference canon-docs at runtime | Extracting and generalizing avoids domain leakage and removes runtime dependency on canon-docs path |
| Relative path `../canon-docs` for all references | Absolute paths, no path at all | Relative path is portable across machines while remaining machine-readable |
| Source citations use relative paths | Human-readable names only, absolute paths | Agents can `Read` the cited file to go deeper; relative paths work for any developer who clones canon-docs to the expected location |
| Template points to installed skill path | Inline key patterns in template | Users need `/apply-core` full install; pointing to `~/.claude/skills/development-patterns.md` keeps template lean and skill as single source of truth |

## Completion criteria

- [ ] `skills/development-patterns.md` exists and is ≤100 lines
- [ ] `skills/patterns/` contains extension files (≥1), each ≤80 lines
- [ ] Every extension file has a comment header citing its canon-docs source(s)
- [ ] Zero domain content — grep for "prediction market", "Polymarket", "Canon Arena", "strategy" returns no matches in any created file
- [ ] `CLAUDE.md` skills table includes `development-patterns`
- [ ] `claude-md-template.md` references the patterns skill
- [ ] `skills/patterns/_research.md` does not exist (cleaned up)

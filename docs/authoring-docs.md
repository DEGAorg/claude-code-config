# Authoring Docs

How to add, rename, or remove documentation in this repo. Keep the docs dir
small and legible — every file here is loaded by agents and read by humans
scanning for reference.

---

## Scope rule

`docs/` contains documentation about **this repo's internals only**:
harness, orchestrator, install flow, agent patterns, architecture decisions.

Anything outside that scope belongs elsewhere:

| Content | Belongs in |
|---------|------------|
| Canon product/strategy/roadmap | [`canon-docs`](../../canon-docs) repo |
| Execution plans, phases, hackathon prep | GitHub Issues (source of truth) |
| Session notes, temporary instructions, research spikes | `docs/.discard/` (gitignored) or personal notes |
| User-facing install/update instructions | [`INSTALL.md`](../INSTALL.md) at repo root |

If a doc's primary audience is not "someone working on DEGA Core", it does not
belong here.

---

## Naming convention

**Use `kebab-case.md`** for all new docs in this repo.

```
✅ agent-agnostic-architecture.md
✅ canon-tui-integration.md
✅ timeline-api-guide.md

❌ Agent_Agnostic_Architecture.md   (PascalCase_Underscored — canon-docs style)
❌ CanonTuiIntegration.md           (PascalCase)
❌ canon tui integration.md         (spaces)
```

All docs in this repo have been normalized to `kebab-case`. If you spot a
file that drifts from the convention, rename it with `git mv` and update
references in the same commit — see [Renaming a doc](#renaming-a-doc) below.

### Exception: ADRs

Architecture Decision Records in `decisions/` use a date prefix:

```
decisions/YYYYMMDD-topic-slug.md
```

Example: `decisions/20260320-tui-framework-selection.md`.

### Cross-repo note

The sibling [`canon-docs`](../../canon-docs) repo uses
`PascalCase_With_Underscores` (e.g. `Canon_MVP_Technical_Roadmap.md`).
That is **their** convention for product/strategy docs. Do not copy it here.

---

## Categories

Keep `docs/` **flat**. No subdirectories except `decisions/` (ADRs). Pick a
category by the file's role in the [`README.md`](README.md) index:

| Category | Doc answers… | Example |
|----------|--------------|---------|
| **Architecture** | "How is this built? Why these parts?" | `agent-agnostic-architecture.md` |
| **Guide** | "How do I do X with this?" | `canon-quickstart.md` |
| **Reference** | "What exactly does Y mean / do?" | `agent-operating-mode.md` |
| **Decision (ADR)** | "Why did we choose A over B?" | `decisions/20260320-tui-framework-selection.md` |

If a doc doesn't fit any category, it probably belongs in GitHub Issues, a
commit message, or `.discard/`.

---

## Frontmatter

Optional but recommended for longer docs:

```markdown
---
title: Short human title
status: current | draft | superseded
updated: 2026-04-23
---
```

Mark superseded docs with a **Status** banner at the top (see
[`ralph-loop-reference.md`](ralph-loop-reference.md) for the pattern). Do not
silently let docs rot — either update them or move them to `.discard/`.

---

## Adding a doc — checklist

1. **Confirm scope.** Does it describe this repo's internals? If not, pick
   another home (see the table above).
2. **Pick a category** — architecture, guide, reference, or ADR.
3. **Name it** `kebab-case.md` (or `YYYYMMDD-slug.md` if it's an ADR).
4. **Write lean.** Target < 300 lines. Link out rather than duplicate.
5. **Add it to [`README.md`](README.md)** in the matching category table.
6. **Link from the natural caller** — e.g. if it documents a script, link
   from the script's header comment or the root `README.md` section that
   introduces the script.

---

## Removing a doc

Two paths:

- **Stale but might resurface** → move to `docs/.discard/` (gitignored).
  Git history preserves the file; the working tree stays clean.
- **Stale and dead** → `git rm` it. History is still there.

When you remove a doc, `rg -F '<filename>'` across the repo to find dangling
references and clean those up in the same commit.

---

## Renaming a doc

Rename with `git mv` so history follows the file. Then update every reference:

```bash
git mv docs/Old_Name.md docs/new-name.md
rg -l -F "Old_Name.md" | xargs sed -i '' 's|Old_Name.md|new-name.md|g'
```

Always grep first — docs are linked from `README.md`, `AGENTS.md`, skills,
and commands.

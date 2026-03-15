# Plan Registry

How to discover and query execution plans without scanning directories.
Use this skill when checking if a plan exists, finding plans by date or
method, or understanding the history of what's been built.

---

## File

`docs/exec-plans/REGISTRY.md` is the single index of all completed plans.
Read it to get a full list without iterating `docs/exec-plans/completed/`.

## Format

```markdown
| Date | Slug | Status | Iterations | Method |
|------|------|--------|------------|--------|
| 2026-03-15 | [slug](completed/slug/plan.md) | completed | 1 | orch |
```

Each row is one plan. Fields:

| Field | Description |
|-------|-------------|
| Date | When the plan was completed (YYYY-MM-DD) |
| Slug | Plan directory name, linked to `completed/<slug>/plan.md` |
| Status | Always `completed` (only completed plans are registered) |
| Iterations | How many worker/reviewer cycles before SHIP (0 = first pass, `-` = manual) |
| Method | `orch` (orchestrator), `ralph` (Ralph Loop), or `manual` |

---

## Automatic updates

The orchestrator and Ralph Loop both call `orch_registry_append()` on SHIP.
This function appends a row to the registry table and commits it. No manual
entry is needed for automated work.

## Manual updates

For plans completed outside the orchestrator, append a row manually:

```markdown
| 2026-03-15 | [slug](completed/slug/plan.md) | completed | - | manual |
```

---

## Querying

**All plans:** read `docs/exec-plans/REGISTRY.md`

**Plans by date:**
```bash
rg "^\\| 2026-03-15" docs/exec-plans/REGISTRY.md
```

**Plans by method:**
```bash
rg "\\| orch \\|$" docs/exec-plans/REGISTRY.md
```

**Plan count:**
```bash
tail -n +3 docs/exec-plans/REGISTRY.md | wc -l
```

**Active plans (not in registry):** check `docs/exec-plans/active/` — these
are in-progress and haven't been registered yet.

---

## Plan lifecycle

```
active/<slug>/plan.md     (in progress)
    ↓ SHIP
completed/<slug>/plan.md  (archived)
    + REGISTRY.md row     (indexed)
    + CHANGELOG.md entry  (logged)
```

The registry only tracks completed plans. To find active work, read
`docs/exec-plans/active/` or check `.orchestrator/plans/*/state.json`
for running orchestrator state.

---

## Directory structure

```
docs/exec-plans/
├── REGISTRY.md           ← This index (read first)
├── active/               ← In-progress plans
│   └── <slug>/plan.md
├── completed/            ← Archived plans (65+)
│   └── <slug>/plan.md
├── tech-debt.md          ← Known debt index
└── tech-debt/            ← Detailed debt write-ups
```

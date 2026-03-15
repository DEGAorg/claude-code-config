# Tech Debt Tracking

How to discover, log, and resolve technical debt items. Use this skill when
triaging cleanup findings, logging new debt during development, or checking
what debt exists before starting work in an area.

---

## Index file

`docs/exec-plans/tech-debt.md` is the single index of all known debt. Every
item lives in this file with severity, area, date, and context. Read it first
to understand what's known before scanning for new issues.

## Per-item files

`docs/exec-plans/tech-debt/` contains detailed write-ups for debt items that
need more than a paragraph. Each file describes the problem, proposed fix,
and current workarounds. Not every item in the index has a per-item file —
only items complex enough to warrant one.

**Staleness check:** per-item files go stale when the underlying issue gets
fixed. Before acting on a tech-debt file, verify the problem still exists in
code. If it's been fixed, delete the file and remove the index entry.

---

## Logging new debt

When you discover debt that's out of scope for the current task, add it to
`docs/exec-plans/tech-debt.md` using this format:

```markdown
## [short description]

**Severity:** P1 / P2 / P3
**Area:** [module or subsystem]
**Logged:** YYYY-MM-DD
**Context:** [what task or PR surfaced this]

[Description of the debt and why it was deferred]
```

Severity scale:
- **P1** — violates a hard limit or creates a security/correctness risk
- **P2** — meaningful drift or tech debt worth fixing soon
- **P3** — minor inconsistency; fix if trivial, otherwise defer

If the item needs a detailed write-up (multiple code paths, design options),
create a file in `docs/exec-plans/tech-debt/<slug>.md` and reference it from
the index.

---

## Resolving debt

When fixing a debt item:

1. Fix the code
2. Remove the entry from `docs/exec-plans/tech-debt.md`
3. Delete the per-item file from `docs/exec-plans/tech-debt/` if one exists
4. Mention the resolution in the commit message

---

## Discovery during /cleanup

The `/cleanup` command scans for new debt and logs findings here. Existing
items should be checked for staleness during each scan — if the underlying
code has changed, update or remove the entry.

## Current items

Read `docs/exec-plans/tech-debt.md` for the full list. As of last scan:

| Area | Active items |
|------|-------------|
| `docs/exec-plans/tech-debt/` | Per-item files for complex debt |
| `docs/exec-plans/tech-debt.md` | Master index with all items |

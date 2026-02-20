# Codebase Quality Grades

Quality assessment by area. Updated during `/cleanup` runs and after
significant refactors. Agents read this to understand where to focus
scrutiny during reviews and where to be cautious when making changes.

**Grade scale:** A (excellent) → B (good) → C (acceptable) → D (needs work) → F (broken)

---

## How to grade an area

| Grade | Meaning |
|-------|---------|
| A | Consistent patterns, full test coverage, clean linting, no known debt |
| B | Minor inconsistencies, good coverage, occasional lint warnings addressed |
| C | Noticeable drift, partial coverage, some principles violated |
| D | Significant debt, sparse tests, multiple principle violations |
| F | Broken contracts, no tests, active bugs, do not touch without a plan |

---

## Template (copy per area)

```markdown
### [Area Name]

**Grade:** [A–F]
**Last reviewed:** YYYY-MM-DD
**Reviewer:** [human or `/cleanup` run]

**Strengths:**
- ...

**Known issues:**
- ...

**Trend:** Improving / Stable / Degrading
```

---

## Areas

<!-- Add graded areas below. One section per logical module or layer. -->

### (No areas graded yet)

Run `/cleanup` to perform the first scan, then populate grades here.

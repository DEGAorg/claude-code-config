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

### Core Scripts (`scripts/`)

**Grade:** C
**Last reviewed:** 2026-03-06
**Reviewer:** `/cleanup` run

**Strengths:**
- All scripts pass shellcheck
- Python log-server.py is well-typed with structured logging
- Consistent use of `${HOME}` paths (no hardcoded absolutes)
- Good separation of concerns across scripts

**Known issues:**
- 3 scripts missing `set -euo pipefail`: statusline.sh, canon-runner.sh, canon-scaffold.sh
- ralph-loop.sh uses hardcoded `/tmp/` paths instead of `mktemp` (race condition risk)
- statusline.sh lacks error handling for `cd` and git command failures

**Trend:** Stable

---

### Hooks (`hooks/`)

**Grade:** B
**Last reviewed:** 2026-03-06
**Reviewer:** `/cleanup` run

**Strengths:**
- All 9 hooks have `set -euo pipefail`
- Clean lifecycle convention compliance (PreToolUse, PostToolUse, Stop)
- No dead code or commented-out code
- play-sound.sh has excellent cross-platform support

**Known issues:**
- ~~update-exec-plan-reminder.sh uses `.tool_result.exit_code`~~ **Fixed** → `.tool_response.exit_code`
- ~~log-gam.sh (example) has same schema mismatch~~ **Fixed**
- Several hooks have 644 permissions instead of 755

**Trend:** Stable

---

### Commands (`commands/`)

**Grade:** A
**Last reviewed:** 2026-03-06
**Reviewer:** `/cleanup` run

**Strengths:**
- Consistent structure across all 7 commands
- All file references verified and valid
- canon-init.sh → canon-scaffold.sh rename fully propagated
- Convergence loop well-documented in fix-issue and review-pr

**Known issues:**
- canon-init.md hardcodes `ace-work` branch in GitHub URL
- fix-issue.md and review-pr.md assume external `/compound-engineering` skill

**Trend:** Stable

---

### Canon Layer (`canon/`)

**Grade:** C
**Last reviewed:** 2026-03-06
**Reviewer:** `/cleanup` run

**Strengths:**
- Well-structured agent personas with consistent YAML frontmatter and handoff protocols
- 8 skills with consistent metadata and dependency chains
- Domain layering rules clearly enforced
- nba-momentum template is complete and functional

**Known issues:**
- Package manager inconsistency: quick-dev.md, register.md, arena-tracking.md use `npm`/`npx` instead of `pnpm exec`
- ~~canon-start.md references nonexistent template~~ **Fixed** — replaced with generic path note
- CLAUDE.md claims apply-canon.md is done but the command file does not exist
- Only 1 of 6 strategy patterns has a bootstrap template

**Trend:** Improving

---

### Documentation (`docs/`)

**Grade:** B
**Last reviewed:** 2026-03-06
**Reviewer:** `/cleanup` run

**Strengths:**
- Dev_Flow.md and AI_Dev_Pipeline.md are well-structured
- Exec-plans structure is clean with proper active/completed separation
- All new plans use YYYYMMDD date prefix convention
- Skills directory has 3 complete, well-documented skill files

**Known issues:**
- ~~Dev_Flow.md references nonexistent `meet.md`~~ **Fixed** — removed dangling ref
- README.md still has Trail of Bits branding from upstream fork
- 26 of 33 completed exec-plans lack date prefixes (accepted debt)

**Trend:** Improving

---

### Terminal UI (`scripts/terminal-ui-write.sh`, `scripts/statusline.sh`)

**Grade:** C
**Last reviewed:** 2026-03-06
**Reviewer:** `/cleanup` run

**Strengths:**
- terminal-ui-write.sh is well-structured with proper temp file handling
- statusline.sh has fallback logic for missing data

**Known issues:**
- statusline.sh missing `set -euo pipefail`
- No validation that `$current_dir` is a valid path before `cd`
- Silent degradation on git command failures

**Trend:** Stable

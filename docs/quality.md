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
**Last reviewed:** 2026-03-15
**Reviewer:** `/cleanup` run

**Strengths:**
- All scripts pass shellcheck
- Python log-server.py is well-typed with structured logging
- Consistent use of `${HOME}` paths (no hardcoded absolutes)
- Good separation of concerns across scripts
- Orchestrator suite (7 scripts) is the primary workhorse, well-structured

**Known issues:**
- `orch-state.sh` is 822 lines (2x the 400-line limit) — needs splitting
- 5 scripts use `#!/bin/bash` instead of `#!/usr/bin/env bash`
- `orch-engine.sh` calls `play-sound.sh` with wrong interface (positional arg vs env var)
- Duplicate 20-line SHIP block in `ralph-loop.sh`
- `statusline.sh` lacks error handling for `cd` and git command failures

**Trend:** Stable (orchestrator growing in complexity)

---

### Hooks (`hooks/`)

**Grade:** B
**Last reviewed:** 2026-03-15
**Reviewer:** `/cleanup` run

**Strengths:**
- All 10 hooks have `set -euo pipefail`
- Clean lifecycle convention compliance (PreToolUse, PostToolUse, Stop)
- play-sound.sh has excellent cross-platform support

**Known issues:**
- `orch-done-sync.sh` had broken `orch_update_item_status` call (missing slug) — **Fixed**
- ~~`test-echo.sh` diagnostic debris~~ **Removed**
- Several hooks have 644 permissions instead of 755

**Trend:** Improving

---

### Commands (`commands/`)

**Grade:** A
**Last reviewed:** 2026-03-15
**Reviewer:** `/cleanup` run

**Strengths:**
- Consistent structure across all 8 commands
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
**Last reviewed:** 2026-03-15
**Reviewer:** `/cleanup` run

**Strengths:**
- Well-structured agent personas with consistent YAML frontmatter and handoff protocols
- 8 skills with consistent metadata and dependency chains
- Domain layering rules clearly enforced
- nba-momentum template is complete and functional

**Known issues:**
- Package manager inconsistency: quick-dev.md, register.md, arena-tracking.md use `npm`/`npx` instead of `pnpm exec`
- ~~AGENTS.md claims apply-canon.md is done but the command file does not exist~~ **Fixed** — removed `/apply-canon` references
- `canon/hooks/` and `canon/docs/` are empty directories (marked as future use)
- Only 1 of 6 strategy patterns has a bootstrap template
- 12 TODO stub tests in `canon/templates/nba-momentum` assert nothing

**Trend:** Stable

---

### Documentation (`docs/`)

**Grade:** B
**Last reviewed:** 2026-03-15
**Reviewer:** `/cleanup` + `/doc-garden` run

**Strengths:**
- dev-flow.md and ai-dev-pipeline.md are well-structured
- Exec-plans structure is clean with proper active/completed separation
- All new plans use YYYYMMDD date prefix convention
- AGENTS.md repo map now includes orchestrator scripts and agents/

**Known issues:**
- README.md still has Trail of Bits branding from upstream fork
- 26 of 33 completed exec-plans lack date prefixes (accepted debt)

**Trend:** Improving (doc-garden scan cleaned 17 stale references)

---

### Orchestrator (`scripts/orch-*.sh`)

**Grade:** C+
**Last reviewed:** 2026-03-15
**Reviewer:** `/cleanup` run

**Strengths:**
- Complete end-to-end pipeline: parse → spawn → poll → review → SHIP/merge
- Per-plan state isolation with worktrees
- 8-step SHIP path with validation and changelog/registry updates
- Dashboard with live tmux capture-pane output

**Known issues:**
- `orch-state.sh` is 822 lines — needs splitting into logical modules
- `orch-engine.sh` is 568 lines
- Test suites (`test-orch-e2e.sh`, `test-orch-stale-detection.sh`) broken against multi-plan API
- Dashboard viewport loses output after SHIP (worker windows killed, no log-file fallback)

**Trend:** Rapidly growing — needs structural refactoring to stay maintainable

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

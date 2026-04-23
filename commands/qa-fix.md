# QA Fix — Report-to-Plan Bridge

@description Run QA, convert findings into a prioritized execution plan, and launch the orchestrator so dev agents fix each issue.
@arguments $ARGUMENTS: optional — path to an existing MASTER.md to skip re-running QA (e.g. "qa-reports/20260423-120000/MASTER.md")

Execute every step below in order. Do not stop or ask for confirmation.

---

## 1. Get QA Findings

### If `$ARGUMENTS` is a path to an existing MASTER.md

Read that file directly. Skip to step 2.

### Otherwise — check for a recent report

```bash
REPO_ROOT="$(pwd)"
LATEST_TIMESTAMP=$(cat "$REPO_ROOT/qa-reports/.latest" 2>/dev/null)
```

If `$LATEST_TIMESTAMP` exists and the report directory
`$REPO_ROOT/qa-reports/$LATEST_TIMESTAMP/MASTER.md` was written within the
last 30 minutes (check `mtime` with `stat`), use it.

If no recent report exists, run `/qa-review` first, then continue.

Set `MASTER_PATH="$REPO_ROOT/qa-reports/$LATEST_TIMESTAMP/MASTER.md"`.

---

## 2. Parse Findings

Read `MASTER_PATH` in full.

Extract every finding section — these are markdown headings matching
`### [CRITICAL]`, `### [HIGH]`, `### [MEDIUM]`, `### [LOW]`.

Skip `### [INFO]` entirely — no action required.

For each finding, collect:

| Field | Source in MASTER.md |
|-------|---------------------|
| `priority` | tag in heading: CRITICAL / HIGH / MEDIUM / LOW |
| `title` | heading text after the tag |
| `location` | **Location:** line |
| `description` | **Description:** line(s) |
| `evidence` | **Evidence:** line(s) |
| `fix` | **Fix:** line(s) |
| `agent` | **Agent:** line (which QA agent found it) |

Group findings by priority. Count them:

```
CRITICAL: N
HIGH:     N
MEDIUM:   N
LOW:      N
```

If CRITICAL = 0 and HIGH = 0 and MEDIUM = 0:
- Print: "QA report is clean — no actionable findings. No plan needed."
- Stop.

---

## 3. Create Execution Plan

```bash
PLAN_DATE=$(date +%Y%m%d)
PLAN_SLUG="${PLAN_DATE}-qa-fix"
PLAN_DIR="$REPO_ROOT/docs/exec-plans/active/$PLAN_SLUG"
mkdir -p "$PLAN_DIR"
PLAN_FILE="$PLAN_DIR/plan.md"
```

Write `$PLAN_FILE` using this exact structure:

```markdown
# QA Fix — <YYYYMMDD>

**Source report:** `qa-reports/<TIMESTAMP>/MASTER.md`
**Generated:** <ISO datetime>
**Findings:** <N> CRITICAL · <N> HIGH · <N> MEDIUM · <N> LOW

---

## Requirements

Resolve every finding from the QA report above. Fix in priority order:
CRITICAL first, then HIGH, then MEDIUM, then LOW. Each fix must address
the root cause — not just silence the symptom.

Do not add new features or refactor code unrelated to the finding.
Stay within the scope of each item.

## Approach

Each item maps to one QA finding. The item description includes the
finding location, evidence, and suggested fix — use them as your primary
context. If the fix requires understanding more of the codebase, read the
surrounding code before changing anything.

After all items pass review, the verifier re-runs the QA check command
for each severity tier to confirm the findings are gone.

## Progress log

```

Then for each finding, ordered CRITICAL → HIGH → MEDIUM → LOW, append:

```markdown
- [ ] [<PRIORITY>] Fix <title>
  - **Location:** `<location>`
  - **Agent:** <agent that found it>
  - **Evidence:** <evidence — exact command output or log line>
  - **Fix:** <concrete fix from QA report — include code example if present>
```

After all items, append:

```markdown

## Completion criteria

- [ ] No CRITICAL findings in re-run: `grep -c "\[CRITICAL\]" qa-reports/.latest-qa-fix/MASTER.md` returns 0
- [ ] No HIGH findings in re-run: `grep -c "\[HIGH\]" qa-reports/.latest-qa-fix/MASTER.md` returns 0
- [ ] Full test suite passes: run the project check command from dega-core.yaml
- [ ] No linting errors introduced by fixes

## Check command

Run this after each item to validate changes don't break existing behavior:
<extract `check_command` from `$REPO_ROOT/dega-core.yaml` if it exists,
 otherwise use the project's test/lint commands from package.json or Makefile>
```

---

## 4. Write Re-verification Trigger

After the orchestrator finishes all items, the completion criteria include
re-running QA. To support this, write a small helper file:

```bash
cat > "$PLAN_DIR/recheck.sh" << 'EOF'
#!/usr/bin/env bash
# Re-run QA scoped to files changed by this fix plan.
# Called by the verifier as part of completion criteria.
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
CHANGED=$(git diff HEAD --name-only 2>/dev/null | head -50)
if [[ -z "$CHANGED" ]]; then
  echo "No changed files detected — run /qa-review manually"
  exit 0
fi
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_DIR="$REPO_ROOT/qa-reports/$TIMESTAMP"
mkdir -p "$REPORT_DIR"
echo "$TIMESTAMP" > "$REPO_ROOT/qa-reports/.latest-qa-fix"
echo "Re-check scope: $CHANGED" > "$REPORT_DIR/RUN_INFO.txt"
echo "Run /qa-review changed to verify fixes"
EOF
chmod +x "$PLAN_DIR/recheck.sh"
```

---

## 5. Print Summary

```
QA FIX PLAN CREATED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Plan:     docs/exec-plans/active/<PLAN_SLUG>/plan.md
Source:   qa-reports/<TIMESTAMP>/MASTER.md

Items:    N CRITICAL · N HIGH · N MEDIUM · N LOW
Workers:  orchestrator will spawn one orch-worker per item (parallel where safe)

To launch:
  bash ~/.degacore/scripts/orch-run.sh <PLAN_SLUG>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Ask the user: **"Launch the orchestrator now? (y/n)"**

If yes:
```bash
bash ~/.degacore/scripts/orch-run.sh "$PLAN_SLUG"
```

If no: print the launch command and stop.

---

## Rules

- **CRITICAL and HIGH are always included** — never skip them regardless of count
- **MEDIUM is included by default** — skip only if the user explicitly passes `scope=critical-high`
- **LOW is included** — workers are cheap; include everything actionable
- **INFO is never included** — non-actionable findings don't belong in a fix plan
- **One item per finding** — do not merge findings even if in the same file;
  workers need clear, atomic scope
- **Evidence is required per item** — a worker without evidence cannot reproduce
  the issue; copy it verbatim from the QA report
- **Non-destructive** — this command only reads reports and writes plan files;
  it never edits source code directly
- **Fresh report preferred** — if the last report is > 30 min old, re-run QA
  to avoid fixing stale findings

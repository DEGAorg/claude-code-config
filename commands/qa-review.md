# QA Review — Full QA AI Team

@description Run the full QA AI Team on the current project. Spawns the QA Leader, which orchestrates all specialist agents and produces a master report with priority flags.
@arguments $ARGUMENTS: optional scope modifier — "changed" (only changed files), "api" (API only), "security" (security only), "full" (default)

You are about to run a full QA review. Execute every step below in order.

## 1. Bootstrap

Set up the run context — the QA Leader receives these; do not duplicate work here.

```bash
REPO_ROOT="$(pwd)"
SCOPE="${ARGUMENTS:-full}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_DIR="$REPO_ROOT/qa-reports/$TIMESTAMP"
DEGA_CORE_HOME="${DEGA_CORE_HOME:-$HOME/.degacore}"

mkdir -p "$REPORT_DIR"
echo "$TIMESTAMP" > "$REPO_ROOT/qa-reports/.latest"
echo "QA Review started: $(date)" > "$REPORT_DIR/RUN_INFO.txt"
echo "Scope: $SCOPE" >> "$REPORT_DIR/RUN_INFO.txt"

# Detect running services (thin scan — leader does the deep scan)
BASE_URL=""
for port in 3000 3001 4000 5000 8000 8080; do
  code=$(curl -s --connect-timeout 1 --max-time 2 -o /dev/null \
    -w "%{http_code}" http://localhost:$port 2>/dev/null)
  if [[ "$code" =~ ^[2345] ]]; then
    BASE_URL="http://localhost:$port"
    break
  fi
done

# Detect changed files (for scope=changed)
CHANGED_FILES=""
if [[ "$SCOPE" == "changed" ]]; then
  CHANGED_FILES=$(git diff HEAD~1 --name-only 2>/dev/null || \
    git show --name-only --format="" HEAD 2>/dev/null | head -30)
fi
```

## 2. Scope — Agent Selection Rules

**If `$SCOPE` is `full` or unspecified:** the QA Leader selects all agents matching
the detected stack (see its selection matrix).

**If `$SCOPE` is `changed`:** pass `$CHANGED_FILES` to the leader. Agent relevance:

| Changed file pattern | Relevant agents |
|---------------------|----------------|
| `*.test.*`, `*.spec.*`, `test_*.py` | `qa-automation` |
| routes, handlers, controllers, `api/` | `qa-api`, `qa-security` |
| `*.tsx`, `*.jsx`, `*.vue`, `*.svelte` | `qa-ui`, `qa-a11y` |
| `Dockerfile`, `docker-compose.*`, `.github/` | `qa-infra` |
| `migrations/`, `schema.*`, `models.*` | `qa-data` |
| any backend file | `qa-security` (always) |

**If `$SCOPE` is `api`:** leader spawns only `qa-api` and `qa-security`.

**If `$SCOPE` is `security`:** leader spawns only `qa-security` and `qa-infra`.

## 3. Spawn the QA Leader

Locate the qa-leader agent file:
```bash
QA_AGENTS_DIR="$DEGA_CORE_HOME/config/agents"
# Fallback to project-local if global not found
[[ ! -f "$QA_AGENTS_DIR/qa-leader.md" ]] && QA_AGENTS_DIR="$REPO_ROOT/agents"
```

Read the full content of `$QA_AGENTS_DIR/qa-leader.md` and spawn it as a subagent,
passing this context in the prompt:

```
REPO_ROOT=<value>
REPORT_DIR=<value>   ← use the TIMESTAMP from step 1 — do NOT re-generate
SCOPE=<value>
BASE_URL=<value or empty>
CHANGED_FILES=<value or empty>
QA_AGENTS_DIR=<value>
```

The QA Leader handles all context detection, agent selection, specialist
spawning, and report aggregation. Do not duplicate any of that work here.

## 4. Present Results

Once the QA Leader completes:

1. **Print the overall result** (PASS / FAIL / WARN) prominently
2. **Print all CRITICAL findings inline** — never bury these
3. **Print HIGH findings count** with a brief summary
4. **Print the master report path**: `$REPORT_DIR/MASTER.md`
5. **Print top 3 improvement proposals**

```
QA RESULT: FAIL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[CRITICAL] SQL injection in search endpoint
  Location: src/api/search.ts:42
  Fix: Use parameterized query — replace template literal with `db.query('SELECT...', [input])`

[HIGH] JWT decoded without verification
  Location: src/auth/middleware.py:18
  Fix: Replace `jwt.decode(token)` with `jwt.decode(token, SECRET, algorithms=['HS256'])`

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Findings: 1 CRITICAL · 3 HIGH · 7 MEDIUM · 4 LOW
Report:   qa-reports/20260422-143022/MASTER.md

Next: run /qa-fix to convert findings into a dev execution plan
```

## 5. Archive Tracking

```bash
echo "$(date +%Y-%m-%d) $TIMESTAMP $SCOPE" >> "$REPO_ROOT/qa-reports/RUN_LOG.txt"
```

## Rules

- **Thin bootstrap only** — do not gather context, select agents, or run QA logic; that is the leader's job
- **Pass REPORT_DIR, not TIMESTAMP** — the leader must use the directory already created
- **CRITICAL findings are inline** — the user sees them without opening any file
- **Non-destructive** — no production writes, no deploys, no pushes, ever
- **Report path is always shown** — the user can always find the full report

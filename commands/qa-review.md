# QA Review — Full QA AI Team

@description Run the full QA AI Team on the current project. Spawns the QA Leader, which orchestrates all specialist agents and produces a master report with priority flags.
@arguments $SCOPE: optional scope modifier — "changed" (only changed files), "api" (API only), "security" (security only), "full" (default)

You are about to run a full QA review. Execute every step below in order.

## 1. Gather Project Context

Before spawning any agent, collect context:

```bash
# Detect tech stack
ls package.json pyproject.toml Cargo.toml go.mod pom.xml 2>/dev/null
cat package.json 2>/dev/null | head -30 || cat pyproject.toml 2>/dev/null | head -30

# Running services
for port in 3000 3001 4000 5000 8000 8080; do
  curl -s -o /dev/null -w "port $port: %{http_code}\n" http://localhost:$port 2>/dev/null
done
docker ps --format "table {{.Names}}\t{{.Ports}}" 2>/dev/null

# Infrastructure present
ls .github/workflows/ Dockerfile docker-compose.yml k8s/ 2>/dev/null

# Recent changes (if scope=changed)
git diff HEAD~1 --name-only 2>/dev/null | head -20
git status --short 2>/dev/null | head -20
```

## 2. Create Report Directory

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p qa-reports/$TIMESTAMP
echo "$TIMESTAMP" > qa-reports/.latest
echo "QA Review started: $(date)" > qa-reports/$TIMESTAMP/RUN_INFO.txt
echo "Scope: ${SCOPE:-full}" >> qa-reports/$TIMESTAMP/RUN_INFO.txt
```

## 3. Select Agents Based on Scope and Context

**If `$SCOPE` is `full` or unspecified:** spawn all agents that match the
detected stack (see `agents/qa-leader.md` for the selection matrix).

**If `$SCOPE` is `changed`:** spawn only agents relevant to the changed files.

**If `$SCOPE` is `api`:** spawn only `qa-api` and `qa-security`.

**If `$SCOPE` is `security`:** spawn only `qa-security` and `qa-infra`.

Available specialist agents:

| Agent | File | Triggers |
|-------|------|---------|
| QA Automation | `agents/qa-automation.md` | Tests exist or testable code |
| QA API | `agents/qa-api.md` | API endpoints detected |
| QA UI | `agents/qa-ui.md` | Frontend/browser UI |
| QA Manual | `agents/qa-manual.md` | Running service detected |
| QA Infrastructure | `agents/qa-infra.md` | CI/CD, Docker, K8s present |
| QA Security | `agents/qa-security.md` | Always |
| QA Performance | `agents/qa-performance.md` | API or DB present |
| QA Accessibility | `agents/qa-a11y.md` | Frontend UI present |
| QA Data | `agents/qa-data.md` | DB schema/migrations present |

## 4. Spawn the QA Leader

Locate the qa-leader agent file:
```bash
DEGA_CORE_HOME="${DEGA_CORE_HOME:-$HOME/.degacore}"
QA_AGENTS_DIR="$DEGA_CORE_HOME/config/agents"
# Fallback to project-local if global not found
[[ ! -f "$QA_AGENTS_DIR/qa-leader.md" ]] && QA_AGENTS_DIR="agents"
```

Spawn the agent at `$QA_AGENTS_DIR/qa-leader.md` with:
- The repo root path (current working directory)
- The report directory: `qa-reports/$TIMESTAMP`
- The detected stack summary
- The selected agents list (based on scope)
- The base URL (from env or detected port)

The QA Leader will orchestrate all specialist agents and write the master report.

## 5. Present Results

Once the QA Leader completes:

1. **Print the overall result** (PASS / FAIL / WARN) prominently
2. **Print all CRITICAL findings inline** — never bury these
3. **Print HIGH findings count** with a brief summary
4. **Print the master report path**: `qa-reports/$TIMESTAMP/MASTER.md`
5. **Print top 3 improvement proposals**

Format findings like this:

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
```

## 6. Archive Tracking

```bash
# Keep an index of all QA runs
echo "$(date +%Y-%m-%d) $TIMESTAMP ${SCOPE:-full}" >> qa-reports/RUN_LOG.txt
```

## Rules

- **Never skip context detection** — wrong stack = wrong agents = useless report
- **Always write MASTER.md** — even on clean runs, a PASS report is evidence
- **CRITICAL findings are inline** — the user sees them without opening any file
- **Non-destructive** — no production writes, no deploys, no pushes, ever
- **Report path is always shown** — the user can always find the full report

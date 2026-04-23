# QA Standards — Shared Reporting Protocol

Common standards, report format, and priority taxonomy used by every agent
in the QA AI Team. All QA agents must follow this protocol exactly.

---

## Priority Taxonomy

Every finding must carry exactly one priority flag:

| Flag | Label | Definition | SLA |
|------|-------|-----------|-----|
**Overall result determination:**
- `FAIL` — one or more CRITICAL findings present
- `WARN` — one or more HIGH findings, no CRITICAL
- `PASS` — no findings above MEDIUM

| `[CRITICAL]` | Blocker | Data loss, security breach, production down, auth bypass | Fix before next deploy |
| `[HIGH]` | Must Fix | Core feature broken, significant regression, OWASP vulnerability | Fix this sprint |
| `[MEDIUM]` | Should Fix | Degraded UX, missing validation, non-critical regression | Fix next sprint |
| `[LOW]` | Nice to Fix | Minor UX issue, code smell, suboptimal behavior | Backlog |
| `[INFO]` | Observation | Best-practice note, improvement idea, non-actionable signal | Track only |

Never inflate or deflate priority. A missed null-check is not CRITICAL unless
it causes data loss. A production outage is never LOW.

---

## Report Format

Every QA agent writes its report to:
```
<repo-root>/qa-reports/<YYYYMMDD-HHMMSS>/<agent-name>.md
```

The QA Leader writes the master report to:
```
<repo-root>/qa-reports/<YYYYMMDD-HHMMSS>/MASTER.md
```

### Individual Agent Report Template

```markdown
# QA Report — <Agent Name>

**Run:** YYYY-MM-DD HH:MM:SS
**Project:** <project name from package.json / pyproject.toml / Cargo.toml>
**Tech Stack:** <detected stack>
**Coverage:** <what was tested — be specific>
**Result:** PASS | FAIL | WARN

---

## Summary

<2-4 sentences: what was tested, overall health, headline finding.>

## Findings

### [CRITICAL] <Finding title>
- **Location:** `file:line` or `endpoint` or `component`
- **Description:** What is wrong and why it matters.
- **Evidence:** command output, log snippet, or test result.
- **Fix:** Concrete action to resolve. Code example if applicable.

### [HIGH] <Finding title>
...

### [MEDIUM] ...
### [LOW] ...
### [INFO] ...

## Coverage Map

| Area | Tested | Status |
|------|--------|--------|
| <area> | Yes/No/Partial | Pass/Fail/Skip |

## Improvement Proposals

Ordered by impact:

1. **<Proposal title>** `[HIGH impact]` — description and rationale.
2. ...

## Metrics

<Agent-specific metrics: coverage %, response times, pass/fail counts, etc.>
```

---

## Master Report Template (QA Leader)

```markdown
# QA Master Report

**Run:** YYYY-MM-DD HH:MM:SS
**Project:** <name>
**QA Team Agents:** <list of agents that ran>
**Overall Result:** PASS | FAIL | WARN

---

## Executive Summary

<3-5 sentences: overall quality posture, blocker count, top risks.>

## Priority Matrix

| Priority | Count | Top Finding |
|----------|-------|-------------|
| CRITICAL | N | <title> |
| HIGH | N | <title> |
| MEDIUM | N | <title> |
| LOW | N | <title> |
| INFO | N | — |

## Critical & High Findings (Action Required)

<Consolidated list — do not duplicate, merge identical findings across agents.>

### [CRITICAL] <title>
- **Agent:** qa-security / qa-api / ...
- **Location:** `file:line`
- **Fix:** ...

### [HIGH] ...

## Agent Reports

| Agent | Result | Findings (C/H/M/L) | Report |
|-------|--------|-------------------|--------|
| qa-automation | PASS | 0/1/3/2 | `qa-automation.md` |
| qa-api | FAIL | 1/2/1/0 | `qa-api.md` |
| ... | | | |

## Top 5 Improvement Proposals

<Cross-agent, ranked by impact.>

## Next Steps

- [ ] Fix all CRITICAL findings before next deploy
- [ ] Address HIGH findings this sprint
- [ ] Schedule MEDIUM findings for next sprint
```

---

## Context Gathering Protocol

Every QA agent must detect the project context before testing.
All commands run from `$REPO_ROOT` — cd there first.

```bash
cd "$REPO_ROOT"

# 1. Detect tech stack
ls package.json pyproject.toml Cargo.toml go.mod pom.xml 2>/dev/null

# 2. Read the project manifest
cat "$REPO_ROOT/package.json" 2>/dev/null || \
  cat "$REPO_ROOT/pyproject.toml" 2>/dev/null || \
  cat "$REPO_ROOT/Cargo.toml" 2>/dev/null

# 3. Read project instructions
{ cat "$REPO_ROOT/AGENTS.md" 2>/dev/null || cat "$REPO_ROOT/README.md" 2>/dev/null; } | head -80

# 4. Detect running services
cat docker-compose.yml 2>/dev/null || cat docker-compose.yaml 2>/dev/null
ls .env .env.local .env.development 2>/dev/null

# 5. Check CI configuration
ls .github/workflows/ 2>/dev/null
```

Adapt every test strategy, tool selection, and finding to what actually exists.
Never test for technologies that are not in the stack.
Never skip this step — a context-blind QA agent is a liability.

---

## Rules for All QA Agents

1. **Evidence-first** — every finding must include a command, log line, or test
   result as evidence. Never flag without proof.
2. **Actionable** — every finding must have a concrete fix suggestion.
3. **Calibrated** — use the priority taxonomy strictly. When in doubt, go lower.
4. **Stack-aware** — adapt to the actual project. No boilerplate findings.
5. **Reproducible** — include the exact command to reproduce each finding.
6. **Non-destructive** — never modify production data, never deploy, never push.
7. **Report always** — write the report even on clean runs. A PASS with no
   findings is a valid report.

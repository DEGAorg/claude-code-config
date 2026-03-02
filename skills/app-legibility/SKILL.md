---
name: app-legibility
description: >
  Reference: how to make running applications observable to agents. Load when
  scaffolding a new service, adding observability, or diagnosing why an agent
  cannot inspect a running application. Covers log file redirection,
  per-worktree port and database isolation, health endpoints, and crash surfacing.
user-invocable: false
---

# App Legibility for Agents

How to make a running application observable to agents. Use this skill when
scaffolding a new service or debugging why an agent can't inspect a running app.

The goal: agents must be able to read application state, check health, and diagnose
failures using only the tools available to them (Read, Bash, WebFetch) — without
humans relaying information.

---

## Pattern 1 — Log File Redirection

**Problem:** Application stdout/stderr is invisible to agents. Agents cannot attach
to a terminal process or tail a live stream.

**Solution:** Redirect all output to a file at a known path. Agents use `Read` or
`Bash tail` to inspect it at any time.

```bash
# scripts/start-dev.sh
set -euo pipefail

LOG_DIR="logs"
mkdir -p "$LOG_DIR"

# Redirect both streams; tee to terminal for human debugging
exec > >(tee -a "$LOG_DIR/server.log") 2>&1

node dist/server.js
```

```bash
# Or for background processes — redirect without tee
node dist/server.js >> logs/server.log 2>&1 &
echo $! > logs/server.pid
```

**Agent usage:**

```
Read logs/server.log          # scan recent output
Bash: tail -n 50 logs/server.log   # last 50 lines
Bash: grep "ERROR" logs/server.log  # filter errors
```

**Convention:** Always write to `logs/` in the project root. Agents know to look
there first. Add `logs/` to `.gitignore`.

---

## Pattern 2 — Per-Worktree Port and Database Isolation

**Problem:** Multiple parallel agents share the same machine. Default ports (3000,
5432) collide when two worktrees run the same service simultaneously.

**Solution:** Derive port and database name from the worktree directory name.
Each worktree gets a unique, deterministic set of resources.

```bash
# scripts/dev-env.sh — source this in start scripts
set -euo pipefail

# Derive a stable 4-digit offset from the worktree name
WORKTREE_NAME=$(basename "$PWD")
# djb2-style hash mod 1000 → offset 0–999
OFFSET=$(echo "$WORKTREE_NAME" | cksum | awk '{print $1 % 1000}')

export PORT=$((3000 + OFFSET))
export DB_NAME="app_${WORKTREE_NAME}"
export REDIS_DB=$((OFFSET % 16))  # Redis supports DBs 0–15

echo "WORKTREE: $WORKTREE_NAME  PORT: $PORT  DB: $DB_NAME"
```

```bash
# scripts/start-dev.sh
set -euo pipefail
source scripts/dev-env.sh
mkdir -p logs
node dist/server.js >> logs/server.log 2>&1
```

**Agent usage:** An agent working in worktree `feature-auth` reads `dev-env.sh`
to know which port and database to target — no manual coordination needed.

```bash
# Agent can discover its own port:
source scripts/dev-env.sh && echo $PORT
```

**Convention:** Never hardcode port 3000 in agent instructions. Always derive
from the worktree name so parallel agents never conflict.

---

## Pattern 3 — Health Endpoint

**Problem:** Agents cannot know if a server is running, healthy, or stuck without
a machine-readable signal. Parsing log files for "server started" text is fragile.

**Solution:** Expose `GET /health` returning structured JSON. Agents poll it with
a single HTTP call to confirm the server is up and ready.

```typescript
// src/routes/health.ts
import type { RequestHandler } from "express";

interface HealthResponse {
  status: "ok" | "degraded";
  uptime: number;
  timestamp: string;
  checks: Record<string, "ok" | "fail">;
}

export const healthHandler: RequestHandler = (_req, res) => {
  const response: HealthResponse = {
    status: "ok",
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
    checks: {
      db: isDatabaseConnected() ? "ok" : "fail",
    },
  };
  const httpStatus = response.checks.db === "fail" ? 503 : 200;
  res.status(httpStatus).json(response);
};
```

```python
# Python / FastAPI equivalent
from fastapi import FastAPI
import time

start_time = time.time()

@app.get("/health")
def health():
    return {
        "status": "ok",
        "uptime": time.time() - start_time,
        "timestamp": datetime.utcnow().isoformat(),
    }
```

**Agent usage:**

```bash
# Check if server is up
curl -sf http://localhost:$PORT/health | jq .

# Wait for server to become ready (poll up to 30s)
for i in $(seq 1 30); do
  curl -sf http://localhost:$PORT/health > /dev/null && break
  sleep 1
done
```

**Convention:** Always respond with `Content-Type: application/json`. Return 200
when healthy, 503 when degraded. Include at least `status` and `timestamp`.

---

## Pattern 4 — Crash Surfacing

**Problem:** Unhandled exceptions crash the server silently. Agents see an empty
log or a generic "process exited" message with no stack trace.

**Solution:** Install a global crash handler that writes the full stack trace and
context to `logs/crashes.log` before exiting.

```typescript
// src/crash-handler.ts — load this before anything else
import fs from "fs";
import path from "path";

const CRASH_LOG = path.join(process.cwd(), "logs", "crashes.log");

function writeCrash(label: string, err: unknown): void {
  const entry = {
    timestamp: new Date().toISOString(),
    label,
    message: err instanceof Error ? err.message : String(err),
    stack: err instanceof Error ? err.stack : undefined,
  };
  fs.mkdirSync(path.dirname(CRASH_LOG), { recursive: true });
  fs.appendFileSync(CRASH_LOG, JSON.stringify(entry) + "\n");
}

process.on("uncaughtException", (err) => {
  writeCrash("uncaughtException", err);
  process.exit(1);
});

process.on("unhandledRejection", (reason) => {
  writeCrash("unhandledRejection", reason);
  process.exit(1);
});
```

```python
# Python equivalent — add to main entry point
import sys
import json
import traceback
from pathlib import Path
from datetime import datetime, timezone

CRASH_LOG = Path("logs/crashes.log")

def _crash_handler(exc_type, exc_value, exc_tb):
    CRASH_LOG.parent.mkdir(parents=True, exist_ok=True)
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "message": str(exc_value),
        "stack": "".join(traceback.format_exception(exc_type, exc_value, exc_tb)),
    }
    with CRASH_LOG.open("a") as f:
        f.write(json.dumps(entry) + "\n")
    sys.__excepthook__(exc_type, exc_value, exc_tb)

sys.excepthook = _crash_handler
```

**Agent usage:**

```
Read logs/crashes.log          # inspect all crashes
Bash: tail -n 1 logs/crashes.log | jq .   # last crash entry
```

**Convention:** Append to `logs/crashes.log`, never overwrite. Each entry is a
JSON object on one line (NDJSON). Agents can `Read` the file and parse each line.

---

## Checklist — Is Your App Agent-Legible?

| Check | File/endpoint |
|-------|---------------|
| stdout/stderr redirected to file | `logs/server.log` |
| Port and DB derived from worktree | `scripts/dev-env.sh` |
| Health endpoint returns JSON | `GET /health` |
| Crash handler writes structured log | `logs/crashes.log` |

Apply all four patterns when scaffolding a new service. Retrofit missing patterns
before asking an agent to debug or validate a running application.

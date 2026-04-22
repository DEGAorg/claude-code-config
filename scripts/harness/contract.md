# Harness Capability Contract

The **Harness** is the Conductor's OS-primitive provider for process
lifecycle: spawn, query, terminate, tail logs, list active. Conductor
code (orch-engine, orch-review, orch-verify, orch-run, orch-gc,
planner-loop) calls these functions instead of invoking `tmux`, `nohup`,
or `kill` directly.

Each backend (`local.sh` today; `docker.sh`, `remote.sh` later) implements
the same five functions. The dispatcher (`harness/dispatcher.sh`) reads
`harness:` from `dega-core.yaml` — overridable via the `DEGA_HARNESS`
environment variable — and sources the matching implementation.

Callers source `dispatcher.sh` — never a specific backend directly.

```bash
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/harness/dispatcher.sh"
```

## Conventions

- **Exit codes:** 0 = success, 1 = error, 2 = process-not-found (query /
  terminate only).
- **Output:** Functions print structured results to stdout. Diagnostics
  go to stderr.
- **Errors:** Print `error: <message>` to stderr and return non-zero.
  Include context (operation, PID, logfile) so callers can surface
  actionable messages.
- **No globals:** Functions receive all inputs as `key=value` arguments.
  The backend reads its own config (PID directory, timeouts) from
  `dega-core.yaml` or env vars.
- **Idempotent where possible:** Terminating an already-dead PID or
  listing an empty PID directory should succeed silently.
- **Handles are opaque strings:** For the local backend the handle is
  the PID (a decimal integer). Future backends may return container IDs,
  job URLs, etc. Callers persist the handle in `.orchestrator/state.json`
  under `workerPid` and pass it back untouched.

## Required functions

### `harness::spawn_process`

Start a detached background process. Writes the handle to a PID file
under `pid_dir` named `<role>-<id>.pid` so `list_active` can enumerate
the backend's running processes without re-reading state.json.

```
Arguments (key=value):
  role=ROLE           required — one of: worker, reviewer, verifier, engine
  id=ID               required — numeric item id (or a label, for engine)
  cwd=PATH            required — working directory for the process
  cmd=COMMAND         required — shell command line to execute
  logfile=PATH        required — combined stdout+stderr log path
  pid_dir=PATH        required — directory to write <role>-<id>.pid
  started_at_file=PATH  optional — path to write ISO-8601 start time for
                        PID-reuse sanity checks

Stdout:  handle (for local backend: the PID as a decimal integer)
Exit:    0 on success, 1 on failure (e.g. cwd missing, logfile unwritable)
```

### `harness::query_status`

Check whether a previously spawned handle is still alive.

```
Arguments (key=value):
  handle=HANDLE       required — value returned by spawn_process
  started_at=ISO8601  optional — if provided, verify process start time
                      matches (guards against PID reuse)

Stdout:  one of: alive | dead
Exit:    0 if alive, 2 if dead, 1 on error
```

### `harness::terminate`

Stop a running process. Sends SIGTERM, waits up to `grace` seconds, then
sends SIGKILL. Idempotent: terminating a dead handle exits 0.

```
Arguments (key=value):
  handle=HANDLE       required
  grace=SECONDS       optional — default 5

Stdout:  (none)
Exit:    0 on success (or already-dead), 1 on failure
```

### `harness::tail_logs`

Stream a log file. Shell consumers use this; the Ink TUI implements its
own Node tailer against the same log path.

```
Arguments (key=value):
  logfile=PATH        required
  follow=BOOL         optional — default false. When true, stream new
                      lines as they arrive (like `tail -F`).
  lines=N             optional — default 50. Initial number of tail lines.

Stdout:  log content
Exit:    0 on success, 1 if logfile is missing
```

### `harness::list_active`

Enumerate handles in a PID directory that are still alive. Stale PID
files (process dead) are pruned as a side effect.

```
Arguments (key=value):
  pid_dir=PATH        required

Stdout:  one "<role> <id> <handle>" triple per line, space-separated
Exit:    0 on success (even if empty), 1 if pid_dir is unreadable
```

## Backend selection

`dega-core.yaml` names the active backend:

```yaml
harness: local
```

`DEGA_HARNESS=<name>` overrides the file value for a single invocation
(useful for tests and one-off scripts). Absence of both defaults to
`local`.

## Implementing a new backend

1. Create `scripts/harness/<name>.sh`.
2. Implement every function listed above with the same signature and
   exit semantics.
3. Pass `shellcheck` and `shfmt -d`.
4. Set `harness: <name>` in `dega-core.yaml` (or export `DEGA_HARNESS`).

No changes to Conductor callers should be needed — the dispatcher routes
automatically based on the `harness:` config value.

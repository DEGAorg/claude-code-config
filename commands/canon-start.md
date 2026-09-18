# Canon Start

@description Guided entry point for Canon prediction-market development — detects project phase and drives the full pipeline.

Run every step below in order. Quote real shell output for anything
you cite; don't pretend a command ran when it didn't. Keep chat output
brief — phase names + decisions + user questions. State detail goes to
the Canon TUI panel via `terminal-ui-write.sh`, not chat.

---

## 0. Pre-flight — open the State panel (and optional diagnostic probe)

**ALWAYS run this bash block first**, before any phase detection, before
the live-mode short-circuit, before anything else. It opens the TUI's
State panel. If `CANON_DEBUG_PROBE=1` is set in the environment, it
also writes a host-visible probe file to `~/Desktop/canon-canary/` so
you can verify the Bash tool is reaching the real filesystem (used
when diagnosing canon-tui agent issues; default off).

```bash
command -v canon-ctl >/dev/null && canon-ctl action "screen.show_state" || true
if [[ -n "${CANON_DEBUG_PROBE:-}" ]]; then
  mkdir -p ~/Desktop/canon-canary
  PROBE=~/Desktop/canon-canary/canon-start-$(date -u +%Y%m%dT%H%M%SZ)-$$.md
  {
    echo "# canon-start probe"
    echo "pid: $$"
    echo "pwd: $(pwd)"
    echo "host: $(hostname)"
    echo "user: $USER"
    echo "date_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "home: $HOME"
    echo "degacore_scaffold_exists: $([[ -x ~/.degacore/scripts/canon-scaffold.sh ]] && echo yes || echo no)"
    echo "cwd_entry_count: $(ls -la | wc -l | tr -d ' ')"
  } >"$PROBE"
  echo "probe written: $PROBE"
fi
```

---

## 1. Initialize

**State write convention:** Every `terminal-ui-write.sh` call in steps 2–7 is guarded.
Require the installed state writer before continuing. If it is missing, report
an incomplete Core installation. If a required write is blocked, request the
necessary permission instead of continuing with stale state. Only opening the
socket panel is best-effort.

**Live-mode short-circuit.** If the user invoked `/canon-start --live` (look
for `--live` in the argument the slash command was called with), the project
must already be in dry-run-validated state from a prior `/canon-start`
invocation. Skip phases 2–7 entirely and jump to **Phase 8: live**. That
phase calls a deterministic shell script that handles deposit collection,
onboarding, and the live runner launch — do not reimplement any of it
inline. If `src/main.ts` does not exist, the script will fail with a clear
"run /canon-start in dry-run first" message and exit non-zero; do not
fall back to the dry-run flow.

For the standard (no `--live`) invocation, proceed directly to step 2.

---

## 2. Detect phase

Run this **single** bash block. Do NOT run individual checks — one command, one output line.

```bash
set -euo pipefail

phase="run"  # default — overridden below if earlier phase detected

# Phase: init
if [[ ! -d .canon ]]; then
  phase="init"
else
  # Phase: scaffold
  scaffold_ok=true
  for f in .canon/config.yaml dega-core.yaml package.json tsconfig.json \
           types/TradeSignal.ts types/RiskInterface.ts; do
    [[ -f "$f" ]] || { scaffold_ok=false; break; }
  done
  ls .canon/agents/*.md &>/dev/null || scaffold_ok=false
  ls .canon/skills/*.md &>/dev/null || scaffold_ok=false

  if [[ "$scaffold_ok" == false ]]; then
    phase="scaffold"
  else
    # Phase: strategy
    # Only an authorized downloaded package can resume the selected strategy.
    selected_key=$(python3 <<'PYTHON'
import json
from pathlib import Path
import subprocess
import sys

result = subprocess.run(["canon", "strategies"], capture_output=True, text=True, check=True)
if result.stderr:
    print(result.stderr, file=sys.stderr, end="")
choices = json.loads(result.stdout)
selected = [choice["key"] for choice in choices
            if (Path("docs") / f"strategy-{choice['key']}.md").is_file()
            and (Path("strategies") / choice["key"]).is_dir()]
print(selected[0] if len(selected) == 1 else "")
PYTHON
)
    strategy_found=false
    [[ -n "$selected_key" ]] && strategy_found=true

    if [[ "$strategy_found" == false ]]; then
      phase="strategy"
    elif [[ ! -f src/main.ts ]]; then
      phase="develop"
    else
      # Run checks silently — any failure means develop phase
      pnpm exec vitest run --reporter=dot &>/dev/null || phase="develop"
      if [[ "$phase" == "run" ]]; then
        pnpm exec tsc --noEmit &>/dev/null || phase="develop"
      fi
      if [[ "$phase" == "run" ]]; then
        pnpm run lint &>/dev/null || phase="develop"
      fi
    fi
  fi
fi

# Write the detected phase; errors must remain visible.
TUI_WRITE="${DEGA_CORE_HOME:-${HOME}/.degacore}/scripts/terminal-ui-write.sh"
[[ -f "${TUI_WRITE}" ]] || { echo "Missing Core state writer: ${TUI_WRITE}" >&2; exit 1; }
bash "${TUI_WRITE}" .canon/state.json \
  phase="$phase" status=running log.info="Detected phase: $phase" >/dev/null

echo "$phase"
```

The only output is the phase name (e.g. `run`). Print it as:

Phase: <phase>

Then jump to the step for that phase.

---

## 3. Phase: init

The project has no `.canon/` directory. Set up the Canon framework by running
the canon-init shell script. This is a deterministic, self-verifying script —
not an agent-driven process.

**Guard:** If the current directory is `claude-code-config` (this config repo itself),
stop and tell the user:

> Run `/canon-start` from inside your strategy project directory, not from
> `claude-code-config`. Navigate to your project first, then re-run.

Write state update:

```bash
TUI_WRITE="${DEGA_CORE_HOME:-${HOME}/.degacore}/scripts/terminal-ui-write.sh"
[[ -f "${TUI_WRITE}" ]] && \
  bash "${TUI_WRITE}" .canon/state.json \
    phase=init status=running log.info="Initializing Canon framework..."
```

Run the canon-init script:

```bash
bash "${DEGA_CORE_HOME:-${HOME}/.degacore}/scripts/canon-scaffold.sh"
```

The script copies `canon/templates/` wholesale as the project root (runner,
types, strategies, configs), fetches agents, skills, and commands from GitHub,
and verifies every file is present before reporting success. It writes dashboard
state updates as it progresses (if terminal-ui-write.sh is installed).

**If the script exits non-zero**, stop and report the error to the user. Do not
attempt to fix or retry — the script already gives a clear error message.

**If the script succeeds**, print the summary it outputs and proceed to step 4.

After init completes, install dependencies:

```bash
pnpm install
```

Ensure a project-local burner wallet exists. Idempotent — generates one on
first run, reports the address (and a funding prompt) once, and is a no-op
on subsequent runs. This is the single entry point for wallet
auto-instantiation:

```bash
"${DEGA_CORE_HOME:-${HOME}/.degacore}/bin/canon-cli" wallet ensure --pretty
```

The wallet lives at `.canon/wallet.env` (mode 0600). Each Canon project gets
its own wallet, so different strategies in different projects trade from
different accounts automatically. When `created: true` appears in the
output, tell the user to fund the printed address with USDC.e on Polygon
before running any strategy.

Proceed to step 4 (scaffold verification).

---

## 4. Phase: scaffold

The `.canon/` directory exists but may be incomplete. Verify and fill gaps.

Write state update:

```bash
TUI_WRITE="${DEGA_CORE_HOME:-${HOME}/.degacore}/scripts/terminal-ui-write.sh"
[[ -f "${TUI_WRITE}" ]] && \
  bash "${TUI_WRITE}" .canon/state.json \
    phase=scaffold status=running log.info="Verifying scaffold completeness..."
```

Check each required scaffold file from the list in step 2. If files are missing,
run the canon-init script with `--force` to regenerate them:

```bash
bash "${DEGA_CORE_HOME:-${HOME}/.degacore}/scripts/canon-scaffold.sh" --force
```

Only report if files were missing or created. If all present, say nothing
and proceed to step 5.

Write state update:

```bash
TUI_WRITE="${DEGA_CORE_HOME:-${HOME}/.degacore}/scripts/terminal-ui-write.sh"
[[ -f "${TUI_WRITE}" ]] && \
  bash "${TUI_WRITE}" .canon/state.json \
    phase=scaffold status=running log.info="Scaffold complete"
```

---

## 5. Phase: strategy

The scaffold is complete. Select an activated, downloaded curated strategy:

```bash
canon strategies
```

This returns JSON objects with `key`, `name`, and `path`. Show only those choices.
Use the host's question tool, or ask in chat when no question tool is available.
Honor an explicit selection already provided by the user if it appears in the
verified list. An empty list means there is no verified download: explain the
reported access/login/download issue and direct the user to the DEGA panel.
Do not activate a strategy automatically.

Do not enumerate Core examples, offer `/discover` or a new specification as a
replacement, or select a similar template. Arbiter is not arb-binary.

For the chosen `<key>`:

1. Read documentation, configuration, and source from the returned package `path`.
2. Copy that source into `strategies/<key>` as editable project code. Exclude
   `.git`, `node_modules`, runtime logs/state, and private environment files.
   Preserve user edits in an existing copy; do not overwrite it to resume.
3. Write `docs/strategy-<key>.md` with the verified key, source path, intended
   behavior, configuration needs, and requested changes. Stale documents for
   other strategies must not select a Core example or another package.
4. Inspect the package's actual entrypoint. Do not assume `entry.ts`, `main.ts`,
   `strategy.md`, or a template plan exists. Adapt its editable source through
   the development phase so `src/main.ts` starts the selected strategy in dry-run.
   Do not launch the global download directly or bypass setup and validation.
5. Preserve initialization, dependencies, wallet detection/creation, configuration,
   tests, and explicit live preflight. A runnable package does not skip these steps.

Write `phase=strategy status=complete` with the selected key using the installed
state writer, then proceed to step 6. Report unsupported integration honestly;
a web server or one completed cycle does not prove continuous dry-run support.

---

## 6. Phase: develop

A curated strategy has been selected. Develop its editable project copy and
validate its integration with the original Canon runner.

Write state update:

```bash
TUI_WRITE="${DEGA_CORE_HOME:-${HOME}/.degacore}/scripts/terminal-ui-write.sh"
[[ -f "${TUI_WRITE}" ]] && \
  bash "${TUI_WRITE}" .canon/state.json \
    phase=develop status=running log.info="Starting development..."
```

### 6a. Set up exec plan

Determine the strategy slug from the spec filename (e.g. `strategy-nba-momentum.md` → `nba-momentum`).

```bash
SLUG="$(date +%Y%m%d)-<strategy-slug>"
mkdir -p "docs/exec-plans/active/${SLUG}"
```

Read `strategies/<key>/plan.md` if the package provides one. Otherwise create
an execution plan from its actual source and the requested behavior. Save the
plan under `docs/exec-plans/active/${SLUG}/plan.md`. Include configuration,
entrypoint integration, dry-run safety, cycle/state reporting, tests, and clean
shutdown. Do not fabricate a template layout or mark checks complete without
running them. Preserve editable strategy logic and user-requested changes.

Write state update:

```bash
[[ -f "${TUI_WRITE}" ]] && \
  bash "${TUI_WRITE}" .canon/state.json \
    phase=develop status=running log.info="Exec plan generated: ${SLUG}"
```

### 6b. Build the strategy

Read the exec plan at `docs/exec-plans/active/${SLUG}/plan.md`. For each
unchecked item, implement it directly:

1. Read the item description
2. Write the code (create files, implement logic)
3. Write state update for each item completed:
   ```bash
   [[ -f "${TUI_WRITE}" ]] && \
     bash "${TUI_WRITE}" .canon/state.json \
       phase=develop status=running log.info="Done: <item description>"
   ```
4. Mark the item as checked in the plan: `[x]`
5. Move to the next unchecked item

After all items are done, run the success criteria checks:

```bash
pnpm exec tsc --noEmit
pnpm exec oxlint src/
pnpm exec vitest run
```

If checks fail, fix the issues and re-run. Iterate until all pass.

When all checks pass:

```bash
[[ -f "${TUI_WRITE}" ]] && \
  bash "${TUI_WRITE}" .canon/state.json \
    phase=develop status=complete log.info="Strategy built — all checks pass"
```

Proceed to step 7.

---

## 7. Phase: run

All checks pass and QA is approved. The strategy is ready for execution
in **dry-run mode**. This is the validation step before going live —
never auto-runs real orders.

Run this **single** bash block to verify the entry point exists, launch the runner, and confirm:

```bash
set -euo pipefail

if [[ ! -f "src/main.ts" ]]; then
  echo "NO_ENTRY"
  exit 0
fi

# Recheck access with `canon strategies` before this block. The selected key
# must still be listed; this check does not consume a new activation.

# Create empty .env if missing (some strategies run without auth)
touch .env

mkdir -p .canon/execution
RUNNER_PID=$(python3 - "${DEGA_CORE_HOME:-${HOME}/.degacore}/scripts/canon-runner.sh" <<'PYTHON'
import subprocess
import sys

with open(".canon/execution/wrapper.log", "a") as output:
    process = subprocess.Popen(
        ["bash", sys.argv[1]],
        stdin=subprocess.DEVNULL,
        stdout=output,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
print(process.pid)
PYTHON
)
sleep 2

if kill -0 "${RUNNER_PID}" 2>/dev/null; then
  echo "OK ${RUNNER_PID}"
else
  echo "FAIL"
  tail -5 .canon/execution/runner.log 2>/dev/null
fi
```

Handle the output:
- `NO_ENTRY` → tell the user: `No entry point at src/main.ts — run strategy selection first (phase 5).`
- `OK <pid>` means startup only. Observe at least two completed cycles and confirm
  the supervisor remains alive after the launch call returns before reporting
  continuous dry-run validated. Report the PID and stop command `kill <pid>`.
  A missing/stopped process is a failure even if earlier tests or cycles passed.
- `FAIL` → print the log tail, nothing else.

---

## 8. Phase: live

Reached only when the user invoked `/canon-start --live`. Drives the
project from "dry-run validated" to "live trading" by collecting a
native-USDC deposit at the EOA, running the gasless onboarding chain
that pulls funds into the Polymarket Safe (V1+V2 approvals + builder
creds + EIP-2612 permit + Uniswap swap + Onramp wrap), and launching
`canon-runner.sh --live`.

Before live preflight, recheck the selected key with `canon strategies` and
confirm the selected package actually implements live execution. Missing access
or unsupported live execution must stop here.

Run this **single** bash block. Do not split into multiple tool calls —
the script is the deterministic spine, this command stays a thin
wrapper:

```bash
bash "${DEGA_CORE_HOME:-${HOME}/.degacore}/scripts/canon-live-readiness.sh"
```

Behaviour:
- The script writes its own state into `.canon/state.json` at every
  transition (`deposit-pending` → `funds-detected` → `onboarding` →
  `ready` → `running`). The TUI surfaces those.
- If `src/main.ts` does not exist, the script exits non-zero with a
  message telling the user to run `/canon-start` (no flag) first. Do
  not auto-fall-back to the build phases — `--live` is for the
  transition, never for the initial scaffold.
- If the wallet is already onboarded (Safe deployed, V1+V2 approvals
  set, creds derivable, collateral > 0), the script skips deposit
  polling and goes straight to launching the live runner. Re-running
  `/canon-start --live` is therefore safe and idempotent.
- Deposit polling defaults to 10s cadence with a 30-min timeout
  (`CANON_LIVE_POLL_SECS` and `CANON_LIVE_TIMEOUT_SECS` override).
- On timeout, the script writes `phase=live, status=timeout` so the
  TUI keeps the EOA address visible. Re-running resumes polling.

When the script exits 0, print:

`Live runner started. PID and live status are in .canon/state.json. Stop: kill <pid>.`

When the script exits non-zero, print the `error` field from
`.canon/state.json` (if present) and stop. Do not retry automatically;
let the operator inspect and decide.

---

## Host behavior

This command works from Canon TUI, tmux, a terminal, or an IDE. Opening the
socket panel is best-effort. Required state-file writes are not: report a missing
writer as an incomplete Core installation, and surface permission failures.
Do not gate phase execution on `$TMUX`, `$CANON_TUI`, or `$TOAD_CWD`.

---

## Completion criteria

- Phase detection correctly identifies the project's current state
- Each phase delegates to the right sub-command logic (canon-scaffold.sh, curated selection, develop)
- State file is updated at each phase transition; write failures are surfaced
- Only verified curated downloads are selected, and their project copies remain editable
- Continuous dry-run validation requires at least two cycles and a living supervisor
- User is guided through the full pipeline with minimal questions

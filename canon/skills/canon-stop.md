# Canon Stop

@description Stop the currently running Canon strategy runner and reset state to idle. Triggers on natural-language intent like "stop canon", "halt the runner", "kill the strategy", or "shut down canon" when a Canon session is active. Safe to invoke when nothing is running — it reports no active runner and exits.

Run every step below in order.

---

## 1. Stop the runner

Check if a runner is active:

```bash
cat .canon/execution/runner.pid 2>/dev/null
```

If a PID file exists, kill the process:

```bash
PID=$(cat .canon/execution/runner.pid 2>/dev/null)
if [[ -n "${PID}" ]] && kill -0 "${PID}" 2>/dev/null; then
  kill "${PID}"
  echo "Runner stopped (PID ${PID})"
else
  echo "No active runner"
fi
rm -f .canon/execution/runner.pid
```

Also check for any stray runner processes:

```bash
pkill -f "canon-runner" 2>/dev/null || true
pkill -f "src/runner.ts" 2>/dev/null || true
```

---

## 2. Update state

```bash
TUI_WRITE="${DEGA_CORE_HOME:-${HOME}/.degacore}/scripts/terminal-ui-write.sh"
[[ -f "${TUI_WRITE}" ]] && \
  bash "${TUI_WRITE}" .canon/state.json \
    phase=idle status=idle log.info="Canon stopped"
```

Print:

> Canon stopped. Run `/canon-start` to resume.

# Canon

@description Default canon entry point. Triggers on canon-specific
natural-language intent like "run canon", "continue canon", "what's next in
canon", or "resume canon". Detects the current canon phase by calling
`canon/scripts/phase-detect.sh` and dispatches to the appropriate sub-skill
(`canon-new`, `canon-start`, `canon-stop`) or returns a resume message when a
run is already active. Do not fire on generic prediction-market talk — only
when the user explicitly refers to "canon".

## When to use this skill

Invoke this umbrella skill when the user expresses canon-specific intent
without naming a sub-flow, for example:

- "run canon"
- "continue canon"
- "what's next in canon"
- "resume canon"

For explicit sub-flow intent (e.g. "start a new prediction-market project",
"stop the canon run"), invoke the matching sub-skill directly. This umbrella
exists so a user who just says "canon" always lands somewhere useful.

---

## 1. Detect the current phase

Run the phase oracle. It is the single source of truth for which sub-skill
should handle the request:

```bash
bash canon/scripts/phase-detect.sh
```

The script prints exactly one of these tokens on stdout:

| Token | Meaning |
|-------|---------|
| `not-bootstrapped` | No `dega-core.yaml` at cwd — canon is not installed here. |
| `bootstrapped-no-strategy` | `dega-core.yaml` present but `canon/strategies/` is empty or missing. |
| `has-strategy` | At least one strategy scaffolded; no active run. |
| `running` | `.canon/state.json` shows `phase != idle` and `status != idle`. |

Do not re-implement detection in this skill — always delegate to
`canon/scripts/phase-detect.sh` so the oracle stays single-sourced.

---

## 2. Dispatch table

Route by phase token. Invoke the named sub-skill; do not inline its body.

| Phase | Route to | Behaviour |
|-------|----------|-----------|
| `not-bootstrapped` | `canon-new` | Hand off to the `canon-new` skill — it owns install + init. |
| `bootstrapped-no-strategy` | `canon-new` | Canon is installed but has no strategy yet; `canon-new` runs the init flow. |
| `has-strategy` | `canon-start` | A strategy exists and no run is active — start one via the `canon-start` skill. |
| `running` | resume message (see §3); offer `canon-stop` | A run is already active. Do not start a second one. Surface state and offer `canon-stop`. |

Each sub-skill remains individually callable; this umbrella only chooses
which one to invoke.

---

## 3. Running-phase resume message

When `phase-detect.sh` reports `running`, do **not** invoke `canon-start`.
Instead, read `.canon/state.json` and print a short summary of the active
run, then offer two next actions:

> Canon is already running. Current phase: `<phase>` (status: `<status>`).
>
> - To stop it, invoke the `canon-stop` skill.
> - To watch progress, attach to the existing session (`./canon.sh` or the
>   canon TUI).

Do not start a new session. Do not overwrite `.canon/state.json`.

---

## 4. Phase → skill quick reference

For traceability, the mapping in one line per phase:

- `not-bootstrapped` → `canon-new`
- `bootstrapped-no-strategy` → `canon-new`
- `has-strategy` → `canon-start`
- `running` → resume message + offer `canon-stop`

---

## 5. Do not

- Do not re-implement phase detection — always call
  `canon/scripts/phase-detect.sh`.
- Do not inline sub-skill bodies — invoke them by name (`canon-new`,
  `canon-start`, `canon-stop`).
- Do not over-fire on generic prompts. This skill is reserved for
  canon-specific phrases ("run canon", "continue canon",
  "what's next in canon").

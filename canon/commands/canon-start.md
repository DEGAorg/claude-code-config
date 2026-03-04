# Canon Start

@description Guided entry point for Canon prediction-market development — detects project phase and drives the full pipeline.

Run every step below in order. Do not stop between steps unless explicitly told to.

---

## 1. Verify tmux environment

`canon.sh` launches the tmux session with the dashboard. This command expects to
already be running inside tmux. Check the environment:

```bash
echo "${TMUX:-not-set}"
```

- **Inside tmux** (`$TMUX` is set): good. Check the session name:

  ```bash
  tmux display-message -p '#S'
  ```

  - Session name is "canon": print nothing, continue to step 2.
  - Different session name: print once and continue:

    > Running inside tmux session "<name>" (not "canon"). Dashboard may not be
    > visible, but the workflow works the same.

- **Not inside tmux** (`$TMUX` is not set): print and stop:

  > Not running inside tmux. Run `./canon.sh` first to launch the Canon
  > environment with the dashboard.

  Do not proceed to step 2.

**State write convention:** Every `terminal-ui-write.sh` call in steps 2–7 is guarded.
Before each call, check if the script exists and skip silently if it does not.

---

## 2. Detect phase

Assess the current project state by checking what exists. Evaluate conditions
top-to-bottom — the first match determines the current phase.

| Condition | Phase | Next action |
|-----------|-------|-------------|
| No `.canon/` directory | **init** | Go to step 3 |
| `.canon/` exists but missing required files (see below) | **scaffold** | Go to step 4 |
| No strategy spec found (see below) | **strategy** | Go to step 5 |
| Strategy spec exists but no `src/` directory | **develop** | Go to step 6 |
| `src/` exists but tests fail (`pnpm exec vitest run` exits non-zero) | **develop** | Go to step 6 |
| All checks pass | **run** | Go to step 7 |

**Required scaffold files** (for scaffold-complete check):
- `.canon/config.yaml`
- `.canon/ralph.yaml`
- `.canon/agents/` directory with at least one `.md` file
- `.canon/skills/` directory with at least one `.md` file
- `package.json`
- `tsconfig.json`
- `src/types/TradeSignal.ts`
- `src/types/RiskInterface.ts`

**Strategy spec detection** — a strategy spec is any of:
- A file matching `*.strategy.md` anywhere in the project
- A file matching `docs/strategy-*.md`
- A design spec output from `/discover` (check `.canon/execution/` for spec files)

Write the detected phase to the state file:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=<detected-phase> status=running log.info="Detected phase: <detected-phase>"
```

Tell the user what you found:

> **Phase: <phase>** — <one-sentence description of what was detected>

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
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=init status=running log.info="Initializing Canon framework..."
```

Run the canon-init script:

```bash
bash "${HOME}/.claude/scripts/canon-scaffold.sh"
```

The script fetches all agents, skills, and commands from GitHub, generates
template files (package.json, tsconfig.json, types, configs), and verifies
every file is present before reporting success. It writes dashboard state
updates as it progresses (if terminal-ui-write.sh is installed).

**If the script exits non-zero**, stop and report the error to the user. Do not
attempt to fix or retry — the script already gives a clear error message.

**If the script succeeds**, print the summary it outputs and proceed to step 4.

After init completes, install dependencies:

```bash
pnpm install
```

Proceed to step 4 (scaffold verification).

---

## 4. Phase: scaffold

The `.canon/` directory exists but may be incomplete. Verify and fill gaps.

Write state update:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=scaffold status=running log.info="Verifying scaffold completeness..."
```

Check each required scaffold file from the list in step 2. If files are missing,
run the canon-init script with `--force` to regenerate them:

```bash
bash "${HOME}/.claude/scripts/canon-scaffold.sh" --force
```

Report what was found:

> Scaffold check: <N> of <total> files present. <Missing: list, or "All present.">

If any files were created, report them. Then proceed to step 5.

Write state update:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=scaffold status=running log.info="Scaffold complete"
```

---

## 5. Phase: strategy

The scaffold is complete but no strategy spec was found.

Write state update:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=strategy status=running log.info="Looking for strategy specification..."
```

First, check for available starter templates:

```bash
ls .canon/templates/*.strategy.md 2>/dev/null
```

Build the list of options based on what's available:

> No strategy specification found. Choose one:

If templates were found, list each one:

> 1. **Use starter template: <name>** — <read the first line of the template for description>

Always include these two options at the end:

> - **Run /discover** — I'll scan prediction markets, identify opportunities,
>   and generate a strategy design spec automatically.
> - **Provide a spec** — Point me to an existing strategy document or describe
>   your strategy and I'll write the spec.

Wait for the user's response.

**If the user chooses a starter template:**

Copy the template to `docs/`:

```bash
cp .canon/templates/<name>.strategy.md docs/strategy-<name>.md
```

Read the copied spec and print a brief summary (market, archetype, edge thesis).

**If the user chooses /discover:**

Execute the `/discover` procedure inline:

1. As market-analyst, research available prediction markets using web search
   and the Polymarket API documentation.
2. Scan for opportunities (price movements, volume spikes, thin liquidity, resolution events).
3. Select the top opportunity by edge size, liquidity, resolution clarity, and capital efficiency.
4. As strategy-architect, design a strategy for the selected opportunity:
   - Select strategy archetype (from strategy-patterns skill)
   - Design entry/exit signal logic
   - Define risk parameters (position size ≤5%, stop-loss, circuit breakers)
   - Define backtest success criteria (win rate >55%, profit factor >1.2,
     max drawdown <15%, min 30 trades)

Write the strategy spec to `docs/strategy-<name>.md`.

Load agents: market-analyst, strategy-architect.
Load skills: prediction-markets, polymarket, strategy-patterns, risk-management.

**If the user provides a spec:**

Read the provided document. Validate it contains:
- Target market(s)
- Strategy archetype or approach
- Entry/exit logic
- Risk parameters

If anything is missing, ask the user to clarify before proceeding.

Write state update:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=strategy status=running log.info="Strategy spec ready"
```

Proceed to step 6.

---

## 6. Phase: develop

A strategy spec exists. Build the strategy using the Ralph Loop — an automated
worker + reviewer iteration loop that drives implementation from an exec plan.

Write state update:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=develop status=running log.info="Starting development..."
```

### 6a. Generate exec plan from template

Read the strategy spec (found in step 5). Read the plan template at
`.canon/templates/sports-strategy-plan.md`.

Generate an exec plan by filling in the template placeholders:

| Placeholder | Source |
|-------------|--------|
| `{{STRATEGY_NAME}}` | Name from strategy spec title |
| `{{DATE}}` | Today's date (YYYY-MM-DD) |
| `{{STRATEGY_SLUG}}` | Kebab-case strategy name (e.g. `nba-momentum`) |
| `{{STRATEGY_DESCRIPTION}}` | 2-3 sentence summary from strategy spec |
| `{{ENTRY_LOGIC}}` | Entry conditions from strategy spec (bullet list) |
| `{{EXIT_LOGIC}}` | Exit conditions from strategy spec (bullet list) |
| `{{RISK_PARAMS}}` | Risk parameters from strategy spec (bullet list) |
| `{{SPORT_KEY}}` | The Odds API sport key (e.g. `basketball_nba`) |
| `{{MARKET_QUERY}}` | Polymarket search query (e.g. `NBA`) |

Write the generated plan to:

```bash
SLUG="$(date +%Y%m%d)-{{STRATEGY_SLUG}}"
mkdir -p "docs/exec-plans/active/${SLUG}"
```

Write the plan as `docs/exec-plans/active/${SLUG}/plan.md`.

Also ensure `ralph.yaml` exists at the project root (it should from scaffold).
If not, create it with the standard success criteria:

```yaml
version: 1
max_iterations: 5

success_criteria:
  - id: types_compile
    check: "pnpm exec tsc --noEmit"
    required: true
  - id: lint_clean
    check: "pnpm exec oxlint src/"
    required: true
  - id: tests_pass
    check: "pnpm exec vitest run"
    required: true
```

Write state update:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=develop status=running log.info="Exec plan generated: ${SLUG}"
```

Print:

> **Exec plan generated** at `docs/exec-plans/active/<slug>/plan.md`
>
> Launching Ralph Loop to build the strategy...

### 6b. Run Ralph Loop

Execute the Ralph Loop with the dashboard state pointed at `.canon/state.json`:

```bash
RALPH_TUI_STATE="$(pwd)/.canon/state.json" \
  bash "${HOME}/.claude/scripts/ralph-loop.sh" "${SLUG}"
```

The Ralph Loop will:

1. Read the exec plan and find unchecked items
2. Spawn a worker agent to implement each item
3. Spawn a reviewer agent to evaluate the work
4. Iterate until the reviewer outputs SHIP and all health checks pass
5. Write dashboard state updates throughout (to `.canon/state.json` via `RALPH_TUI_STATE`)

**If the Ralph Loop exits 0 (SHIP):** The strategy was built, tested, and approved.
The exec plan has been moved to `docs/exec-plans/completed/`. Proceed to step 7.

**If the Ralph Loop exits 1 (max iterations):** Print:

> Ralph Loop reached max iterations without SHIP. Review the latest
> feedback at `docs/exec-plans/active/<slug>/review-feedback.txt`
> and run `/ralph-cycle` to continue iterating.

Do not proceed to step 7. Stop here.

**If the Ralph Loop exits 2 (stagnated or blocked):** Print:

> Ralph Loop is blocked. Check `docs/exec-plans/active/<slug>/review-feedback.txt`
> for details. Fix the blocker and re-run `/canon-start` to continue.

Do not proceed to step 7. Stop here.

Write state update after Ralph Loop completes:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=develop status=running log.info="Ralph Loop complete — strategy built"
```

---

## 7. Phase: run

All checks pass and QA is approved. The strategy is ready for execution.

Write state update:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=run status=idle log.info="Strategy ready for execution"
```

Print:

> **Strategy development complete.**
>
> All checks pass. QA approved. Your strategy is ready.
>
> Next steps:
> - Run `/register` to submit to Canon Arena for tracked performance
> - Automation runner is not yet implemented — run your strategy manually
>   or monitor markets and execute signals by hand
>
> To re-run any phase, use the individual commands:
> - `/discover` — market analysis and strategy design
> - `/develop` — implement, test, iterate
> - `/ralph-cycle` — iterate until all success criteria pass
> - `/register` — risk review and Arena registration

---

## Graceful degradation

This command requires tmux — it expects to be launched via `./canon.sh`.
Dashboard state writes degrade gracefully:

| Component | If missing | Behavior |
|-----------|-----------|----------|
| tmux / `$TMUX` not set | Stop with message | User told to run `./canon.sh` first |
| `~/.claude/scripts/terminal-ui-write.sh` | Skip state file writes | No dashboard updates, workflow still runs |

Every `terminal-ui-write.sh` call in this command is already guarded with
`[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] &&`. If the script
does not exist, the call is skipped silently — no error, no repeated warnings.

---

## Completion criteria

- Tmux environment verified at entry — stops if not inside tmux
- Phase detection correctly identifies the project's current state
- Each phase delegates to the right sub-command logic (canon-scaffold.sh, discover, develop)
- State file is updated at each phase transition (when terminal-ui-write.sh is available)
- Graceful degradation: dashboard writes skipped silently when terminal-ui-write.sh is missing
- User is guided through the full pipeline with minimal questions

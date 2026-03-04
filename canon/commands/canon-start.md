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

Ask the user:

> No strategy specification found. Choose one:
>
> 1. **Run /discover** — I'll scan prediction markets, identify opportunities,
>    and generate a strategy design spec automatically.
> 2. **Provide a spec** — Point me to an existing strategy document or describe
>    your strategy and I'll write the spec.

Wait for the user's response.

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

A strategy spec exists. Implement, test, and iterate.

Write state update:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=develop status=running log.info="Starting development..."
```

Execute the `/develop` procedure inline:

Load agent: dev.
Load skills: canon-conventions, backtesting, ralph-loop, risk-management.

### 6a. Implement

Implement strategy logic from the design specification:

- Implement `TradeSignal` interface in `src/strategy.ts`
- Implement `RiskInterface` in `src/types/RiskInterface.ts` with hard limits from the spec.
  Do not skip RiskInterface — "I'll add it later" is not acceptable.
- Follow domain layering: Types -> Config -> Repo -> Service -> Runtime -> UI
- Use agent-oriented error messages (what/why/how format)

### 6b. Test and iterate

Run every check command from `.canon/ralph.yaml` `success_criteria`:

```
pnpm exec tsc --noEmit
pnpm exec oxlint src/
pnpm exec vitest run
```

All must pass. If any fail, iterate:

1. Read failing output to identify what broke
2. Fix the issue in code
3. Re-run all checks
4. Repeat until all pass or `max_iterations` from `.canon/ralph.yaml` is reached

Write state update on each iteration:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=develop status=running metric.iteration=<N> log.info="Iteration <N>: <pass/fail summary>"
```

If max iterations reached without passing, surface failing criteria for human review.

### 6c. QA review

As qa, validate strategy quality:

Load skills: canon-conventions, backtesting, risk-management.

1. Code conventions: domain layering respected, error messages follow what/why/how
2. Backtest results across multiple timeframes (7d, 30d, 90d if data available)
3. No overfitting signals
4. RiskInterface correctly enforces hard limits
5. Edge cases: zero liquidity, API timeout, zero balance

Verdict:
- **Approved**: All criteria met -> proceed to step 7
- **Return to dev**: Specific blocking issues -> list issues -> loop back to step 6a

Write state update:

```bash
[[ -f "${HOME}/.claude/scripts/terminal-ui-write.sh" ]] && \
  bash "${HOME}/.claude/scripts/terminal-ui-write.sh" .canon/state.json \
    phase=develop status=running log.info="QA: <Approved|Returned with N issues>"
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

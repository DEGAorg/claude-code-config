# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Strategy seeds — add DAG nodes + edges for canon-tui automation panel (`20260515-strategy-dag-nodes`) — 2026-05-15

### Changed
- Runner writes active_since timestamp on active step change (`20260515-runner-active-since`) — 2026-05-15

### Fixed
- Fix Codex-native skill installation in CORE installer (`20260605-codex-skill-install`) — 2026-06-05

## [0.1.10] — 2026-05-27

Unjams the orchestrator's document phase + engine dispatch end-to-end
after a cascade of seven bugs that together made plans either crash on
every run or loop the wave indefinitely. The work itself always finished
in about two minutes, then the run hung on document-phase artifacts —
which on `bash 5.3.9` manifested as the "massive time to execute plans"
complaint. Smoke-confirmed shipping a real plan in 2 min 41 sec where
prior runs hung until killed.

Also ships the Kalshi adapter Unreleased entries (KALSHI.md integration
guide for partner share, `createOrder` / `buildOrder` TIF + dollar-string
fix) and folds in the `20260515-kalshi-poc` line that was sitting in
Unreleased through the 0.1.9 release.

### Added
- `canon/templates/adapters/KALSHI.md` — Kalshi adapter integration guide
  for partner share: file map, env vars, RSA-PSS auth, `MarketClient`
  capability matrix per method, order shape (TIF mapping + dollar-string
  prices), live smoke runbook. Calls out that `watchOrderBook` /
  `watchTrades` are REST snapshots today, not WS — streaming and a real
  subscriber are Phase-2 scope. Also refreshes the stale `README.md` line
  that still listed Kalshi as "planned" after `20260515-kalshi-poc`
  shipped (`92b103d5`) — 2026-05-22

### Changed
- Kalshi adapter PoC — full demo coverage (`20260515-kalshi-poc`) — 2026-05-15

### Fixed
- `scripts/orch-document.sh` `spawn_documenter` — `printf '- **Item ID**:
  %s\n' …` parsed the leading `-` as an option flag under bash builtin
  printf (`printf: - : invalid option`), exiting `rc=2` under
  `set -euo pipefail` on every run. Guarded with `printf --`. zsh's
  builtin tolerates it, which is why the bug hid in interactive shells
  until a real orch run on `bash 5.3.9` triggered it.
- `scripts/orch-document.sh` `persist_pending_reports` — inverted the
  live-window check. The previous form only matched `pane_dead=1`
  (window exited but still listed); tmux's default removes a window
  when its pane exits, so between two 10s polls a window could
  transition `alive → gone` without ever being observed as
  `pane_dead=1`. Persist now fires whenever the window is **not alive**
  (dead OR gone); the pipe-pane log exists either way, so a clean
  documenter exit between polls no longer races
  `detect_stale_documenters` into marking the item failed.
- `scripts/orch-document.sh` `orch_document_parse_report` — prefilters
  the documenter log with `grep '^{'` before `jq -rs`. The tmux
  pipe-pane log captures terminal ANSI restore-state when the pane
  closes (plus the `--- documenter N exited ---` marker), and `jq -rs`
  slurps every line — so a single malformed trailing line broke the
  whole parse, dropping the agent's `doc-writer-report` block and
  miscategorizing `NO_CHANGES_NEEDED` as `FAIL`.
- `scripts/orch-engine.sh` document-phase rc handler — a script crash
  (`rc != 0, != 124`) was misread as a legitimate REVISE verdict and
  triggered an unconditional rework wave — an infinite loop, since the
  next wave hit the same crash. Now sets `DOCUMENT_FAILED`, marks items
  still in `documenting` as failed, and halts cleanly via a new explicit
  exit branch that mirrors `FORMATTING_FAILED`.
- `scripts/orch-engine.sh` review-phase rc handler — same anti-pattern.
  `orch-review.sh` legitimately exits `rc=1` with `error: no items
  completed — nothing to review` when every item has terminally failed;
  the engine misread that as REVISE → wave re-exec → loop. Now sets
  `REVIEW_FAILED`, marks stuck `reviewing` items failed, and halts via a
  new explicit exit branch.
- `scripts/orch-engine.sh` wave-bail gate before REVISE re-exec — counts
  items in non-terminal status (`ready/running/queued/pending`). If
  zero, halts with `status=failed` instead of re-execing the wave on a
  state where nothing can change. Defense in depth against future
  REVISE-leak bugs.
- `scripts/orch-state.sh` `git add -A` at both worktree commit sites
  (`orch_commit_worktree` and the per-item progress commit) now use
  pathspec excludes — `git add -A -- '.' ':(exclude)inputs'
  ':(exclude)formatting'` — so the orch-internal `inputs/` and
  `formatting/` scratch dirs that `stage_inputs` functions write at the
  worktree root no longer leak into PR commits. Neither path is in the
  repo `.gitignore` (only `/.orchestrator/` is). Observed contaminating
  an auto-PR with ~87 lines of agent scratch alongside the real work.
- `canon/templates/adapters/kalshi.ts` `createOrder` / `buildOrder` — the
  `MarketClient` `time_in_force` enum (`GTC` / `IOC` / `FOK`) is now
  mapped to Kalshi's snake_case values (`good_till_canceled` /
  `immediate_or_cancel` / `fill_or_kill`) instead of being passed
  through verbatim. Prices switched from the deprecated integer-cent
  `yes_price` / `no_price` fields (removed by Kalshi in March 2026) to
  `yes_price_dollars` / `no_price_dollars` with 4-decimal sub-penny
  precision. Live smoke (`RUN_LIVE=1 RUN_ORDER=1`) now places and
  cancels a real order end-to-end (`66c0b822`) — 2026-05-15

## [0.1.9] — 2026-05-13

Subtracts prescriptive rules added in 0.1.8 (#329-#333) that, in
hindsight, over-constrained the agent. Plain `claudep` runs
`/canon-start` cleanly with no special instructions; canon-tui needed
the system-prompt-level binding fix (`DEGAorg/canon-tui#61`) but did
not need the layered rule prescriptions on top. Late-session testing
showed the layered rules occasionally led the agent to deny it had a
Bash tool ("I don't have a direct Bash tool — only the Task tool")
and fabricate completion claims, despite all our anti-fabrication
rules. Less is more.

### Changed
- `agents/conductor.md` — strip the "⚠️ Binding constraints" preamble
  and reduce the "Rules" list. Keep: "don't fabricate, don't block,
  defer to panel, confirm before spawning work, gather state first,
  TUI via socket, graceful degradation." Drop: tool-prescription rules
  ("use Bash directly, never Task"), forbidden-summary enumeration,
  "scope override" instructions. Trust the agent's defaults; let it
  autodiscover the right tool — 2026-05-13
- `commands/canon-start.md` + `canon/commands/canon-start.md` — strip
  the "Output rules — STRICT" block at the top. Keep a one-sentence
  framing: "Quote real shell output; don't pretend a command ran;
  keep chat brief; state detail goes to the panel." All phase logic
  and bash blocks are unchanged — those work fine when not buried
  under rule contradictions — 2026-05-13

### Why
0.1.8 layered binding constraints (#329, #330, #331, #332, #333)
intended to force execution and ban narration. Each worked in
isolation but compounded into contradictions when the agent also
received Canon TUI's injected `agent_context.md` ("Never echo tool
output", "The panel IS the answer") at system-prompt level. The agent
spent more cycles resolving conflicting rules than running the slash
command. Removing the prescriptions lets the agent's own defaults
apply — same defaults that make plain `claudep` work cleanly on the
same `canon-start.md` file.

The one rule we keep — "don't fabricate" — is a guardrail, not a
behavioral prescription. It tells the agent what NOT to do without
specifying what to do instead, leaving choice to the agent's
defaults.

## [0.1.8] — 2026-05-13

Hardens Conductor + `/canon-start` against agent fabrication when
running inside Canon TUI (`canon run`). The agent had been narrating
"Phase: init / Scaffold complete / N packages installed / Wallet exists
at 0x…" while the project directory stayed empty, because the rules
layered into `agents/conductor.md` and `commands/canon-start.md` were
being delivered to Claude as *user-prompt content* and lost weight
against the built-in `claude_code` preset's own defaults. The fix in
this release is the defense-in-depth layer on this side; the
protocol-level companion fix lives in `DEGAorg/canon-tui#61`
(system-prompt injection via `_meta.systemPrompt.append`). Together
they make the rules binding. End-to-end verified inside `canon run`:
scaffold lands ~46 entries on the first attempt with no per-turn
overrides, wallet address agrees three ways (chat / `.canon/wallet.env`
on disk / `canon-cli wallet info --pretty` from outside the TUI), and
the state panel moves through phases.

### Added
- `commands/canon-start.md` + `canon/commands/canon-start.md` — host-
  visible diagnostic probe at phase 0, gated by `CANON_DEBUG_PROBE=1`
  env var. Writes a timestamped marker file to `~/Desktop/canon-canary/`
  so an operator can deterministically verify the Bash tool reached the
  real filesystem when diagnosing agent hallucination. Default off — no
  chat noise on normal runs (#331, #332) — 2026-05-13

### Changed
- `agents/conductor.md` — restructured rules so binding constraints
  come first ("Never fabricate tool output OR narrated completion",
  "For slash commands: issue every bash block via the Bash tool
  directly, never the Task tool", "Defer to the panel"). The default
  delegation posture moved below as the non-slash-command rule.
  Canon-TUI injects this file at the start of every session, so the
  leading rules prime the agent's behavior the most (#329, #332,
  #333) — 2026-05-13
- `commands/canon-start.md` + `canon/commands/canon-start.md` — added
  explicit "every fenced bash block is a Bash tool call contract" and
  "use the Bash tool directly, never the Task tool" rules at the top
  of the STRICT output rules. Enumerated forbidden narrated-completion
  phrases ("Init complete", "Scaffold created", "N packages installed",
  "Wallet exists at 0x…") that must be backed by a real Bash call.
  Added scope override clarifying that Canon-TUI's `agent_context.md`
  "Never echo tool output" rule applies only to `canon-ctl` panel-
  control commands, not to scaffold / install / wallet bash blocks
  (#330, #331, #332, #333) — 2026-05-13

### Fixed
- `/canon-start` from inside Canon TUI now runs the scaffold pipeline
  end-to-end on the first attempt instead of narrating fictional
  completion. Three-way wallet cross-check matches; state panel
  reflects every phase transition; agent no longer routes
  infrastructure bash through Task subagents that fabricate (#329,
  #330, #331, #332, #333) — 2026-05-13

## [0.1.7] — 2026-05-12

Two new agentic phases land in the orchestrator — a per-item DOCUMENTING
phase (#302 / PR #305) that runs a locked-scope doc-writer agent on each
item before SHIP, and a per-plan FORMATTING phase (#310 / PR #311) that
auto-fixes `shfmt` and `shellcheck` on every changed `.sh` before SHIP so
the kind of CI failure that surfaced on PR #305 cannot reach CI again. The
MINT-01 and MINT-04 strategy templates also flip to **Turnkey (live)**:
both now wire the full cycle loop (splitPosition mint → dual-leg sell-limit
→ 24h reconcile / 5¢ stop-loss), joining ARB-01, ARB-03, and TRADE-02 as
live-capable templates. Additional install-path hardening canonicalizes
the orchestrator launcher at `~/.degacore/scripts/orch-run.sh` and adds
stale-install detection to `/apply-core`.

### Added
- Per-plan FORMATTING phase — single lint-fixer agent runs in the plan
  worktree after DOCUMENTING all-PASS (or after REVIEW all-PASS when
  DOCUMENTING is absent) and before SHIP. Auto-fixes `shfmt -i 2 -w` and
  runs `shellcheck -e SC1091 -S warning` (CI-matching flags) on every
  `.sh` file the orch branch changed vs base; on PASS commits one
  `chore: shfmt + shellcheck pass` if anything was staged. On FAIL the
  plan halts with `REVIEW_RESULT=FORMATTING_FAILED` and the worktree is
  preserved for triage. Adds `scripts/orch-format.sh`,
  `agents/lint-fixer.md`, `state.formatting` schema fields, and a
  CI-matching `.pre-commit-config.yaml` for hand-committers. Item-level
  REVISE routing is deferred to v2 (#310) — 2026-05-12
- Per-item DOCUMENTING phase to orchestrator (#302) — 2026-05-08
- MINT-01 cycle loop — `strategies/mint-01/cycle.ts:runCycle` orchestrates
  scan → `splitPosition($1,000)` → dual GTC sell-limit at midpoint+0.75¢
  on each leg → 24h fill-poll with stop-loss on 5¢ drift → cancel and
  reconcile. Shared `mint-cycle-helpers.ts` (`planTwoLegs`,
  `withinDriftBand`) extracted so MINT-04 reuses the same primitives.
  Flips MINT-01 to **Turnkey (live)** in `STRATEGY-INDEX.md` (#306) —
  2026-05-11
- MINT-04 cycle loop — `strategies/mm-premium/cycle.ts:runMmPremiumCycle`
  composes the same mint + dual-leg + 24h reconcile flow with the
  market-making tier-offset latched at cycle start (1.0¢ / 0.75¢ / 0.5¢
  per volume bracket from `evaluateMintPremiumOpportunity`). Dry-run keeps
  using the shared scanner runner; `--live` branches into the cycle.
  Adds `stopLossDrift` (default 0.05) + `fillPollIntervalMs` (default
  60_000) to `MintPremiumConfig`. Flips MINT-04 to **Turnkey (live)**
  (#307) — 2026-05-11
- "Use it at your own risk" disclaimer surfaced in three install/init
  touchpoints so users see it before any live action: the
  `scripts/canon.sh` welcome banner (above the `Launching Canon TUI`
  echo and the tmux fallback), `INSTALL.md` (after the "For AI
  agents — bootstrap instructions" intro paragraph), and
  `commands/canon-init.md` (as the first printed step in the init
  walkthrough). Informative-only, no acknowledgment gate — agent-native
  UX prefers no friction (#152) — 2026-05-07
- `tests/orch/test_no_stale_claude_scripts_refs.bats` — bats regression
  asserting `AGENTS.md` and `agents/conductor.md` never reintroduce the
  stale `~/.claude/scripts/orch-run.sh` path (#300) — 2026-05-07
- `commands/apply-core.md` Step 0b — stale-install detection that runs
  `[[ -e ~/.claude/scripts/orch-run.sh ]]` and, on hit, prints a warning
  block explaining the pre-flip code shadowing risk and the recommended
  `trash ~/.claude/scripts/` command. Advisory only — destructive removal
  under `$HOME` requires explicit operator approval, so the step never
  auto-executes (#300) — 2026-05-07
- Gate C v2 — AST-based detector (advisory) in `scripts/orch-reviewer-run.sh`.
  `gate_c_ast()` runs alongside the existing v1 grep detector and uses
  `ast-grep --pattern '$NAME($$$)' --lang ts` over non-test `.ts` files to
  decide whether each newly exported hook has a real call-expression — not
  just a text reference, type-position mention, or re-export. The verdict
  lands in `${OUT_DIR}/gate-c.ast.verdict` (`PASS` / `FAIL` / `SKIP`),
  `${OUT_DIR}/gate-c.ast.reason`, the `verdict.json` `gateCAst` field, and
  a "Gate C v2" section in `findings.md`. The aggregate SHIP/FAIL still
  gates on the v1 grep verdict (`gate-c.verdict`) — the AST verdict is
  recorded for observation until a follow-up plan flips the aggregate. If
  `ast-grep` is not on `PATH`, the gate writes `SKIP` with reason
  "ast-grep not installed on PATH" and continues (fail-open). Bats coverage
  in `tests/orch/test_gate_c_ast.bats`; advisory rollout documented under
  "Known limitations (v1)" in `docs/reviews/orch-reviewer-gates.md`
  (#266) — 2026-05-08

### Changed
- `AGENTS.md` (line ~312) and `agents/conductor.md` (line ~107) now
  reference `~/.degacore/scripts/orch-run.sh` instead of
  `~/.claude/scripts/orch-run.sh`, matching every other doc
  (`README.md`, `commands/plan.md`, `agent-template.md`,
  `commands/core-init.md`, `canon/skills/orchestrator.md`) (#300)
  — 2026-05-07

## [0.1.6] — 2026-05-07

Fixes a blocker in `/canon-start --live` where deposit detection never
fired even after the EOA was funded. `scripts/canon-live-readiness.sh`
called `canon-cli balance`, `canon-cli wallet address`, and `canon-cli
onboard --status` without first sourcing `.canon/wallet.env`, so every
balance lookup returned `POLYMARKET_PRIVATE_KEY required` and the poll
loop treated it as zero — the script timed out after 30 minutes with
funds visibly present at the EOA.

### Fixed
- `scripts/canon-live-readiness.sh` now sources `.canon/wallet.env`
  before any `canon-cli` invocation, exports
  `POLYMARKET_PRIVATE_KEY` from `WALLET_PRIVATE_KEY`, and exits early
  with a clear message if no wallet credentials are present. Verified
  end-to-end on a fresh `test-live5` run: deposit detection, Safe
  deployment, V1+V2 approvals, USDC swap, and live runner launch all
  completed.

## [0.1.5] — 2026-05-07

Introduces a venue-agnostic `MarketClient` interface in `canon/templates`
(#251) so non-Polymarket adapters (Kalshi etc.) can be added later without
a rewrite. Phase 1 — interface, Polymarket adapter, and a re-export shim
that preserves the legacy named-function API. No consumer migration
required.

### Added
- `canon/templates/client-market.ts` — `MarketClient` interface, shared
  types, and `getMarketClient()` factory that selects the adapter via the
  `MARKET_VENUE` env var (defaults to `polymarket`)
- `canon/templates/adapters/polymarket.ts` — `PolymarketAdapter implements
  MarketClient`, ports the public market functions from the previous
  monolithic `client-polymarket.ts` (preserves the sidecar workaround for
  `fetchOHLCV` / `watchOrderBook` / `watchTrades`)
- Tests: `canon/templates/__tests__/client-market.test.ts` and
  `canon/templates/__tests__/adapters/polymarket.test.ts`
- `docs/market-client-smoke-test.md` — post-install verification procedure
  across four risk tiers

### Changed
- `canon/templates/client-polymarket.ts` reduced to a re-export shim that
  delegates market methods to a default `getMarketClient()` instance and
  re-exports on-chain helpers from `adapters/polymarket-onchain.ts`. The
  legacy named-function API (`searchMarkets`, `fetchOrderBook`,
  `createOrder`, …) still works unchanged for existing callers.

## [0.1.4] — 2026-05-06

Fixes the install path for the agent-bump Stop hook from #260 so it
fires from any project, not just `claude-code-config`. The 0.1.3
release shipped a `settings.json` entry pointing at
`${CLAUDE_PROJECT_DIR}/hooks/stop/01-orch-notify.sh` (a path that only
resolves inside this repo) and an `apply-core` manifest that did not
include the two new hook scripts at all — so a fresh install from
0.1.3 left the agent-bump non-functional outside of this repo and
silently broken on every Stop event in any other project.

### Fixed
- `settings.json` `hooks.Stop` entry for `01-orch-notify.sh` now uses
  the absolute path `~/.degacore/scripts/hooks/stop/01-orch-notify.sh`,
  matching every other hook in the file (#260 follow-up) — 2026-05-06
- `commands/apply-core.md` manifest now lists
  `hooks/orch-lifecycle/02-agent-notify.sh` and
  `hooks/stop/01-orch-notify.sh`, includes `~/.degacore/scripts/hooks/stop/`
  in the inventory check + `mkdir -p` layout, and adds an explicit
  install step that writes both files to
  `~/.degacore/scripts/hooks/{orch-lifecycle,stop}/` and `chmod +x`s
  them. The Orchestrator component description now mentions the
  agent-bump hooks explicitly so users see what the install adds
  (#260 follow-up) — 2026-05-06

### Notes
- `scripts/test-orch-notify-live.sh` is intentionally **not** in the
  install manifest. It uses `git rev-parse --show-toplevel` and
  references hook paths under the source-repo layout, so it only
  works from a checkout of this repo. It remains available to hook
  developers via `git clone`; end users do not need it.

## [0.1.3] — 2026-05-06

Adds an agent-bump notification mechanism so orchestrator plan
completions surface back to the user automatically on the next
Claude Code turn — no need to ask. Lands a starter library of portable
Claude Code and Codex skills under `skills/{claude,codex}/`. Adds a
repeatable end-to-end test for the notification hook pair so future
changes to the lifecycle/Stop pair can be validated locally before
release.

### Added
- `hooks/orch-lifecycle/02-agent-notify.sh` — writes
  `.orchestrator/notifications/<slug>.json` on terminal events
  (`ship`, `verify` when failed, `revise` when the engine bails). The
  schema is shared with Canon TUI per
  `docs/specs/canon-tui-plan-completion.md` so both consumers can
  read the same files (#260) — 2026-05-06
- `hooks/stop/01-orch-notify.sh` — Stop hook that reads unseen
  notifications, builds a single human-readable message (capped at
  6 detailed entries; remainder summarized), and emits
  `{"decision":"block","reason":"..."}` so the agent surfaces
  "plan X completed: PR Y" on the next turn. Idempotent (marks each
  entry `seen: true` via atomic rewrite); no-op outside this repo
  (#260) — 2026-05-06
- `docs/orch-agent-notifications.md` — user-facing reference for the
  notification mechanism: trigger events, file location, schema,
  Stop-hook behavior, how to disable, and a Testing section linking
  to the bats coverage and the live-test wrapper script
  (#260, #294) — 2026-05-06
- `tests/orch/test_notify_lifecycle.bats` and
  `tests/orch/test_notify_stop_hook.bats` — bats coverage for the
  schema, JSON output, idempotency, and dir-absent no-op
  (#260) — 2026-05-06
- `tests/orch/test_notify_handshake.bats` — end-to-end bats that
  runs both hooks against a single shared fixture (`ship` and
  `verify`-failed paths), so a schema drift between the lifecycle
  hook output and the Stop hook input gets caught (#294) — 2026-05-06
- `scripts/test-orch-notify-live.sh` — wrapper with `unit` /
  `setup` / `status` / `teardown` subcommands that automate the
  manual Claude Code integration check, scoped to this repo's
  `.claude/settings.local.json` so it never touches the global
  config (#294) — 2026-05-06
- `skills/claude/` and `skills/codex/` — eight portable skills
  packaged for both harnesses: `no-edits`, `git-update`, `ls`,
  `make-universal-skill`, `calendar-create-event`, `transcribe-yt`,
  `transcribe-ig`, `word-docx-redlines`. Includes bundled Python
  helpers for transcription and Word Track Changes generation
  (#242) — 2026-05-06

### Changed
- `settings.json` registers `hooks/stop/01-orch-notify.sh` in the
  existing `hooks.Stop` array (after `orch-done-sync.sh`) so the
  agent-bump fires automatically on every Claude Code session
  Stop event (#260) — 2026-05-06
- `README.md` Plugins-and-Skills + Adding-a-Skill sections
  rewritten to distinguish shared `skills/*.md`
  (installer-distributed) from packaged
  `skills/{claude,codex}/<name>/` (manual copy until installer
  support lands), document the per-harness frontmatter contracts,
  and add a privacy/portability scan recipe (#242) — 2026-05-06

## [0.1.2] — 2026-05-05

Closes the canon-tui audit findings (`docs/core-request-pending.md`):
ships the conductor message-aware session start, extends the startup
heartbeat sweep to also reap stale `verifying` plans, lands the
helper script + reference for natural-language version queries, and
unblocks `verify.mode=enforce` on Homebrew-using machines.

### Added
- `CORE_VERSION.md` — natural-language reference for where the version lives, how to read the installed/remote pair, and how the AI should answer "what core version am I on?" — 2026-05-05
- `scripts/core-version.sh` — helper that prints `installed=<x>  latest=<y>  status=<up-to-date|behind|ahead|unknown>` by comparing `~/.degacore/VERSION` against the remote `main` `VERSION` (override with `DEGACORE_VERSION_FILE` / `DEGACORE_REMOTE_REPO`) — 2026-05-05
- `tests/orch/test_verify_path.bats` — regression coverage for the verify-subshell PATH injection — 2026-05-05

### Changed
- Install copies `VERSION` and `CORE_VERSION.md` to `~/.degacore/` and installs `scripts/core-version.sh` to `~/.degacore/scripts/`, so the running install records its release and the AI has the natural-language reference on hand — 2026-05-05
- `agents/conductor.md` `## Session Start` is now a message-aware classifier — Conductor reads the user's first message before doing anything, runs `canon-ctl ping` once, then routes (greeting → full sweep, status request → targeted gather, specific task → address directly, unclear → ask). The unconditional state-sweep table is gone. Operators stop mistrusting the panel for ignoring their input — 2026-05-05

### Fixed
- `scripts/orch-verify.sh` now prepends `/opt/homebrew/bin:/usr/local/bin:/usr/local/sbin` to the `bash -c` subshell's PATH so `rg`, `yq`, `fd` resolve under tmux/launchd subshells where Homebrew is otherwise stripped from `$PATH`. Override the prefix via `ORCH_VERIFY_PATH_PREFIX` (used by tests) — 2026-05-05
- `orch_state_reap_stale` (called from `orch-run.sh` at startup) now also flips stale `verifying` plans to `aborted`, not just `running`. Plans whose engine crashed mid-verify no longer leave canon-tui rendering "● VERIFYING" forever — 2026-05-05

## [0.1.1] — 2026-05-04

Live-mode template fixes uncovered during test-live-4. Strategies now
size signals against a persisted bankroll (init from Polymarket
balance on first live run) and clamp orders against the live wallet
capital — fixing the regression where signals at the config bankroll
were rejected against a much smaller funded balance.

### Added
- `canon/templates/bankroll.ts` — persisted bankroll resolution
  (`--bankroll <amount>` → `.canon/bankroll.json` → dry-run default →
  live init from `positions.reconcile().total_value`). Once persisted
  the value is not auto-updated; operators reset by passing the flag
  again — 2026-05-04
- `canon/templates/risk-clamp.ts` — shared `clampToHeadroom(requested,
  caps[])` primitive that approves at the binding cap (via
  `modified_size`) instead of rejecting, with a fillable-size floor
  for true no-headroom cases — 2026-05-04
- `--bankroll <amount>` flag on all five strategy entry points
  (trade-momentum, arb-binary, arb-negrisk-buy, mm-premium,
  fair-value) — 2026-05-04
- Live-wallet capital floor in every `risk.ts`: aggregate exposure can
  never exceed `portfolio.total_value`, so the strategy will not
  submit orders the wallet cannot cover even when the persisted
  bankroll is stale — 2026-05-04

### Changed
- All five strategies now use `clampToHeadroom` for per-position,
  aggregate, and live-capital caps; signals over a cap are clamped via
  `modified_size` rather than rejected outright — 2026-05-04
- Strategy signal sizing reads `config.bankroll` consistently, mutated
  at runtime from `.canon/bankroll.json` — 2026-05-04

### Fixed
- Execution log path doubling — every strategy's `entry.ts` was
  passing `.canon/execution` as `baseDir`, producing
  `.canon/execution/.canon/execution/YYYY-MM-DD.jsonl`. Now passes the
  project root; the `runner.ts` `.replace(/\/execution$/, "")`
  band-aid is removed — 2026-05-04
- Bankroll-vs-portfolio mismatch where signals sized from
  `config.bankroll` (\$10k default) were rejected by the risk checker
  against a `portfolio.total_value` of \$9.83 — every order rejected
  during live-test-4 — 2026-05-04
- arb-negrisk-buy approving zero-size bundles when `netEdge ≤ 0`; now
  rejected explicitly with a Kelly-no-edge reason — 2026-05-04

## [0.1.0] — 2026-05-04

First formal versioned release. Captures the install-procedure restoration,
template-side wallet-store relocation, and the install/runtime correctness
fixes shipped tonight (#284–#287), on top of every prior `[Unreleased]`
entry below.

### Added
- canon-cli onboard chain — Polymarket gasless deploy + V1+V2 approvals + EIP-2612 permit + Uniswap swap + Onramp wrap (`20260503-polymarket-onboarding`) — 2026-05-03
- `/canon-start --live` transition flow — deposit → onboard → live runner; idempotent (`20260503-polymarket-onboarding`) — 2026-05-03
- `scripts/canon-live-readiness.sh` — Phase 8 spine for the live transition (`20260503-polymarket-onboarding`) — 2026-05-03
- Templates-side `FileWalletStore` in `canon/templates/wallet-store.ts` (#282) — 2026-05-04
- Orchestrator status watchdog — engine EXIT/INT/TERM trap, `orch_state_reap_stale` heartbeat reaper, per-item stale detection (#282) — 2026-05-03
- canon-start Step 0 pre-flight — unconditional `canon-ctl screen.show_state` action before phase logic (#282) — 2026-05-04

### Changed
- Restore `commands/apply-core.md` to the full 819-line agentic install procedure (was reduced to a 25-line circular pointer in #229) (#284) — 2026-05-04
- canon-cli launcher → shell wrapper invoking local `tsx` instead of direct `.ts` symlink (#287) — 2026-05-04
- Strategy entry.ts files use static `import { FileWalletStore }` instead of dynamic cross-package import (#282) — 2026-05-04
- Runner log strings drop the literal "Cycle" word — `SCAN #N` instead of `SCAN Cycle N` (#285) — 2026-05-04

### Fixed
- `@polymarket/builder-signing-sdk` declared as a direct dep in `canon/templates/package.json` (was only present transitively, broke fresh-scaffold runtime imports) (#286) — 2026-05-04
- `~/.degacore/canon-cli/node_modules/canon-templates` retargeted post-install to `~/.degacore/canon/templates/` (the `file:../templates` resolution mismatch between source and install layout) (#287) — 2026-05-04
- Manifest gaps in `commands/apply-core.md` for the 12 days of files added since the deprecation: `commands/canon-start.md`, `commands/core-update.md`, `scripts/canon-live-readiness.sh`, `canon/cli/env.ts`, `canon/cli/commands/index.ts` (#284) — 2026-05-04

### Added
- Make orch detached-by-default; add `--attach` (`20260427-orch-detach-default`) — 2026-04-28

- Add missing gh-plan scripts to /apply-core install manifest (`20260324-apply-core-gh-scripts`) — 2026-03-24

- Create GitHub Issue when plan is written, not when orch starts (`20260324-issue-on-plan-create`) — 2026-03-24

- Orchestrator creates PR on SHIP with linked branch (`20260320-orch-ship-pr`) — 2026-03-21

- Orchestrator auto-creates GitHub Issue for local plans (`20260320-orch-auto-issue`) — 2026-03-21

### Changed
- MINT-01 simple mint cycle (Group 2 — Minting & Market Making) (`20260430-mint-01-cycle-v3`) — 2026-04-30

- ARB-01 live-execution completion (Q-2 / Q-3 / Q-4 / Q-5) (`20260430-arb01-live-completion`) — 2026-04-30

- ARB-01 production-ready + shared live executor layer (`20260429-arb01-live-executor`) — 2026-04-29

- MarketClient abstraction (Phase 1 — interface + adapter, no consumer migration) (`20260428-market-client-abstraction`) — 2026-04-28

- Extract gh-push-and-pr.sh (`20260427-extract-gh-push-and-pr`) — 2026-04-27

- Wire Strategy Templates into Canon Start Pipeline (`20260415-wire-templates`) — 2026-04-16

- ARB-01 Binary Arbitrage Scanner (`20260414-arb-01`) — 2026-04-16

- Canon CLI — Agent-Callable Trading Tools (`20260414-canon-cli`) — 2026-04-14

- Polymarket Trading Execution Pipeline (`20260414-polymarket-trading-pipeline`) — 2026-04-14

- Polymarket Trading Client (`20260413-polymarket-trading-client`) — 2026-04-14

- RPA DoraHacks — Multi-Account Session Management (`20260404-rpa-multi-account`) — 2026-04-04

- RPA DoraHacks — Neon DB Migration (`20260404-rpa-neon-migration`) — 2026-04-04

- Migrate timeline from JSON to GitHub Issues + Milestones (`20260403-timeline-migration`) — 2026-04-04

- DoraHacks Listing for Canon Hackathon (`dorahacks-listing`) — 2026-04-02

- Complete GH audit trail with work summaries, feedback, and verify results (`20260325-gh-audit-trail`) — 2026-03-25

- Skip git-tracked plan artifacts when github.sync is true (`20260325-gh-mode-skip-local-artifacts`) — 2026-03-25

- Development Patterns Skill System (`20260321-development-patterns-skill`) — 2026-03-21

- Agent-to-panel integration — Claude controls the GitHub panel (`20260321-agent-panel-integration`) — 2026-03-21

- Redesign GitHub panel — PM dashboard with status and timeline (`20260320-gh-panel-redesign`) — 2026-03-21

- Agent-controlled panels + direct conductor launch (`20260320-agent-panel-control`) — 2026-03-21

- Verify issue body sync works end-to-end (`20260320-verify-body-sync`) — 2026-03-21

- Sync issue body — check off progress log and completion criteria (`20260320-issue-body-sync`) — 2026-03-21

- Conductor TUI — Toad Fork + GitHub Project State (`20260320-project-state-tui`) — 2026-03-21

- GitHub Issues as Plan System (`20260320-github-issues-plans`) — 2026-03-21

- Clear SHIP completion — state, dashboard, and session cleanup (`20260315-fix-orch-ship-completion`) — 2026-03-15

- Autonomous planner loop — long-running agent that plans and executes (`20260315-planner-loop`) — 2026-03-15

- Rename ralph.yaml to dega-core.yaml (`20260315-config-and-state-cleanup`) — 2026-03-15

- Dashboard viewport uses flexGrow for adaptive sizing (`20260315-dashboard-viewport-flexgrow`) — 2026-03-15

- Self-development guide (`20260315-self-development-guide`) — 2026-03-15

### Fixed
- Fix deprecated local-plan-flow in agent prompts (`20260428-agent-prompts-flow`) — 2026-04-28

- Fix CI pipeline — shellcheck severity and excluded codes (`20260321-fix-ci-pipeline`) — 2026-03-27

- Fix sound interface bug in orch-engine.sh (`20260324-fix-sound-bug`) — 2026-03-24

- Fix shebang inconsistency across scripts and hooks (`20260324-fix-shebang`) — 2026-03-24

- Fix GitHub panel — agent-summoned and repo-aware (`20260320-fix-gh-panel-design`) — 2026-03-21

- Fix orchestrator review quality — reject partial completions (`20260320-orch-review-quality`) — 2026-03-21

- Fix SHIP flow — don't close issue until PR merges (`20260320-fix-ship-close-flow`) — 2026-03-21

- Workshop Prep — Install Fixes, Ralph Cleanup, Merge to Develop (`20260319-workshop-prep`) — 2026-03-20

- Fix orch worktree commits stalling on pre-commit hooks (`20260315-fix-orch-worktree-hooks`) — 2026-03-16

- Fix orch scripts to work when installed globally (`20260315-fix-orch-global-paths`) — 2026-03-15

- Fix apply-core to include all orchestrator and planner files (`20260315-fix-apply-core-orch-files`) — 2026-03-15


### Removed
- Delete diagnostic debris and stale worktrees (`20260324-delete-diagnostic-debris`) — 2026-03-24

## 2026-03-15

### Changed

- AI plan registry (`20260315-ai-plan-registry`)
- Orch clean dashboard exit on SHIP (`20260315-orch-clean-exit`)
- Orch completion criteria gate (`20260315-orch-completion-criteria-gate`)
- Orch done-file validation (`20260315-orch-donefile-validation`)
- Orch fullscreen terminal window (`20260315-orch-fullscreen-terminal`)
- Orch persist engine logs on SHIP (`20260315-orch-persist-logs`)
- Orch progress resilience on failure (`20260315-orch-progress-resilience`)
- Orch worktree plan isolation (`20260315-orch-worktree-plan-isolation`)

## 2026-03-14

### Changed

- Dashboard Live Worker Output (`20260314-orch-dashboard-live-output`)
- Dashboard Terminal Viewport (`20260314-orch-dashboard-terminal-viewport`)
- Fire-and-Forget Orchestrator Launch (`20260314-orch-fire-and-forget`)
- Multi-Plan Orchestration with Master State (`20260314-orch-multi-plan`)
- Parallel Per-Item Review (`20260314-orch-parallel-review`)
- Reviewer Dashboard Visibility (`20260314-orch-reviewer-dashboard-visibility`)

### Fixed

- Dashboard Rendering Fixes (`20260314-orch-dashboard-rendering`)
- Orch/Ralph quick fixes (`20260314-orch-quick-fixes`)

## 2026-03-13

### Changed

- Orchestrator Cleanup (`20260313-orch-cleanup`)
- Orchestrator Full Auto — One Command Does Everything (`20260313-orch-full-auto`)
- Orchestrator Stale Worker Detection (`20260313-orch-stale-worker-detection`)
- Orchestrator Visibility Layer (`20260313-orch-visibility`)

### Fixed

- Fix ralph-loop.sh sed multiline substitution bug (`20260313-ralph-sed-bug`)
- Verify ralph-loop.sh sed fix (`20260313-ralph-sed-verify`)

## 2026-03-10

### Changed

- Orchestrator Tmux Execution Engine (`20260310-orch-tmux-rebuild`)

## 2026-03-09

### Changed

- Orchestrator Smoke Test (`20260309-orch-smoke-test`)
- [DEPRECATED] Hybrid Orchestrator: State Layer + Agent Teams Execution (`20260309-hybrid-orch`)

## 2026-03-08

### Changed

- Orchestrator End-to-End — Polling Loop + Review Integration (`20260308-orch-e2e`)

## 2026-03-07

### Changed

- Orchestrator Agent — Multi-Plan Conductor (`20260307-orchestrator`)
- Orchestrator Hardening — Per-Item Scoping + Single State File (`20260307-orch-hardening`)
- Review-Advance — Per-Item Reviewer Loop (`20260307-review-advance`)

## 2026-03-06

### Changed

- Core Init Command (`20260306-core-init`)
- Docs Update (`20260306-docs-update`)
- Parallel Ralph Loops via Worktrees (`20260306-parallel-worktrees`)
- Post-Demo Cleanup (`20260306-post-demo-cleanup`)

### Fixed

- Fix Ralph Loop Reviewer Not Writing review-result.txt (`20260306-ralph-reviewer-fix`)

## 2026-03-03

### Changed

- /canon-start Command (`20260303-canon-start-command`)
- Demo Prep — March 5 Canon Demo (`20260303-demo-prep`)
- Exec-Plan Naming Enforcement (`20260303-exec-plan-naming-enforcement`)
- Ink Status Dashboard (terminal-ui) (`20260303-ink-status-dashboard`)
- Terminal UI Wiring (End-to-End) (`20260303-terminal-ui-wiring`)
- tmux Session Launcher (`20260303-tmux-session-launcher`)

## 2026-03-02

### Changed

- Demo Prep — Canon Init Flow for March 5 Recording (`20260302-demo-prep`)

## Pre-dating

### Added

- Add ralph loop command hint to /plan hand-off (`plan-ralph-hint`)
- Add shfmt Formatting Check to CI (`shfmt-ci`)

### Changed

- Build /apply-canon Command (`apply-canon-command`)
- Canon Agent Framework Artifacts (`canon-agent-framework`)
- Canon Init — Project-Local Model (`canon-init`)
- Cross-Platform Sound Hooks (WSL2 + Linux) (`sound-hooks-linux`)
- Demo S1 — Sports Arb Strategy Repo Bootstrap (`demo-s1-strategy-repo`)
- Demo S2 — pmxt + Sportsbook API Scaffolding (`demo-s2-pmxt-scaffold`)
- Demo S3 — Sports Arb Strategy Build (The Demo Moment) (`demo-s3-sports-arb`)
- Full Ralph Loop Implementation (`ralph-loop`)
- Harness Gap 7 — App-Legibility Skill (`harness-gap7-app-legibility-skill`)
- Logging Infrastructure — Persistent Server + Ralph Event Logging (`logging-infrastructure`)
- Logging Integration (`logging-integration`)
- Ralph Loop Global Install (`ralph-global-install`)
- Ralph Loop Sound Behavior (`ralph-loop-sounds`)
- Ralph S1 — Per-Item Loop (`ralph-s1-per-item-loop`)
- Ralph S2 — Enforcement (`ralph-s2-enforcement`)
- Ralph S3 — Reliability (`ralph-s3-reliability`)
- Ralph S4 — Structured Logging (`ralph-s4-logging`)
- Ralph S5 — Context Handoff (`ralph-s5-context-handoff`)
- Resume Test (Multi-Step Interrupt/Resume Smoke Test) (`resume-test`)
- Sound Hooks on Task Completion (`sound-hooks`)
- Terminal UI State File Spec (`terminal-ui-state-spec`)
- Test (Exec-Plan Lifecycle Smoke Test) (`test`)

### Fixed

- Add date prefix to exec-plan slugs (`plan-date-prefix`)
- Fix apply-core — install ralph loop scripts per repo (`apply-core-ralph-install`)

### Removed

- Remove ralph-check.sh from global Stop hook (`remove-global-ralph-check`)

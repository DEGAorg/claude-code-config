# Canon live smoke from a develop checkout

Run an end-to-end live cycle of a strategy template **straight from your
local `develop` checkout**, before merging anything to `main`. The
agentic flow (`/canon-init`, `/canon-start --live`, Conductor) picks up
the develop templates because we point `~/.degacore/canon/templates` at
the checkout via a reversible symlink.

Use case: smoke-test unreleased template work (e.g. a new `runCycle`,
allowance flow, signal change) on a real chain with a small bankroll
before promoting via the develop → main release PR.

---

## Prerequisites

- A clone of `claude-code-config` on the branch you want to test
  (usually `develop`).
- `/apply-core` has run at least once on this machine so
  `~/.degacore/` is populated.
- A wallet you've onboarded for live trading (`.canon/wallet.env`
  present in the project, or `canon-cli onboard --execute` runnable).
- Enough USDC.e on Polygon to cover `cycleCapital` (set a tiny value
  below — $10–$50 is plenty for a smoke).

---

## 1. Point the global install at develop

From inside the `claude-code-config` clone, on the branch you want to
test:

```bash
bash scripts/dev-link-canon-templates.sh link
bash scripts/dev-link-canon-templates.sh check
```

You should see `OK:` on the install symlink, the `canon-cli`
`node_modules` link, and the develop sentinel (`mint-cycle-helpers.ts`
visible through the link). The script backs up the existing real
`~/.degacore/canon/templates/` snapshot to a timestamped sibling and
records state to `~/.degacore/.canon-templates-dev-link.json` for
revert.

Subsequent edits on `develop` (or the branch you have checked out) are
immediately visible to anything that reads
`~/.degacore/canon/templates/` — no re-copy step needed.

---

## 2. Scaffold a fresh smoke project

A fresh project picks up develop's templates wholesale; an existing
scaffolded project still has its own copy of the older templates under
`src/` and would need a re-scaffold or manual sync.

```bash
mkdir -p ~/canon-smoke && cd ~/canon-smoke
```

Open Claude Code in this directory (`claude` from the terminal, or your
IDE). Then in the Conductor session:

```
/canon-init
```

Conductor walks the scaffold. When it asks for a strategy template,
pick the one you're smoke-testing (e.g. `MINT-01`, `MINT-04`,
`ARB-01`, `TRADE-02`).

Confirm the develop code landed in `src/`:

```bash
ls src/cycle.ts src/scan.ts src/entry.ts 2>/dev/null
# Sentinel grep — adjust for the strategy you picked. MINT-01:
grep -lE 'runCycle|mint-cycle-helpers' src/cycle.ts && echo "develop code in place"
```

---

## 3. Configure wallet and safety knobs

`canon-cli` writes `.canon/wallet.env` during onboarding. If it's
absent:

```bash
ls .canon/wallet.env 2>/dev/null || canon-cli onboard --execute
```

Drop the cycle capital to a small amount **before going live**.
Strategy-specific:

```bash
# MINT-01
sed -i.bak 's/cycleCapital: 1_000/cycleCapital: 25/' src/config.ts

# MINT-04 (mm-premium)
sed -i.bak 's/cycleCapital: 1_000/cycleCapital: 25/' src/config.ts

# ARB-01 / TRADE-02 — different shape; see src/config.ts for the
# bankroll / kelly fraction knobs that bound exposure.
```

The `.bak` suffix is your revert path. Restore with
`mv src/config.ts.bak src/config.ts`.

Optional environment overrides:

```bash
export POLYGON_RPC_URL=https://polygon.drpc.org   # or your preferred RPC
export POLL_INTERVAL_MS=30000                     # scanner poll, not cycle fill-poll
```

The MINT cycle fill-poll defaults to 300_000ms (5 min) since the
2026-05-12 Q1 review; override via the strategy's own config if you
want tighter detection.

---

## 4. Run live, agentically

In the same Claude Code session, from the smoke project root:

```
/canon-start --live
```

Conductor takes the live-mode short-circuit and invokes
`canon-runner.sh --live`, which exec's `pnpm tsx src/main.ts --live`.

Watch the runner log in another terminal:

```bash
tail -f .canon/execution/runner.log
```

Expected sequence for the MINT cycle loops (similar shape for ARB / TRADE):

1. `START <strategy> cycle (live)`
2. **Two USDC.e allowance approval txs on first run** — CTF Exchange
   spender and ConditionalTokens spender. Subsequent runs skip if the
   cached allowance is above threshold.
3. `mint_set` event with the `splitPosition` tx hash.
4. `cycle_start` event with two CLOB order IDs (sell-YES + sell-NO).
5. `cycle_fill` events on partial / full fills, OR
6. `cycle_stop_loss` if YES midpoint drifts > 5¢ from entry, OR
7. `cycle_reconcile` after the 24h `maxCycleDurationMs` timeout —
   any unfilled legs are cancelled, filled legs stay realized.

If anything stalls or throws, kill the runner (`Ctrl-C` in the
Conductor session, or `kill $(cat .canon/execution/runner.pid)`),
inspect `.canon/execution/runner.log` and the JSONL execution log,
fix on develop, and re-run. The symlink picks up your edits
immediately — no copy step.

---

## 5. Cleanup

After the smoke is done (success or fail):

```bash
# In the smoke project — revert the cycleCapital edit
mv src/config.ts.bak src/config.ts 2>/dev/null || true

# Back in the claude-code-config clone
cd /path/to/claude-code-config
bash scripts/dev-link-canon-templates.sh revert
bash scripts/dev-link-canon-templates.sh check   # should FAIL — back to /apply-core snapshot
```

The revert removes the symlink and restores the backup directory at
`~/.degacore/canon/templates/`. The state file
(`~/.degacore/.canon-templates-dev-link.json`) is deleted.

If you want to keep the smoke project around for the next test, you
can leave it — re-running `link` later will pick up whatever branch
you have checked out at link time.

---

## Troubleshooting

- **`check` reports the develop sentinel is missing** — your branch
  doesn't have the file the script checks for
  (`canon/templates/mint-cycle-helpers.ts`). Either you're on a branch
  predating the MINT cycle work, or the symlink is pointing somewhere
  unexpected. Run `readlink ~/.degacore/canon/templates` to inspect.
- **`canon-cli` still uses old code** — the `canon-cli` package
  resolves `canon-templates` through
  `~/.degacore/canon-cli/node_modules/canon-templates`, which is a
  symlink to `~/.degacore/canon/templates`. The dev-link script
  preserves that chain; if it got broken, re-run `link`.
- **First run hangs on allowance approval** — both USDC.e allowance
  txs need to confirm before the first `splitPosition` fires. RPC
  congestion can stretch this. Bump `POLYGON_RPC_URL` to a faster
  endpoint and retry.
- **`getOrder` rate-limit errors** — the fill-poll runs at 300s by
  default. If you've dropped it via `deps.fillPollIntervalMs`, raise
  it back. CLOB rate ceilings hit faster when multiple cycles run
  concurrently.
- **`splitPosition` reverts** — usually means the ConditionalTokens
  allowance is missing or below the cycle amount. Check the second
  allowance client landed during link (run `check`) and that the
  approval tx hash from step 4.2 actually confirmed on-chain.

---

## When to ship

A clean cycle on this smoke = green light to merge the release PR
(`develop → main`). Don't skip the revert step — leaving a symlinked
install lets stale develop edits leak into normal `canon-cli` runs.

# Tech Debt

Single index of known debt. Severity is P1 (blocks something soon), P2
(annoys but works), P3 (cosmetic). Append; don't reorder. When fixed,
delete the entry.

---

## Stale `docs/exec-plans/` references

**Severity:** P2
**Area:** harness docs + config
**Logged:** 2026-05-03
**Context:** Plans now live as GitHub issues with `plan:draft`; the
orchestrator fetches them at run time. The `docs/exec-plans/` directory
is fully deprecated, but several files still point at it as the
canonical location.

**Live references to remove or rewrite:**

- `README.md:537` — `orch-run.sh` example uses `docs/exec-plans/active/...` as the plan path.
- `AGENTS.md:101` — directory map row: `` `docs/exec-plans/` | Execution plans: `active/` (in progress), `completed/` (archived), `tech-debt.md` ``.
- `AGENTS.md:174` — milestones table row referencing `docs/exec-plans/`.
- `AGENTS.md:215` — "Versioned specs at Stage 2 (`docs/exec-plans/active/`)".
- `AGENTS.md:259` — "log follow-ups to `docs/exec-plans/tech-debt.md`" — also points at this file's old home.
- `docs/conductor-agent-design.md:38` — table row: `` Active plans | `docs/exec-plans/active/` ``.
- `docs/self-development.md:31,42,76,85` — describes a flow that `mv`s plans between `active/` and `completed/`.
- `canon/AGENTS.md:67-69` — canon harness inheritance line listing `docs/exec-plans/`.
- `dega-core.yaml:50-53` — `success_criteria` `exec-plan-dirs` checks `docs/exec-plans/active/` (passes vacuously today; remove).
- `skills/tech-debt-tracking.md:11,17` — points debt index + per-item files at `docs/exec-plans/tech-debt.md` and `docs/exec-plans/tech-debt/`. Should point at `docs/tech-debt.md`.

**Fix:** one PR rewrites every reference to either drop the path or point
at the GitHub-issue flow / `docs/tech-debt.md`. No code changes.

---

## Missing `docs/agent-operating-mode.md`

**Severity:** P3
**Area:** harness docs
**Logged:** 2026-05-03
**Context:** `AGENTS.md:259` instructs agents to read
`docs/agent-operating-mode.md` for default operating rules. The file
does not exist in the repo.

**Fix:** either write the doc (canonising the rules already in `AGENTS.md`)
or remove the broken pointer. Bundle with the `docs/exec-plans/` cleanup
above.

---

## Polymarket SDK trips Cloudflare bot challenge by default

**Severity:** P2
**Area:** `canon/templates` Polymarket integration
**Logged:** 2026-05-03
**Context:** `@polymarket/clob-client-v2` (and the older
`@polymarket/clob-client`) ship with a default User-Agent of
`@polymarket/clob-client`. Cloudflare's WAF in front of
`clob.polymarket.com` matches that pattern as automated and 403s every
cold call from a Node process. Hit this consistently during the
2026-05-03 live test until we overrode the UA.

**Workaround in place:** `canon/templates/clob-axios-defaults.ts`
mutates `axios.defaults.headers.common["User-Agent"]` to a Mozilla
string. Side-effect imported from `client-polymarket.ts` and
`polymarket-onboard.ts` before any SDK loads.

**Fix:** file an upstream issue with Polymarket. Two viable upstream
fixes: (a) whitelist `@polymarket/*` UAs in their CF rules, or (b) ship
the SDK with a non-bot-pattern UA by default. Until then keep our
override; track via env `CLOB_USER_AGENT` if their rules change shape.

---

## `clob-client-v2.getContractConfig(137)` returns V1 + V2 spenders without distinction

**Severity:** P2
**Area:** `canon/templates/polymarket-onboard.ts`
**Logged:** 2026-05-03
**Context:** The config object returned by
`@polymarket/clob-client-v2`'s `getContractConfig(137)` exposes both
the legacy V1 (`exchange`, `negRiskExchange`) and post-April-2026 V2
(`exchangeV2`, `negRiskExchangeV2`) addresses with no semantic
distinction. Easy to use only V1 and have the onboarding chain succeed
while V2 markets reject orders with
`the allowance is not enough -> spender: <V2 address>`.

Verified live 2026-05-03 — initial implementation only approved V1,
NegRisk markets failed at the matcher.

**Fix:** `polymarket-onboard.ts:ensureApprovals()` must include both V1
and V2 spenders. Tracked as item 1 of the four follow-ups in
[`docs/handoff-live-trade02.md`](handoff-live-trade02.md).

---

## pmxt-core 2.37 over-paginates `fetchMarkets({limit:N})` without a query

**Severity:** P3
**Area:** `canon/templates/__tests__/integration.test.ts`
**Logged:** 2026-05-03
**Context:** `pmxt-core ≥ 2.37` paginates `fetchMarkets({limit: N})`
calls (no `query` parameter) up to ~1.25M rows internally before
returning, which never completes within reasonable test timeouts.
Strategy code always passes a query so live paths are unaffected, but
the integration `read-only` suite hits this on its `beforeAll` and was
skipped.

**Fix:** rewrite the integration fixture to pass a query, or wait for
pmxt-core to stop pre-paginating without a search term. Re-enable the
suite when fixed.

---

## Old POC wallet has unresolved security issues

**Severity:** P1 (security hygiene)
**Area:** local dev environment
**Logged:** 2026-05-03
**Context:** PK `0x89be…744` / EOA `0x7b2d23fd…fC8C` has three
problems: (1) hard-banned by the Polymarket CLOB matcher, (2)
EIP-7702-delegated to `0x3ae1f70cf6da80955936f5599d103fcf62162d10`
of unknown origin, (3) leaked across 13+ local `.env` files.

**Fix:** see [`docs/security-old-poc-wallet.md`](security-old-poc-wallet.md)
on the `orch/281-...` branch for the full write-up + mitigation steps.
Stop using this PK; rotate it out; investigate the delegation
contract; clean up the `.env` leakage.

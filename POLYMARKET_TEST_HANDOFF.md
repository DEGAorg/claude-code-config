# Polymarket Integration Test — Session Handoff

Handoff doc to continue in a new Claude Code session from inside
`/Users/cerratoa/dega/aidd/claude-code-config`.

## Goal

Get working, tested Polymarket integration code in Canon Automations and the
base templates. Operate as autonomously as possible; only ask the user for
input on items that genuinely require a human decision (wallet/auth, real-money
approval).

## Context carried over from prior session

- Prior conversation was in `/Users/cerratoa/dega/canon-docs` (docs-only repo,
  no code).
- User clarified the actual code lives under a `canon/` directory — which
  exists here at `/Users/cerratoa/dega/aidd/claude-code-config/canon/`.
- Base templates and Canon Automations referenced by the user are expected to
  be inside this repo — confirm by exploring `canon/` and anywhere else that
  references `pmxt` / `polymarket`.

## Key findings from the docs repo (for reference, don't re-research)

Pulled from `/Users/cerratoa/dega/canon-docs`:

### Wallet / auth model

- **No dedicated wallet-security pattern doc exists.** `specs/SAS_Security_Future.md:75`
  explicitly scopes private-key / wallet management **out** of the general
  security model.
- `specs/SAS_UI_Collaboration.md:263` mentions a "Secrets Wallet" UI concept
  (Doppler / `pass`-backed) for exchange API keys — not seeds.
- `Canon_Managed_Agents_Research.md:14,193` — wallet keys must stay local
  (cannot traverse Anthropic infra).
- `Canon_DEGA_Token_Integration.md:223` — wallet security scoped out of the
  certification network.

### Polymarket auth reality (important)

- **API-key-only auth is NOT sufficient for order placement.** Polymarket CLOB
  requires **EIP-712 per-order signing** (`Prediction_Sets_Protocol.md:213-219`).
- Polymarket "API credentials" (L2 keys) are derived from an L1 signature and
  authenticate requests, but each order payload still needs an EIP-712
  signature from the signing EOA.
- Current Canon pattern (`Canon_Polymarket_Automation_Guide.md:60-63`):
  ```python
  exchange = pmxt.Polymarket(
      private_key=os.getenv('POLYMARKET_PRIVATE_KEY'),
      proxy_address=os.getenv('POLYMARKET_PROXY_ADDRESS')
  )
  ```
  → user's private key in env vars, plus the proxy wallet address.
- Workshop 3 flags this as unvalidated:
  `hackathon/workshops/session-3/workshop3-demo-scope.md:62,85,112`.
- Safer pattern described for SetVault only (not documented as a general Canon
  MCP pattern): `Prediction_Sets_Protocol.md:227-236` — Gnosis Safe where user
  EOA is owner, Safe holds USDC, executor keys scoped to
  `placeOrder` / `cancelOrder` only (no withdraw).

### pmxt status

- `Canon_Polymarket_Automation_Guide.md` reads as **aspirational** (docs say
  `pip install pmxt` / `npm install pmxtjs`).
- Prior session memory note: "pmxt/RPA not started."
- **Verify first** whether the `canon/` directory here actually uses a real
  `pmxt` package, a vendored local copy, or calls `py-clob-client` directly.
  If pmxt is vendored/partial, the autonomous path is probably to go direct to
  `py-clob-client` (Polymarket's official SDK) for the test spike.

## Recommended plan (pending user confirmation on auth only)

1. **Explore** `canon/` inside `claude-code-config/` — find Polymarket-related
   code, base templates, any existing test harness. Also grep for `pmxt`,
   `polymarket`, `py-clob` across the whole repo.
2. **Identify** what already works vs. what's stubbed. Report a short punch list.
3. **Stand up a minimal smoke test**:
   - Fetch a live market list.
   - Fetch order book for one market.
   - Construct + sign a tiny limit order far from mid (no fill).
   - Cancel it.
   - Teardown.
4. **Environment:** Polygon mainnet with ~$5 USDC in a burner EOA. Amoy
   testnet is an option but has thin/no real markets, so mainnet-tiny is more
   realistic.
5. **Wire the validated flow into the base templates** once the smoke test
   passes.
6. **Do not** add abstraction, fallbacks, or speculative config. Bug fix / test
   spike only (per global CLAUDE.md: no premature abstraction, no speculative
   features).

## What to ask the user (only these)

- Which is preferred for the smoke test:
  1. User provides an existing funded burner EOA private key + Polymarket
     proxy address, OR
  2. Agent generates a fresh burner wallet and user funds it with ~$5 USDC
     on Polygon mainnet.
- Are we OK placing a real (tiny, far-from-mid, immediately-cancelled) order
  on mainnet, or does the user want strict read-only for the first pass?

Everything else — SDK install, market fetch, signing, cancel, teardown, wiring
to templates, tests — proceed autonomously.

## Open gap worth flagging (not blocking this task)

No Canon doc currently describes a "user pre-authorizes via Safe / session
keys so the MCP never touches their seed" pattern as a general MCP convention.
Prior session offered to draft one in `specs/` next to `SAS_Security_Future.md`
— user did not yet accept. Revisit after the smoke test works.

## Repo pointers

- This repo (code + config): `/Users/cerratoa/dega/aidd/claude-code-config`
- Docs repo (reference only): `/Users/cerratoa/dega/canon-docs`
- Sibling repos that may also contain Polymarket code if `canon/` here turns
  out to be empty of it: `nba-strategy`, `sports-arb`, `test-arb*`, `canon-tui`,
  `core-test`, `dega`.

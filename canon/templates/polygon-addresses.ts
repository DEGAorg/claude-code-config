/**
 * Pinned Polygon mainnet contract addresses used by the live executor.
 *
 * Polymarket settles in USDC.e (the bridged variant, not native USDC).
 * Order placement requires the trading EOA to approve USDC.e spending
 * by both the CTF Exchange (standard markets) and the NegRisk CTF
 * Exchange (negative-risk multi-outcome markets).
 *
 * Sources verified 2026-04-30:
 *   - canon/skills/polymarket.md (project-internal canonical reference)
 *   - https://docs.polymarket.com/ (CLOB/CTF contracts page)
 *
 * USDC.e is being deprecated in favour of native USDC across Polygon
 * dApps, but Polymarket has not migrated. Pin the bridged address
 * explicitly so a future native-USDC migration is a deliberate code
 * change, not a silent surprise. See `docs/reviews/261-open-questions.md`
 * Q-3.
 */

/** Polygon PoS mainnet chain id. */
export const POLYGON_CHAIN_ID = 137;

/** Bridged USDC (USDC.e) — Polymarket's settlement token. */
export const USDC_E_ADDRESS = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";

/** Polymarket CTF Exchange — standard binary markets. */
export const CTF_EXCHANGE_ADDRESS =
  "0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E";

/** Polymarket NegRisk CTF Exchange — negative-risk multi-outcome markets. */
export const NEG_RISK_CTF_EXCHANGE_ADDRESS =
  "0xC5d563A36AE78145C45a50134d48A1215220f80a";

/**
 * Default spender for ARB-01 allowance flows. ARB-01 trades binary YES/NO
 * pairs, which clear through the standard CTF Exchange.
 */
export const DEFAULT_ALLOWANCE_SPENDER = CTF_EXCHANGE_ADDRESS;

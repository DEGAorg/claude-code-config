/**
 * Typed wrapper around the pmxtjs Polymarket client.
 *
 * All prediction-market data flows through these functions.
 * Strategy code never touches the pmxtjs SDK directly.
 */

import { Polymarket } from "pmxtjs";
import { getWalletPrivateKey, getWalletProxyAddress } from "./env.js";
import {
  callSidecar,
  getSidecarCapabilities,
  type SidecarCapabilities,
} from "./sidecar.js";

/** YES/NO price snapshot for a Polymarket condition. */
export interface MarketPrice {
  conditionId: string;
  yes: number;
  no: number;
  timestamp: Date;
}

/** A Polymarket market search result. */
export interface PolymarketMatch {
  conditionId: string;
  question: string;
  yesPrice: number;
  noPrice: number;
  yesTokenId: string;
  noTokenId: string;
  resolutionDate?: string;
}

/** A single leg (outcome) of a multi-outcome Polymarket market. */
export interface MultiOutcomeLeg {
  /** Human-readable outcome label (e.g. "Lakers"). */
  outcome: string;
  /** CLOB token ID for this leg's YES outcome. */
  tokenId: string;
  /** Last-known YES price. */
  yesPrice: number;
}

/** A multi-outcome (>2 outcomes) Polymarket market — NegRisk candidate. */
export interface MultiOutcomeMatch {
  conditionId: string;
  question: string;
  legs: MultiOutcomeLeg[];
}

/**
 * Snapshot of a binary market with the time-series fields strategies
 * like TRADE-02 momentum and IA-03 fair-value need.
 *
 * `topWalletShare` is not surfaced by the pmxt SDK; it is set to 0
 * here. Strategies that depend on the manipulation guard should plug in
 * an on-chain indexer (Phase 2/3 work) and override this value.
 */
/**
 * Raw market shape returned by the pmxt sidecar's `fetchMarkets`
 * endpoint. We type only the fields the read paths consume; the
 * sidecar surfaces additional fields (eventId, tags, image, …) that we
 * do not currently use. Bypassing the SDK's `Polymarket(...)` wrapper
 * means dry-run reads work without wallet creds — only order
 * submission goes through the authenticated path.
 */
interface RawSidecarMarket {
  marketId: string;
  title: string;
  outcomes: {
    outcomeId?: string;
    label: string;
    price?: number;
  }[];
  volume24h?: number;
  openInterest?: number;
  resolutionDate?: string;
}

export interface BinaryMarketSnapshot {
  conditionId: string;
  question: string;
  yesTokenId: string;
  noTokenId: string;
  /** Last-known YES price (probability). */
  yesPrice: number;
  /** Last-known NO price (probability). */
  noPrice: number;
  /** 24-hour USD volume. */
  volume24h: number;
  /** Open interest in USD. */
  openInterest: number;
  /** Milliseconds until market close, or `undefined` when not surfaced. */
  timeToCloseMs?: number;
  /** Snapshot timestamp (ms since epoch). */
  timestampMs: number;
}

/** A single price level in an order book. */
export interface PriceLevel {
  price: number;
  size: number;
}

/** Order book for a single outcome token. */
export interface OrderBook {
  tokenId: string;
  bids: PriceLevel[];
  asks: PriceLevel[];
}

/** A current position in a Polymarket market. */
export interface Position {
  marketId: string;
  outcomeId: string;
  outcomeLabel: string;
  size: number;
  entryPrice: number;
  currentPrice: number;
  unrealizedPnL: number;
}

/** Account balance entry for a Polymarket account. */
export interface AccountBalance {
  currency: string;
  total: number;
  available: number;
  locked: number;
}

/** On-chain balance entry with product metadata for the user. */
export interface OnChainBalance {
  /** Display symbol (e.g. "USDC.e", "USDC", "POL"). */
  currency: string;
  /** Token contract address, or "native" for POL. */
  address: string;
  /** Human-readable balance (decimal-adjusted). */
  amount: number;
  /** True if this token can be used directly on Polymarket. */
  tradeable: boolean;
  /** Optional hint for the user about what to do with this balance. */
  note?: string;
}

/** Assets swap-to-usdce supports on Polygon. */
export type SwapSource = "USDC" | "USDT" | "POL";

/** Result of a swap-to-USDC.e on-chain transaction. */
export interface SwapResult {
  from: SwapSource;
  amountIn: number;
  amountOut: number;
  txHash: string;
  approveTxHash?: string;
}

/** A single trade from the authenticated user's trade history. */
export interface UserTrade {
  id: string;
  price: number;
  amount: number;
  side: string;
  timestamp: number;
  orderId?: string;
  outcomeId?: string;
  marketId?: string;
}

/** Parameters for filtering trade history. */
export interface FetchMyTradesParams {
  marketId?: string;
  limit?: number;
  cursor?: string;
}

/** OHLCV price candle from the pmxt sidecar. */
export interface PriceCandle {
  timestamp: number;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number | null;
}

/** Options for fetchOHLCV. */
export interface FetchOHLCVOptions {
  timeframe?: string;
}

/** Order book snapshot from the pmxt sidecar. */
export interface SidecarOrderBook {
  bids: PriceLevel[];
  asks: PriceLevel[];
  timestamp: number | null;
}

/** A single trade from the pmxt sidecar. */
export interface Trade {
  id: string;
  price: number;
  size: number;
  side: string;
  timestamp: number;
}

let client: Polymarket | undefined;

/**
 * Resolve the Polymarket signatureType for the SDK.
 *
 * Defaults to `'gnosis-safe'` when a proxy address is supplied (modern
 * Polymarket accounts use a Gnosis Safe proxy that holds funds — without
 * this hint the SDK falls back to EOA-style L2 derivation and dies with
 * "Derived credentials are incomplete"). Falls back to undefined (SDK
 * default) when no proxy is configured. Operators can override via
 * `POLYMARKET_SIGNATURE_TYPE` (`'eoa' | 'poly-proxy' | 'gnosis-safe'`).
 *
 * Reference: pmxt-dev/pmxt SETUP_POLYMARKET.md
 *   github.com/pmxt-dev/pmxt/blob/main/core/docs/SETUP_POLYMARKET.md
 */
function resolveSignatureType(
  proxyAddress: string | undefined,
): "eoa" | "poly-proxy" | "gnosis-safe" | undefined {
  const override = process.env["POLYMARKET_SIGNATURE_TYPE"];
  if (override === "eoa" || override === "poly-proxy" || override === "gnosis-safe") {
    return override;
  }
  return proxyAddress ? "gnosis-safe" : undefined;
}

function getClient(): Polymarket {
  if (!client) {
    const privateKey = getWalletPrivateKey();
    const proxyAddress = getWalletProxyAddress();
    const signatureType = resolveSignatureType(proxyAddress);

    client = new Polymarket({
      ...(privateKey ? { privateKey } : {}),
      ...(proxyAddress ? { proxyAddress } : {}),
      ...(signatureType ? { signatureType } : {}),
      autoStartServer: true,
    });
  }
  return client;
}

/**
 * Fetch the current YES/NO price snapshot for a Polymarket condition.
 *
 * @param conditionId - Polymarket condition ID (the market's unique identifier).
 */
export async function fetchMarketPrice(
  conditionId: string,
): Promise<MarketPrice> {
  const poly = getClient();
  let markets = await poly.fetchMarkets({ query: conditionId });
  let market = markets[0];

  // Text search may not match numeric marketIds; fall back to
  // fetching recent markets and filtering by ID.
  if (!market) {
    markets = await poly.fetchMarkets({ limit: 100 });
    market = markets.find(
      (m) => String(m.marketId) === String(conditionId),
    );
  }

  if (!market) {
    throw new Error(`Market ${conditionId} not found`);
  }

  if (market.outcomes.length !== 2) {
    throw new Error(
      `Market ${conditionId} is not a binary market ` +
        `(${String(market.outcomes.length)} outcomes)`,
    );
  }

  const yesPrice = market.outcomes[0]?.price;
  const noPrice = market.outcomes[1]?.price;

  if (yesPrice === undefined || noPrice === undefined) {
    throw new Error(
      `Market ${conditionId} missing outcome prices ` +
        `(yes=${String(yesPrice)}, no=${String(noPrice)})`,
    );
  }

  return {
    conditionId: market.marketId,
    yes: yesPrice,
    no: noPrice,
    timestamp: new Date(),
  };
}

/**
 * Search Polymarket for markets matching a query string.
 *
 * Returns binary YES/NO markets with current prices. Non-binary markets
 * (missing YES or NO price) are filtered out.
 *
 * @param query - Search text (e.g. "NBA", "Warriors Celtics").
 */
export async function searchMarkets(
  query: string,
): Promise<PolymarketMatch[]> {
  const poly = getClient();
  const markets = await poly.fetchMarkets({ query });
  const results: PolymarketMatch[] = [];

  for (const m of markets) {
    // Polymarket outcomes use descriptive labels (e.g. "Indiana Pacers" /
    // "Not Indiana Pacers"), not "Yes"/"No". Any 2-outcome market is
    // binary: first outcome = affirmative, second = negative.
    if (m.outcomes.length !== 2) continue;
    const yesOutcome = m.outcomes[0];
    const noOutcome = m.outcomes[1];
    if (!yesOutcome || !noOutcome) continue;
    if (yesOutcome.price === undefined || noOutcome.price === undefined) continue;

    const resDate = m.resolutionDate?.toISOString();
    results.push({
      conditionId: m.marketId,
      question: m.title,
      yesPrice: yesOutcome.price,
      noPrice: noOutcome.price,
      yesTokenId: yesOutcome.outcomeId,
      noTokenId: noOutcome.outcomeId,
      ...(resDate !== undefined ? { resolutionDate: resDate } : {}),
    });
  }

  return results;
}

/**
 * Search Polymarket for multi-outcome (>2) markets matching a query.
 *
 * Returns markets whose `outcomes.length > 2` — the necessary structural
 * condition for a NegRisk multi-condition arb. The pmxt SDK does not
 * currently surface the `neg_risk` event flag, so callers must treat the
 * result as a NegRisk *candidate* and apply their own confirmation
 * (e.g. resolve every leg's order book and check Σ yes_ask < 1 — the
 * sufficient market-driven test).
 *
 * @param query - Search text (e.g. "NBA Champion").
 */
export async function searchMultiOutcomeMarkets(
  query: string,
): Promise<MultiOutcomeMatch[]> {
  const markets = await callSidecar<RawSidecarMarket[]>("fetchMarkets", [
    { query },
  ]);
  const results: MultiOutcomeMatch[] = [];

  for (const m of markets) {
    if (m.outcomes.length <= 2) continue;
    const legs: MultiOutcomeLeg[] = [];
    let skip = false;
    for (const o of m.outcomes) {
      if (o.price === undefined || o.outcomeId === undefined) {
        skip = true;
        break;
      }
      legs.push({ outcome: o.label, tokenId: o.outcomeId, yesPrice: o.price });
    }
    if (skip) continue;
    results.push({
      conditionId: m.marketId,
      question: m.title,
      legs,
    });
  }

  return results;
}

/**
 * Fetch binary-market snapshots matching a query.
 *
 * Returns volume / open-interest / time-to-close enriched snapshots that
 * `TRADE-02` momentum and `IA-03` fair-value scanners consume directly.
 * `topWalletShare` is not exposed by the SDK — strategies that rely on
 * manipulation guards must layer their own data source.
 *
 * @param query - Search text (e.g. "NBA").
 */
export async function fetchBinaryMarketSnapshots(
  query: string,
): Promise<BinaryMarketSnapshot[]> {
  const markets = await callSidecar<RawSidecarMarket[]>("fetchMarkets", [
    { query },
  ]);
  const now = Date.now();
  const results: BinaryMarketSnapshot[] = [];

  for (const m of markets) {
    if (m.outcomes.length !== 2) continue;
    const yesOutcome = m.outcomes[0];
    const noOutcome = m.outcomes[1];
    if (!yesOutcome || !noOutcome) continue;
    if (yesOutcome.price === undefined || noOutcome.price === undefined) {
      continue;
    }
    if (yesOutcome.outcomeId === undefined || noOutcome.outcomeId === undefined) {
      continue;
    }
    const closeMs =
      m.resolutionDate !== undefined ? Date.parse(m.resolutionDate) : NaN;
    const timeToCloseMs = Number.isFinite(closeMs)
      ? Math.max(0, closeMs - now)
      : undefined;
    results.push({
      conditionId: m.marketId,
      question: m.title,
      yesTokenId: yesOutcome.outcomeId,
      noTokenId: noOutcome.outcomeId,
      yesPrice: yesOutcome.price,
      noPrice: noOutcome.price,
      volume24h: m.volume24h ?? 0,
      openInterest: m.openInterest ?? 0,
      ...(timeToCloseMs !== undefined ? { timeToCloseMs } : {}),
      timestampMs: now,
    });
  }

  return results;
}

/**
 * Fetch the current order book for a Polymarket outcome token.
 *
 * @param tokenId - CLOB token ID (from `market.outcomes[n].outcomeId`).
 */
export async function fetchOrderBook(tokenId: string): Promise<OrderBook> {
  const book = await callSidecar<{
    bids: { price: number; size: number }[];
    asks: { price: number; size: number }[];
  }>("fetchOrderBook", [tokenId]);

  const mapLevel = (l: { price: number; size: number }): PriceLevel => ({
    price: l.price,
    size: l.size,
  });

  return {
    tokenId,
    bids: book.bids.map(mapLevel),
    asks: book.asks.map(mapLevel),
  };
}

/**
 * Fetch current positions for the authenticated Polymarket account.
 *
 * Requires `WALLET_PRIVATE_KEY` to be set. Auth errors from
 * pmxtjs propagate to the caller.
 */
export async function fetchPositions(): Promise<Position[]> {
  const poly = getClient();
  const positions = await poly.fetchPositions();

  return positions.map((p) => ({
    marketId: p.marketId,
    outcomeId: p.outcomeId,
    outcomeLabel: p.outcomeLabel,
    size: p.size,
    entryPrice: p.entryPrice,
    currentPrice: p.currentPrice,
    unrealizedPnL: p.unrealizedPnL,
  }));
}

/**
 * Fetch account balances for the authenticated Polymarket account.
 *
 * Requires `WALLET_PRIVATE_KEY` to be set. Auth errors from
 * pmxtjs propagate to the caller.
 */
export async function fetchBalance(): Promise<AccountBalance[]> {
  const poly = getClient();
  const balances = await poly.fetchBalance();

  return balances.map((b) => ({
    currency: b.currency,
    total: b.total,
    available: b.available,
    locked: b.locked,
  }));
}

/**
 * Fetch on-chain balances for the authenticated EOA on Polygon.
 *
 * Returns USDC.e (tradeable), native USDC (swap needed), and POL (gas).
 * This is the user-facing balance — what `canon-cli balance` should show.
 *
 * Requires `WALLET_PRIVATE_KEY`. Uses a public Polygon RPC.
 */
export async function fetchOnChainBalances(): Promise<OnChainBalance[]> {
  const privateKey = getWalletPrivateKey();
  if (!privateKey) throw new Error("WALLET_PRIVATE_KEY required");

  const { ethers } = await import("ethers");
  const rpc = process.env["POLYGON_RPC_URL"] ?? "https://polygon.drpc.org";
  const provider = new ethers.providers.StaticJsonRpcProvider(
    rpc,
    { name: "polygon", chainId: 137 },
  );
  const address = new ethers.Wallet(privateKey).address;

  const USDC_E = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
  const USDC_NATIVE = "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359";
  const abi = ["function balanceOf(address) view returns (uint256)"];
  const usdcE = new ethers.Contract(USDC_E, abi, provider);
  const usdcNative = new ethers.Contract(USDC_NATIVE, abi, provider);

  const [polRaw, usdcERaw, usdcNativeRaw] = await Promise.all([
    provider.getBalance(address),
    usdcE["balanceOf"](address),
    usdcNative["balanceOf"](address),
  ]);

  const fmt6 = (v: { toString(): string }): number =>
    Number(ethers.utils.formatUnits(v.toString(), 6));
  const fmt18 = (v: { toString(): string }): number =>
    Number(ethers.utils.formatUnits(v.toString(), 18));

  const out: OnChainBalance[] = [
    {
      currency: "USDC.e",
      address: USDC_E,
      amount: fmt6(usdcERaw),
      tradeable: true,
    },
  ];

  const nativeAmt = fmt6(usdcNativeRaw);
  if (nativeAmt > 0) {
    out.push({
      currency: "USDC",
      address: USDC_NATIVE,
      amount: nativeAmt,
      tradeable: false,
      note: "native USDC — swap to USDC.e to trade on Polymarket",
    });
  }

  const USDT_ADDR = "0xc2132D05D31c914a87C6611C10748AEb04B58e8F";
  const usdt = new ethers.Contract(USDT_ADDR, abi, provider);
  const usdtRaw = (await usdt["balanceOf"](address)) as { toString(): string };
  const usdtAmt = fmt6(usdtRaw);
  if (usdtAmt > 0) {
    out.push({
      currency: "USDT",
      address: USDT_ADDR,
      amount: usdtAmt,
      tradeable: false,
      note: "swap to USDC.e to trade on Polymarket",
    });
  }

  out.push({
    currency: "POL",
    address: "native",
    amount: fmt18(polRaw),
    tradeable: false,
    note: "for gas; excess can be swapped to USDC.e",
  });

  return out;
}

const SWAP_ROUTER = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45";
const UNISWAP_QUOTER_V2 = "0x61fFE014bA17989E743c5F6cB21bF9697530B21e";
const USDC_E_ADDR = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
const WPOL_ADDR = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";

interface SwapRoute {
  tokenIn: string;
  decimals: number;
  /** Fee tiers to try in order — first one with a quote wins. */
  feeCandidates: readonly number[];
  isNative: boolean;
}

const SWAP_ROUTES: Record<SwapSource, SwapRoute> = {
  USDC: {
    tokenIn: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359",
    decimals: 6,
    feeCandidates: [100, 500],
    isNative: false,
  },
  USDT: {
    tokenIn: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F",
    decimals: 6,
    feeCandidates: [100, 500, 3000],
    isNative: false,
  },
  POL: {
    tokenIn: WPOL_ADDR,
    decimals: 18,
    feeCandidates: [3000, 500, 10000],
    isNative: true,
  },
};

/**
 * Swap a supported asset (native USDC, USDT, or POL) to USDC.e on Uniswap v3.
 *
 * Required because Polymarket's CTFExchange only accepts USDC.e. Users who
 * fund the burner with native USDC / USDT / excess POL need a one-call
 * conversion path. Approves the swap router if allowance is insufficient.
 * Slippage tolerance is 0.5% (configurable via SWAP_SLIPPAGE_BPS env var).
 *
 * @param from - Source asset symbol.
 * @param amountIn - Amount to swap in human units (e.g. 5 = 5 USDC).
 */
export async function swapToUsdce(
  from: SwapSource,
  amountIn: number,
): Promise<SwapResult> {
  if (amountIn <= 0) throw new Error(`amountIn must be > 0, got ${amountIn}`);
  const privateKey = getWalletPrivateKey();
  if (!privateKey) throw new Error("WALLET_PRIVATE_KEY required");

  const route = SWAP_ROUTES[from];
  const slippageBps = Number(process.env["SWAP_SLIPPAGE_BPS"] ?? "50");
  if (!Number.isFinite(slippageBps) || slippageBps < 0 || slippageBps > 1000) {
    throw new Error(`SWAP_SLIPPAGE_BPS invalid: ${String(slippageBps)}`);
  }

  const { ethers } = await import("ethers");
  const rpc = process.env["POLYGON_RPC_URL"] ?? "https://polygon.drpc.org";
  const provider = new ethers.providers.StaticJsonRpcProvider(
    rpc,
    { name: "polygon", chainId: 137 },
  );
  const signer = new ethers.Wallet(privateKey, provider);

  const amountInRaw = ethers.utils.parseUnits(
    amountIn.toFixed(route.decimals),
    route.decimals,
  );

  const block = await provider.getBlock("latest");
  const baseFee = block.baseFeePerGas ?? ethers.utils.parseUnits("50", "gwei");
  const tip = ethers.utils.parseUnits("30", "gwei");
  const feeOpts = {
    maxPriorityFeePerGas: tip,
    maxFeePerGas: baseFee.mul(2).add(tip),
  };

  let approveTxHash: string | undefined;
  if (!route.isNative) {
    const erc20 = new ethers.Contract(
      route.tokenIn,
      [
        "function allowance(address,address) view returns (uint256)",
        "function approve(address,uint256) returns (bool)",
      ],
      signer,
    );
    const allow = (await erc20["allowance"](
      signer.address,
      SWAP_ROUTER,
    )) as { lt(other: unknown): boolean };
    if (allow.lt(amountInRaw)) {
      const approveTx = (await erc20["approve"](
        SWAP_ROUTER,
        ethers.constants.MaxUint256,
        { ...feeOpts, gasLimit: 100_000 },
      )) as { hash: string; wait(): Promise<unknown> };
      approveTxHash = approveTx.hash;
      await approveTx.wait();
    }
  }

  // Find a pool with liquidity and fetch a real quote via QuoterV2 staticCall.
  const quoter = new ethers.Contract(
    UNISWAP_QUOTER_V2,
    [
      "function quoteExactInputSingle((address tokenIn,address tokenOut,uint256 amountIn,uint24 fee,uint160 sqrtPriceLimitX96)) returns (uint256 amountOut,uint160,uint32,uint256)",
    ],
    provider,
  );
  let chosenFee = 0;
  let expectedOut: { toString(): string; mul(n: number): { div(n: number): unknown }} | undefined;
  for (const fee of route.feeCandidates) {
    try {
      const quoteFn = quoter.callStatic["quoteExactInputSingle"];
      if (!quoteFn) throw new Error("quoteExactInputSingle not on contract");
      const result = (await quoteFn({
        tokenIn: route.tokenIn,
        tokenOut: USDC_E_ADDR,
        amountIn: amountInRaw,
        fee,
        sqrtPriceLimitX96: 0,
      })) as readonly [{ toString(): string; mul(n: number): { div(n: number): unknown } }];
      const [amountOut] = result;
      chosenFee = fee;
      expectedOut = amountOut;
      break;
    } catch {
      continue;
    }
  }
  if (chosenFee === 0 || !expectedOut) {
    throw new Error(
      `No Uniswap v3 pool found for ${from} → USDC.e (tried fees ${route.feeCandidates.join(", ")})`,
    );
  }
  const minOut = expectedOut.mul(10_000 - slippageBps).div(10_000);

  const router = new ethers.Contract(
    SWAP_ROUTER,
    [
      "function exactInputSingle((address,address,uint24,address,uint256,uint256,uint160)) payable returns (uint256)",
    ],
    signer,
  );
  const params = [
    route.tokenIn,
    USDC_E_ADDR,
    chosenFee,
    signer.address,
    amountInRaw,
    minOut,
    0,
  ];
  const usdcE = new ethers.Contract(
    USDC_E_ADDR,
    ["function balanceOf(address) view returns (uint256)"],
    provider,
  );
  const beforeRaw = (await usdcE["balanceOf"](signer.address)) as {
    toString(): string;
  };

  const swapTx = (await router["exactInputSingle"](params, {
    ...feeOpts,
    ...(route.isNative ? { value: amountInRaw } : {}),
    gasLimit: 300_000,
  })) as { hash: string; wait(): Promise<{ logs: unknown[] }> };
  await swapTx.wait();

  const afterRaw = (await usdcE["balanceOf"](signer.address)) as {
    toString(): string;
  };
  const before = Number(ethers.utils.formatUnits(beforeRaw.toString(), 6));
  const after = Number(ethers.utils.formatUnits(afterRaw.toString(), 6));
  const amountOut = Number((after - before).toFixed(6));

  return {
    from,
    amountIn,
    amountOut,
    txHash: swapTx.hash,
    ...(approveTxHash !== undefined ? { approveTxHash } : {}),
  };
}

/**
 * Fetch trade history for the authenticated Polymarket account.
 *
 * Requires `WALLET_PRIVATE_KEY` to be set. Auth errors from
 * pmxtjs propagate to the caller.
 *
 * @param params - Optional filtering/pagination parameters.
 */
export async function fetchMyTrades(
  params?: FetchMyTradesParams,
): Promise<UserTrade[]> {
  const poly = getClient();
  const trades = await poly.fetchMyTrades(params);

  return trades.map(
    (t: {
      id: string;
      price: number;
      amount: number;
      side: string;
      timestamp: number;
      orderId?: string;
      outcomeId?: string;
      marketId?: string;
    }): UserTrade => ({
      id: t.id,
      price: t.price,
      amount: t.amount,
      side: t.side,
      timestamp: t.timestamp,
      ...(t.orderId !== undefined ? { orderId: t.orderId } : {}),
      ...(t.outcomeId !== undefined ? { outcomeId: t.outcomeId } : {}),
      ...(t.marketId !== undefined ? { marketId: t.marketId } : {}),
    }),
  );
}

/**
 * Fetch all open orders for the authenticated Polymarket account.
 *
 * Requires `WALLET_PRIVATE_KEY` to be set. Auth errors from
 * pmxtjs propagate to the caller.
 *
 * @param marketId - Optional market ID to filter orders.
 */
export async function fetchOpenOrders(
  marketId?: string,
): Promise<OrderResponse[]> {
  const poly = getClient();
  const orders = await poly.fetchOpenOrders(marketId);
  return orders.map(
    (o: {
      id: string;
      marketId: string;
      outcomeId: string;
      side: "buy" | "sell";
      type: "market" | "limit";
      amount: number;
      price?: number;
      status: string;
      filled: number;
      remaining: number;
    }): OrderResponse => ({
      id: o.id,
      marketId: o.marketId,
      outcomeId: o.outcomeId,
      side: o.side,
      type: o.type,
      amount: o.amount,
      price: o.price ?? 0,
      status: o.status,
      filled: o.filled,
      remaining: o.remaining,
    }),
  );
}

/**
 * Time-in-force semantics for limit orders.
 *
 * - "GTC" — good-til-cancelled (default for plain limits).
 * - "IOC" — immediate-or-cancel; partial fills allowed, remainder cancelled.
 * - "FOK" — fill-or-kill; full size fills atomically or the whole order cancels.
 *
 * The templates layer forwards this as `tif` on the sidecar's
 * `createOrder` payload. Use {@link getCapabilities} to verify the
 * running sidecar supports time-in-force before relying on FOK
 * semantics — older sidecars silently ignore the field.
 */
export type TimeInForce = "GTC" | "IOC" | "FOK";

/** Parameters for creating or building an order. */
export interface OrderParams {
  marketId: string;
  tokenId: string;
  side: "buy" | "sell";
  size: number;
  price: number;
  orderType: "market" | "limit";
  /** Optional time-in-force; only meaningful for `orderType === "limit"`. */
  timeInForce?: TimeInForce;
}

/** Order response from createOrder. */
export interface OrderResponse {
  id: string;
  marketId: string;
  outcomeId: string;
  side: "buy" | "sell";
  type: "market" | "limit";
  amount: number;
  price: number;
  status: string;
  filled: number;
  remaining: number;
}

/** Result of a cancelOrder call — sparse response from the exchange. */
export interface CancelResult {
  id: string;
  status: string;
}

/** Dry-run result from buildOrder. */
export interface BuildOrderResult {
  exchange: string;
  params: {
    marketId: string;
    outcomeId: string;
    side: string;
    type: string;
    amount: number;
    price: number;
  };
  signedOrder?: Record<string, unknown>;
  raw: unknown;
}

const VALID_SIDES = ["buy", "sell"] as const;
const VALID_ORDER_TYPES = ["market", "limit"] as const;

function validateOrderParams(params: OrderParams): void {
  if (params.price < 0 || params.price > 1) {
    throw new Error(
      `Invalid price ${String(params.price)}: ` +
        "must be between 0 and 1",
    );
  }
  if (params.size <= 0) {
    throw new Error(
      `Invalid size ${String(params.size)}: ` +
        "must be greater than 0",
    );
  }
  if (!VALID_SIDES.includes(params.side)) {
    throw new Error(
      `Invalid side "${String(params.side)}": ` +
        "must be \"buy\" or \"sell\"",
    );
  }
  if (!VALID_ORDER_TYPES.includes(params.orderType)) {
    throw new Error(
      `Invalid orderType "${String(params.orderType)}": ` +
        "must be \"market\" or \"limit\"",
    );
  }
}

/**
 * Create a new order on the exchange.
 *
 * Validates price (0-1) and size (> 0) before delegating to pmxtjs.
 *
 * @param params - Order parameters.
 */
export async function createOrder(
  params: OrderParams,
): Promise<OrderResponse> {
  validateOrderParams(params);
  const privateKey = getWalletPrivateKey();
  if (!privateKey) throw new Error("WALLET_PRIVATE_KEY required");
  const order = await callSidecar<{
    id: string;
    marketId: string;
    outcomeId: string;
    side: "buy" | "sell";
    type: "market" | "limit";
    amount: number;
    price?: number;
    status: string;
    filled: number;
    remaining: number;
  }>(
    "createOrder",
    [{
      marketId: params.marketId,
      outcomeId: params.tokenId,
      side: params.side,
      type: params.orderType,
      amount: params.size,
      price: params.price,
      ...(params.timeInForce !== undefined
        ? { tif: params.timeInForce }
        : {}),
    }],
    { privateKey, signatureType: "eoa" },
  );
  return {
    id: order.id,
    marketId: order.marketId,
    outcomeId: order.outcomeId,
    side: order.side,
    type: order.type,
    amount: order.amount,
    price: order.price ?? params.price,
    status: order.status,
    filled: order.filled,
    remaining: order.remaining,
  };
}

/**
 * Cancel an existing order.
 *
 * @param orderId - The order ID to cancel.
 */
export async function cancelOrder(
  orderId: string,
): Promise<CancelResult> {
  const privateKey = getWalletPrivateKey();
  if (!privateKey) throw new Error("WALLET_PRIVATE_KEY required");
  const order = await callSidecar<{ id?: string; status?: string }>(
    "cancelOrder",
    [orderId],
    { privateKey, signatureType: "eoa" },
  );
  return {
    id: order.id ?? orderId,
    status: order.status ?? "cancelled",
  };
}

/**
 * Build an order payload without submitting.
 *
 * Validates params (same as createOrder) before delegating to pmxtjs.
 *
 * @param params - Order parameters.
 */
export async function buildOrder(
  params: OrderParams,
): Promise<BuildOrderResult> {
  validateOrderParams(params);
  const privateKey = getWalletPrivateKey();
  if (!privateKey) throw new Error("WALLET_PRIVATE_KEY required");
  const built = await callSidecar<{
    exchange: string;
    params: {
      marketId: string;
      outcomeId: string;
      side: string;
      type: string;
      amount: number;
      price?: number;
    };
    signedOrder?: Record<string, unknown>;
    raw: unknown;
  }>(
    "buildOrder",
    [{
      marketId: params.marketId,
      outcomeId: params.tokenId,
      side: params.side,
      type: params.orderType,
      amount: params.size,
      price: params.price,
      ...(params.timeInForce !== undefined
        ? { tif: params.timeInForce }
        : {}),
    }],
    { privateKey, signatureType: "eoa" },
  );
  return {
    exchange: built.exchange,
    params: {
      marketId: built.params.marketId,
      outcomeId: built.params.outcomeId,
      side: built.params.side,
      type: built.params.type,
      amount: built.params.amount,
      price: built.params.price ?? params.price,
    },
    ...(built.signedOrder !== undefined
      ? { signedOrder: built.signedOrder }
      : {}),
    raw: built.raw,
  };
}

/**
 * Query the running pmxt sidecar for advertised feature flags.
 *
 * Used by `--live` start-up gates to refuse to run when the sidecar
 * cannot honour required semantics (e.g. FOK time-in-force).
 */
export async function getCapabilities(): Promise<SidecarCapabilities> {
  return getSidecarCapabilities();
}

// ---------------------------------------------------------------------------
// Sidecar-dependent methods
// ---------------------------------------------------------------------------
// These methods bypass the pmxtjs SDK to work around the header-clobbering
// bug in pmxtjs v2.22.1. They call the pmxt sidecar HTTP API directly via
// the callSidecar helper.

/**
 * Fetch OHLCV candle data for a Polymarket outcome token.
 *
 * Uses the pmxt sidecar directly (SDK header-clobbering workaround).
 *
 * @param tokenId - CLOB token ID for the outcome.
 * @param options - Optional parameters (e.g. timeframe).
 */
export async function fetchOHLCV(
  tokenId: string,
  options?: FetchOHLCVOptions,
): Promise<PriceCandle[]> {
  const resolved = {
    resolution: options?.timeframe ?? "1h",
  };
  return callSidecar<PriceCandle[]>("fetchOHLCV", [tokenId, resolved]);
}

/**
 * Watch the order book for a Polymarket outcome token.
 *
 * Uses the pmxt sidecar directly (SDK header-clobbering workaround).
 * Returns a snapshot with bids, asks, and a nullable timestamp.
 *
 * @param tokenId - CLOB token ID for the outcome.
 */
export async function watchOrderBook(
  tokenId: string,
): Promise<SidecarOrderBook> {
  return callSidecar<SidecarOrderBook>("watchOrderBook", [tokenId]);
}

/**
 * Watch recent trades for a Polymarket outcome token.
 *
 * Uses the pmxt sidecar directly (SDK header-clobbering workaround).
 * May block until a trade occurs on low-activity markets.
 *
 * @param tokenId - CLOB token ID for the outcome.
 */
export async function watchTrades(
  tokenId: string,
): Promise<Trade[]> {
  return callSidecar<Trade[]>("watchTrades", [tokenId]);
}

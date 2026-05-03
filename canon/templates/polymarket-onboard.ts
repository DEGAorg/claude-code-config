/**
 * Polymarket onboarding adapter — venue-agnostic OnboardClient impl.
 *
 * Wraps `@polymarket/builder-relayer-client` (gasless Safe deploy + batched
 * Safe approvals) and `@polymarket/clob-client-v2` (CLOB API credentials).
 *
 * Spender list and collateral token are read from `getContractConfig(137)` at
 * runtime — never hard-coded — so a Polymarket-side migration (e.g.
 * USDC.e → pUSD) is picked up by upgrading the SDK rather than by editing
 * this file. A malformed config surfaces as an actionable error rather than
 * silently using stale defaults.
 */
import { Contract, Wallet, providers } from "ethers";
import {
  RelayClient,
  deriveSafe,
} from "@polymarket/builder-relayer-client";
import type { Transaction } from "@polymarket/builder-relayer-client";
// `getContractConfig` lives at @polymarket/builder-relayer-client/dist/config
// and is not re-exported from the package root in 0.0.9. Pull it via the
// namespace and cast — vitest's `vi.mock("@polymarket/builder-relayer-client")`
// still replaces the whole module at runtime.
import * as builderRelayer from "@polymarket/builder-relayer-client";
import {
  ClobClient,
  getContractConfig as getClobContractConfig,
} from "@polymarket/clob-client-v2";
import type { Chain } from "@polymarket/clob-client-v2";
import type {
  OnboardClient,
  OnboardStatus,
} from "./types/OnboardClient.js";
import type { MarketVenueOnboard } from "./types/MarketVenueOnboard.js";

const POLYGON_CHAIN_ID = 137;
const RELAYER_URL =
  process.env["POLYMARKET_RELAYER_URL"] ??
  "https://relayer-v2.polymarket.com";
const CLOB_HOST =
  process.env["POLYMARKET_CLOB_HOST"] ?? "https://clob.polymarket.com";
const POLYGON_RPC_URL =
  process.env["POLYGON_RPC_URL"] ?? "https://polygon-rpc.com";

const COLLATERAL_DECIMALS = 6;
const MAX_UINT256: bigint = (1n << 256n) - 1n;
// Half of MaxUint256 — anything below this counts as "needs re-approve" so the
// idempotency check is robust against minor allowance burn.
const ALLOWANCE_THRESHOLD: bigint = MAX_UINT256 / 2n;

const APPROVE_SELECTOR = "0x095ea7b3";
const SET_APPROVAL_FOR_ALL_SELECTOR = "0xa22cb465";

const ERC20_ABI = [
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address owner) view returns (uint256)",
];
const ERC1155_ABI = [
  "function isApprovedForAll(address account, address operator) view returns (bool)",
];

interface BigNumberLike {
  toBigInt: () => bigint;
}

function asBigInt(value: unknown): bigint {
  if (typeof value === "bigint") return value;
  if (
    typeof value === "object" &&
    value !== null &&
    typeof (value as BigNumberLike).toBigInt === "function"
  ) {
    return (value as BigNumberLike).toBigInt();
  }
  throw new TypeError(
    `polymarket-onboard: expected BigNumber-like, got ${typeof value}`,
  );
}

function pad32(hex: string): string {
  return hex.replace(/^0x/, "").toLowerCase().padStart(64, "0");
}

function encodeApprove(spender: string, amount: bigint): string {
  return APPROVE_SELECTOR + pad32(spender) + pad32(amount.toString(16));
}

function encodeSetApprovalForAll(operator: string, approved: boolean): string {
  return (
    SET_APPROVAL_FOR_ALL_SELECTOR +
    pad32(operator) +
    pad32(approved ? "1" : "0")
  );
}

interface ClobAddresses {
  exchange: string;
  negRiskExchange: string;
  negRiskAdapter: string;
  collateral: string;
  conditionalTokens: string;
}

interface ClobConfigShape {
  exchange?: string;
  negRiskExchange?: string;
  negRiskAdapter?: string;
  collateral?: string;
  conditionalTokens?: string;
}

function loadClobAddresses(): ClobAddresses {
  const cfg = getClobContractConfig(POLYGON_CHAIN_ID) as ClobConfigShape;
  if (!cfg?.exchange) {
    throw new Error(
      "polymarket-onboard: clob getContractConfig() returned an invalid config — missing 'exchange' spender. Refusing to proceed with stale defaults.",
    );
  }
  if (!cfg.negRiskExchange || !cfg.negRiskAdapter) {
    throw new Error(
      "polymarket-onboard: clob getContractConfig() returned an invalid config — missing negRiskExchange/negRiskAdapter spender.",
    );
  }
  if (!cfg.conditionalTokens) {
    throw new Error(
      "polymarket-onboard: clob getContractConfig() returned an invalid config — missing 'conditionalTokens' address.",
    );
  }
  if (!cfg.collateral) {
    throw new Error(
      "polymarket-onboard: clob getContractConfig() returned an invalid config — missing 'collateral' token. Update @polymarket/clob-client-v2 — never hard-code USDC.e vs pUSD.",
    );
  }
  return {
    exchange: cfg.exchange,
    negRiskExchange: cfg.negRiskExchange,
    negRiskAdapter: cfg.negRiskAdapter,
    collateral: cfg.collateral,
    conditionalTokens: cfg.conditionalTokens,
  };
}

interface RelayConfigShape {
  SafeContracts?: { SafeFactory?: string; SafeMultisend?: string };
}

function loadSafeFactory(): string {
  const fn = (
    builderRelayer as unknown as {
      getContractConfig?: (chainId: number) => RelayConfigShape;
    }
  ).getContractConfig;
  if (typeof fn !== "function") {
    throw new Error(
      "polymarket-onboard: @polymarket/builder-relayer-client does not export getContractConfig from the package root — refusing to derive Safe address with no config source.",
    );
  }
  const cfg = fn(POLYGON_CHAIN_ID);
  const safeFactory = cfg?.SafeContracts?.SafeFactory;
  if (!safeFactory) {
    throw new Error(
      "polymarket-onboard: relayer getContractConfig() returned an invalid config — missing 'SafeContracts.SafeFactory'. Refusing to derive Safe address from stale defaults.",
    );
  }
  return safeFactory;
}

interface AllowanceContract {
  allowance(owner: string, spender: string): Promise<unknown>;
  balanceOf(owner: string): Promise<unknown>;
}

interface OperatorContract {
  isApprovedForAll(account: string, operator: string): Promise<boolean>;
}

interface RelayerTxLike {
  hash?: string;
  transactionHash?: string;
  wait: () => Promise<
    { transactionHash?: string; status?: number } | undefined
  >;
}

function erc20SpenderList(addr: ClobAddresses): readonly string[] {
  return [
    addr.exchange,
    addr.negRiskExchange,
    addr.negRiskAdapter,
    addr.conditionalTokens,
  ];
}

function erc1155OperatorList(addr: ClobAddresses): readonly string[] {
  return [addr.exchange, addr.negRiskExchange, addr.negRiskAdapter];
}

interface OnboardCtx {
  safeAddress: string;
  // The ethers v5 provider used for read calls. Typed loosely to avoid
  // pinning the impl to a specific subclass.
  provider: providers.Provider;
  relay: RelayClient;
  clob: ClobClient;
}

async function readAllowance(
  ctx: OnboardCtx,
  addr: ClobAddresses,
  spender: string,
): Promise<bigint> {
  const c = new Contract(
    addr.collateral,
    ERC20_ABI,
    ctx.provider,
  ) as unknown as AllowanceContract;
  return asBigInt(await c.allowance(ctx.safeAddress, spender));
}

async function readIsApprovedForAll(
  ctx: OnboardCtx,
  addr: ClobAddresses,
  operator: string,
): Promise<boolean> {
  const c = new Contract(
    addr.conditionalTokens,
    ERC1155_ABI,
    ctx.provider,
  ) as unknown as OperatorContract;
  return c.isApprovedForAll(ctx.safeAddress, operator);
}

async function readCollateralBalance(
  ctx: OnboardCtx,
  addr: ClobAddresses,
): Promise<bigint> {
  const c = new Contract(
    addr.collateral,
    ERC20_ABI,
    ctx.provider,
  ) as unknown as AllowanceContract;
  return asBigInt(await c.balanceOf(ctx.safeAddress));
}

async function statusImpl(ctx: OnboardCtx): Promise<OnboardStatus> {
  const funderDeployed = await ctx.relay.getDeployed(ctx.safeAddress);
  if (!funderDeployed) {
    return {
      funderDeployed: false,
      approvalsReady: false,
      credsReady: false,
      fundedCollateral: 0,
      funderAddress: ctx.safeAddress,
    };
  }
  const addr = loadClobAddresses();
  const erc20Ok = await Promise.all(
    erc20SpenderList(addr).map(
      async (s) => (await readAllowance(ctx, addr, s)) >= ALLOWANCE_THRESHOLD,
    ),
  );
  const erc1155Ok = await Promise.all(
    erc1155OperatorList(addr).map((op) =>
      readIsApprovedForAll(ctx, addr, op),
    ),
  );
  const approvalsReady =
    erc20Ok.every(Boolean) && erc1155Ok.every(Boolean);
  const balance = await readCollateralBalance(ctx, addr);
  const fundedCollateral = Number(balance) / 10 ** COLLATERAL_DECIMALS;
  let credsReady = false;
  try {
    const creds = await ctx.clob.deriveApiKey();
    credsReady = !!(creds?.key && creds.secret && creds.passphrase);
  } catch {
    credsReady = false;
  }
  return {
    funderDeployed: true,
    approvalsReady,
    credsReady,
    fundedCollateral,
    funderAddress: ctx.safeAddress,
  };
}

async function ensureFunderImpl(
  ctx: OnboardCtx,
): Promise<{ deployed: boolean; txHash?: string }> {
  if (await ctx.relay.getDeployed(ctx.safeAddress)) {
    return { deployed: true };
  }
  let tx: RelayerTxLike;
  try {
    tx = (await ctx.relay.deploy()) as unknown as RelayerTxLike;
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(`polymarket-onboard: relayer deploy() failed — ${msg}`);
  }
  const receipt = await tx.wait();
  const txHash = receipt?.transactionHash ?? tx.transactionHash ?? tx.hash;
  return txHash !== undefined
    ? { deployed: true, txHash }
    : { deployed: true };
}

async function ensureApprovalsImpl(
  ctx: OnboardCtx,
): Promise<{ approved: boolean; txHash?: string }> {
  const addr = loadClobAddresses();
  const txs: Transaction[] = [];
  for (const spender of erc20SpenderList(addr)) {
    if ((await readAllowance(ctx, addr, spender)) < ALLOWANCE_THRESHOLD) {
      txs.push({
        to: addr.collateral,
        data: encodeApprove(spender, MAX_UINT256),
        value: "0",
      });
    }
  }
  for (const operator of erc1155OperatorList(addr)) {
    if (!(await readIsApprovedForAll(ctx, addr, operator))) {
      txs.push({
        to: addr.conditionalTokens,
        data: encodeSetApprovalForAll(operator, true),
        value: "0",
      });
    }
  }
  if (txs.length === 0) {
    return { approved: true };
  }
  const tx = (await ctx.relay.execute(
    txs,
    "canon: initial CLOB approvals",
  )) as unknown as RelayerTxLike;
  const receipt = await tx.wait();
  const txHash = receipt?.transactionHash ?? tx.transactionHash ?? tx.hash;
  return txHash !== undefined
    ? { approved: true, txHash }
    : { approved: true };
}

async function ensureCredsImpl(
  ctx: OnboardCtx,
): Promise<{ key: string; secret: string; passphrase: string }> {
  let creds: { key: string; secret: string; passphrase: string };
  try {
    creds = await ctx.clob.deriveApiKey();
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    if (!/incomplete/i.test(msg)) {
      throw err;
    }
    creds = await ctx.clob.createApiKey();
  }
  if (!creds?.key || !creds.secret || !creds.passphrase) {
    throw new Error(
      "polymarket-onboard: CLOB returned incomplete creds (missing key/secret/passphrase) after derive+create fallback",
    );
  }
  return creds;
}

function build(privateKey: string): OnboardClient {
  const safeFactory = loadSafeFactory();
  const wallet = new Wallet(privateKey);
  const safeAddress = deriveSafe(wallet.address, safeFactory);
  const provider = new providers.JsonRpcProvider(POLYGON_RPC_URL);
  const relay = new RelayClient(RELAYER_URL, POLYGON_CHAIN_ID, wallet);
  const clob = new ClobClient({
    host: CLOB_HOST,
    chain: POLYGON_CHAIN_ID as unknown as Chain,
    signer: wallet,
  });
  const ctx: OnboardCtx = { safeAddress, provider, relay, clob };
  return {
    status: () => statusImpl(ctx),
    ensureFunder: () => ensureFunderImpl(ctx),
    ensureApprovals: () => ensureApprovalsImpl(ctx),
    ensureCreds: () => ensureCredsImpl(ctx),
  };
}

export const polymarketOnboard: MarketVenueOnboard = {
  venue: "polymarket",
  chainId: POLYGON_CHAIN_ID,
  build,
};

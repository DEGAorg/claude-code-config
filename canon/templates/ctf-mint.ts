/**
 * Conditional Tokens minting adapter for the MINT-01 strategy.
 *
 * Thin wrapper around Gnosis `ConditionalTokens.splitPosition(...)` —
 * the on-chain call that converts USDC.e collateral into a matched
 * pair of YES + NO outcome tokens. MINT-01 uses this to mint a
 * hedged position, then sells both legs at midpoint + 0.75¢.
 *
 * Mirrors `usdc-allowance.ts`: the adapter accepts `getSigner` /
 * `getProvider` hooks so the templates layer stays decoupled from any
 * concrete wallet store, and uses ethers v5 `Contract` for the actual
 * RPC calls.
 *
 * For Polymarket binary markets the partition is always `[1, 2]`
 * (one bit per outcome). Multi-outcome markets are not in scope for
 * MINT-01 and are rejected by the strategy's market filter, not here.
 */
import { Contract } from "ethers";

/** Minimal Gnosis ConditionalTokens ABI — only the calls we use. */
const CONDITIONAL_TOKENS_ABI = [
  "function splitPosition(address collateralToken, bytes32 parentCollectionId, bytes32 conditionId, uint256[] partition, uint256 amount)",
  "function mergePositions(address collateralToken, bytes32 parentCollectionId, bytes32 conditionId, uint256[] partition, uint256 amount)",
];

/** Standard partition for a binary YES/NO market: one bit per outcome. */
export const BINARY_PARTITION: readonly [bigint, bigint] = [1n, 2n];

/** All-zero parent collection id — top-level (no parent condition). */
export const ROOT_PARENT_COLLECTION_ID =
  "0x0000000000000000000000000000000000000000000000000000000000000000";

/** Configuration for `createCtfMintClient`. */
export interface CtfMintConfig {
  /** Gnosis ConditionalTokens contract address on Polygon. */
  conditionalTokensAddress: string;
  /** Collateral token address (USDC.e for Polymarket). */
  collateralAddress: string;
  /**
   * Hook returning the wallet/signer used to send the split transaction.
   * Kept abstract to avoid coupling to a concrete WalletStore at import.
   */
  getSigner: () => Promise<unknown>;
  /** Hook returning a read-only provider (reserved for future read calls). */
  getProvider: () => Promise<unknown>;
}

/**
 * Arguments accepted by `CtfMintClient.splitPosition` /
 * `CtfMintClient.mergePositions`. Both calls take the same shape — split
 * converts collateral → outcome-token pair; merge converts the pair back
 * to collateral.
 */
export interface SplitPositionArgs {
  /**
   * Market condition id (bytes32 hex string). Identifies the binary
   * outcome question on Gnosis ConditionalTokens.
   */
  conditionId: string;
  /**
   * Collateral amount in raw token units (USDC.e is 6-decimal, so
   * `1_000_000_000n` = $1,000).
   */
  amount: bigint;
  /**
   * Parent collection id. Defaults to `ROOT_PARENT_COLLECTION_ID` for
   * top-level binary markets — Polymarket markets are always top-level.
   */
  parentCollectionId?: string;
  /**
   * Outcome partition. Defaults to `[1, 2]` (binary YES/NO).
   */
  partition?: readonly bigint[];
}

/** Result of a successful `splitPosition` or `mergePositions` call. */
export interface SplitPositionResult {
  txHash: string;
}

/** Alias kept for symmetry with `splitPosition`. */
export type MergePositionsArgs = SplitPositionArgs;
/** Alias kept for symmetry with `splitPosition`. */
export type MergePositionsResult = SplitPositionResult;

/** Public surface of the CTF mint adapter. */
export interface CtfMintClient {
  splitPosition: (args: SplitPositionArgs) => Promise<SplitPositionResult>;
  mergePositions: (args: MergePositionsArgs) => Promise<MergePositionsResult>;
}

/**
 * Build a CTF mint adapter.
 *
 * `splitPosition({ conditionId, amount })` submits a Gnosis
 * `splitPosition(collateral, parent, conditionId, partition, amount)`
 * transaction via the injected signer, awaits one confirmation, and
 * returns `{ txHash }`. RPC and revert errors propagate to the caller.
 */
/** Signature shared by `splitPosition` and `mergePositions` on the ABI. */
interface CtfPositionCall {
  (
    collateralToken: string,
    parentCollectionId: string,
    conditionId: string,
    partition: readonly bigint[],
    amount: bigint,
  ): Promise<{ hash: string; wait: () => Promise<unknown> }>;
}

export function createCtfMintClient(config: CtfMintConfig): CtfMintClient {
  async function sendPositionCall(
    method: "splitPosition" | "mergePositions",
    args: SplitPositionArgs,
  ): Promise<SplitPositionResult> {
    if (args.amount <= 0n) {
      throw new RangeError(
        `ctf-mint: ${method} amount must be > 0 (got ${args.amount})`,
      );
    }
    const partition = args.partition ?? BINARY_PARTITION;
    if (partition.length < 2) {
      throw new RangeError(
        `ctf-mint: partition must have at least 2 entries (got ${partition.length})`,
      );
    }
    const parentCollectionId =
      args.parentCollectionId ?? ROOT_PARENT_COLLECTION_ID;

    const signer = await config.getSigner();
    const contract = new Contract(
      config.conditionalTokensAddress,
      CONDITIONAL_TOKENS_ABI,
      signer as never,
    );

    const fn = (
      contract as unknown as Record<string, CtfPositionCall>
    )[method];
    if (fn === undefined) {
      throw new Error(`ctf-mint: ConditionalTokens missing ${method} method`);
    }

    const tx = await fn(
      config.collateralAddress,
      parentCollectionId,
      args.conditionId,
      partition,
      args.amount,
    );

    await tx.wait();
    return { txHash: tx.hash };
  }

  return {
    splitPosition(args: SplitPositionArgs): Promise<SplitPositionResult> {
      return sendPositionCall("splitPosition", args);
    },
    mergePositions(args: MergePositionsArgs): Promise<MergePositionsResult> {
      return sendPositionCall("mergePositions", args);
    },
  };
}

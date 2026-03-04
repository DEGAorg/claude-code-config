/** NBA game state from Polymarket + sportsbook data. */
export interface Game {
  id: string;
  homeTeam: string;
  awayTeam: string;
  tipoff: Date;
  /** Polymarket YES price (home team wins). */
  polymarketPrice: number;
  /** Total USD volume on the Polymarket market. */
  totalVolume: number;
  /** True if the game is live (in progress). */
  isLive: boolean;
  /** True if the game has a final result. */
  isResolved: boolean;
  /** Pre-game sportsbook spread (negative = home favorite). */
  pregameSpread: number;
  /** Current sportsbook spread (may differ from pregame after news). */
  currentSpread: number;
}

/** Injury/rest report for a single player. */
export interface InjuryReport {
  playerId: string;
  playerName: string;
  team: string;
  /** Player's rank in team minutes played (1 = most minutes). */
  minutesRank: number;
  /** Injury status per NBA rules. */
  status: "out" | "doubtful" | "questionable" | "probable" | "available";
  reportedAt: Date;
}

/** Portfolio snapshot for risk calculations. */
export interface Portfolio {
  totalValue: number;
  cashBalance: number;
  positions: Position[];
  peakValue: number;
  dailyPnl: number;
  consecutiveLosses: number;
}

/** A single open position. */
export interface Position {
  marketId: string;
  side: "yes" | "no";
  entryPrice: number;
  size: number;
  enteredAt: Date;
}

/** Why a position was exited. */
export type ExitReason = "resolution" | "stop_loss" | "edge_gone" | "hold";

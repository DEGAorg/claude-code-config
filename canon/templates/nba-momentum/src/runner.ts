/**
 * NBA championship futures scanner.
 *
 * Compares NBA Championship Winner odds from sportsbooks (The Odds API)
 * against Polymarket futures prices. Flags mispricings where the implied
 * probability gap exceeds a threshold.
 *
 * In dry-run mode: scans and logs but never places orders.
 *
 * Stdout protocol — each line is tagged for dashboard parsing:
 *   START <message>       Runner started
 *   SCAN <message>        Cycle started, fetching data
 *   NO_EDGE <message>     Scan cycle complete, no opportunities
 *   SIGNAL <message>      Mispricing detected (dry-run skip)
 *   SCAN_ERROR <message>  Scan cycle failed
 *   STOP <message>        Runner shutting down
 *
 * Usage: pnpm exec tsx src/runner.ts --dry-run
 */

import { appendFileSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { fetchOdds } from "./clients/sportsbook.js";
import { searchMarkets } from "./clients/polymarket.js";
import type { StrategyConfig } from "./config/strategy.js";
import { DEFAULT_CONFIG } from "./config/strategy.js";
import { shouldFlag } from "./service/signals.js";
import { checkRiskLimits } from "./service/risk.js";
import { DEFAULT_RISK_CONFIG } from "./config/risk.js";

// ── Log entry types ─────────────────────────────────────────────────────────

interface SignalLogEntry {
  ts: string;
  automation_id: string;
  cycle: number;
  action: "SIGNAL";
  team: string;
  sportsbookProb: number;
  polymarketPrice: number;
  delta: number;
  reasoning: string;
}

interface HeartbeatLogEntry {
  ts: string;
  automation_id: string;
  cycle: number;
  action: "NO_EDGE";
  teams: number;
  markets: number;
  matched: number;
  reasoning: string;
}

interface ScanErrorLogEntry {
  ts: string;
  automation_id: string;
  cycle: number;
  action: "SCAN_ERROR";
  reasoning: string;
}

type LogEntry = SignalLogEntry | HeartbeatLogEntry | ScanErrorLogEntry;

// ── Constants ───────────────────────────────────────────────────────────────

const AUTOMATION_ID = "nba-futures-v1";
const EXECUTION_DIR = join(process.cwd(), ".canon", "execution");
const DEFAULT_POLL_INTERVAL_MS = 30_000;

// ── Counters ────────────────────────────────────────────────────────────────

let cycleCount = 0;
let signalCount = 0;
let errorCount = 0;

// ── Helpers ─────────────────────────────────────────────────────────────────

function ensureExecutionDir(): void {
  if (!existsSync(EXECUTION_DIR)) {
    mkdirSync(EXECUTION_DIR, { recursive: true });
  }
}

function logFilePath(): string {
  const date = new Date().toISOString().slice(0, 10);
  return join(EXECUTION_DIR, `${date}.jsonl`);
}

function appendLog(entry: LogEntry): void {
  ensureExecutionDir();
  appendFileSync(logFilePath(), JSON.stringify(entry) + "\n");
}

function out(tag: string, msg: string): void {
  process.stdout.write(`${tag} ${msg}\n`);
}

function parsePollInterval(): number {
  const envVal = process.env["POLL_INTERVAL_MS"];
  if (envVal) {
    const parsed = Number(envVal);
    if (Number.isFinite(parsed) && parsed > 0) return parsed;
  }
  return DEFAULT_POLL_INTERVAL_MS;
}

function isDryRun(): boolean {
  return process.argv.includes("--dry-run");
}

// ── Team matching ───────────────────────────────────────────────────────────

/** Normalize team name for fuzzy matching. */
export function normalize(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9 ]/g, "")
    .trim();
}

/**
 * NBA team name aliases — maps common short names to the full
 * team name fragments. Extend as needed.
 */
const NBA_ALIASES: Record<string, string[]> = {
  "76ers": ["philadelphia", "sixers", "76ers"],
  blazers: ["portland", "trail blazers", "blazers"],
  cavs: ["cleveland", "cavaliers", "cavs"],
  mavs: ["dallas", "mavericks", "mavs"],
  wolves: ["minnesota", "timberwolves", "wolves"],
};

/**
 * Check if a text string mentions a team (fuzzy match with aliases).
 *
 * Strategy:
 * 1. Direct substring match on normalized full team name.
 * 2. Last-word fallback — match on just the last word (e.g. "Thunder").
 * 3. Alias table — match any registered alias fragment for the team.
 */
export function textMentionsTeam(
  text: string,
  teamName: string,
): boolean {
  const normText = normalize(text);
  const normTeam = normalize(teamName);

  // 1. Direct substring match
  if (normText.includes(normTeam)) return true;

  // 2. Last-word fallback (e.g. "Thunder" from "Oklahoma City Thunder")
  const lastWord = normTeam.split(" ").at(-1);
  if (lastWord && lastWord.length > 3 && normText.includes(lastWord)) return true;

  // 3. Alias table — check if any alias for any alias key matches the team
  //    and the text contains that alias fragment
  for (const [_key, aliases] of Object.entries(NBA_ALIASES)) {
    // Does this alias group relate to the queried team?
    const groupMatchesTeam = aliases.some((a) => normTeam.includes(normalize(a)));
    if (!groupMatchesTeam) continue;
    // Does the text contain any alias fragment from this group?
    if (aliases.some((a) => normText.includes(normalize(a)))) return true;
  }

  return false;
}

// ── Team odds extraction ────────────────────────────────────────────────────

/** Raw odds event from The Odds API. */
export interface OddsEvent {
  id: string;
  homeTeam: string;
  awayTeam: string;
  commence: Date;
  bookmakers: Array<{
    key: string;
    title: string;
    markets: Array<{
      key: string;
      outcomes: Array<{ name: string; price: number }>;
    }>;
  }>;
}

/** Per-team implied probability aggregated across sportsbooks. */
export interface TeamOdds {
  team: string;
  /** Average implied probability across all bookmaker outrights. */
  impliedProb: number;
  /** Number of bookmakers contributing to the average. */
  sources: number;
}

/**
 * Extract per-team average implied probability from outrights markets.
 *
 * For each team name found across all bookmaker outright outcomes:
 *  - Convert decimal odds → implied probability: 1 / price
 *  - Average across all bookmakers that list the team
 *
 * Only processes markets with key "outrights".
 */
export function extractTeamOdds(events: OddsEvent[]): TeamOdds[] {
  // Accumulate sum of implied probs and count per team name
  const accumulator = new Map<string, { sum: number; count: number }>();

  for (const event of events) {
    for (const bookmaker of event.bookmakers) {
      for (const market of bookmaker.markets) {
        // Only process outright (futures) markets
        if (market.key !== "outrights") continue;

        for (const outcome of market.outcomes) {
          if (!outcome.name || outcome.price <= 0) continue;

          // Convert decimal odds to implied probability
          const impliedProb = 1 / outcome.price;
          const existing = accumulator.get(outcome.name);

          if (existing) {
            existing.sum += impliedProb;
            existing.count += 1;
          } else {
            accumulator.set(outcome.name, { sum: impliedProb, count: 1 });
          }
        }
      }
    }
  }

  // Convert accumulator to TeamOdds array
  const result: TeamOdds[] = [];
  for (const [team, { sum, count }] of accumulator.entries()) {
    result.push({
      team,
      impliedProb: sum / count,
      sources: count,
    });
  }

  return result;
}

// ── Scan cycle ───────────────────────────────────────────────────────────────

/**
 * Run one scan cycle:
 * 1. Fetch sportsbook outright odds for NBA championship futures.
 * 2. Extract per-team implied probabilities.
 * 3. For each team, search Polymarket for a matching championship market.
 * 4. Compare implied probs — flag mispricings above threshold.
 */
async function runCycle(config: StrategyConfig, dryRun: boolean): Promise<void> {
  cycleCount += 1;
  out("SCAN", `cycle=${cycleCount} fetching sportsbook + polymarket data`);

  let teamOddsList: TeamOdds[];
  try {
    // Fetch NBA championship outright odds from sportsbooks
    const events = await fetchOdds("basketball_nba", "outrights");
    teamOddsList = extractTeamOdds(events);
  } catch (err) {
    errorCount += 1;
    const reasoning = err instanceof Error ? err.message : String(err);
    out("SCAN_ERROR", `cycle=${cycleCount} sportsbook fetch failed: ${reasoning}`);
    appendLog({
      ts: new Date().toISOString(),
      automation_id: AUTOMATION_ID,
      cycle: cycleCount,
      action: "SCAN_ERROR",
      reasoning,
    });
    return;
  }

  // Search Polymarket for championship markets
  let polyMarkets: Awaited<ReturnType<typeof searchMarkets>>;
  try {
    polyMarkets = await searchMarkets("NBA Championship Winner");
  } catch (err) {
    errorCount += 1;
    const reasoning = err instanceof Error ? err.message : String(err);
    out("SCAN_ERROR", `cycle=${cycleCount} polymarket fetch failed: ${reasoning}`);
    appendLog({
      ts: new Date().toISOString(),
      automation_id: AUTOMATION_ID,
      cycle: cycleCount,
      action: "SCAN_ERROR",
      reasoning,
    });
    return;
  }

  let matchedCount = 0;
  let signalThisCycle = 0;

  for (const teamOdds of teamOddsList) {
    // Risk check: require minimum bookmaker sources
    const riskOk = checkRiskLimits(
      { sources: teamOdds.sources },
      DEFAULT_RISK_CONFIG,
    );
    if (!riskOk) continue;

    // Find matching Polymarket market for this team
    const match = polyMarkets.find((m) =>
      textMentionsTeam(m.question, teamOdds.team),
    );
    if (!match) continue;

    matchedCount += 1;

    // Compare sportsbook implied prob vs Polymarket YES price
    const signal = shouldFlag(
      teamOdds.impliedProb,
      match.yesPrice,
      config,
    );

    if (!signal) continue;

    signalThisCycle += 1;
    signalCount += 1;

    const reasoning =
      `${teamOdds.team}: sportsbook=${teamOdds.impliedProb.toFixed(4)} ` +
      `poly=${match.yesPrice.toFixed(4)} delta=${signal.absDelta.toFixed(4)} ` +
      `direction=${signal.direction}`;

    if (dryRun) {
      out("SIGNAL", `[DRY-RUN] ${reasoning}`);
    } else {
      out("SIGNAL", reasoning);
    }

    appendLog({
      ts: new Date().toISOString(),
      automation_id: AUTOMATION_ID,
      cycle: cycleCount,
      action: "SIGNAL",
      team: teamOdds.team,
      sportsbookProb: teamOdds.impliedProb,
      polymarketPrice: match.yesPrice,
      delta: signal.absDelta,
      reasoning,
    });
  }

  if (signalThisCycle === 0) {
    const reasoning =
      `teams=${teamOddsList.length} markets=${polyMarkets.length} matched=${matchedCount} — no edges above threshold`;
    out("NO_EDGE", `cycle=${cycleCount} ${reasoning}`);
    appendLog({
      ts: new Date().toISOString(),
      automation_id: AUTOMATION_ID,
      cycle: cycleCount,
      action: "NO_EDGE",
      teams: teamOddsList.length,
      markets: polyMarkets.length,
      matched: matchedCount,
      reasoning,
    });
  }
}

// ── Entry point ──────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  const dryRun = isDryRun();
  const pollIntervalMs = parsePollInterval();

  out("START", `NBA futures scanner | dry-run=${dryRun} | poll=${pollIntervalMs}ms`);

  // Graceful shutdown
  const shutdown = (): void => {
    out(
      "STOP",
      `cycles=${cycleCount} signals=${signalCount} errors=${errorCount}`,
    );
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  // Run immediately, then poll
  await runCycle(DEFAULT_CONFIG, dryRun);

  setInterval(() => {
    void runCycle(DEFAULT_CONFIG, dryRun);
  }, pollIntervalMs);
}

main().catch((err) => {
  process.stderr.write(`FATAL ${String(err)}\n`);
  process.exit(1);
});

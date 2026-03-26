import type { Database as DatabaseType } from "better-sqlite3";
import type { Prospect } from "./db.js";
import { queryByStatus } from "./db.js";

// ---------- Category keywords ----------

export type InterestCategory = "crypto" | "ai-ml" | "sports" | "generic";

const CATEGORY_KEYWORDS: Record<Exclude<InterestCategory, "generic">, string[]> =
  {
    crypto: [
      "blockchain",
      "crypto",
      "web3",
      "defi",
      "nft",
      "solidity",
      "ethereum",
      "bitcoin",
      "smart contract",
      "dao",
      "dapp",
      "token",
      "wallet",
      "layer 2",
      "l2",
      "zk",
      "zero knowledge",
      "rollup",
      "consensus",
      "staking",
    ],
    "ai-ml": [
      "machine learning",
      "deep learning",
      "neural network",
      "nlp",
      "natural language",
      "computer vision",
      "ai",
      "artificial intelligence",
      "llm",
      "large language model",
      "transformer",
      "gpt",
      "tensorflow",
      "pytorch",
      "reinforcement learning",
      "generative ai",
      "diffusion",
      "ml ops",
      "mlops",
      "data science",
    ],
    sports: [
      "sports",
      "fantasy sports",
      "sports betting",
      "esports",
      "gaming",
      "athlete",
      "fitness",
      "sports analytics",
      "sports data",
      "fantasy league",
      "sports prediction",
      "tournament",
    ],
  };

// ---------- Scoring ----------

export interface FilterResult {
  interest: InterestCategory;
  score: number;
}

/**
 * Score a single prospect's bio and tags against category keywords.
 * Returns the best-matching category and a relevance score 0-10.
 */
export function scoreProspect(bio: string, tags: string): FilterResult {
  const text = `${bio} ${tags}`.toLowerCase();

  const categoryCounts: Record<Exclude<InterestCategory, "generic">, number> = {
    crypto: 0,
    "ai-ml": 0,
    sports: 0,
  };

  for (const [category, keywords] of Object.entries(CATEGORY_KEYWORDS)) {
    for (const keyword of keywords) {
      if (text.includes(keyword)) {
        categoryCounts[category as Exclude<InterestCategory, "generic">] += 1;
      }
    }
  }

  const bestCategory = (
    Object.entries(categoryCounts) as Array<
      [Exclude<InterestCategory, "generic">, number]
    >
  ).reduce((best, current) => (current[1] > best[1] ? current : best));

  if (bestCategory[1] === 0) {
    return { interest: "generic", score: 1 };
  }

  const interest: InterestCategory = bestCategory[0];
  const matchCount = bestCategory[1];
  const maxKeywords = CATEGORY_KEYWORDS[interest].length;

  // Scale match ratio to 2-10 range (1 is reserved for generic/no-match)
  const ratio = matchCount / maxKeywords;
  const score = Math.min(10, Math.round(2 + ratio * 8));

  return { interest, score };
}

// ---------- Pipeline ----------

export interface FilterStats {
  processed: number;
  byCategory: Record<InterestCategory, number>;
}

/**
 * Filter all prospects with status 'scraped': score them, tag interest,
 * and update status to 'filtered'.
 */
export function filterProspects(db: DatabaseType): FilterStats {
  const prospects = queryByStatus(db, "scraped");

  const stats: FilterStats = {
    processed: 0,
    byCategory: { crypto: 0, "ai-ml": 0, sports: 0, generic: 0 },
  };

  const updateStmt = db.prepare(`
    UPDATE prospects
    SET relevance_score = ?, interest_tag = ?, status = 'filtered', updated_at = datetime('now')
    WHERE id = ?
  `);

  const runAll = db.transaction(() => {
    for (const prospect of prospects) {
      const { interest, score } = scoreProspect(prospect.bio, prospect.tags);
      updateStmt.run(score, interest, prospect.id);
      stats.byCategory[interest] += 1;
      stats.processed += 1;
    }
  });

  runAll();

  return stats;
}

import { describe, it, expect, beforeAll, afterAll, beforeEach } from "vitest";
import type { Pool as PoolType } from "@neondatabase/serverless";
import { scoreProspect, filterProspects } from "../src/filter.js";
import { insertProspect, getProspectById, getPool, closePool } from "../src/db.js";

const skipDb = !process.env["DATABASE_URL"];

// ---------- scoreProspect (pure function, no DB needed) ----------

describe("scoreProspect", () => {
  it("returns generic with score 1 for empty bio and tags", () => {
    const result = scoreProspect("", "");
    expect(result.interest).toBe("generic");
    expect(result.score).toBe(1);
  });

  it("returns generic with score 1 for unrelated content", () => {
    const result = scoreProspect("I like cooking pasta", "chef, foodie");
    expect(result.interest).toBe("generic");
    expect(result.score).toBe(1);
  });

  it("detects crypto interest from bio keywords", () => {
    const result = scoreProspect(
      "Building DeFi protocols on Ethereum with Solidity smart contracts",
      "",
    );
    expect(result.interest).toBe("crypto");
    expect(result.score).toBeGreaterThanOrEqual(2);
  });

  it("detects AI/ML interest from tags", () => {
    const result = scoreProspect("", "machine learning, pytorch, deep learning");
    expect(result.interest).toBe("ai-ml");
    expect(result.score).toBeGreaterThanOrEqual(2);
  });

  it("detects sports interest", () => {
    const result = scoreProspect(
      "Fantasy sports analytics and sports prediction models",
      "sports betting, esports",
    );
    expect(result.interest).toBe("sports");
    expect(result.score).toBeGreaterThanOrEqual(2);
  });

  it("picks the category with the most keyword matches", () => {
    const result = scoreProspect(
      "blockchain crypto defi with some ai",
      "",
    );
    expect(result.interest).toBe("crypto");
  });

  it("is case insensitive", () => {
    const result = scoreProspect("BLOCKCHAIN ETHEREUM DEFI", "");
    expect(result.interest).toBe("crypto");
  });

  it("scores higher with more keyword matches", () => {
    const low = scoreProspect("blockchain", "");
    const high = scoreProspect(
      "blockchain crypto defi ethereum solidity smart contract nft web3 dao token",
      "",
    );
    expect(high.score).toBeGreaterThan(low.score);
  });

  it("caps score at 10", () => {
    const allCrypto = "blockchain crypto web3 defi nft solidity ethereum bitcoin smart contract dao dapp token wallet layer 2 l2 zk zero knowledge rollup consensus staking";
    const result = scoreProspect(allCrypto, allCrypto);
    expect(result.score).toBeLessThanOrEqual(10);
  });

  it("combines bio and tags for matching", () => {
    const bioOnly = scoreProspect("blockchain", "");
    const combined = scoreProspect("blockchain", "ethereum, defi");
    expect(combined.score).toBeGreaterThan(bioOnly.score);
  });
});

// ---------- filterProspects (requires Neon DB) ----------

describe.skipIf(skipDb)("filterProspects", () => {
  let pool: PoolType;

  beforeAll(async () => {
    pool = await getPool();
  });

  afterAll(async () => {
    await closePool();
  });

  beforeEach(async () => {
    await pool.query("TRUNCATE prospects RESTART IDENTITY CASCADE");
  });

  it("filters scraped prospects and updates status to filtered", async () => {
    await insertProspect(pool, {
      username: "alice",
      profile_url: "https://dorahacks.io/alice",
      display_name: "Alice",
      bio: "Blockchain developer building DeFi",
      tags: "crypto, ethereum",
      source_hackathon: "hackathon-1",
    });

    const stats = await filterProspects(pool);

    expect(stats.processed).toBe(1);
    expect(stats.byCategory.crypto).toBe(1);

    const prospect = await getProspectById(pool, 1);
    expect(prospect?.status).toBe("filtered");
    expect(prospect?.interest_tag).toBe("crypto");
    expect(prospect?.relevance_score).toBeGreaterThanOrEqual(2);
  });

  it("does not re-filter already filtered prospects", async () => {
    await insertProspect(pool, {
      username: "bob",
      profile_url: "https://dorahacks.io/bob",
      display_name: "Bob",
      bio: "ML engineer",
      tags: "machine learning",
      source_hackathon: "hackathon-1",
    });

    await filterProspects(pool);
    const stats2 = await filterProspects(pool);

    expect(stats2.processed).toBe(0);
  });

  it("handles multiple prospects in a batch", async () => {
    const prospects = [
      { username: "crypto-dev", bio: "blockchain ethereum defi", tags: "web3" },
      { username: "ml-eng", bio: "deep learning neural network", tags: "pytorch" },
      { username: "sports-fan", bio: "fantasy sports analytics", tags: "esports" },
      { username: "generic-dev", bio: "I like building things", tags: "coding" },
    ];

    for (const p of prospects) {
      await insertProspect(pool, {
        username: p.username,
        profile_url: `https://dorahacks.io/${p.username}`,
        display_name: p.username,
        bio: p.bio,
        tags: p.tags,
        source_hackathon: "hackathon-1",
      });
    }

    const stats = await filterProspects(pool);

    expect(stats.processed).toBe(4);
    expect(stats.byCategory.crypto).toBe(1);
    expect(stats.byCategory["ai-ml"]).toBe(1);
    expect(stats.byCategory.sports).toBe(1);
    expect(stats.byCategory.generic).toBe(1);

    const result = await pool.query<{ status: string }>(
      "SELECT status FROM prospects",
    );
    for (const row of result.rows) {
      expect(row.status).toBe("filtered");
    }
  });

  it("returns zeroed stats when no scraped prospects exist", async () => {
    const stats = await filterProspects(pool);
    expect(stats.processed).toBe(0);
    expect(stats.byCategory).toEqual({
      crypto: 0,
      "ai-ml": 0,
      sports: 0,
      generic: 0,
    });
  });

  it("assigns relevance scores in valid range", async () => {
    await insertProspect(pool, {
      username: "dev1",
      profile_url: "https://dorahacks.io/dev1",
      display_name: "Dev",
      bio: "blockchain",
      tags: "",
      source_hackathon: "h1",
    });
    await insertProspect(pool, {
      username: "dev2",
      profile_url: "https://dorahacks.io/dev2",
      display_name: "Dev2",
      bio: "",
      tags: "",
      source_hackathon: "h1",
    });

    await filterProspects(pool);

    const result = await pool.query<{ relevance_score: number }>(
      "SELECT relevance_score FROM prospects",
    );
    for (const row of result.rows) {
      expect(row.relevance_score).toBeGreaterThanOrEqual(1);
      expect(row.relevance_score).toBeLessThanOrEqual(10);
    }
  });
});

import { describe, it, expect, beforeAll, afterAll, beforeEach } from "vitest";
import type { Pool as PoolType } from "@neondatabase/serverless";
import {
  getPool,
  closePool,
  insertProspect,
  upsertProspect,
  queryByStatus,
  updateStatus,
  countByStatus,
  claimNextProspect,
} from "../src/db.js";
import type { ProspectInsert } from "../src/db.js";
import { filterProspects } from "../src/filter.js";

const skipDb = !process.env["DATABASE_URL"];

function makeProspect(
  username: string,
  bio: string,
  tags: string,
): ProspectInsert {
  return {
    username,
    profile_url: `https://dorahacks.io/${username}`,
    display_name: username,
    bio,
    tags,
    source_hackathon: "ETHGlobal 2026",
  };
}

describe.skipIf(skipDb)("e2e: scrape -> filter -> send (dry-run)", () => {
  let pool: PoolType;

  beforeAll(async () => {
    pool = await getPool();
  });

  afterAll(async () => {
    await closePool();
  });

  beforeEach(async () => {
    await pool.query(
      "TRUNCATE prospects RESTART IDENTITY CASCADE",
    );
  });

  it("full pipeline: upsert -> filter -> claim (dry-run send)", async () => {
    // --- Phase 1: Scrape (simulated via upsert) ---
    const prospects = [
      makeProspect("alice", "blockchain developer, DeFi protocols", "crypto,ethereum"),
      makeProspect("bob", "machine learning engineer, pytorch expert", "ai,deep learning"),
      makeProspect("charlie", "fantasy sports analytics", "sports,esports"),
      makeProspect("dana", "full-stack web developer", "react,node"),
    ];

    for (const p of prospects) {
      await upsertProspect(pool, p);
    }

    const scraped = await queryByStatus(pool, "scraped");
    expect(scraped).toHaveLength(4);

    // --- Phase 2: Filter ---
    const filterStats = await filterProspects(pool);
    expect(filterStats.processed).toBe(4);

    const filtered = await queryByStatus(pool, "filtered");
    expect(filtered).toHaveLength(4);

    // Verify each prospect got scored and tagged
    for (const p of filtered) {
      expect(p.relevance_score).toBeGreaterThanOrEqual(1);
      expect(p.relevance_score).toBeLessThanOrEqual(10);
      expect(p.interest_tag).toBeTruthy();
      expect(p.status).toBe("filtered");
    }

    // --- Phase 3: Send dry-run (claim one at a time) ---
    const claimed: number[] = [];
    let next = await claimNextProspect(pool, "filtered", "queued");
    while (next) {
      claimed.push(next.id);
      // Simulate dry-run: no actual message sent, mark as messaged
      await updateStatus(pool, next.id, "messaged");
      next = await claimNextProspect(pool, "filtered", "queued");
    }

    expect(claimed).toHaveLength(4);

    // All prospects should now be messaged
    const counts = await countByStatus(pool);
    expect(counts.filtered).toBe(0);
    expect(counts.queued).toBe(0);
    expect(counts.messaged).toBe(4);
  });

  it("upsert is idempotent (re-scrape does not duplicate)", async () => {
    const p = makeProspect("alice", "blockchain dev", "crypto");
    const id1 = await upsertProspect(pool, p);
    const id2 = await upsertProspect(pool, { ...p, bio: "updated bio" });

    // Same row updated, not a new insert
    expect(id2).toBe(id1);

    const all = await queryByStatus(pool, "scraped");
    expect(all).toHaveLength(1);
    expect(all[0]?.bio).toBe("updated bio");
  });

  it("two concurrent sessions never claim the same prospect", async () => {
    // Insert 10 filtered prospects
    for (let i = 0; i < 10; i++) {
      await insertProspect(
        pool,
        makeProspect(`user-${i}`, "blockchain dev", "crypto"),
      );
      await updateStatus(pool, i + 1, "filtered");
    }

    const filtered = await queryByStatus(pool, "filtered");
    expect(filtered).toHaveLength(10);

    // Simulate two concurrent operators claiming prospects
    const session1Claims: number[] = [];
    const session2Claims: number[] = [];

    async function operatorLoop(
      claims: number[],
    ): Promise<void> {
      let prospect = await claimNextProspect(
        pool,
        "filtered",
        "queued",
      );
      while (prospect) {
        claims.push(prospect.id);
        prospect = await claimNextProspect(
          pool,
          "filtered",
          "queued",
        );
      }
    }

    // Run both operators concurrently
    await Promise.all([
      operatorLoop(session1Claims),
      operatorLoop(session2Claims),
    ]);

    // Every prospect must be claimed exactly once
    const allClaimed = [...session1Claims, ...session2Claims].sort(
      (a, b) => a - b,
    );
    expect(allClaimed).toHaveLength(10);

    // No duplicates — the core SKIP LOCKED guarantee
    const uniqueClaimed = new Set(allClaimed);
    expect(uniqueClaimed.size).toBe(10);

    // Both sessions should have gotten some work (not all to one)
    // With 10 items and concurrent claiming, both should get at least 1
    expect(session1Claims.length).toBeGreaterThan(0);
    expect(session2Claims.length).toBeGreaterThan(0);

    // All prospects should now be queued
    const counts = await countByStatus(pool);
    expect(counts.filtered).toBe(0);
    expect(counts.queued).toBe(10);
  });

  it("concurrent claiming with interleaved status updates", async () => {
    // Insert 6 filtered prospects
    for (let i = 0; i < 6; i++) {
      await insertProspect(
        pool,
        makeProspect(`worker-${i}`, "ai engineer", "machine learning"),
      );
      await updateStatus(pool, i + 1, "filtered");
    }

    const s1: number[] = [];
    const s2: number[] = [];

    async function claimAndProcess(
      claims: number[],
    ): Promise<void> {
      let prospect = await claimNextProspect(
        pool,
        "filtered",
        "queued",
      );
      while (prospect) {
        claims.push(prospect.id);
        // Simulate processing delay then mark as messaged
        await updateStatus(pool, prospect.id, "messaged");
        prospect = await claimNextProspect(
          pool,
          "filtered",
          "queued",
        );
      }
    }

    await Promise.all([
      claimAndProcess(s1),
      claimAndProcess(s2),
    ]);

    const allIds = [...s1, ...s2].sort((a, b) => a - b);
    expect(allIds).toHaveLength(6);
    expect(new Set(allIds).size).toBe(6);

    const counts = await countByStatus(pool);
    expect(counts.filtered).toBe(0);
    expect(counts.queued).toBe(0);
    expect(counts.messaged).toBe(6);
  });
});

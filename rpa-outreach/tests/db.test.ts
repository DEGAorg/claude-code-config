import { describe, it, expect, beforeAll, afterAll, beforeEach } from "vitest";
import type { Pool as PoolType } from "@neondatabase/serverless";
import {
  getPool,
  closePool,
  insertProspect,
  upsertProspect,
  queryByStatus,
  updateStatus,
  updateStatusWithTimestamp,
  isDuplicate,
  getProspectByUsername,
  getProspectById,
  countByStatus,
  claimNextProspect,
} from "../src/db.js";
import type { ProspectInsert } from "../src/db.js";

const skipDb = !process.env["DATABASE_URL"];

const SAMPLE: ProspectInsert = {
  username: "alice",
  profile_url: "https://dorahacks.io/alice",
  display_name: "Alice",
  bio: "blockchain dev and AI enthusiast",
  tags: "crypto,AI",
  source_hackathon: "ETHGlobal 2026",
};

describe.skipIf(skipDb)("db", () => {
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

  describe("schema", () => {
    it("creates prospects table on getPool", async () => {
      const result = await pool.query(
        `SELECT table_name FROM information_schema.tables
         WHERE table_schema = 'public' AND table_name = 'prospects'`,
      );
      expect(result.rows).toHaveLength(1);
    });

    it("creates indexes", async () => {
      const result = await pool.query<{ indexname: string }>(
        `SELECT indexname FROM pg_indexes
         WHERE schemaname = 'public'
           AND tablename = 'prospects'
           AND indexname LIKE 'idx_prospects_%'`,
      );
      const names = result.rows.map((i) => i.indexname);
      expect(names).toContain("idx_prospects_status");
      expect(names).toContain("idx_prospects_username");
      expect(names).toContain("idx_prospects_relevance");
    });
  });

  describe("insertProspect", () => {
    it("inserts and returns id", async () => {
      const id = await insertProspect(pool, SAMPLE);
      expect(id).toBe(1);
    });

    it("rejects duplicate username", async () => {
      await insertProspect(pool, SAMPLE);
      await expect(insertProspect(pool, SAMPLE)).rejects.toThrow(
        /unique/i,
      );
    });

    it("sets default status to scraped", async () => {
      const id = await insertProspect(pool, SAMPLE);
      const row = await getProspectById(pool, id);
      expect(row?.status).toBe("scraped");
    });
  });

  describe("upsertProspect", () => {
    it("inserts new prospect", async () => {
      const id = await upsertProspect(pool, SAMPLE);
      expect(id).toBeGreaterThan(0);
      const row = await getProspectByUsername(pool, "alice");
      expect(row?.display_name).toBe("Alice");
    });

    it("updates existing prospect on conflict", async () => {
      await insertProspect(pool, SAMPLE);
      await upsertProspect(pool, {
        ...SAMPLE,
        display_name: "Alice Updated",
      });
      const row = await getProspectByUsername(pool, "alice");
      expect(row?.display_name).toBe("Alice Updated");
    });
  });

  describe("queryByStatus", () => {
    it("returns prospects matching status", async () => {
      await insertProspect(pool, SAMPLE);
      await insertProspect(pool, {
        ...SAMPLE,
        username: "bob",
        profile_url: "https://dorahacks.io/bob",
      });
      const results = await queryByStatus(pool, "scraped");
      expect(results).toHaveLength(2);
    });

    it("returns empty array when no matches", async () => {
      const results = await queryByStatus(pool, "messaged");
      expect(results).toHaveLength(0);
    });
  });

  describe("updateStatus", () => {
    it("updates prospect status", async () => {
      const id = await insertProspect(pool, SAMPLE);
      await updateStatus(pool, id, "filtered");
      const row = await getProspectById(pool, id);
      expect(row?.status).toBe("filtered");
    });
  });

  describe("updateStatusWithTimestamp", () => {
    it("updates status and messaged_at", async () => {
      const id = await insertProspect(pool, SAMPLE);
      const ts = "2026-03-26T12:00:00Z";
      await updateStatusWithTimestamp(pool, id, "messaged", ts);
      const row = await getProspectById(pool, id);
      expect(row?.status).toBe("messaged");
      expect(row?.messaged_at).toBe(
        new Date(ts).toISOString(),
      );
    });
  });

  describe("isDuplicate", () => {
    it("returns true for existing username", async () => {
      await insertProspect(pool, SAMPLE);
      expect(await isDuplicate(pool, "alice")).toBe(true);
    });

    it("returns false for unknown username", async () => {
      expect(await isDuplicate(pool, "unknown")).toBe(false);
    });
  });

  describe("countByStatus", () => {
    it("returns zero counts when empty", async () => {
      const counts = await countByStatus(pool);
      expect(counts.scraped).toBe(0);
      expect(counts.filtered).toBe(0);
      expect(counts.messaged).toBe(0);
    });

    it("counts correctly across statuses", async () => {
      await insertProspect(pool, SAMPLE);
      await insertProspect(pool, {
        ...SAMPLE,
        username: "bob",
        profile_url: "https://dorahacks.io/bob",
      });
      await updateStatus(pool, 1, "filtered");

      const counts = await countByStatus(pool);
      expect(counts.scraped).toBe(1);
      expect(counts.filtered).toBe(1);
    });
  });

  describe("claimNextProspect", () => {
    it("claims prospect and updates status", async () => {
      await insertProspect(pool, SAMPLE);
      const claimed = await claimNextProspect(
        pool,
        "scraped",
        "queued",
      );
      expect(claimed).toBeDefined();
      expect(claimed?.username).toBe("alice");

      const row = await getProspectById(pool, claimed!.id);
      expect(row?.status).toBe("queued");
    });

    it("returns undefined when no prospects match", async () => {
      const claimed = await claimNextProspect(
        pool,
        "scraped",
        "queued",
      );
      expect(claimed).toBeUndefined();
    });
  });
});

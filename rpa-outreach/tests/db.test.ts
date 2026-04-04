import { describe, it, expect, afterEach } from "vitest";
import type { Database as DatabaseType } from "better-sqlite3";
import {
  getDb,
  closeDb,
  insertProspect,
  upsertProspect,
  queryByStatus,
  updateStatus,
  updateStatusWithTimestamp,
  isDuplicate,
  getProspectByUsername,
  getProspectById,
  countByStatus,
} from "../src/db.js";
import type { ProspectInsert } from "../src/db.js";

const SAMPLE: ProspectInsert = {
  username: "alice",
  profile_url: "https://dorahacks.io/alice",
  display_name: "Alice",
  bio: "blockchain dev and AI enthusiast",
  tags: "crypto,AI",
  source_hackathon: "ETHGlobal 2026",
};

function freshDb(): DatabaseType {
  return getDb(":memory:");
}

describe("db", () => {
  afterEach(() => {
    closeDb();
  });

  describe("schema", () => {
    it("creates prospects table on getDb", () => {
      const db = freshDb();
      const tables = db
        .prepare(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='prospects'",
        )
        .all();
      expect(tables).toHaveLength(1);
    });

    it("creates indexes", () => {
      const db = freshDb();
      const indexes = db
        .prepare(
          "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_prospects_%'",
        )
        .all() as Array<{ name: string }>;
      const names = indexes.map((i) => i.name);
      expect(names).toContain("idx_prospects_status");
      expect(names).toContain("idx_prospects_username");
      expect(names).toContain("idx_prospects_relevance");
    });
  });

  describe("insertProspect", () => {
    it("inserts and returns id", () => {
      const db = freshDb();
      const id = insertProspect(db, SAMPLE);
      expect(id).toBe(1);
    });

    it("rejects duplicate username", () => {
      const db = freshDb();
      insertProspect(db, SAMPLE);
      expect(() => insertProspect(db, SAMPLE)).toThrow(/UNIQUE/);
    });

    it("sets default status to scraped", () => {
      const db = freshDb();
      const id = insertProspect(db, SAMPLE);
      const row = getProspectById(db, id);
      expect(row?.status).toBe("scraped");
    });
  });

  describe("upsertProspect", () => {
    it("inserts new prospect", () => {
      const db = freshDb();
      const id = upsertProspect(db, SAMPLE);
      expect(id).toBeGreaterThan(0);
      const row = getProspectByUsername(db, "alice");
      expect(row?.display_name).toBe("Alice");
    });

    it("updates existing prospect on conflict", () => {
      const db = freshDb();
      insertProspect(db, SAMPLE);
      upsertProspect(db, { ...SAMPLE, display_name: "Alice Updated" });
      const row = getProspectByUsername(db, "alice");
      expect(row?.display_name).toBe("Alice Updated");
    });
  });

  describe("queryByStatus", () => {
    it("returns prospects matching status", () => {
      const db = freshDb();
      insertProspect(db, SAMPLE);
      insertProspect(db, { ...SAMPLE, username: "bob", profile_url: "https://dorahacks.io/bob" });
      const results = queryByStatus(db, "scraped");
      expect(results).toHaveLength(2);
    });

    it("returns empty array when no matches", () => {
      const db = freshDb();
      const results = queryByStatus(db, "messaged");
      expect(results).toHaveLength(0);
    });
  });

  describe("updateStatus", () => {
    it("updates prospect status", () => {
      const db = freshDb();
      const id = insertProspect(db, SAMPLE);
      updateStatus(db, id, "filtered");
      const row = getProspectById(db, id);
      expect(row?.status).toBe("filtered");
    });
  });

  describe("updateStatusWithTimestamp", () => {
    it("updates status and messaged_at", () => {
      const db = freshDb();
      const id = insertProspect(db, SAMPLE);
      const ts = "2026-03-26T12:00:00Z";
      updateStatusWithTimestamp(db, id, "messaged", ts);
      const row = getProspectById(db, id);
      expect(row?.status).toBe("messaged");
      expect(row?.messaged_at).toBe(ts);
    });
  });

  describe("isDuplicate", () => {
    it("returns true for existing username", () => {
      const db = freshDb();
      insertProspect(db, SAMPLE);
      expect(isDuplicate(db, "alice")).toBe(true);
    });

    it("returns false for unknown username", () => {
      const db = freshDb();
      expect(isDuplicate(db, "unknown")).toBe(false);
    });
  });

  describe("countByStatus", () => {
    it("returns zero counts when empty", () => {
      const db = freshDb();
      const counts = countByStatus(db);
      expect(counts.scraped).toBe(0);
      expect(counts.filtered).toBe(0);
      expect(counts.messaged).toBe(0);
    });

    it("counts correctly across statuses", () => {
      const db = freshDb();
      insertProspect(db, SAMPLE);
      insertProspect(db, { ...SAMPLE, username: "bob", profile_url: "https://dorahacks.io/bob" });
      const id1 = 1;
      updateStatus(db, id1, "filtered");

      const counts = countByStatus(db);
      expect(counts.scraped).toBe(1);
      expect(counts.filtered).toBe(1);
    });
  });
});

import Database from "better-sqlite3";
import type { Database as DatabaseType } from "better-sqlite3";

// ---------- Types ----------

export type ProspectStatus =
  | "scraped"
  | "filtered"
  | "queued"
  | "messaged"
  | "replied"
  | "skipped"
  | "failed";

export interface Prospect {
  id: number;
  username: string;
  profile_url: string;
  display_name: string;
  bio: string;
  tags: string;
  source_hackathon: string;
  relevance_score: number | null;
  interest_tag: string | null;
  status: ProspectStatus;
  messaged_at: string | null;
  created_at: string;
  updated_at: string;
}

export type ProspectInsert = Pick<
  Prospect,
  | "username"
  | "profile_url"
  | "display_name"
  | "bio"
  | "tags"
  | "source_hackathon"
>;

export type ProspectUpsert = ProspectInsert;

// ---------- Schema ----------

const SCHEMA_SQL = `
CREATE TABLE IF NOT EXISTS prospects (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  username        TEXT    NOT NULL UNIQUE,
  profile_url     TEXT    NOT NULL,
  display_name    TEXT    NOT NULL DEFAULT '',
  bio             TEXT    NOT NULL DEFAULT '',
  tags            TEXT    NOT NULL DEFAULT '',
  source_hackathon TEXT   NOT NULL DEFAULT '',
  relevance_score REAL,
  interest_tag    TEXT,
  status          TEXT    NOT NULL DEFAULT 'scraped',
  messaged_at     TEXT,
  created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
  updated_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_prospects_status ON prospects(status);
CREATE INDEX IF NOT EXISTS idx_prospects_username ON prospects(username);
CREATE INDEX IF NOT EXISTS idx_prospects_relevance ON prospects(relevance_score);
`;

// ---------- Connection ----------

let _db: DatabaseType | null = null;

export function getDb(dbPath = "outreach.db"): DatabaseType {
  if (!_db) {
    _db = new Database(dbPath);
    _db.pragma("journal_mode = WAL");
    _db.pragma("foreign_keys = ON");
    _db.exec(SCHEMA_SQL);
  }
  return _db;
}

export function closeDb(): void {
  if (_db) {
    _db.close();
    _db = null;
  }
}

// ---------- CRUD ----------

export function insertProspect(
  db: DatabaseType,
  prospect: ProspectInsert,
): number {
  const stmt = db.prepare(`
    INSERT INTO prospects (username, profile_url, display_name, bio, tags, source_hackathon)
    VALUES (@username, @profile_url, @display_name, @bio, @tags, @source_hackathon)
  `);
  const result = stmt.run(prospect);
  return Number(result.lastInsertRowid);
}

export function upsertProspect(
  db: DatabaseType,
  prospect: ProspectUpsert,
): number {
  const stmt = db.prepare(`
    INSERT INTO prospects (username, profile_url, display_name, bio, tags, source_hackathon)
    VALUES (@username, @profile_url, @display_name, @bio, @tags, @source_hackathon)
    ON CONFLICT(username) DO UPDATE SET
      profile_url      = excluded.profile_url,
      display_name     = excluded.display_name,
      bio              = excluded.bio,
      tags             = excluded.tags,
      source_hackathon = excluded.source_hackathon,
      updated_at       = datetime('now')
  `);
  const result = stmt.run(prospect);
  return Number(result.lastInsertRowid);
}

export function queryByStatus(
  db: DatabaseType,
  status: ProspectStatus,
): Prospect[] {
  const stmt = db.prepare(
    "SELECT * FROM prospects WHERE status = ? ORDER BY id",
  );
  return stmt.all(status) as Prospect[];
}

export function updateStatus(
  db: DatabaseType,
  id: number,
  status: ProspectStatus,
): void {
  const stmt = db.prepare(`
    UPDATE prospects
    SET status = ?, updated_at = datetime('now')
    WHERE id = ?
  `);
  stmt.run(status, id);
}

export function updateStatusWithTimestamp(
  db: DatabaseType,
  id: number,
  status: ProspectStatus,
  messagedAt: string,
): void {
  const stmt = db.prepare(`
    UPDATE prospects
    SET status = ?, messaged_at = ?, updated_at = datetime('now')
    WHERE id = ?
  `);
  stmt.run(status, messagedAt, id);
}

export function isDuplicate(db: DatabaseType, username: string): boolean {
  const stmt = db.prepare(
    "SELECT 1 FROM prospects WHERE username = ? LIMIT 1",
  );
  return stmt.get(username) !== undefined;
}

export function getProspectByUsername(
  db: DatabaseType,
  username: string,
): Prospect | undefined {
  const stmt = db.prepare("SELECT * FROM prospects WHERE username = ?");
  return stmt.get(username) as Prospect | undefined;
}

export function getProspectById(
  db: DatabaseType,
  id: number,
): Prospect | undefined {
  const stmt = db.prepare("SELECT * FROM prospects WHERE id = ?");
  return stmt.get(id) as Prospect | undefined;
}

export function countByStatus(
  db: DatabaseType,
): Record<ProspectStatus, number> {
  const stmt = db.prepare(
    "SELECT status, COUNT(*) as count FROM prospects GROUP BY status",
  );
  const rows = stmt.all() as Array<{ status: ProspectStatus; count: number }>;

  const counts: Record<ProspectStatus, number> = {
    scraped: 0,
    filtered: 0,
    queued: 0,
    messaged: 0,
    replied: 0,
    skipped: 0,
    failed: 0,
  };

  for (const row of rows) {
    counts[row.status] = row.count;
  }

  return counts;
}

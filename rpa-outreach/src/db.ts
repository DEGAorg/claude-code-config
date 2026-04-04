import "dotenv/config";
import { Pool } from "@neondatabase/serverless";
import type { Pool as PoolType } from "@neondatabase/serverless";

// ---------- Types ----------

export type { PoolType as DbPool };

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
  id              SERIAL PRIMARY KEY,
  username        TEXT    NOT NULL UNIQUE,
  profile_url     TEXT    NOT NULL,
  display_name    TEXT    NOT NULL DEFAULT '',
  bio             TEXT    NOT NULL DEFAULT '',
  tags            TEXT    NOT NULL DEFAULT '',
  source_hackathon TEXT   NOT NULL DEFAULT '',
  relevance_score REAL,
  interest_tag    TEXT,
  status          TEXT    NOT NULL DEFAULT 'scraped',
  messaged_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_prospects_status ON prospects(status);
CREATE INDEX IF NOT EXISTS idx_prospects_username ON prospects(username);
CREATE INDEX IF NOT EXISTS idx_prospects_relevance ON prospects(relevance_score);
`;

// ---------- Connection ----------

let _pool: PoolType | null = null;

export async function getPool(): Promise<PoolType> {
  if (!_pool) {
    const connectionString = process.env["DATABASE_URL"];
    if (!connectionString) {
      throw new Error(
        "DATABASE_URL is not set. Add it to .env or set it in the environment.",
      );
    }
    _pool = new Pool({ connectionString });
    await _pool.query(SCHEMA_SQL);
  }
  return _pool;
}

export async function closePool(): Promise<void> {
  if (_pool) {
    await _pool.end();
    _pool = null;
  }
}

// ---------- CRUD ----------

export async function insertProspect(
  pool: PoolType,
  prospect: ProspectInsert,
): Promise<number> {
  const result = await pool.query<{ id: number }>(
    `INSERT INTO prospects
       (username, profile_url, display_name, bio, tags, source_hackathon)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id`,
    [
      prospect.username,
      prospect.profile_url,
      prospect.display_name,
      prospect.bio,
      prospect.tags,
      prospect.source_hackathon,
    ],
  );
  return result.rows[0]!.id;
}

export async function upsertProspect(
  pool: PoolType,
  prospect: ProspectUpsert,
): Promise<number> {
  const result = await pool.query<{ id: number }>(
    `INSERT INTO prospects
       (username, profile_url, display_name, bio, tags, source_hackathon)
     VALUES ($1, $2, $3, $4, $5, $6)
     ON CONFLICT(username) DO UPDATE SET
       profile_url      = EXCLUDED.profile_url,
       display_name     = EXCLUDED.display_name,
       bio              = EXCLUDED.bio,
       tags             = EXCLUDED.tags,
       source_hackathon = EXCLUDED.source_hackathon,
       updated_at       = NOW()
     RETURNING id`,
    [
      prospect.username,
      prospect.profile_url,
      prospect.display_name,
      prospect.bio,
      prospect.tags,
      prospect.source_hackathon,
    ],
  );
  return result.rows[0]!.id;
}

export async function queryByStatus(
  pool: PoolType,
  status: ProspectStatus,
): Promise<Prospect[]> {
  const result = await pool.query<Prospect>(
    "SELECT * FROM prospects WHERE status = $1 ORDER BY id",
    [status],
  );
  return result.rows;
}

export async function updateStatus(
  pool: PoolType,
  id: number,
  status: ProspectStatus,
): Promise<void> {
  await pool.query(
    `UPDATE prospects SET status = $1, updated_at = NOW() WHERE id = $2`,
    [status, id],
  );
}

export async function updateStatusWithTimestamp(
  pool: PoolType,
  id: number,
  status: ProspectStatus,
  messagedAt: string,
): Promise<void> {
  await pool.query(
    `UPDATE prospects
     SET status = $1, messaged_at = $2, updated_at = NOW()
     WHERE id = $3`,
    [status, messagedAt, id],
  );
}

export async function isDuplicate(
  pool: PoolType,
  username: string,
): Promise<boolean> {
  const result = await pool.query(
    "SELECT 1 FROM prospects WHERE username = $1 LIMIT 1",
    [username],
  );
  return result.rows.length > 0;
}

export async function getProspectByUsername(
  pool: PoolType,
  username: string,
): Promise<Prospect | undefined> {
  const result = await pool.query<Prospect>(
    "SELECT * FROM prospects WHERE username = $1",
    [username],
  );
  return result.rows[0];
}

export async function getProspectById(
  pool: PoolType,
  id: number,
): Promise<Prospect | undefined> {
  const result = await pool.query<Prospect>(
    "SELECT * FROM prospects WHERE id = $1",
    [id],
  );
  return result.rows[0];
}

export async function countByStatus(
  pool: PoolType,
): Promise<Record<ProspectStatus, number>> {
  const result = await pool.query<{
    status: ProspectStatus;
    count: string;
  }>(
    "SELECT status, COUNT(*) as count FROM prospects GROUP BY status",
  );

  const counts: Record<ProspectStatus, number> = {
    scraped: 0,
    filtered: 0,
    queued: 0,
    messaged: 0,
    replied: 0,
    skipped: 0,
    failed: 0,
  };

  for (const row of result.rows) {
    counts[row.status] = Number(row.count);
  }

  return counts;
}

// ---------- Atomic claim ----------

/**
 * Atomically claim the next prospect with the given status for processing.
 * Uses SELECT ... FOR UPDATE SKIP LOCKED to prevent concurrent operators
 * from claiming the same prospect.
 */
export async function claimNextProspect(
  pool: PoolType,
  fromStatus: ProspectStatus,
  toStatus: ProspectStatus,
): Promise<Prospect | undefined> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await client.query<Prospect>(
      `SELECT * FROM prospects
       WHERE status = $1
       ORDER BY id
       LIMIT 1
       FOR UPDATE SKIP LOCKED`,
      [fromStatus],
    );
    const prospect = result.rows[0];
    if (prospect) {
      await client.query(
        `UPDATE prospects
         SET status = $1, updated_at = NOW()
         WHERE id = $2`,
        [toStatus, prospect.id],
      );
    }
    await client.query("COMMIT");
    return prospect;
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    client.release();
  }
}

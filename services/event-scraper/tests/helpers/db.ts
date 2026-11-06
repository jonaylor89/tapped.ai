import { randomBytes } from "node:crypto";
import pg from "pg";
import { type Db, openDb } from "../../src/db.js";

/**
 * Every test gets its own throwaway schema on a local Postgres (EVENT_SCRAPER_TEST_DATABASE_URL). It holds a stub of
 * the production `scraped_events` table, so the search_path finds it where production finds the real one.
 */
export function testDatabaseUrl(): string {
  const url = process.env.EVENT_SCRAPER_TEST_DATABASE_URL;
  if (!url) throw new Error("Set EVENT_SCRAPER_TEST_DATABASE_URL to a local Postgres (see the README)");
  if (!["127.0.0.1", "localhost"].includes(new URL(url).hostname)) throw new Error("Tests require a local database");
  return url;
}

export const SCRAPED_EVENTS_STUB = `CREATE TABLE scraped_events (
  source text NOT NULL, source_key text NOT NULL, venue_id text, title text, start_time timestamptz,
  event_url text, music_classification text NOT NULL DEFAULT 'music', PRIMARY KEY (source, source_key)
)`;

/** Creates an empty schema with the production stub; returns its name. */
export async function createTestSchema(): Promise<string> {
  const schema = `t_${randomBytes(8).toString("hex")}`;
  const client = new pg.Client({ connectionString: testDatabaseUrl() });
  await client.connect();
  try {
    await client.query(`CREATE SCHEMA ${schema}; SET search_path=${schema}; ${SCRAPED_EVENTS_STUB}`);
  } finally {
    await client.end();
  }
  return schema;
}

export async function openTestDb(): Promise<Db> {
  return openDb({
    url: testDatabaseUrl(),
    schema: await createTestSchema(),
    maxConnections: 3,
    idleTimeoutMs: 100,
  });
}

/** Environment for CLI tests: the scraper's real connection settings, pointed at a fresh test schema. */
export async function testDatabaseEnv(): Promise<{
  EVENT_SCRAPER_DATABASE_URL: string;
  EVENT_SCRAPER_DB_SCHEMA: string;
}> {
  return { EVENT_SCRAPER_DATABASE_URL: testDatabaseUrl(), EVENT_SCRAPER_DB_SCHEMA: await createTestSchema() };
}

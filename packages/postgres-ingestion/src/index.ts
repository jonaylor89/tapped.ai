import { randomUUID } from "node:crypto";
import { Pool } from "pg";

let connection: Pool | undefined;
/** A dedicated member of tapped_ingestion on a private network; never the API owner role. */
export function database(): Pool {
  if (!connection) {
    const url = process.env.INGESTION_DATABASE_URL;
    if (!url) throw new Error("INGESTION_DATABASE_URL is required; no Firestore fallback");
    connection = new Pool({
      connectionString: url,
      max: 2,
      connectionTimeoutMillis: 10_000,
      statement_timeout: 30_000,
    });
    // Do not log connection strings or raw pg errors (they may contain private payloads).
    connection.on("error", () => console.error("Postgres ingestion connection failed"));
  }
  return connection;
}

export async function profile<T>(id: string): Promise<T | null> {
  const result = await database().query("SELECT doc FROM ingestion_profiles WHERE id=$1", [id]);
  return result.rows[0]?.doc ?? null;
}
export async function profileByUsername<T>(username: string): Promise<T | null> {
  const result = await database().query(
    "SELECT doc FROM ingestion_profiles WHERE lower(btrim(username))=lower(btrim($1))",
    [username],
  );
  return result.rows[0]?.doc ?? null;
}
export async function venueUrls(): Promise<string[]> {
  const result = await database().query(
    "SELECT DISTINCT venue_website_url FROM ingestion_profiles WHERE venue_website_url IS NOT NULL",
  );
  return result.rows.flatMap(({ venue_website_url: value }) => {
    const candidate = String(value).trim();
    try {
      const url = new URL(/^https?:\/\//i.test(candidate) ? candidate : `https://${candidate}`);
      return ["https:", "http:"].includes(url.protocol) ? [url.href] : [];
    } catch {
      return [];
    }
  });
}
export async function scrapedLinks(venueIds: string[]): Promise<string[]> {
  const result = await database().query(
    "SELECT DISTINCT source_key FROM scraped_events WHERE venue_id=ANY($1::text[])",
    [venueIds],
  );
  return result.rows.map((row) => row.source_key);
}
export async function hasScrapedLink(key: string): Promise<boolean> {
  const result = await database().query("SELECT EXISTS(SELECT 1 FROM scraped_events WHERE source_key=$1) AS found", [
    key,
  ]);
  return result.rows[0].found;
}
export type EventFacts = {
  isMusicEvent: boolean;
  performers: string[];
  startTime: Date | string;
  endTime: Date | string;
  title?: string | null;
  description?: string | null;
  url?: string | null;
  flierUrl?: string | null;
  runId?: string;
  ticketPrice?: number | null;
  doorPrice?: number | null;
};
/** Only facts/provenance: no embedded private venue records, ratings, accounts or counters. */
export function eventPayload(event: EventFacts): object {
  if (typeof event.isMusicEvent !== "boolean") throw new Error("Invalid event classification");
  for (const amount of [event.ticketPrice, event.doorPrice])
    if (amount != null && (!Number.isFinite(amount) || amount < 0)) throw new Error("Invalid ticket price");
  const start = new Date(event.startTime);
  const end = new Date(event.endTime);
  if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime()) || start > end)
    throw new Error("Invalid event times");
  if (
    !Array.isArray(event.performers) ||
    event.performers.length > 100 ||
    event.performers.some((name) => typeof name !== "string" || !name.trim() || name.length > 200)
  )
    throw new Error("Invalid performers");
  return {
    isMusicEvent: event.isMusicEvent,
    performers: [...new Set(event.performers.map((name) => name.trim()))],
    startTime: start.toISOString(),
    endTime: end.toISOString(),
    title: event.title ?? null,
    description: event.description ?? null,
    url: event.url ?? null,
    flierUrl: event.flierUrl ?? null,
    runId: event.runId ?? null,
    ticketPrice: event.ticketPrice ?? null,
    doorPrice: event.doorPrice ?? null,
  };
}
export async function saveEvent(source: string, key: string, venueId: string, event: EventFacts): Promise<void> {
  await database().query("SELECT ingest_scraped_event($1,$2,$3,$4::jsonb)", [
    source,
    key,
    venueId,
    eventPayload(event),
  ]);
}
export async function startRun(scraperId: string): Promise<string> {
  const id = randomUUID();
  await database().query("INSERT INTO scrape_runs(id,scraper_id) VALUES($1,$2)", [id, scraperId]);
  return id;
}
export async function endRun(id: string, error: string | null): Promise<void> {
  await database().query("UPDATE scrape_runs SET ended_at=now(),error=$2 WHERE id=$1", [id, error]);
}
export async function latestRun(
  scraperId: string,
): Promise<{ id: string; startTime: Date; endTime: Date | null; error: null } | null> {
  const result = await database().query(
    'SELECT id,started_at AS "startTime",ended_at AS "endTime",error FROM scrape_runs WHERE scraper_id=$1 AND error IS NULL ORDER BY started_at DESC LIMIT 1',
    [scraperId],
  );
  return result.rows[0] ?? null;
}
export async function saveRunEvent(
  source: string,
  runId: string,
  key: string,
  venueId: string,
  event: EventFacts,
): Promise<void> {
  const data = eventPayload(event);
  const client = await database().connect();
  try {
    await client.query("BEGIN");
    await client.query(
      "INSERT INTO scrape_results(run_id,source_key,payload) VALUES($1,$2,$3) ON CONFLICT(run_id,source_key) DO NOTHING",
      [runId, key, data],
    );
    await client.query("SELECT ingest_scraped_event($1,$2,$3,$4::jsonb)", [source, key, venueId, data]);
    await client.query("COMMIT");
  } catch {
    await client.query("ROLLBACK");
    throw new Error("Scraped event transaction failed");
  } finally {
    client.release();
  }
}
export async function unclaimedArtist(name: string, genres: string[], venueId?: string): Promise<string> {
  const result = await database().query("SELECT ingest_unclaimed_artist($1,$2,$3) AS id", [
    name,
    genres,
    venueId ?? null,
  ]);
  return result.rows[0].id;
}

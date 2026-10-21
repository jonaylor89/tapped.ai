import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { r2EvidenceStore } from "./evidence";
import { captureObservations, deliveryKey, withFormattingV2 } from "./observations";
import { normalizeVenueRoutes, type VenueRoute } from "./venue-routing";

export * from "./evidence";
export * from "./firestore-crawler";
export * from "./formatting-v2";
export * from "./observations";
export * from "./targets";
export * from "./venue-routing";

let connection: Pool | undefined;
let evidenceStorage: ReturnType<typeof r2EvidenceStore> | undefined;
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
/** Public routing identity catalog, not historical private venue snapshots or processed URL preloads. */
export async function knownVenueRoutes(): Promise<VenueRoute[]> {
  const result = await database().query(
    "SELECT id,venue_website_url FROM ingestion_profiles WHERE venue_website_url IS NOT NULL",
  );
  return result.rows.flatMap((row) => {
    const raw = typeof row.venue_website_url === "string" ? row.venue_website_url.trim() : "";
    try {
      const url = new URL(
        raw.toLowerCase().startsWith("https://") || raw.toLowerCase().startsWith("http://") ? raw : `https://${raw}`,
      );
      // Catalog only: credentials must not hide a competing profile or be copied into discovery evidence.
      // Selected seed validation still rejects credential-bearing URLs before any fetching.
      url.username = "";
      url.password = "";
      return normalizeVenueRoutes([{ venueId: String(row.id), url: url.href }]);
    } catch {
      return [];
    }
  });
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
    "SELECT DISTINCT source_key FROM scraped_events WHERE venue_id=ANY($1::text[]) AND source='event-crawler' AND last_seen_at > now()-interval '6 hours'",
    [venueIds],
  );
  return result.rows.map((row) => row.source_key);
}
export async function hasScrapedLink(key: string, source = "event-crawler"): Promise<boolean> {
  const result = await database().query(
    "SELECT EXISTS(SELECT 1 FROM scraped_events WHERE source=$1 AND source_key_hash=scrape_key_hash($2) AND source_key=$2 AND last_seen_at > now()-interval '6 hours') AS found",
    [source, key],
  );
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
  /** Raw extractor dollar-major values. The ingestion boundary converts to canonical USD cents. */
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
  await saveRunEvent(source, event.runId ?? null, key, venueId, event);
}
export async function startRun(
  scraperId: string,
  source = "legacy-scrapers",
  parserVersion = "event-facts-v1",
): Promise<string> {
  const id = randomUUID();
  await database().query("INSERT INTO scrape_runs(id,scraper_id,source,parser_version) VALUES($1,$2,$3,$4)", [
    id,
    scraperId,
    source,
    parserVersion,
  ]);
  return id;
}
export async function endRun(id: string, error: string | null): Promise<void> {
  await database().query(
    "UPDATE scrape_runs SET ended_at=now(),error=$2,status=CASE WHEN $2::text IS NULL THEN 'completed' ELSE 'failed' END WHERE id=$1",
    [id, error],
  );
}
export async function latestRun(
  scraperId: string,
  source = "legacy-scrapers",
): Promise<{ id: string; startTime: Date; endTime: Date | null; error: null } | null> {
  const result = await database().query(
    'SELECT id,started_at AS "startTime",ended_at AS "endTime",error FROM scrape_runs WHERE scraper_id=$1 AND source=$2 AND status=\'completed\' ORDER BY started_at DESC LIMIT 1',
    [scraperId, source],
  );
  return result.rows[0] ?? null;
}
export async function saveRunEvent(
  source: string,
  runId: string | null,
  key: string,
  venueId: string,
  event: EventFacts,
): Promise<void> {
  const pool = database();
  // Compatibility producers use the durable run start as their capture time. New producers should
  // use captureObservations directly with actual per-response timestamps and stable delivery IDs.
  const run = runId ? await pool.query("SELECT started_at FROM scrape_runs WHERE id=$1", [runId]) : null;
  if (runId && !run?.rows.length) throw new Error("Unknown scrape run");
  const observedAt = run?.rows[0].started_at.toISOString() ?? new Date().toISOString();
  await captureObservations(
    pool,
    (evidenceStorage ??= r2EvidenceStore()),
    [
      withFormattingV2(
        {
          source,
          sourceKey: key,
          deliveryKey: deliveryKey(source, runId ?? observedAt, key),
          observedAt,
          parserVersion: "event-facts-v1",
          venueId,
          runId,
          data: event as unknown as Record<string, unknown>,
        },
        "usd_major",
      ),
    ],
    Buffer.from(JSON.stringify(event)),
    { retention: "evidence", contentType: "application/json" },
  );
}

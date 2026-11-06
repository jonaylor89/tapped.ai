#!/usr/bin/env node
/**
 * event-scraper CLI. Every network client is built here from the configuration and can
 * be replaced (tests inject fakes through `main(argv, { services })`).
 *
 *   run-once            fetch every due source once, then publish the outbox
 *   loop                run-once every tick, publish and discover on their own intervals, until SIGTERM/SIGINT
 *   discover            one venue-discovery pass (feeds -> resolve -> source finder -> prove)
 *   prove <id>          prove one candidate now
 *   publish             drain the publish outbox
 *   export-candidates   write the human review list (promoted + needs_review) as JSON and CSV
 *   add-source          register a calendar/iCal/listing URL for a venue (or from a promoted candidate)
 *   import-venues       pull the venue snapshot (file or production's read-only view) into the scraper schema
 *   import-sqlite       one-off: copy an old SQLite state file into Postgres
 *   status              counts of sources, jobs, candidates, open alerts
 */
import { realpathSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";
import { ConfigError, loadConfig, type ScraperConfig } from "./config.js";
import {
  addSource,
  all,
  type Db,
  getCandidate,
  getKv,
  getVenue,
  hostSlotStore,
  listAlerts,
  listCandidates,
  listSources,
  one,
  openDb,
  pruneHostSlots,
  pruneJobs,
  pruneKv,
  pruneOutbox,
  pruneRawPages,
  setKv,
  updateCandidate,
} from "./db.js";
import { isTicketingUrl } from "./denylist.js";
import { createBandsintownClientFromEnv } from "./discovery/bandsintown.js";
import { writeReviewList } from "./discovery/export.js";
import { OverpassHttpClient } from "./discovery/osm.js";
import { createPlacesClientFromEnv } from "./discovery/places.js";
import { proveCandidate } from "./discovery/prove.js";
import { syncVenuePlaceAliases } from "./discovery/resolve.js";
import { seedKnownVenues } from "./discovery/seed.js";
import { runDiscovery } from "./discovery-runner.js";
import { parseRoutes } from "./extract/routes.js";
import { createHttpClient } from "./fetch.js";
import { importSqlite } from "./import-sqlite.js";
import { llmClientFromEnv } from "./llm/openai.js";
import { pageStoreFromEnv } from "./pages.js";
import { NdjsonPublisher, PostgresIngestionPublisher, publishOutbox } from "./publish/publisher.js";
import { JsonFileVenueSnapshot, syncVenueSnapshot, venueSnapshotFromEnv } from "./publish/venues-snapshot.js";
import {
  createLlmExtractor,
  dailyLlmBudget,
  LLM_PAGES_KEY_PREFIX,
  type Logger,
  runOnce,
  runPublish,
} from "./runner.js";
import type {
  BandsintownClient,
  CandidateStatus,
  Clock,
  HttpClient,
  LlmClient,
  OverpassClient,
  PlacesClient,
  Publisher,
  Sleep,
  SourceKind,
  VenueSnapshotSource,
} from "./types.js";
import { CANDIDATE_STATUSES, realSleep, SOURCE_KINDS, systemClock } from "./types.js";
import { isValidTimeZone } from "./validate/time.js";

type Env = Record<string, string | undefined>;

const DAY = 24 * 60 * 60 * 1000;

export interface Services {
  http: HttpClient;
  llm: LlmClient | null;
  places: PlacesClient | null;
  overpass: OverpassClient | null;
  bandsintown: BandsintownClient | null;
  publisher: Publisher | null;
  venueSnapshot: VenueSnapshotSource | null;
  clock: Clock;
  sleep: Sleep;
}

/**
 * Builds the real network clients for the enabled features only. Keys are read by the clients, never printed. With
 * `db`, the HTTP client's per-host politeness slots live in Postgres, shared with every other process and laptop.
 */
export function buildServices(
  config: ScraperConfig,
  env: Env,
  overrides: Partial<Services> = {},
  db: Db | null = null,
): Services {
  const clock = overrides.clock ?? systemClock;
  const sleep = overrides.sleep ?? realSleep;
  const lazy = <K extends keyof Services>(key: K, make: () => Services[K]): Services[K] =>
    key in overrides ? (overrides[key] as Services[K]) : make();
  return {
    clock,
    sleep,
    http: lazy("http", () =>
      createHttpClient({
        clock,
        sleep,
        minHostIntervalMs: config.http.minHostIntervalMs,
        timeoutMs: config.http.timeoutMs,
        slotStore: db ? hostSlotStore(db) : null,
      }),
    ),
    llm: lazy("llm", () => (config.features.llm ? llmClientFromEnv(env) : null)),
    places: lazy("places", () => (config.features.places ? createPlacesClientFromEnv(env) : null)),
    overpass: lazy("overpass", () => (config.features.osm ? new OverpassHttpClient({ clock, sleep }) : null)),
    bandsintown: lazy("bandsintown", () =>
      config.features.bandsintown ? createBandsintownClientFromEnv(env, { enabled: true, clock, sleep }) : null,
    ),
    publisher: lazy("publisher", () => {
      if (config.publish.mode === "off") return null;
      if (config.publish.mode === "postgres") return new PostgresIngestionPublisher();
      return new NdjsonPublisher(config.publish.dryRunPath);
    }),
    venueSnapshot: lazy("venueSnapshot", () => venueSnapshotFromEnv(env, clock, db)),
  };
}

export interface MainIo {
  env?: Env;
  stdout?: (text: string) => void;
  stderr?: (text: string) => void;
  services?: Partial<Services>;
  /** Stops `loop` (tests); SIGTERM/SIGINT do the same in the real process. */
  signal?: AbortSignal;
}

const USAGE = `Usage: event-scraper <command> [options]

Commands:
  run-once [--max-jobs N] [--no-publish]
  loop [--no-publish] [--no-discover]
  discover [--city NAME] [--skip-prove]
  prove <candidateId>
  publish [--limit N]
  export-candidates [--out DIR] [--status promoted,needs_review]
  add-source --url URL (--venue ID | --listing | --kind multi_venue --route KEY=VENUE_ID|ignore ...) [--kind html|ical|wp_tribe|squarespace|listing]
             [--timezone IANA] [--label TEXT]
  add-source --candidate ID [--venue ID]      (register a reviewed, promoted candidate's proven source)
  import-venues [--file venues.json]
  import-sqlite FILE                          (one-off: copy an old SQLite state file into Postgres)
  seed-venues --city NAME                     (send known venues in a city through find-source -> prove)
  status

Global options: --config FILE (cities/listings JSON)
Environment variables are documented in services/event-scraper/README.md.`;

const OPTIONS = {
  config: { type: "string" },
  "max-jobs": { type: "string" },
  "no-publish": { type: "boolean" },
  "no-discover": { type: "boolean" },
  city: { type: "string" },
  "skip-prove": { type: "boolean" },
  limit: { type: "string" },
  out: { type: "string" },
  status: { type: "string" },
  url: { type: "string" },
  venue: { type: "string" },
  listing: { type: "boolean" },
  kind: { type: "string" },
  timezone: { type: "string" },
  label: { type: "string" },
  route: { type: "string", multiple: true },
  candidate: { type: "string" },
  file: { type: "string" },
  help: { type: "boolean", short: "h" },
} as const;

class UsageError extends Error {}

function positiveInt(value: string | undefined, name: string): number | undefined {
  if (value === undefined) return undefined;
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) throw new UsageError(`--${name} must be a positive integer`);
  return n;
}

function discoveryOptions(config: ScraperConfig) {
  return {
    cities: config.cities,
    listings: config.features.listings ? config.listings : [],
    bandsintownArtists: config.bandsintownArtists,
    placesBudget: config.discovery.placesBudgetPerRun,
    placesQueries: config.discovery.placesQueries,
    placesMaxPages: config.discovery.placesMaxPages,
    placesRefreshMs: config.discovery.placesRefreshMs,
    osmRefreshMs: config.discovery.osmRefreshMs,
    listingsRefreshMs: config.discovery.listingsRefreshMs,
    bandsintownRefreshMs: config.discovery.bandsintownRefreshMs,
    bandsintownMaxArtists: config.discovery.bandsintownMaxArtists,
    minProvenEvents: config.discovery.minProvenEvents,
    proveLimit: config.discovery.proveLimitPerRun,
  };
}

function runnerOptions(config: ScraperConfig, maxJobs?: number) {
  return {
    maxJobs: maxJobs ?? config.scrape.maxJobsPerRun,
    concurrency: config.scrape.concurrency,
    productiveIntervalMs: config.scrape.productiveIntervalMs,
    maxIntervalMs: config.scrape.maxIntervalMs,
    llmMaxPages: config.scrape.llmMaxPagesPerDay,
    // Standalone mode (EVENT_SCRAPER_PUBLISH=off): nothing would ever drain the outbox, so do not fill it.
    enqueueOutbox: config.publish.mode !== "off",
  };
}

export const HOUSEKEEPING_KEY = "housekeeping:last_run_at";
const HOUSEKEEPING_EVERY_MS = 6 * 60 * 60 * 1000;

export interface HousekeepingResult {
  jobs: number;
  rawPages: number;
  outbox: number;
  kv: number;
  hostSlots: number;
}

/**
 * Retention for the scraper schema, run from every command that does work (run-once, loop, discover) and at most
 * once per 6 hours (timestamp in kv), so timer-driven deployments never grow the file without bound:
 * finished jobs after 30 days; published outbox rows after 30 days (and, with publishing off, unpublished rows too,
 * so their evidence becomes prunable); unreferenced raw pages after 90 days; old daily counters and host slots.
 */
export async function runHousekeeping(
  db: Db,
  options: { now: number; publishOff: boolean; force?: boolean },
): Promise<HousekeepingResult | null> {
  const { now } = options;
  const last = Number((await getKv(db, HOUSEKEEPING_KEY)) ?? 0);
  if (!options.force && Number.isFinite(last) && now - last < HOUSEKEEPING_EVERY_MS) return null;
  await setKv(db, HOUSEKEEPING_KEY, String(now), now);
  const outbox = await pruneOutbox(db, {
    publishedBefore: now - 30 * DAY,
    pendingBefore: options.publishOff ? now - 30 * DAY : null,
  });
  return {
    jobs: await pruneJobs(db, now - 30 * DAY),
    outbox,
    rawPages: await pruneRawPages(db, now - 90 * DAY),
    kv: await pruneKv(db, LLM_PAGES_KEY_PREFIX, now - 7 * DAY),
    hostSlots: await pruneHostSlots(db, now - DAY),
  };
}

/** Compact run summary for stdout (per-source rows only for sources that did something notable). */
function compactRun(summary: Awaited<ReturnType<typeof runOnce>>) {
  return {
    scheduled: summary.scheduled,
    processed: summary.processed,
    totals: summary.totals,
    llmPages: summary.llmPages,
    sources: summary.results.map((r) => ({
      sourceId: r.sourceId,
      outcome: r.outcome,
      status: r.status,
      extractor: r.extractor,
      extracted: r.extracted,
      valid: r.valid,
      rejected: r.rejectedReasons,
      changes: r.reconcile,
      zeroResults: r.zeroResults || undefined,
      nextFetchInHours: r.nextDelayMs == null ? null : Math.round((r.nextDelayMs / 3_600_000) * 10) / 10,
      message: r.message,
    })),
  };
}

async function importVenues(db: Db, services: Services, file: string | undefined, clock: Clock) {
  const source = file ? new JsonFileVenueSnapshot(resolve(file), clock) : services.venueSnapshot;
  if (!source) {
    throw new UsageError(
      "No venue snapshot configured: pass --file or set VENUE_SNAPSHOT_FILE / VENUE_SNAPSHOT_DATABASE_URL",
    );
  }
  const now = clock.now().getTime();
  const synced = await syncVenueSnapshot(db, source, now);
  const aliases = await syncVenuePlaceAliases(db, now);
  return { ...synced, aliasesAssigned: aliases.assigned, sharedPlaceIds: aliases.shared };
}

async function addSourceCommand(db: Db, values: Record<string, unknown>, clock: Clock) {
  const now = clock.now().getTime();
  if (values.candidate !== undefined) {
    const id = positiveInt(values.candidate as string, "candidate") as number;
    const candidate = await getCandidate(db, id);
    if (!candidate) throw new UsageError(`Unknown candidate ${id}`);
    if (candidate.status !== "promoted" || !candidate.sourceUrl || !candidate.sourceKind) {
      throw new UsageError(`Candidate ${id} is ${candidate.status}; only promoted candidates with a proven source`);
    }
    const venueId = (values.venue as string | undefined) ?? candidate.matchedVenueId;
    if (!venueId) {
      throw new UsageError(
        `Candidate ${id} has no production venue yet; create it in production after review, import-venues, then pass --venue`,
      );
    }
    const timezone = (values.timezone as string | undefined) ?? candidate.timezone;
    if (!timezone || !isValidTimeZone(timezone)) throw new UsageError("A valid --timezone is required");
    const source = await addSource(
      db,
      {
        venueId,
        kind: candidate.sourceKind,
        url: candidate.sourceUrl,
        timezone,
        label: candidate.name,
        origin: "discovery",
      },
      now,
    );
    await updateCandidate(db, id, { matchedVenueId: venueId, statusReason: `source_added:${source.id}` }, now);
    return source;
  }
  const url = values.url as string | undefined;
  if (!url) throw new UsageError("--url is required");
  if (isTicketingUrl(url)) throw new UsageError("Ticketing platforms are never used as sources");
  const kind = ((values.kind as string | undefined) ?? (values.listing ? "listing" : "html")) as SourceKind;
  if (!SOURCE_KINDS.includes(kind)) throw new UsageError(`--kind must be one of ${SOURCE_KINDS.join(", ")}`);
  const venueId = (values.venue as string | undefined) ?? null;
  const venueRoutes = kind === "multi_venue" ? parseRoutes((values.route as string[] | undefined) ?? []) : null;
  if (kind === "multi_venue" && !Object.keys(venueRoutes ?? {}).length)
    throw new UsageError("--kind multi_venue needs --route KEY=VENUE_ID or --route KEY=ignore for each venue");
  if (kind === "multi_venue" && venueId) throw new UsageError("A multi-venue source has routes; omit --venue");
  for (const target of Object.values(venueRoutes ?? {}))
    if (target && !(await getVenue(db, target as string)))
      throw new UsageError(`Unknown venue ${target}; run import-venues first`);
  if (!venueId && kind !== "listing" && kind !== "multi_venue")
    throw new UsageError("--venue is required (or --listing for a city listing)");
  if (venueId && kind === "listing") throw new UsageError("Listing sources cover many venues; omit --venue");
  const venue = venueId ? await getVenue(db, venueId) : null;
  if (venueId && !venue) throw new UsageError(`Unknown venue ${venueId}; run import-venues first`);
  const timezone = (values.timezone as string | undefined) ?? venue?.timezone ?? null;
  if (!timezone || !isValidTimeZone(timezone)) throw new UsageError("A valid IANA --timezone is required");
  return addSource(
    db,
    {
      venueId,
      venueRoutes,
      kind,
      url,
      timezone,
      label: (values.label as string | undefined) ?? venue?.name ?? null,
      origin: "manual",
    },
    now,
  );
}

async function status(db: Db) {
  const jobs = await all(
    db,
    "SELECT kind, status, COUNT(*) AS n FROM jobs GROUP BY kind, status ORDER BY kind, status",
  );
  const candidates: Record<string, number> = {};
  for (const c of await listCandidates(db)) candidates[c.status] = (candidates[c.status] ?? 0) + 1;
  const pendingOutbox = (await one(db, "SELECT COUNT(*) AS n FROM publish_outbox WHERE published_at IS NULL")) as {
    n: number;
  };
  return {
    sources: { enabled: (await listSources(db, { enabled: true })).length, total: (await listSources(db)).length },
    jobs,
    candidates,
    pendingOutbox: Number(pendingOutbox.n),
    openAlerts: (await listAlerts(db, { open: true })).map((a) => ({
      kind: a.kind,
      sourceId: a.sourceId,
      message: a.message,
    })),
  };
}

/** Entry point. Returns the process exit code. */
export async function main(argv: string[], io: MainIo = {}): Promise<number> {
  const env = io.env ?? process.env;
  const out = io.stdout ?? ((text: string) => process.stdout.write(text));
  const err = io.stderr ?? ((text: string) => process.stderr.write(text));
  const print = (value: unknown) => out(`${JSON.stringify(value, null, 2)}\n`);
  const log: Logger = (event, data) => err(`${JSON.stringify({ at: new Date().toISOString(), event, ...data })}\n`);

  let parsed: ReturnType<typeof parseArgs<{ options: typeof OPTIONS; allowPositionals: true }>>;
  try {
    parsed = parseArgs({ args: argv, options: OPTIONS, allowPositionals: true, strict: true });
  } catch (error) {
    err(`${(error as Error).message}\n\n${USAGE}\n`);
    return 2;
  }
  const { values, positionals } = parsed;
  const command = positionals[0];
  if (!command || values.help) {
    out(`${USAGE}\n`);
    return command ? 0 : 2;
  }

  let config: ScraperConfig;
  try {
    config = loadConfig(env, values.config ? { configFile: values.config } : {});
  } catch (error) {
    if (error instanceof ConfigError) {
      err(`${error.message}\n`);
      return 2;
    }
    throw error;
  }

  const known = [
    "run-once",
    "loop",
    "discover",
    "prove",
    "publish",
    "export-candidates",
    "add-source",
    "import-venues",
    "import-sqlite",
    "seed-venues",
    "status",
  ];
  if (!known.includes(command)) {
    err(`Unknown command "${command}"\n\n${USAGE}\n`);
    return 2;
  }

  const db = await openDb({
    url: config.databaseUrl,
    schema: config.dbSchema,
    maxConnections: config.maxDbConnections,
    pages: pageStoreFromEnv(env, config.dataDir),
  });
  const services = buildServices(config, env, io.services, db);
  const clock = services.clock;
  try {
    // Every LLM page (scraping and proving, in any process) is charged to one daily counter in Postgres.
    const fallback = () =>
      services.llm ? createLlmExtractor({ budget: dailyLlmBudget(db, config.scrape.llmMaxPagesPerDay, clock) }) : null;
    const housekeeping = async () => {
      const pruned = await runHousekeeping(db, {
        now: clock.now().getTime(),
        publishOff: config.publish.mode === "off",
      });
      if (pruned && Object.values(pruned).some((n) => n > 0)) log("pruned", { ...pruned });
    };
    const discover = async (city?: string, skipProve?: boolean) =>
      runDiscovery(
        {
          db,
          http: services.http,
          places: services.places,
          overpass: services.overpass,
          bandsintown: services.bandsintown,
          llm: services.llm,
          fallback: fallback(),
          clock,
          sleep: services.sleep,
          log,
        },
        { ...discoveryOptions(config), city: city ?? null, skipProve },
      );
    const publisher = values["no-publish"] ? null : services.publisher;

    switch (command) {
      case "run-once": {
        const run = await runOnce(
          { db, http: services.http, llm: services.llm, clock, log },
          runnerOptions(config, positiveInt(values["max-jobs"], "max-jobs")),
        );
        const published = await runPublish(db, publisher, clock);
        await housekeeping();
        print({ run: compactRun(run), publish: published });
        return 0;
      }
      case "loop": {
        const signal = io.signal ?? processSignal();
        let lastPublish = 0;
        let lastDiscover = 0;
        while (!signal.aborted) {
          const run = await runOnce({ db, http: services.http, llm: services.llm, clock, log }, runnerOptions(config));
          if (run.processed) log("run_once", { processed: run.processed, ...run.totals });
          const now = clock.now().getTime();
          if (publisher && now - lastPublish >= config.loop.publishEveryMs) {
            lastPublish = now;
            const published = await runPublish(db, publisher, clock);
            if (published?.considered) log("publish", { ...published });
          }
          if (!values["no-discover"] && now - lastDiscover >= config.loop.discoverEveryMs) {
            lastDiscover = now;
            try {
              const d = await discover();
              log("discover", { units: d.units.length, placesRequests: d.placesRequests, pipeline: d.pipeline });
            } catch (error) {
              log("discover_failed", { error: (error as Error).message });
            }
          }
          await housekeeping();
          if (signal.aborted) break;
          await abortableSleep(services.sleep, config.loop.tickMs, signal);
        }
        return 0;
      }
      case "discover": {
        const d = await discover(values.city, values["skip-prove"]);
        await housekeeping();
        print({
          scheduled: d.scheduled,
          units: d.units,
          placesRequests: d.placesRequests,
          placesBudget: d.placesBudget,
          placesBudgetExhausted: d.placesBudgetExhausted,
          pipeline: d.pipeline,
          promoted: d.provedDetails.filter((p) => p.status === "promoted").map((p) => p.candidateId),
        });
        return 0;
      }
      case "prove": {
        const id = positiveInt(positionals[1] ?? values.candidate, "candidate");
        if (!id) throw new UsageError("prove needs a candidate id");
        if (!(await getCandidate(db, id))) throw new UsageError(`Unknown candidate ${id}`);
        const result = await proveCandidate(db, id, {
          http: services.http,
          llm: services.llm,
          fallback: fallback(),
          minEvents: config.discovery.minProvenEvents,
          clock,
        });
        print(result);
        return 0;
      }
      case "publish": {
        if (!publisher) {
          print({ publish: null, message: "publishing is off (EVENT_SCRAPER_PUBLISH=off)" });
          return 0;
        }
        const limit = positiveInt(values.limit, "limit");
        const published = await publishOutbox(db, publisher, {
          limit,
          now: () => clock.now().getTime(),
        });
        print({ publish: published });
        return 0;
      }
      case "export-candidates": {
        const statuses = values.status
          ? (values.status.split(",").map((s) => s.trim()) as CandidateStatus[])
          : undefined;
        if (statuses?.some((s) => !CANDIDATE_STATUSES.includes(s))) {
          throw new UsageError(`--status must be a comma list of ${CANDIDATE_STATUSES.join(", ")}`);
        }
        const written = await writeReviewList(db, resolve(values.out ?? resolve(config.dataDir, "review")), {
          statuses,
          now: clock.now(),
        });
        print(written);
        return 0;
      }
      case "add-source": {
        print(await addSourceCommand(db, values, clock));
        return 0;
      }
      case "seed-venues": {
        const city = config.cities.find((c) => c.name.toLowerCase() === (values.city ?? "").toLowerCase());
        if (!city)
          throw new Error(`seed-venues needs --city with one of: ${config.cities.map((c) => c.name).join(", ")}`);
        print(await seedKnownVenues(db, city, clock.now().getTime()));
        return 0;
      }
      case "import-sqlite": {
        const file = positionals[1] ?? values.file;
        if (!file) throw new UsageError("import-sqlite needs a file path");
        print(await importSqlite(db, resolve(file)));
        return 0;
      }
      case "import-venues": {
        print(await importVenues(db, services, values.file, clock));
        return 0;
      }
      case "status": {
        print(await status(db));
        return 0;
      }
    }
    return 2;
  } catch (error) {
    if (error instanceof UsageError) {
      err(`${error.message}\n`);
      return 2;
    }
    err(`event-scraper ${command} failed: ${(error as Error).message}\n`);
    return 1;
  } finally {
    await db.close();
  }
}

function processSignal(): AbortSignal {
  const controller = new AbortController();
  const stop = () => controller.abort();
  process.once("SIGTERM", stop);
  process.once("SIGINT", stop);
  return controller.signal;
}

async function abortableSleep(sleep: Sleep, ms: number, signal: AbortSignal): Promise<void> {
  if (signal.aborted) return;
  await Promise.race([
    await sleep(ms),
    new Promise<void>((resolveAbort) => signal.addEventListener("abort", () => resolveAbort(), { once: true })),
  ]);
}

function isEntryPoint(): boolean {
  const entry = process.argv[1];
  if (!entry) return false;
  try {
    return import.meta.url === pathToFileURL(realpathSync(entry)).href;
  } catch {
    return false;
  }
}

if (isEntryPoint()) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (error) => {
      process.stderr.write(`event-scraper: ${(error as Error).message}\n`);
      process.exit(1);
    },
  );
}

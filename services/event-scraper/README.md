# @tapped/event-scraper

Standalone scraper for live music events (plus comedy, open mic, theater and dance) taken from venues' **own**
websites, with automated discovery of new venues. It replaces `services/event-crawler`, which is left untouched.

> **Status: field-tested on Richmond, VA (2026-11-03), never published to production.** It runs manually from a
> laptop only. Publishing to production (`EVENT_SCRAPER_PUBLISH=postgres`) needs the owner's explicit approval. See
> [Richmond field test](#richmond-field-test-2026-11-03) and [What is not done](#what-is-not-done).

## Architecture

```
                         ┌──────────────────────── event-scraper process (one Node 22 process) ────────────────────────┐
                         │                                                                                              │
 venue snapshot  ──read──┤  import-venues ─► venues + venue_place_ids                                                   │
 (JSON file or           │                                                                                              │
  read-only PG view)     │  SCRAPE LOOP (runner.ts)                                                                     │
                         │   sources ─► fetch_source job (SQLite queue, leases) ─► PoliteHttpClient                      │
                         │     (robots.txt, per-host politeness, conditional GET, ticketing denylist, raw bytes kept)   │
                         │   ─► extract a LIST of events, cheapest first:                                               │
                         │        iCal ─► WP The Events Calendar JSON ─► Squarespace JSON ─► JSON-LD ─► microdata        │
                         │        ─► calendar endpoints advertised on the venue's own domain ─► LLM fallback (opt-in)   │
                         │   ─► validate (year inference, IANA tz, overnight ends, evidence quotes, category)          │
                         │   ─► reconcile vs last snapshot (new / updated / canceled after 2 misses / zero-result alert)│
                         │   ─► publish_outbox ─────────────────────────────────────────────────────────────┐          │
                         │                                                                                  │          │
                         │  DISCOVERY LOOP (discovery-runner.ts)                                            │          │
                         │   OSM Overpass + Google Places grid ─► city listing pages ─► Bandsintown (opt-in)│          │
                         │   ─► venue_candidates ─► resolve identity (place-id clustering + aliases)        │          │
                         │   ─► find event source on the venue's own site ─► PROVE (≥3 valid upcoming)      │          │
                         │   ─► `promoted` ─► export-candidates (JSON + CSV for human review)               │          │
                         │                                                                                  ▼          │
                         │   SQLite file (node:sqlite, WAL): sources, fetch_state, raw_pages, jobs, events,  publish    │
                         │   event_changes, alerts, venue_candidates, venue_place_ids, publish_outbox        │          │
                         └──────────────────────────────────────────────────────────────────────────────────┼──────────┘
                                                                                                            │
                     EVENT_SCRAPER_PUBLISH=ndjson (default): local NDJSON dry run                           │
                     EVENT_SCRAPER_PUBLISH=postgres: captureObservations (@tapped/postgres-ingestion) ◄─────┘
                       with the restricted INGESTION_DATABASE_URL + private R2 evidence
```

### Separation from production

- **All working state is local.** Sources, fetch state and conditional-GET validators, the job queue with leases,
  event snapshots, alerts, venue candidates, place-id aliases, the publish outbox and the raw page bytes kept as
  evidence live in one SQLite file (`node:sqlite`, no native deps). **Production Postgres is not the queue.**
- **Two narrow, optional links.** (1) A read-only venue snapshot pull (`import-venues`), and (2) the publish step,
  which pushes validated observations through the existing producer contract (`captureObservations`, see
  `platform/SCRAPER_INGESTION.md` "Shared producer contract"). With `EVENT_SCRAPER_PUBLISH=ndjson` (default) or
  `off`, and `VENUE_SNAPSHOT_FILE` for venues, the scraper runs fully standalone.
- **No automatic venue creation.** Discovery only promotes candidates for human review.

### The no-ticketing rule

No ticketing platform of any kind (Ticketmaster, Eventbrite, DICE, AXS, SeeTickets, TicketWeb, Etix, Tixr, ...) is
ever a fetch target, an adapter or a discovery feed. `src/denylist.ts` (~75 domains plus brand labels on any TLD) is
enforced:

- in `PoliteHttpClient` before every request (including robots.txt) and on every redirect hop. A source that
  redirects to a ticketing platform is disabled and raises a `ticketing_blocked` alert;
- when adding sources (`add-source` refuses them), in the config file (ticketing listing URLs are rejected), in
  endpoint discovery, the source finder and the listing feed.

Ticket links found on a venue's own page are kept as a `ticketUrl` **string** on the event and never fetched.

### Multi place-id venues (Google Places)

One real venue often has several Google place ids: the business, the building/premise, the street address and the
neighborhood. `src/discovery/resolve.ts` solves this:

1. Places requests ask for `id, displayName, types, primaryType, location, websiteUri, formattedAddress,
   businessStatus`.
2. Pure geocode results (`premise`, `subpremise`, `street_address`, `route`, `locality`, `neighborhood`,
   `postal_code`, `political`, `plus_code`, ...) are never identities. Point geocodes (premise/street address) are
   attached as aliases only when unambiguous; areas are discarded.
3. Remaining places are clustered by proximity (~75 m) **and** normalized-name similarity. A shared website
   registrable domain only widens the distance; two different domains block a merge; a domain alone never merges.
4. The establishment-typed place (`live_music_venue`, `concert_hall`, `performing_arts_theater`, `comedy_club`,
   `night_club`, `bar`, `restaurant`, ...) becomes canonical; **every** member id is stored in `venue_place_ids`, so
   any of them resolves to the same venue or candidate. Production venues' place ids are registered on import.
5. Same building but clearly different names (rooms, e.g. "The Hi-Fi" vs "Hi-Fi Annex") become `needs_review` and
   are never auto-merged; no aliases are assigned while identity is in doubt.

OSM features and listing/Bandsintown venues go through the same identity matching (place id, then geo + name, then
name within the same city), so one venue found by several feeds ends up as one candidate.

## Scrape loop details

- **Sources** are explicit URLs per venue (calendar page, `.ics`, TEC REST endpoint, Squarespace `?format=json`, or a
  city `listing`). The venue always comes from the source row, never from the domain.
- **Scheduling** (one pending `fetch_source` job per enabled source, dedupe key `fetch_source:<id>`):
  events changed → next fetch after `EVENT_SCRAPER_PRODUCTIVE_INTERVAL_HOURS` (default 24h); 304 / identical bytes /
  nothing changed / zero events → exponential backoff up to `EVENT_SCRAPER_MAX_INTERVAL_DAYS` (default 7);
  fetch failures → 1h, 2h, 4h ... 24h with a `fetch_failed` alert after 3 in a row; robots.txt disallow → weekly
  retry with a `robots_blocked` alert.
- **Identical bytes** skip extraction when the previous extraction used only that page; when endpoints were followed
  (or TEC paginated) the page is re-extracted.
- **Reconcile** only runs after a successful fetch whose body parsed without extractor errors, so a broken site or
  parser never cancels events. Cancellation needs 2 consecutive successful fetches that miss an event; a
  zero-result fetch on a previously productive source raises a `zero_results` alert instead.
- **LLM fallback** (opt-in, `EVENT_SCRAPER_LLM=1`) runs only when no structured extractor found anything, is capped
  per UTC day across all runs and processes (`EVENT_SCRAPER_LLM_MAX_PAGES`, counted in SQLite), uses a strict JSON schema with venue timezone + "today" context, and every
  evidence quote must appear verbatim in the page text or the event is rejected.

## Commands

From `services/event-scraper` after `pnpm --filter @tapped/postgres-ingestion build && pnpm --filter
@tapped/event-scraper build`. Every command prints JSON to stdout.

| Command | What it does |
|---------|--------------|
| `import-venues [--file venues.json]` | Pull the read-only venue snapshot (file, or `VENUE_SNAPSHOT_*`) and register place-id aliases |
| `add-source --venue ID --url URL [--kind html\|ical\|wp_tribe\|squarespace] [--timezone IANA] [--label TEXT]` | Register a venue's calendar URL (timezone defaults to the venue's) |
| `add-source --listing --url URL --timezone IANA` | Register a city listing source (not a ticketing site) |
| `add-source --candidate ID --venue ID` | After review: register a promoted candidate's proven source for an existing venue |
| `run-once [--max-jobs N] [--no-publish]` | Fetch every due source once, then drain the outbox |
| `loop [--no-publish] [--no-discover]` | Long-running: run-once every tick, publish and discover on their intervals; stops on SIGTERM/SIGINT |
| `discover [--city NAME] [--skip-prove]` | One discovery pass: feeds → resolve → source finder → prove |
| `prove <candidateId>` | Prove one candidate now |
| `publish [--limit N]` | Drain the publish outbox |
| `export-candidates [--out DIR] [--status promoted,needs_review]` | Write the human review list (JSON + CSV) |
| `status` | Sources, jobs, candidates, pending outbox, open alerts |

Global options: `--config FILE` (cities/listings JSON, see `examples/config.example.json`) and `--db FILE`.

### Config file (`EVENT_SCRAPER_CONFIG`)

```json
{
  "cities": [{ "name": "Indianapolis", "bbox": { "south": 39.63, "west": -86.33, "north": 39.93, "east": -85.94 },
               "timezone": "America/Indiana/Indianapolis", "cellMeters": 2500 }],
  "listings": [{ "url": "https://alt-weekly.example/music/calendar", "city": "Indianapolis",
                 "timezone": "America/Indiana/Indianapolis" }],
  "placesQueries": ["live music venue", "jazz club", "concert hall", "comedy club", "theater"],
  "bandsintownArtists": []
}
```

Discovery feeds, in owner priority order: (1) map search per city: OpenStreetMap Overpass (free, on by default) and
Google Places Text Search per grid cell (off by default; `EVENT_SCRAPER_PLACES_BUDGET` is a hard cap on requests
per run, and each cell/area is refreshed every 30 days); (2) non-ticketing city listing pages, run through the same
extractors, whose unknown venues become candidates; (3) Bandsintown artist events (off by default, rate-limited,
never the only source). Candidates that cannot be proven become `no_source` and are retried monthly.

## Configuration (env)

Only names are listed; never commit values. `examples/event-scraper.env.example` has a template.

| Variable | Default | Use |
|----------|---------|-----|
| `EVENT_SCRAPER_DATA_DIR` | `./data` | Data directory (SQLite, dry-run NDJSON, review exports) |
| `EVENT_SCRAPER_DB` | `<data>/event-scraper.sqlite` | SQLite path |
| `EVENT_SCRAPER_CONFIG` | none | Cities / listings / artists JSON |
| `EVENT_SCRAPER_OSM` / `EVENT_SCRAPER_LISTINGS` | on | Discovery feeds without keys |
| `EVENT_SCRAPER_PLACES` + `GOOGLE_PLACES_API_KEY` | off | Google Places grid search |
| `EVENT_SCRAPER_PLACES_BUDGET` / `EVENT_SCRAPER_PLACES_MAX_PAGES` | 200 / 3 | Places requests per run (hard cap) / pages per query |
| `EVENT_SCRAPER_BANDSINTOWN` + `BANDSINTOWN_APP_ID` | off | Bandsintown feed |
| `EVENT_SCRAPER_LLM` + `OPENAI_API_KEY` | off | LLM fallback extractor (OpenAI-compatible) |
| `EVENT_SCRAPER_LLM_MODEL` / `EVENT_SCRAPER_LLM_BASE_URL` | `gpt-4o-mini` / OpenAI | Model and endpoint |
| `EVENT_SCRAPER_LLM_MAX_PAGES` | 300 | LLM pages per UTC day, all processes (cost cap); only pages with ≥3 distinct date mentions are sent |
| `EVENT_SCRAPER_PUBLISH` | `ndjson` | `off` (standalone: no outbox rows), `ndjson` (dry run) or `postgres` (production) |
| `EVENT_SCRAPER_DRY_RUN_PATH` | `<data>/publish/observations-<date>.ndjson` | Dry-run output |
| `EVENT_SCRAPER_MIN_HOST_INTERVAL_MS` / `EVENT_SCRAPER_FETCH_TIMEOUT_MS` | 5000 / 20000 | Politeness and timeout |
| `EVENT_SCRAPER_CONCURRENCY` / `EVENT_SCRAPER_MAX_JOBS` | 4 / 200 | Workers (same host is always serialized) / sources per run |
| `EVENT_SCRAPER_PRODUCTIVE_INTERVAL_HOURS` / `EVENT_SCRAPER_MAX_INTERVAL_DAYS` | 24 / 7 | Adaptive refetch bounds |
| `EVENT_SCRAPER_MIN_PROVEN_EVENTS` / `EVENT_SCRAPER_PROVE_LIMIT` | 3 / 20 | Promotion threshold / candidates proved per run |
| `EVENT_SCRAPER_PLACES_REFRESH_DAYS` / `EVENT_SCRAPER_OSM_REFRESH_DAYS` / `EVENT_SCRAPER_LISTINGS_REFRESH_DAYS` / `EVENT_SCRAPER_BANDSINTOWN_REFRESH_DAYS` | 30 / 30 / 7 / 7 | Feed refresh |
| `EVENT_SCRAPER_LOOP_TICK_SECONDS` / `EVENT_SCRAPER_DISCOVER_EVERY_HOURS` / `EVENT_SCRAPER_PUBLISH_EVERY_MINUTES` | 60 / 24 / 15 | `loop` cadence |

Publishing and snapshot variables are listed in the next section. Invalid values fail fast with every problem listed.

## Running

The scraper always runs **manually from a laptop** (yours or another laptop on the Tailscale network), never on the
production VPS or any cloud host. Its SQLite file, raw pages and NDJSON output stay on that laptop. There is no
container, service unit or schedule.

```bash
# once, from the repo root
pnpm install --frozen-lockfile
pnpm --filter @tapped/postgres-ingestion build && pnpm --filter @tapped/event-scraper build

# each session, from services/event-scraper
set -a; source ~/.config/tapped/event-scraper.env; set +a     # see examples/event-scraper.env.example
alias scraper='node --disable-warning=ExperimentalWarning dist/cli.js'
scraper import-venues --file venues.json   # venue snapshot exported from production (read-only)
scraper seed-venues --city Richmond         # send known venues through find-source -> prove
scraper discover --city Richmond            # map feeds -> resolve -> find source -> prove
scraper export-candidates --out review/     # review promoted / needs_review candidates
scraper add-source --candidate ID --venue ID
scraper run-once                            # scrape every due source; NDJSON by default
scraper status
```

Production is reached only over Tailscale and only for the two narrow steps: the read-only venue snapshot and, when
`EVENT_SCRAPER_PUBLISH=postgres`, the publish step. Every other command is local.

`run-once`, `discover` and `loop` may run at the same time on one SQLite file. Per-host politeness slots (including
Retry-After) and the daily LLM page cap live in SQLite, so the processes share them; robots.txt is cached per process.
Housekeeping (old jobs, published outbox rows, unreferenced raw pages, counters) runs from every command at most every
6 hours.

## Development

```bash
pnpm --filter @tapped/postgres-ingestion build   # the scraper loads it from dist/ at runtime
pnpm --filter @tapped/event-scraper typecheck
pnpm --filter @tapped/event-scraper lint
pnpm --filter @tapped/event-scraper test          # offline only: fixtures under tests/fixtures
pnpm --filter @tapped/event-scraper build
```

Tests never touch the network. Every network dependency (HTTP, Places, Overpass, LLM, Bandsintown, publisher) is an
injectable interface in `src/types.ts`; `tests/e2e.test.ts` drives the real CLI over a fake network (two venues, a
Places + Overpass fixture city) and checks extraction, validation, reconcile, the NDJSON output, place-id clustering
and promotion. CI runs lint, typecheck and tests in `.github/workflows/node.yml`.

Requires Node 22.17.0 (pinned in CI). `node:sqlite` prints an ExperimentalWarning on Node 22; pass
`--disable-warning=ExperimentalWarning`.

## Layout

| Path | Purpose |
|------|---------|
| `src/cli.ts` | CLI entry point and service wiring |
| `src/config.ts` | Env + config-file parsing and validation, feature flags |
| `src/runner.ts` | Scrape loop: queue, fetch → extract → validate → reconcile, adaptive scheduling, LLM extractor |
| `src/discovery-runner.ts` | Discovery loop: feed jobs, Places budget, resolve + prove |
| `src/types.ts` | Shared contract (domain types, extractor + network client interfaces) |
| `src/db.ts` | SQLite schema, migrations, repositories, leased job queue |
| `src/fetch.ts`, `src/denylist.ts`, `src/url.ts` | Polite HTTP client, ticketing denylist, URL helpers |
| `src/extract/` | Structured extractors and calendar-endpoint discovery |
| `src/llm/` | OpenAI-compatible client, prompt/schema, page text |
| `src/validate/` | Dates/timezones, prices, classification, evidence quotes |
| `src/reconcile/` | Event identity and snapshot diffing |
| `src/discovery/` | Places, OSM, listings, Bandsintown, identity resolution, source finder, prove, review export |
| `src/publish/` | Venue snapshot pull, publishers and outbox drain |
| `examples/` | Env template and city config example |

## Richmond field test (2026-11-03)

Run from a laptop with `EVENT_SCRAPER_PUBLISH=ndjson`; nothing reached production.

- **Discovery:** OSM (53 elements) and Google Places (63 requests before the project hit its Places quota, HTTP 429),
  plus `seed-venues` for the 40 known Tapped venues in the bbox that had their own website. 186 candidates in total:
  12 promoted, 5 sent to review (rooms sharing a place id, same name with a different website), the rest `no_source`
  (no website, social-only site, Eventbrite-only, 403/robots, or no upcoming events on the site).
- **Scrape of the 12 promoted venues (11 sources; two theaters share one calendar):** 252 events extracted, 192 valid (the rest were past events, non-performance
  events or failed evidence checks). Extractors: LLM on 9 pages, JSON-LD, iCal.
- **Accuracy:** dates for Révéler, The Broadberry and The Camel were checked against each page's own listing layout:
  102 of 102 correct.

Bugs the test found, all fixed with regression tests:

- The LLM fallback ran on any page with text (restaurant homepages used up the daily cap). It now needs at least 3
  distinct date mentions on the page, and the default cap is 300 pages/day.
- An LLM auth or quota error (401/403/429) now stops the fallback for the rest of the run and shows up in proof
  attempts, instead of failing silently page after page.
- LLM events now need the date printed nearest to their title on the page to match. Before, a title could be paired
  with the neighbouring listing's date. Listing items are also separated in the LLM's input text.
- Parks and museums (food trucks, toddler programs, guided tours, workshops, talks) passed as music because
  keyword-less events default to music. They are now dropped, and proving a new source requires events with a positive
  signal (a category keyword, a structured event type, listed performers or a doors time).
- Pages whose start times were correct UTC instants (`00:00:00+00:00` = 7pm Eastern) were read as midnight. The
  choice between trusting the instant and trusting the written time is now made once per page.
- Known venues were never proven unless map discovery happened to find them, so `seed-venues --city` was added.

## What is not done

- **Never published to production.** No production credentials are provisioned. `VENUE_SNAPSHOT_DATABASE_URL` should
  be a separate read-only login with `SELECT` on `ingestion_profiles`; `EVENT_SCRAPER_PUBLISH=postgres` needs the
  restricted ingestion role and the private R2 scrape bucket.
- **Promoted candidates are not turned into venues.** A human reviews the export, creates the venue in production,
  re-runs `import-venues`, then `add-source --candidate ID --venue ID`.
- **Source choice still needs review.** In Richmond, one venue's proven source was a sister venue's page on a shared
  site (Richmond Music Hall on thebroadberry.com).
- **Theater runs** ("Nov 18 - Dec 27") become one date-only event on the opening date, not one event per performance.
- **Rescheduled events** show up as a new event plus a cancel (after 2 misses), not as one "rescheduled" change,
  because identity includes the local date.
- **Only the first page of evidence** is kept when TEC pagination or endpoint following reads several pages.
- **Existing `services/event-crawler`** is untouched; retiring it is a separate change.

## Publishing to production

The scraper and production share no queue and no tables. Everything the scraper works on (sources, jobs, snapshots,
the outbox, evidence bytes) lives in its SQLite file. There are exactly two links to production, and both are optional:

1. **Read-only venue snapshot** (`src/publish/venues-snapshot.ts`). `syncVenueSnapshot` copies production venues into
   the local `venues` table and records each venue's Google place id in `venue_place_ids`. A place id that another
   venue already owns is reported as a conflict and left alone, because shared place ids do not prove identity. The
   Postgres source opens one `BEGIN READ ONLY` transaction, runs `VENUE_SNAPSHOT_SQL` and disconnects. The query reads
   the `ingestion_profiles` view, which `tapped_ingestion` can already `SELECT`, and returns venue-enabled profiles
   (`jsonb_typeof(doc->'venueInfo')='object'`) with id, name (`artistName`, else `username`), `venue_website_url`,
   lat/lng and place id from `users.location`/`users.place_id`. Deleted and shadow-banned users are already excluded
   by the view. Production has no venue street address or timezone column, so those stay null; each source row carries
   its own timezone. To run standalone, point `VENUE_SNAPSHOT_FILE` at a JSON array (or `{ "venues": [...] }`) of
   `{id, name, website, lat, lng, placeId, address?, timezone?}`.
2. **Publish** (`src/publish/publisher.ts`). Reconcile writes changes to the SQLite `publish_outbox`, and
   `publishOutbox(db, publisher)` drains it:
   - `NdjsonPublisher` (the default dry run) appends the exact envelopes that would be sent to a local NDJSON file,
     with evidence metadata but no page bytes.
   - `PostgresIngestionPublisher` calls `captureObservations` from `@tapped/postgres-ingestion`. For each group of
     events from the same fetched page, it first uploads the raw page bytes to the private R2 scrape bucket and verifies
     them, and only then calls `record_scrape_observations`. Envelopes use source `event-scraper` and source key
     `<sourceId>#<identityKey>`. The delivery key is a content-derived hash of source key, capture time and payload,
     so retries and rebuilt SQLite files dedupe in production. Each envelope also has the actual fetch time as
     `observedAt`, parser version `event-scraper-v1:<extractor>`, the venue id from the source row (routing
     `resolved`), normalization v2 with `usd_cent` prices, and the original extraction as `data`. Date-only events are
     sent as local midnight with `datePrecision: "date"`. Events from city listing sources have no venue and are not
     published; they only feed discovery. If a page is no longer stored, the evidence is an NDJSON object of the
     extractions instead, with `evidenceLine` set.
   - Failures never block scraping. Each failure increments the row's `attempts` and records a secret-free
     `last_error`. The row is retried on the next run, up to `maxAttempts` (default 10), and one open
     `publish_failed` alert is raised. A clean run resolves that alert.

| Variable | Use |
|----------|-----|
| `EVENT_SCRAPER_PUBLISH` | `postgres` enables production publishing. Any other value, or unset, is a dry run |
| `EVENT_SCRAPER_DRY_RUN_PATH` | NDJSON output path for the dry run (default `./data/publish/observations-<date>.ndjson`) |
| `INGESTION_DATABASE_URL` | Restricted `tapped_ingestion` role used by `captureObservations` |
| `SCRAPE_R2_ACCOUNT_ID`, `SCRAPE_R2_BUCKET`, `SCRAPE_R2_ACCESS_KEY_ID`, `SCRAPE_R2_SECRET_ACCESS_KEY`, `SCRAPE_R2_SESSION_TOKEN` (optional) | Private scrape evidence bucket (never the media bucket) |
| `VENUE_SNAPSHOT_DATABASE_URL` | Separate read-only connection for the venue snapshot. The role needs only `SELECT` on `ingestion_profiles` |
| `VENUE_SNAPSHOT_FILE` | Standalone venue snapshot JSON file. It takes precedence over the database URL |

`@tapped/postgres-ingestion` is loaded at runtime from its `dist/`, so run `pnpm --filter @tapped/postgres-ingestion build`
before you run or test the scraper.

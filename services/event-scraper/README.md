# @tapped/event-scraper

Standalone scraper for live music events (plus comedy, open mic, theater and dance) taken from venues' **own**
websites, with automated discovery of new venues. It replaces `services/event-crawler`, which is left untouched.

> **Status: field-tested on Richmond, VA (2026-11-03) on SQLite; moved to Postgres afterwards and tested on a local
> Postgres only. Never published to production.** It runs manually from a laptop only. Publishing to production (`EVENT_SCRAPER_PUBLISH=postgres`) needs the owner's explicit approval. See
> [Richmond field test](#richmond-field-test-2026-11-03) and [What is not done](#what-is-not-done).

## Architecture

```
                         ┌──────────────────────── event-scraper process (one Node 22 process) ────────────────────────┐
                         │                                                                                              │
 venue snapshot  ──read──┤  import-venues ─► venues + venue_place_ids                                                   │
 (JSON file or           │                                                                                              │
  read-only PG view)     │  SCRAPE LOOP (runner.ts)                                                                     │
                         │   sources ─► fetch_source job (Postgres queue, leases) ─► PoliteHttpClient                    │
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
                         │   `scraper` schema (Postgres): sources, fetch_state, raw_pages, jobs, events,  publish      │
                         │   event_changes, alerts, venue_candidates, venue_place_ids, publish_outbox        │          │
                         └──────────────────────────────────────────────────────────────────────────────────┼──────────┘
                                                                                                            │
                     EVENT_SCRAPER_PUBLISH=ndjson (default): local NDJSON dry run                           │
                     EVENT_SCRAPER_PUBLISH=postgres: captureObservations (@tapped/postgres-ingestion) ◄─────┘
                       with the restricted INGESTION_DATABASE_URL + private R2 evidence
```

### Separation from production

- **Its own schema and role.** Sources, fetch state and conditional-GET validators, the job queue with leases, event
  snapshots, alerts, venue candidates, place-id aliases and the publish outbox live in a `scraper` schema on the
  production Postgres server, owned by a `tapped_scraper` role. That role can read the identifying columns of
  `scraped_events` and the `ingestion_profiles` view, and can't touch anything else (`sql/production-bootstrap.sql`,
  proven in `tests/postgres-state.test.ts`). Every laptop shares this state.
- **Raw pages are not in Postgres.** They go to the private scrape bucket (`SCRAPE_R2_*`), with only a pointer in
  `raw_pages`. Without R2 they stay on the laptop's disk, which is only good for dry runs.
- **One way in to application data.** Events only reach `scraped_events` through the publish step, using the existing
  producer contract (`captureObservations`, see `platform/SCRAPER_INGESTION.md` "Shared producer contract") and its own
  `tapped_ingestion` credentials. With `EVENT_SCRAPER_PUBLISH=ndjson` (default) or `off` nothing reaches them.
- **It needs the database to run.** If Postgres can't be reached, the run stops; it never scrapes without its state.
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

## Never re-scraping what production already has

Production's `scraped_events` already holds the legacy event-crawler's events and this scraper's own published ones.
Every new event is checked against that table live, so there is no copy to go stale. If the table can't be read, the
run fails rather than continuing unchecked. Calendar pages are still fetched, because that is the only way to see new
shows, and a page that needs the LLM still costs a page.

- **When scraping:** a newly extracted event that matches a production event is dropped. It isn't stored, reconciled
  or queued, and it's counted as `alreadyInProduction` in the run output.
- **When publishing:** a queued row that matches another crawler's production event is marked done without being
  sent. This catches anything that reached production after the row was queued.
- **What counts as a match:** the same venue and the same local start date (within one day, because legacy instants
  are sometimes stored in the wrong zone), plus either matching titles (equal after normalization, or every word of
  the shorter title appears in the longer) or the same event URL. An untitled production event matches its URL only
  on the exact local date.
- **Known limit:** the title rule is loose. Two different shows at one venue a day apart can count as the same when
  one title's words all appear in the other ("Live Music" and "Live Music Night"), which drops a real show.

As of 2026-11-03 the legacy crawler last ran in September 2025, and none of the 192 Richmond test events matched a
production event. Legacy rows stay in place: 333,933 bookings link to them through `booking_imports`.

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
  per UTC day across all runs and processes (`EVENT_SCRAPER_LLM_MAX_PAGES`, counted in Postgres), uses a strict JSON schema with venue timezone + "today" context, and every
  evidence quote must appear verbatim in the page text or the event is rejected.

- **Big pages** go to the LLM about 12 listings at a time, three requests at once. If any batch fails, the page fails and
  is retried, so a run never stores part of a calendar. Pages with a repeatable layout should get their own extractor
  instead: `aeg` (AEG events JSON), `rhp` (RHP WordPress cards) and `webflow_shows` (Webflow show cards) use no LLM.
- **Two views of one event:** a copy with no time is dropped when the same page lists that title on that day with a time.
- **Nothing valid on a page:** if a page lists events and every one is rejected for a reason other than being past,
  non-music or deliberately ignored, the run raises `all_rejected` and keeps no content hash, so the page is read again.

## Multi-venue calendars

Some venue groups publish one calendar for all their rooms (The Broadberry's covers about a dozen, including venues in
other states). A `multi_venue` source has no venue of its own. Each event carries the venue key from its card, and
`--route` decides where it goes:

- `--route the-broadberry-2=VENUE_ID` assigns those shows to that Tapped venue.
- `--route the-camel=ignore` drops them, for rooms out of scope or with a better source of their own.
- A key with no route, or a card with no venue, is held back and raises `unrouted_venue`. Nothing is guessed.

Events are validated per venue and reconciled per source. Each event keeps its own venue id through to publishing.

## Commands

From `services/event-scraper` after `pnpm --filter @tapped/postgres-ingestion build && pnpm --filter
@tapped/event-scraper build`. Every command prints JSON to stdout.

| Command | What it does |
|---------|--------------|
| `import-venues [--file venues.json]` | Pull the read-only venue snapshot (file, or `VENUE_SNAPSHOT_*`) and register place-id aliases |
| `import-sqlite FILE` | One-off: copy an old SQLite state file into the schema. Existing rows win |
| `add-source --venue ID --url URL [--kind html\|ical\|wp_tribe\|squarespace] [--timezone IANA] [--label TEXT]` | Register a venue's calendar URL (timezone defaults to the venue's) |
| `add-source --kind multi_venue --url URL --timezone IANA --route KEY=VENUE_ID [--route KEY=ignore ...]` | Register one calendar that covers several venues (see below) |
| `add-source --listing --url URL --timezone IANA` | Register a city listing source (not a ticketing site) |
| `add-source --candidate ID --venue ID` | After review: register a promoted candidate's proven source for an existing venue |
| `run-once [--max-jobs N] [--no-publish]` | Fetch every due source once, then drain the outbox |
| `loop [--no-publish] [--no-discover]` | Long-running: run-once every tick, publish and discover on their intervals; stops on SIGTERM/SIGINT |
| `discover [--city NAME] [--skip-prove]` | One discovery pass: feeds → resolve → source finder → prove |
| `prove <candidateId>` | Prove one candidate now |
| `publish [--limit N]` | Drain the publish outbox |
| `export-candidates [--out DIR] [--status promoted,needs_review]` | Write the human review list (JSON + CSV) |
| `status` | Sources, jobs, candidates, pending outbox, open alerts |

Global options: `--config FILE` (cities/listings JSON, see `examples/config.example.json`).

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
| `EVENT_SCRAPER_DATA_DIR` | `./data` | Dry-run NDJSON, review exports, raw pages when R2 is not configured |
| `EVENT_SCRAPER_DATABASE_URL` | required | Postgres as `tapped_scraper`, through the tunnel below |
| `EVENT_SCRAPER_DB_SCHEMA` | `scraper` | Schema name (tests use throwaway ones) |
| `EVENT_SCRAPER_DB_CONNECTIONS` | `4` | Connections per process, at most 8. Production allows 30 in total |
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
production VPS or any cloud host. Its state is shared through Postgres, so any laptop can pick up where another left
off, and two laptops can run at once without repeating work. There is no
container, service unit or schedule.

```bash
# once, from the repo root
pnpm install --frozen-lockfile
pnpm --filter @tapped/postgres-ingestion build && pnpm --filter @tapped/event-scraper build

# each session, from services/event-scraper
set -a; source ~/.config/tapped/event-scraper.env; set +a     # see examples/event-scraper.env.example
alias scraper='node --disable-warning=ExperimentalWarning dist/cli.js'
scraper import-venues                       # venue snapshot from production's read-only view
scraper seed-venues --city Richmond         # send known venues through find-source -> prove
scraper discover --city Richmond            # map feeds -> resolve -> find source -> prove
scraper export-candidates --out review/     # review promoted / needs_review candidates
scraper add-source --candidate ID --venue ID
scraper run-once                            # scrape every due source; NDJSON by default
scraper status
```

Production Postgres has no public port, so reach it through a tunnel over Tailscale first:

```bash
ssh -N -o ProxyCommand='tailscale nc %h %p' -L 55433:172.18.0.7:5432 root@tapped-prod   # keep this running
```

Run scrapes under `caffeinate -i` on a Mac. If the laptop sleeps mid-transaction, Postgres closes the connection after 60
seconds and that run fails (nothing is half-written).

`172.18.0.7` is the Postgres container's address on the Docker network; check it with
`docker inspect tapped-postgres-1` if the tunnel can't connect.

`run-once`, `discover` and `loop` may run at the same time, on one laptop or several. Jobs are claimed with leases,
transactions on the schema run one at a time under an advisory lock, and per-host politeness slots (including
Retry-After) and the daily LLM page cap are shared; robots.txt is cached per process.
Housekeeping (old jobs, published outbox rows, unreferenced raw pages, counters) runs from every command at most every
6 hours.

## Development

```bash
pnpm --filter @tapped/postgres-ingestion build   # the scraper loads it from dist/ at runtime
pnpm --filter @tapped/event-scraper typecheck
pnpm --filter @tapped/event-scraper lint
docker run -d --rm --name tapped-scraper-pg -e POSTGRES_USER=tapped -e POSTGRES_PASSWORD=local-test-only \\
  -e POSTGRES_DB=scraper_test -p 127.0.0.1:55432:5432 postgis/postgis:17-3.5 -c max_connections=300
export EVENT_SCRAPER_TEST_DATABASE_URL=postgres://tapped:local-test-only@127.0.0.1:55432/scraper_test
pnpm --filter @tapped/event-scraper test          # local Postgres and fixtures, no network
pnpm --filter @tapped/event-scraper build
```

Tests never touch the network and only accept a local database; each one gets a throwaway schema. Every network dependency (HTTP, Places, Overpass, LLM, Bandsintown, publisher) is an
injectable interface in `src/types.ts`; `tests/e2e.test.ts` drives the real CLI over a fake network (two venues, a
Places + Overpass fixture city) and checks extraction, validation, reconcile, the NDJSON output, place-id clustering
and promotion. CI runs lint, typecheck and tests in `.github/workflows/node.yml`.

Requires Node 22.17.0 (pinned in CI). Only `import-sqlite` uses `node:sqlite`, which prints an ExperimentalWarning on
Node 22; pass `--disable-warning=ExperimentalWarning`.

## Layout

| Path | Purpose |
|------|---------|
| `src/cli.ts` | CLI entry point and service wiring |
| `src/config.ts` | Env + config-file parsing and validation, feature flags |
| `src/runner.ts` | Scrape loop: queue, fetch → extract → validate → reconcile, adaptive scheduling, LLM extractor |
| `src/discovery-runner.ts` | Discovery loop: feed jobs, Places budget, resolve + prove |
| `src/types.ts` | Shared contract (domain types, extractor + network client interfaces) |
| `src/db.ts` | Postgres schema, migrations, repositories, leased job queue |
| `src/extract/rhp.ts`, `src/extract/routes.ts` | Multi-venue calendars: read cards, route each show to its venue |
| `src/pages.ts` | Raw page storage (R2, or disk for dry runs) |
| `src/import-sqlite.ts` | One-off import of an old SQLite state file |
| `sql/` | Production bootstrap and rollback, run by an operator |
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

- **Never published to production, and the `scraper` schema doesn't exist there yet.** No production credentials are
  provisioned. Publishing needs the owner's approval, plus `INGESTION_DATABASE_URL` and `SCRAPE_R2_*` on the laptop.
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

The scraper shares a server with production but no queue and no writable tables. Everything it works on (sources,
jobs, snapshots, the outbox) lives in its own schema. It connects to application data in exactly two ways:

1. **Read-only venue snapshot** (`src/publish/venues-snapshot.ts`). `syncVenueSnapshot` copies production venues into
   the schema's `venues` table and records each venue's Google place id in `venue_place_ids`. A place id that another
   venue already owns is reported as a conflict and left alone, because shared place ids do not prove identity. The
   Postgres source runs `VENUE_SNAPSHOT_SQL` on the scraper's own connection. The query reads the
   `ingestion_profiles` view, the only part of the profile data `tapped_scraper` can read, and returns venue-enabled profiles
   (`jsonb_typeof(doc->'venueInfo')='object'`) with id, name (`artistName`, else `username`), `venue_website_url`,
   lat/lng and place id from `users.location`/`users.place_id`. Deleted and shadow-banned users are already excluded
   by the view. Production has no venue street address or timezone column, so those stay null; each source row carries
   its own timezone. To run standalone, point `VENUE_SNAPSHOT_FILE` at a JSON array (or `{ "venues": [...] }`) of
   `{id, name, website, lat, lng, placeId, address?, timezone?}`.
2. **Publish** (`src/publish/publisher.ts`). Reconcile writes changes to the `publish_outbox` table, and
   `publishOutbox(db, publisher)` drains it:
   - `NdjsonPublisher` (the default dry run) appends the exact envelopes that would be sent to a local NDJSON file,
     with evidence metadata but no page bytes.
   - `PostgresIngestionPublisher` calls `captureObservations` from `@tapped/postgres-ingestion`. For each group of
     events from the same fetched page, it first uploads the raw page bytes to the private R2 scrape bucket and verifies
     them, and only then calls `record_scrape_observations`. Envelopes use source `event-scraper` and source key
     `<sourceId>#<identityKey>`. The delivery key is a content-derived hash of source key, capture time and payload,
     so retries and a rebuilt schema dedupe in production. Each envelope also has the actual fetch time as
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
| `VENUE_SNAPSHOT_FILE` | Standalone venue snapshot JSON file. It takes precedence over the database URL |

`@tapped/postgres-ingestion` is loaded at runtime from its `dist/`, so run `pnpm --filter @tapped/postgres-ingestion build`
before you run or test the scraper.

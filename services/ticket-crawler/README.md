# Ticket crawler

Venue discovery reads sanitized Postgres profiles through `@tapped/postgres-ingestion`; no Firebase Auth/Firestore/FCM client or public search key.

From the monorepo root:

```sh
corepack pnpm install --frozen-lockfile
corepack pnpm --filter @tapped/postgres-ingestion build
corepack pnpm --filter ticket-crawler build
corepack pnpm --filter ticket-crawler exec tsc --noEmit
corepack pnpm --filter ticket-crawler start:prod
docker build -f services/ticket-crawler/Dockerfile .
```

Mandatory private-network `INGESTION_DATABASE_URL` for a dedicated member of `tapped_ingestion`, never the API/owner role. GCS uses mounted ADC with Storage-only permissions. `CRAWLEE_BROWSER_EXECUTABLE_PATH` selects Chromium; the Docker image sets it to `/usr/bin/chromium`. No credentials belong in images/source.

See [models, permissions and rollout](../../platform/POSTGRES_FIRST.md). Ticket-page crawling currently logs/discovers pages; it does not invent ticket sales, charges or performer fees.

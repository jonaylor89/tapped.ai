# Event crawler

Reads sanitized profiles, archives responses/extractions in private R2, and writes immutable observations plus unpublished relational facts through `@tapped/postgres-ingestion`. No artist/profile creation, booking creation/cancellation, Firebase writes or application notifications. Supported legacy scrapers use the same capture transport.

From the monorepo root:

```sh
corepack pnpm install --frozen-lockfile
corepack pnpm --filter @tapped/postgres-ingestion build
corepack pnpm --filter node-webcrawler build
corepack pnpm --filter node-webcrawler typecheck
corepack pnpm --filter node-webcrawler start:prod
# Root build context, not this directory:
docker build -f services/event-crawler/Dockerfile .
```

Configure a private-network `INGESTION_DATABASE_URL` for a dedicated member of `tapped_ingestion`, not the API/owner credential. Independent private-bucket `SCRAPE_R2_ACCOUNT_ID`, `SCRAPE_R2_BUCKET`, `SCRAPE_R2_ACCESS_KEY_ID` and `SCRAPE_R2_SECRET_ACCESS_KEY` are also mandatory. No public-media credentials are reused. Missing configuration fails closed. Provider settings remain `OPENAI_API_KEY`, `GOOGLE_PLACES_API_KEY` and optional `SLACK_WEBHOOK_URL`; never bake them into an image.

See [observations, R2, migration rehearsal and tests](../../platform/SCRAPER_INGESTION.md) and [models, permissions, rollout and preservation](../../platform/POSTGRES_FIRST.md). Nothing here authorizes crawler execution or enables a schedule.

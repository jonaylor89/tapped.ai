# Event crawler

Reads sanitized profiles and writes event facts/import provenance to Postgres through `@tapped/postgres-ingestion`. No Auth users, Firestore writes, client-maintained counters or application notifications. Supported legacy scrapers use the same transport.

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

Configure a private-network `INGESTION_DATABASE_URL` for a dedicated member of `tapped_ingestion`, not the API/owner credential. Missing configuration fails closed. Provider settings remain `OPENAI_API_KEY`, `GOOGLE_PLACES_API_KEY` and optional `SLACK_WEBHOOK_URL`; never bake them into an image.

See [models, permissions, rollout and preservation](../../platform/POSTGRES_FIRST.md). Firestore migration files under `archive/firestore-migrations` are historical source, excluded from runtime builds and unsupported against the new schema. Do not run them on production or restore a dual-write path.

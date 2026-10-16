# Crawler deployment

The old GCP/Typesense/PM2 deployment guide is retired. Do not use it to start a crawler.

Current contracts and operator procedures:

- [Relational observations, private R2, migration rehearsal and recovery](../../../platform/SCRAPER_INGESTION.md)
- [Postgres roles, builds and owner-approved rollout boundaries](../../../platform/POSTGRES_FIRST.md)
- [Event crawler build/runtime](../README.md)
- [Ticket discovery limitations](../../ticket-crawler/README.md)

Neither crawler is automatically scheduled or authorized to run. A future deployment needs owner
approval, a private dedicated `INGESTION_DATABASE_URL`, independent `SCRAPE_R2_*` bucket credentials,
per-domain rate/backoff settings and an explicit refresh schedule. Do not reuse API/owner credentials,
public media storage, Firebase clients, or the retired side-effecting ingestion functions.

Capture persists evidence and unpublished facts only. Publishing events, resolving artists and
reconciling bookings require separate reviewed logic; enabling capture is not enabling publication.

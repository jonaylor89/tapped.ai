# Tapped Stream ↔ email bridge

The Rust API owns email-thread business logic, Stream synchronization, idempotency, and the durable SQLite inbox/outbox. Email transport differs by environment:

- **Production:** Postmark sends outbound mail and posts parsed inbound replies to the Rust API.
- **Local development:** Haraka accepts inbound SMTP and Postfix receives outbound SMTP from the worker.

Production keeps the existing Postmark MX records. Haraka and Postfix are development/test infrastructure and must not replace Postmark in production.

## Production configuration

Run the API and `mail_worker` from the same API image with a shared persistent volume containing `tapped-mail.sqlite3`. Configure the worker with:

```text
MAIL_STORE_PATH=/data/tapped-mail.sqlite3
MAIL_TRANSPORT=postmark
POSTMARK_SERVER_TOKEN=<existing Postmark server token>
```

Configure the API with:

```text
FIREBASE_PROJECT_ID
GOOGLE_APPLICATION_CREDENTIALS
STREAM_KEY
STREAM_SECRET
MAIL_INGRESS_SECRET       # random password used for Postmark inbound webhook Basic auth
MAIL_API_SECRET           # random HMAC secret used by transitional Firebase Functions
MAIL_STORE_PATH=/data/tapped-mail.sqlite3
BOOKING_EMAIL_DOMAIN=booking.tapped.ai
TYPESENSE_HOST
TYPESENSE_PORT
TYPESENSE_PROTOCOL
TYPESENSE_SEARCH_API_KEY
```

In Postmark, configure the inbound webhook as:

```text
https://postmark:<MAIL_INGRESS_SECRET>@api.tapped.ai/webhooks/postmark/inbound
```

Postmark sends HTTP Basic authentication from the URL credentials. Use HTTPS and a dedicated random secret. The API also retains signed `POST /internal/mail/inbound` for local Haraka delivery.

## Local mail stack

The Compose stack builds the API and runs:

- Haraka for inbound SMTP
- Postfix/OpenDKIM as a local SMTP target
- `mail_worker` with `MAIL_TRANSPORT=smtp`

Required local variables are listed in `.env.example`-style form below:

```text
FIREBASE_PROJECT_ID
GOOGLE_APPLICATION_CREDENTIALS
STREAM_KEY
STREAM_SECRET
MAIL_INGRESS_SECRET
MAIL_API_SECRET
TYPESENSE_HOST
TYPESENSE_PORT
TYPESENSE_PROTOCOL
TYPESENSE_SEARCH_API_KEY
BOOKING_EMAIL_DOMAIN      # defaults to booking.tapped.ai
MAIL_HOSTNAME             # defaults to mail.tapped.ai
API_PORT                   # defaults to 3000
MAIL_TLS_KEY               # local Haraka PEM key
MAIL_TLS_CERT              # local Haraka PEM certificate
```

Start it with:

```bash
docker compose up --build
```

No production DNS changes are required for this stack.

## Manual Steps

- [ ] Back up the current Hetzner Compose configuration and tag the running API image for rollback.
- [ ] Add a persistent `mail-data` volume shared by the API and `mail_worker`.
- [ ] Deploy the merged API image with the production variables above; set the worker to `MAIL_TRANSPORT=postmark`.
- [ ] Confirm `/health`, API logs, worker startup, SQLite WAL creation, and Postmark API connectivity.
- [ ] Authenticate Application Default Credentials with `gcloud auth application-default login`, then preview the legacy migration with `python3 services/mail-gateway/tools/backfill_mail_threads.py`.
- [ ] Apply it with `MAIL_API_SECRET=... TAPPED_API_URL=https://api.tapped.ai python3 services/mail-gateway/tools/backfill_mail_threads.py --apply`; confirm the eligible and written counts match.
- [ ] Configure Postmark's inbound webhook with Basic authentication at `/webhooks/postmark/inbound`; do not change the existing MX records.
- [ ] Point the Stream before-message webhook at `https://api.tapped.ai/webhooks/stream/before-message`.
- [ ] Build and release the Flutter app that calls `POST /app/v1/venue-email-threads`.
- [ ] Run **Post-deploy mail smoke** manually. IMAP is used only by this optional end-to-end deliverability test, not by production infrastructure.
- [ ] Verify app → Postmark → recipient, recipient reply → Postmark webhook → Stream, Stream follow-up → Postmark, duplicate webhook retries, and attachment handling.
- [ ] Keep deprecated Firebase handlers for a 72-hour rollback window.
- [ ] After 72 healthy hours, remove deprecated handlers and obsolete Functions configuration. Keep the actual Postmark server token under `POSTMARK_SERVER_TOKEN`; never reuse it as `MAIL_API_SECRET`.

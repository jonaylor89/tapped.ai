# Tapped mail gateway

Self-hosted SMTP edge for the Stream ↔ email bridge.

## Services

- **Haraka** accepts inbound SMTP for `booking.tapped.ai` only and forwards the raw RFC-822 message to the API with a timestamped HMAC.
- **api.tapped.ai** validates Stream/Haraka signatures, parses MIME, resolves email threads, and persists inbox/outbox state in SQLite WAL mode.
- **mail_worker** leases the durable outbox and submits RFC-822 messages to Postfix.
- **Postfix/OpenDKIM** performs internet delivery, retries, and DKIM signing.

## Required environment

```text
FIREBASE_PROJECT_ID
GOOGLE_APPLICATION_CREDENTIALS
STREAM_KEY
STREAM_SECRET
MAIL_INGRESS_SECRET       # random 32+ byte Haraka/API secret
MAIL_API_SECRET           # random 32+ byte Functions/API transition secret
TYPESENSE_HOST
TYPESENSE_PORT           # defaults to 443
TYPESENSE_PROTOCOL       # defaults to https
TYPESENSE_SEARCH_API_KEY
BOOKING_EMAIL_DOMAIN      # defaults to booking.tapped.ai
MAIL_HOSTNAME             # defaults to mail.tapped.ai
API_PORT                  # host loopback port for the HTTPS reverse proxy; defaults to 3000
MAIL_TLS_KEY              # PEM private key mounted into Haraka
MAIL_TLS_CERT             # PEM full certificate chain mounted into Haraka
```

Start with:

```bash
docker compose up --build
```

The host must allow outbound TCP 25. Publish only HTTPS for the API and TCP 25 for Haraka. Keep SQLite, Postfix submission, and Typesense on the private network.

## DNS

Configure:

- `booking.tapped.ai MX 10 mail.tapped.ai`
- `mail.tapped.ai A <VPS IP>`
- matching PTR/rDNS for the VPS IP
- SPF authorizing the VPS IP
- the DKIM public key generated under the `postfix-dkim` volume
- DMARC, initially in monitoring mode

Before changing production MX records, run the Rust integration suite and test inbound/outbound delivery on a staging subdomain. During the Functions transition, set the legacy `POSTMARK_SERVER_ID` Firebase secret to the same value as `MAIL_API_SECRET`; it is now an API HMAC key, not a Postmark token.

## Manual Steps

- [ ] Deploy the stack on a staging mail subdomain with persistent volumes, backups, TLS certificates, and all required secrets.
- [ ] Create a Firebase smoke-test performer and a test venue whose `venueInfo.bookingEmail` points to the controlled IMAP inbox.
- [ ] Configure the `mail-smoke.yml` repository variables (`MAIL_SMOKE_API_URL`, `MAIL_SMOKE_VENUE_ID`, `MAIL_SMOKE_IMAP_HOST`, `MAIL_SMOKE_SMTP_HOST`, and `MAIL_SMOKE_SMTP_PORT`) and matching Firebase, IMAP, and Stream secrets.
- [ ] Run **Post-deploy mail smoke**. It creates a real authenticated thread, waits for internet delivery over IMAP, replies through SMTP, and verifies the reply in Stream. The deployment job can trigger it with a `mail-deployed` repository dispatch.
- [ ] Authenticate Application Default Credentials with `gcloud auth application-default login`, then preview the legacy migration with `python3 services/mail-gateway/tools/backfill_mail_threads.py`.
- [ ] Apply it with `MAIL_API_SECRET=... TAPPED_API_URL=https://api.tapped.ai python3 services/mail-gateway/tools/backfill_mail_threads.py --apply`; confirm the reported eligible and written counts match.
- [ ] Point the Stream before-message webhook at `https://api.tapped.ai/webhooks/stream/before-message`, then rerun the smoke workflow.
- [ ] Lower the MX TTL, publish/verify PTR, SPF, DKIM, and DMARC, and switch `booking.tapped.ai` MX to Haraka.
- [ ] Rerun the smoke workflow after DNS propagation and verify outbox retries, Postfix queue depth, orphan volume, disk usage, and bounce logs.
- [ ] Keep the deprecated Firebase Stream and inbound handlers for a 72-hour rollback window. Because traffic is low, run the smoke workflow at least daily during that window rather than relying only on organic traffic.
- [ ] After 72 healthy hours and three successful daily smoke runs, delete the deprecated handlers, remove the `POSTMARK_SERVER_ID` compatibility name, and remove the old Functions configuration.

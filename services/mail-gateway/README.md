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
DATABASE_URL
REDIS_URL
STREAM_KEY
STREAM_SECRET
MAIL_INGRESS_SECRET       # random password used for Postmark inbound webhook Basic auth
MAIL_API_SECRET           # random HMAC secret for signed internal mail endpoints
MAIL_STORE_PATH=/data/tapped-mail.sqlite3
BOOKING_EMAIL_DOMAIN=booking.tapped.ai
```

No Firebase administrative credential is mounted into the serving API. The optional identity worker has its own least-privilege credential.

When the Postmark plan permits editing inbound webhooks, configure:

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
DATABASE_URL
REDIS_URL
STREAM_KEY
STREAM_SECRET
MAIL_INGRESS_SECRET
MAIL_API_SECRET
OPENAI_API_KEY
OPENAI_MODEL              # defaults to gpt-4.1-mini
VENUE_CONTACT_FOUNDER_CC  # comma-separated; defaults to the legacy founder recipients
SLACK_WEBHOOK_URL          # optional founder notifications
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

## Offline HTTP-client checks

```bash
python3 -m unittest discover -s services/mail-gateway/tools -p 'test_*.py'
```

Administrative/smoke requests identify themselves with descriptive User-Agent headers; default Python requests from the production host were rejected by Cloudflare's browser-integrity policy. Authentication/signatures remain required. These offline checks do not establish real SMTP replies or end-to-end provider delivery.

## Open items

- [ ] Upgrade the Postmark account to a tier entitled to inbound processing, then configure its webhook with Basic authentication at `/webhooks/postmark/inbound`; do not change the existing MX records.
- [ ] Run **Post-deploy mail smoke** manually. IMAP is used only by this optional end-to-end deliverability test, not by production infrastructure.
- [ ] Verify app → Postmark → recipient, recipient reply → Postmark webhook → Stream, Stream follow-up → Postmark, duplicate webhook retries, and attachment handling.

Keep the actual Postmark server token under `POSTMARK_SERVER_TOKEN`; never reuse it as `MAIL_API_SECRET`.

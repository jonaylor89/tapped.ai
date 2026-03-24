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

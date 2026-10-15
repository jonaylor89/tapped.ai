# Local stack

Runs the API, web app and iOS app against local Postgres/PostGIS, Redis, Mailpit and the Firebase
Auth emulator. Nothing touches production data, the production Firebase project or
production credentials.

## Start

```sh
docker compose up -d --build                      # postgres, redis, mailpit, firebase emulators, api
DATABASE_URL=postgres://tapped:tapped@localhost:5432/tapped_local platform/local/seed.sh
platform/local/smoke.sh                           # emulator sign-in + API checks
```

`seed.sh` needs a host `psql` (`brew install libpq` or `apt-get install postgresql-client`); without one, run
`docker compose exec -T postgres psql -U tapped -d tapped_local < platform/local/seed.sql` once the API is ready.

| Service | URL |
| --- | --- |
| API | http://localhost:8080 |
| Firebase emulator UI | http://localhost:4000 |
| Auth emulator | localhost:9099 |
| Mailpit | http://localhost:8025 |

Without Docker, run the same services natively (`brew install postgresql@17 postgis redis mailpit`,
`npm i -g firebase-tools@14.20.0`), start the emulators with
`firebase emulators:start --project demo-tapped --import emulator-seed` from this directory and run the
API with the environment block from `docker-compose.yml` (hosts set to `localhost`).

## Auth

The API accepts unsigned Auth Emulator tokens only when `FIREBASE_AUTH_EMULATOR_HOST` is set, and refuses
to boot unless `FIREBASE_PROJECT_ID` is a `demo-*` project. Production tokens are never accepted in
emulator mode, and emulator tokens are never accepted outside it.

Seeded accounts (password `local-password`, all email-verified):

| UID | Email | Role |
| --- | --- | --- |
| `local-alice` | alice@example.test | performer |
| `local-bluebird` | venue@example.test | venue |
| `local-carol` | carol@example.test | booker |

`seed.sql` holds their Postgres profiles plus services, opportunities, bookings, a review and an activity.
`seed.sh` truncates and reloads it, so run it before each E2E run. To change the emulator accounts, edit
them in the emulator UI and run `firebase emulators:export emulator-seed --project demo-tapped`.

## Web

```sh
cd apps/app.tapped.ai && NEXT_PUBLIC_TAPPED_API_URL=http://localhost:8080 pnpm dev
```

## MCP server

The API serves the MCP server at `http://localhost:8080/mcp` when started with
`MCP_ISSUER=http://localhost:8080` and `MCP_CONSENT_URL=http://localhost:3000/oauth/authorize`.
Run the web app against the Auth emulator so the consent page can sign in:

```sh
cd apps/app.tapped.ai && NEXT_PUBLIC_TAPPED_API_URL=http://localhost:8080 \
  NEXT_PUBLIC_FIREBASE_API_KEY=demo-key NEXT_PUBLIC_FIREBASE_PROJECT_ID=demo-tapped \
  NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN=localhost NEXT_PUBLIC_FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 pnpm dev
claude mcp add --transport http tapped-local http://localhost:8080/mcp   # then /mcp → Authenticate
```

Sign in on the consent page as a seeded account (e.g. `alice@example.test` / `local-password`).

## iOS

Debug builds read these launch environment variables (Xcode scheme or `SIMCTL_CHILD_*` for `simctl launch`):

```sh
SIMCTL_CHILD_TAPPED_API_URL=http://localhost:8080 \
SIMCTL_CHILD_FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
xcrun simctl launch <udid> com.intheloopstudio
```

`SIMCTL_CHILD_*` only applies to that launch. A notification tap or any other OS-initiated cold launch would
start against production, so also persist the overrides (Debug builds read them from user defaults):

```sh
for kv in TAPPED_API_URL=http://localhost:8080 FIREBASE_AUTH_EMULATOR_HOST=localhost:9099; do
  xcrun simctl spawn <udid> defaults write com.intheloopstudio "${kv%%=*}" "${kv#*=}"
done
```

Emulator runs configure Firebase with a fake `demo-tapped` app instead of the bundled
`GoogleService-Info.plist`, use Remote Config's in-code defaults, and skip PostHog, OpenTelemetry,
Crashlytics, FCM and Google Sign-In. Release builds ignore all of these variables.

Image uploads go through the local API's `POST /app/v1/uploads`, which presigns R2 uploads. It answers 503
unless the API has `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY` (use a dev bucket via
`R2_MEDIA_BUCKET` and `MEDIA_PUBLIC_BASE_URL`, never `tapped-media`).

## Not emulated

- Google Places, Geocoding, OpenAI, Spotify and Stream Chat are served by `stub.py` on `:8090`
  (stdlib Python: a few fixed Richmond places such as "The Bluebird", a canned email body, two
  Spotify artists such as `4Z8W4fKeB5YxbusRsdQVPb`, and an in-memory Stream Chat with WebSocket
  events). The API points at it with `GOOGLE_PLACES_BASE_URL`, `GOOGLE_GEOCODE_URL`,
  `OPENAI_CHAT_COMPLETIONS_URL`, `SPOTIFY_TOKEN_URL`, `SPOTIFY_API_BASE_URL` (plus any
  `SPOTIFY_CLIENT_ID`/`SECRET`) and `STREAM_BASE_URL`. Chat state resets when the stub restarts.
- The Stream iOS SDK only speaks https/wss, so the stub also listens with TLS on `:8443`. Create and
  trust the cert, run the stub with it, and point the app at it:

  ```sh
  platform/local/stream-cert.sh <udid>   # writes platform/local/.certs, trusts it in the simulator
  STUB_TLS_CERT=platform/local/.certs/stub.pem STUB_TLS_KEY=platform/local/.certs/stub-key.pem \
    python3 platform/local/stub.py
  # app: TAPPED_STREAM_BASE_URL=https://localhost:8443 (env or `defaults write`, as above)
  ```
- Push notifications: use `xcrun simctl push` with a payload file.

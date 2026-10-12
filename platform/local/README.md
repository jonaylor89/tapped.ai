# Local stack

Runs the API, web app and iOS app against local Postgres/PostGIS, Redis, Mailpit and the Firebase
Auth/Storage emulators. Nothing touches production data, the production Firebase project or
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
| Storage emulator | localhost:9199 |
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

## iOS

Debug builds read these launch environment variables (Xcode scheme or `SIMCTL_CHILD_*` for `simctl launch`):

```sh
SIMCTL_CHILD_TAPPED_API_URL=http://localhost:8080 \
SIMCTL_CHILD_FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
SIMCTL_CHILD_FIREBASE_STORAGE_EMULATOR_HOST=localhost:9199 \
xcrun simctl launch <udid> com.intheloopstudio
```

`SIMCTL_CHILD_*` only applies to that launch. A notification tap or any other OS-initiated cold launch would
start against production, so also persist the overrides (Debug builds read them from user defaults):

```sh
for kv in TAPPED_API_URL=http://localhost:8080 FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
          FIREBASE_STORAGE_EMULATOR_HOST=localhost:9199; do
  xcrun simctl spawn <udid> defaults write com.intheloopstudio "${kv%%=*}" "${kv#*=}"
done
```

Emulator runs configure Firebase with a fake `demo-tapped` app instead of the bundled
`GoogleService-Info.plist`, use Remote Config's in-code defaults, and skip PostHog, OpenTelemetry,
Crashlytics, FCM and Google Sign-In. Release builds ignore all of these variables.

## Not emulated

- Google Places, Geocoding and OpenAI are served by `stub.py` on `:8090` (stdlib Python, a few fixed
  Richmond places such as "The Bluebird", plus a canned email body). The API points at it with
  `GOOGLE_PLACES_BASE_URL`, `GOOGLE_GEOCODE_URL` and `OPENAI_CHAT_COMPLETIONS_URL`. Running natively:
  `python3 platform/local/stub.py`.
- Stream Chat and Spotify use placeholder keys, so chat and Spotify linking fail locally.
- Push notifications: use `xcrun simctl push` with a payload file.

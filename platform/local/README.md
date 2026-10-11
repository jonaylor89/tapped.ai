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

Emulator runs skip PostHog and OpenTelemetry. Release builds ignore all of these variables.

## Not emulated

- Stream Chat, Google Places, Spotify and OpenAI use placeholder keys, so chat, place lookups, Spotify
  and AI email composition fail locally.
- Push notifications: use `xcrun simctl push` with a payload file.
- Remote Config still reads the production project's published defaults (read-only).

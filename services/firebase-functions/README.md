# Firebase Auth transports

Production retains exactly two Firebase Functions: `onUserCreate` and `onUserDelete`.
They sign lifecycle snapshots and forward them to `POST https://api.tapped.ai/webhooks/firebase/auth`.
Firebase retries failed calls; Rust acknowledges only after durable capture and owns all welcome,
founder-notification, Stream and cleanup business logic. Firebase Auth and hosted email verification remain.
Application data/search use Rust/Postgres, never Firestore fallback, synchronization or dual writes.

Unexported legacy modules remain for reference only. All other custom Functions and managed
extensions have been retired. Postmark inbound configuration is owner-managed and must target
Rust directly; there is no Firebase HTTP compatibility handler. StoreKit purchases remain supported;
Stripe and BigQuery integrations are retired without deleting historical provider/source data.

See [DEPLOYMENT_AUDIT.md](DEPLOYMENT_AUDIT.md) and the
[retirement record](../../platform/FIREBASE_FUNCTIONS_RETIREMENT.md) for current production evidence.

## Setup and tests

This isolated npm package is not in the pnpm/Turbo workspace. Dependencies are exact and locked;
Node **22.17.0** and npm **10.9.2** are pinned.

```sh
cd services/firebase-functions
npm ci
npm run lint
npm run build
npm test
```

## Selective deployment only

After explicit release approval:

```sh
npm run deploy -- onUserCreate onUserDelete
```

The guard pins Firebase CLI **14.22.0**, project `in-the-loop-306520`, codebase `default`, and
runtime `nodejs22`. It rejects empty names, blanket/wildcard deploys, retired handlers, extensions
and extra CLI flags. It confirms Firebase's retry-policy prompt with `--force` only after validating
these two allowlisted names. It never deploys Firestore rules/indexes. Do not bypass it with a
blanket `firebase deploy`.

Bind the dedicated `AUTH_WEBHOOK_SECRET` in Secret Manager and the matching private Rust API
environment. Never commit credential files or values. `TAPPED_API_URL` is a trusted optional
API-origin override for transport tests; default `https://api.tapped.ai`.

Auth REST snapshots retain milliseconds but Gen1 events truncate creation time to seconds.
Rust uses their shared precision for lifecycle keys; migration `20261023000000` normalizes its
private ledger and delivered deduplication keys without historical replay or Firebase source writes.
Use fresh Firebase UIDs rather than same-second administrative UID reuse.

CI builds/tests only; it does not automatically deploy Functions.

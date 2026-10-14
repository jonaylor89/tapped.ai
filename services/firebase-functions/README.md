# Firebase functions

Standalone backend extracted from the retired mobile app. The native app, Rust API and web app do not build against the legacy mobile directory. Android is no longer supported.

Firebase **Auth** remains the identity provider; application data/search use Rust/Postgres. This package retains Auth side effects and stable provider compatibility URLs, plus unexported legacy source for reference. It is not a Firestore fallback or synchronization service.

## Setup and tests

This is intentionally **not** a pnpm/Turbo workspace package. It uses its own exact dependencies, npm lockfile, Node **22.17.0** (`.node-version`) and npm **10.9.2** (`packageManager`).

```sh
cd services/firebase-functions
npm ci
npm run lint
npm run build
npm test
```

The lockfile was regenerated from the old resolved dependency versions, removing stale packages and pinning the compiler/test tooling. Lint covers the maintained entrypoint, webhook bridge and deployment guard; legacy modules keep their original source formatting. Build checks all production TypeScript; Vitest retains legacy helper tests and tests the API proxies, while Node tests enforce deployment boundaries.

## Production boundaries

**This package is transitional. The current target is to remove every non-Auth Firebase Function and all managed extensions**, once required behavior/provider routing is replaced. Retain only transport-only Firebase Auth hooks calling authenticated Rust webhooks. Firebase Auth/email verification itself remains. Track the [all-functions retirement plan](../../platform/FIREBASE_FUNCTIONS_RETIREMENT.md); do not delete business notifications merely because they listened to Firestore.

Read [DEPLOYMENT_AUDIT.md](DEPLOYMENT_AUDIT.md) **before deploying**. Many deployed functions/extensions are not maintained by the current entrypoint, and some deployed custom handlers have no source here.

- `src/index.ts` exports only named, allowlisted HTTP/Auth functions; no wildcard exports.
- Legacy Firestore-dependent modules remain under `src/lib/` but are not exported. Do not reconnect them to production or add dual writes.
- Postmark's `inboundEmailWebhook` preserves its existing provider URL and forwards to Rust with the Secret Manager ingress credential.
- Stream's `streamBeforeMessageWebhook` forwards raw request bytes and `x-signature` to Rust for validation and processing. It does not read/write Firestore.
- The four maintained Auth exports now use `src/lib/auth_hooks.ts` and forward signed lifecycle snapshots to `POST /webhooks/firebase/auth`; Firebase retries failed requests. All business effects execute through the durable Rust provider outbox. Provision the dedicated `AUTH_WEBHOOK_SECRET` in Secret Manager and the API before selective rollout; reconcile held jobs before enabling Rust Auth effects. This local change is not itself a production deployment.
- BigQuery is intentionally retired with user approval: all three export extension instances, 15 Functions and 16 task queues were removed. Historical datasets/tables/views remain untouched; no Rust exporter or analytics backfill is required.
- The application launches free: Stripe/payment/subscription Functions and extensions are retirement-only. Do not backfill billing customers, deploy new paid handlers or delete/cancel historical provider objects.
- Mailchimp is intentionally retired: its live Function, export, deployment allowlist entry, source and dependencies were removed. The deployment guard rejects `addUserToMailchimpOnCreated`; Rust no longer subscribes users.
- Existing Spotify compatibility handlers are retained until provider/client routing is separately retired.
- Firebase extensions are managed outside this source. Removing files/exports never undeploys anything.

## Selective deployment only

After explicit release approval and Firebase authentication:

```sh
npm run deploy -- inboundEmailWebhook
# Or explicitly name multiple allowlisted handlers:
npm run deploy -- inboundEmailWebhook streamBeforeMessageWebhook
```

The guard pins Firebase CLI **14.22.0**, project `in-the-loop-306520`, codebase `default`, runtime `nodejs22`, and selects only the named functions. Empty names, wildcard/blanket deployments, retired writers, extensions and additional CLI flags are rejected. It never passes `--force` or deploys Firestore rules/indexes. Do not bypass it with a blanket `firebase deploy`.

`firebase.json` and `.firebaserc` live here. Canonical client shutdown rules remain at `../../platform/firestore.rules` and are managed separately.

Use Cloud runtime Application Default Credentials and Secret Manager bindings (`defineSecret`); never add service-account files, tokens or private keys. Local env files are ignored. `TAPPED_API_URL` is an optional trusted API-origin override for proxy testing (default `https://api.tapped.ai`); changing it changes the destination of privileged ingress traffic.

CI builds/tests only; no automated deploy occurs. Moving this package has not changed any production handler or provider configuration.

# Contributing

## Setup

Use Node + pnpm via Corepack (version from the root `packageManager`), Rust, and Xcode with Swift 6/iOS 26 for the native app. Flutter/Dart are not required; Android is no longer supported.

```bash
just install        # pnpm install --frozen-lockfile
just lint           # Biome across pnpm packages
just typecheck
just build-node
just build-api
just dev-app
just dev <package>
just ios-test       # native app + UI/domain tests
just ios-data-test  # native data package tests
just functions-test # isolated npm Firebase backend
```

For an isolated API/Auth-emulator development stack, see [platform/local/README.md](platform/local/README.md).
For native setup and release configuration, see [com.intheloopstudio/README.md](com.intheloopstudio/README.md).
Firebase backend source/config lives in [services/firebase-functions/](services/firebase-functions/README.md), not in the mobile app. It has its own npm lockfile and is intentionally excluded from pnpm/Turbo.

## Code style

- TypeScript: Biome — 2-space indent, 120 columns, double quotes, semicolons.
- Rust: `cargo fmt` and `cargo clippy`.
- Swift: SwiftUI, Swift 6 strict concurrency; see the native README.
- Shared TS code goes in `packages/`; native code in `com.intheloopstudio/`.

## Pull requests

- Branch from `main`; keep PRs small and single-purpose.
- Relevant Node, Rust, native iOS and Firebase functions CI must pass.
- Commit lockfile changes alongside manifests.
- Never commit private credentials, signing keys, env files or service-account JSON. Public client identity configuration and placeholder `.env.example` files are distinct from private credentials.
- Firebase Auth remains in use. Application data/search are served by Rust/Postgres; do not reintroduce Firestore serving, fallback, synchronization or dual writes.

## Dependency pinning

Every dependency and toolchain version must be exact. Floating ranges (`^1.2.3`, `~1.2.3`, `>=1.2.3`, `*`, `latest`) and moving branches are not allowed.

### Node workspace

- Commit `pnpm-lock.yaml`; CI uses `pnpm install --frozen-lockfile`.
- Keep new dependencies and toolchain versions exact.

### Firebase functions

- Use `npm ci` inside `services/firebase-functions/`, with its committed `package-lock.json`.
- Pin dependency versions, `packageManager`, and Node in `.node-version`/`firebase-functions.yml`.
- Only named, allowlisted handlers may be deployed through the service's deployment command; no blanket function or Firestore rules deployments. See its live deployment audit first.

### Native iOS

- SPM only: `.package(url: …, exact: "x.y.z")`.
- Commit `Tapped.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- Resolve/build in CI with `-disableAutomaticPackageResolution`.
- Xcode Cloud uses the repository-root `ci_scripts/ci_post_clone.sh`, project `com.intheloopstudio/Tapped.xcodeproj`, and scheme `Runner`.

### Rust

- Commit `Cargo.lock`; prefer exact versions for new dependencies.

### GitHub Actions

- Pin actions to release tags and toolchains to exact versions. Do not use `latest` for new toolchain pins.

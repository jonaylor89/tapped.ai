# Contributing

## Setup

Requires [just](https://github.com/casey/just), Node 22 + pnpm (via Corepack, version from `packageManager`), Rust stable, and Flutter 3.41.5 for the mobile app.

```bash
just install        # pnpm install (frozen lockfile)
just lint           # Biome across all Node packages
just typecheck
just build-node     # all apps/ and Node services/
just build-api      # Rust API
just dev-app        # app.tapped.ai dev server
just dev <package>  # any other package
just flutter-ios / flutter-android
```

Run `just --list` for everything else (Typesense, Docker, migrations).

## Code style

- TypeScript: Biome (`biome.json`) — 2-space indent, 120 cols, double quotes, semicolons. `just lint-fix` before committing.
- Rust: `cargo fmt` + `cargo clippy` clean.
- Flutter: `flutter analyze` clean of warnings/errors (info-level lints are non-fatal in CI).
- Shared TS code goes in `packages/`; Flutter code only under `com.intheloopstudio/`.

## Pull requests

- Branch from `main`, keep PRs small and single-purpose.
- CI (`node.yml`, `rust.yml`, `flutter.yml`) must be green; `pubspec.lock` / `pnpm-lock.yaml` / `Cargo.lock` changes are committed alongside the manifest change.
- Never commit secrets: `key.properties`, `*.jks`, `.env*`, service-account JSON. CI reads them from GitHub Actions secrets.

## Dependency pinning

Every dependency and every toolchain version in this repo is pinned to an exact version. Floating ranges (`^1.2.3`, `~1.2.3`, `>=1.2.3`, `*`, `latest`) and moving branches (`stable`, `main`) are not allowed. A build that resolves differently today than it did yesterday is a bug.

Why: the Flutter `stable` channel drifted from 3.41 to 3.47 and broke `flutter pub get` on Xcode Cloud (`flutter_localizations` started requiring `intl ^0.20.3` while the app pinned `0.20.2`). Nothing in the repo had changed.

### Flutter (`com.intheloopstudio/`)

- `pubspec.yaml`: every entry in `dependencies`, `dev_dependencies`, and `dependency_overrides` is an exact version (`foo: 1.2.3`, never `foo: ^1.2.3`).
- Git dependencies pin `ref` to a full commit SHA, not a branch or tag.
- `environment.sdk` and `environment.flutter` are exact versions.
- `pubspec.lock` is committed. Run `flutter pub get` after editing `pubspec.yaml` and commit the lockfile change in the same PR.
- To upgrade a package: change the version in `pubspec.yaml` by hand, run `flutter pub get`, commit both files. Do not run `flutter pub upgrade` without reviewing the resulting diff.

### Flutter toolchain

The Flutter version is pinned in three places and they must always agree:

| Location | Key |
|----------|-----|
| `.github/workflows/flutter.yml` | `flutter-version:` (three jobs) |
| `com.intheloopstudio/ios/ci_scripts/ci_post_clone.sh` | `FLUTTER_VERSION=` |
| `com.intheloopstudio/pubspec.yaml` | `environment.flutter` |

Check the Dart version bundled with that Flutter release (`flutter --version`) and update `environment.sdk` to match when bumping.

### Node (`apps/`, `packages/`, `services/*` on Node)

- `pnpm-lock.yaml` is committed and CI installs with `pnpm install --frozen-lockfile`.
- `packageManager` in the root `package.json` and `node-version` in `.github/workflows/node.yml` are exact versions.
- New `package.json` entries should be exact versions.

### Rust (`services/api.tapped.ai/`, `services/venue-enrichment/`)

- `Cargo.lock` is committed. Exact versions in `Cargo.toml` are preferred for new dependencies.

### GitHub Actions

- Pin third-party actions to a release tag (e.g. `subosito/flutter-action@v2`) and pass exact tool versions to them (`flutter-version: 3.41.5`, `node-version: '22'`).

# Tapped Monorepo

## Quick Commands (via Just)

```bash
just --list          # Show all commands
just install         # pnpm install across all packages
just lint            # Lint everything
just lint-fix        # Auto-fix lint issues
just build-all       # Build Node.js + Rust projects
just dev-app         # Start app.tapped.ai dev server
just dev <package>   # Start dev server for specific package
```

## Project Structure

This is a Turborepo monorepo. Frontend apps live in `apps/`, backend services in `services/`.

| Directory | Tech | Description |
|-----------|------|-------------|
| `apps/app.tapped.ai/` | Next.js | Main web application |
| `apps/getmusicart.com/` | Next.js | Music art generator |
| `apps/getmusicepk.com/` | Next.js | EPK generator |
| `apps/getmusicviralchecker.com/` | Astro | Viral checker tool |
| `apps/linktree.tapped.ai/` | Astro | Link tree page |
| `apps/marketer.tapped.ai/` | Next.js | Marketing tools |
| `apps/viralsocialmediaideas.com/` | Astro | Social media ideas |
| `services/api.tapped.ai/` | Rust | Backend API |
| `services/event-crawler/` | Node.js | Event scraping service |
| `services/ticket-crawler/` | Node.js | Ticket scraping service |
| `services/venue-enrichment/` | Rust | Venue data enrichment |
| `services/midia-to-threads/` | Python | Midia to threads |
| `com.intheloopstudio/` | SwiftUI | Native iOS app (see its README) |
| `services/firebase-functions/` | Node.js | Standalone Firebase Auth hooks and compatibility endpoints (npm) |
| `platform/` | Terraform | Infrastructure |
| `packages/` | TypeScript | Shared code |

## Shared Packages

- `@tapped/firebase-config` - Firebase initialization
- `@tapped/domain` - Shared TypeScript types
- `@tapped/ui` - Shared UI components

## Code Style

- **Formatter**: Biome (2-space indent, 120 line width)
- **Quotes**: Double quotes, semicolons always
- **Linting**: Biome with recommended rules

## Dependency Pinning

Every dependency and toolchain version is pinned exactly — no `^`, `~`, `>=`, `stable`, or `latest`. See CONTRIBUTING.md for the full rule. In short:

- Firebase functions: isolated npm package in `services/firebase-functions/`; exact dependencies and `package-lock.json`, Node pinned in `.node-version` and `firebase-functions.yml`. Use `npm ci`, not the root pnpm workspace.
- Node: `pnpm install --frozen-lockfile`; `packageManager` in `package.json` and `node-version` in `.github/workflows/node.yml` are exact.
- Rust: `Cargo.lock` is committed.
- iOS native (`com.intheloopstudio/`): SPM only, every package `.package(url:…, exact: "x.y.z")`; `Tapped.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` is committed and CI resolves with `-disableAutomaticPackageResolution`.

## CI/CD

- `node.yml` - Lint, typecheck, build all Node.js packages
- `rust.yml` - Build and clippy for Rust projects  
- `firebase-functions.yml` - Build/test the standalone Firebase backend; no automatic deploy
- `ios.yml` - Build and test the native SwiftUI app on an iPhone simulator

## iOS native app (`com.intheloopstudio/`)

Swift 6 (strict concurrency), SwiftUI, iOS 26, xcodegen (`project.yml`) + local packages `TappedDomain`, `TappedData`, `TappedUI`. Native source, tests and README are the specification. The legacy mobile app is retired; Android is no longer supported. Branches `ios/…`, PR titles `feat(ios): …`.

Firebase Auth remains the identity provider. Application data/search use Rust/Postgres; never add Firestore serving, syncing or dual writes. Firebase Functions source/config is independent of mobile code; see `services/firebase-functions/README.md` before deploying. Only explicitly approved functions may be deployed, never a blanket deployment.

```bash
cd com.intheloopstudio
xcodegen generate   # after editing project.yml
xcodebuild build test -project Tapped.xcodeproj -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17'
(cd Packages/TappedData && xcodebuild test -scheme TappedData -destination 'platform=iOS Simulator,name=iPhone 17')
```

Without a real `GoogleService-Info.plist` (or with `TAPPED_MOCK=1`, the `Tapped Mock` scheme) the app runs on mock repositories.

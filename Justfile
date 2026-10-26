
# Default recipe - show available commands
default:
    @just --list

# === Monorepo Commands ===

# Install all dependencies
install:
    pnpm install --frozen-lockfile

# Lint all packages
lint:
    pnpm run lint

# Fix lint issues in all packages  
lint-fix:
    pnpm run lint:fix

# Build all Node.js packages
build-node:
    pnpm run build

# Typecheck all TypeScript packages
typecheck:
    pnpm run typecheck

# Build Rust API
build-api:
    cd services/api.tapped.ai && cargo build --release

# Build Rust venue-enrichment
build-venue:
    cd services/venue-enrichment && cargo build --release

# Build all Rust projects
build-rust: build-api build-venue

# Build everything
build-all: build-node build-rust

# Build and test the native iOS app (override if simulator names repeat)
ios-test destination="platform=iOS Simulator,name=iPhone 17":
    cd com.intheloopstudio && xcodebuild build test -project Tapped.xcodeproj -scheme Runner -destination '{{destination}}'

# Test the native data package separately
ios-data-test destination="platform=iOS Simulator,name=iPhone 17":
    cd com.intheloopstudio/Packages/TappedData && xcodebuild test -scheme TappedData -destination '{{destination}}'

# Standalone Firebase backend; deliberately excluded from the pnpm/Turbo workspace
functions-test:
    cd services/firebase-functions && npm ci && npm run lint && npm run build && npm test

# Dev server for main web app
dev-app:
    cd apps/app.tapped.ai && pnpm dev

# Dev server for a specific app
dev app:
    cd apps/{{app}} && pnpm dev

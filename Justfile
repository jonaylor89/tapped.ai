
# Default recipe - show available commands
default:
    @just --list

# Start Typesense with Docker Compose
start:
    docker-compose up -d

# Stop Typesense services
stop:
    docker-compose down

# Show Typesense logs
logs:
    docker-compose logs -f typesense

# Initialize empty Typesense collection
init:
    deno --allow-env scripts/init-typesense.ts

# Recreate collection (delete existing)
recreate:
    deno --allow-env scripts/init-typesense.ts --recreate

migrate-to-firestore:
    deno --allow-env scripts/migrate-firestore-to-typesense.ts

# Quick setup - start services and initialize
setup: start init

# Health check - verify Typesense is running
health:
    curl -f http://localhost:8108/health || echo "Typesense not responding"

# Search test - basic search query
test-search query="*":
    curl "http://localhost:8108/collections/users/documents/search?q={{query}}&query_by=username" \
        -H "X-TYPESENSE-API-KEY: devapikey123"

# Clean up - stop services and remove volumes
clean: stop
    docker-compose down -v
    docker system prune -f

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

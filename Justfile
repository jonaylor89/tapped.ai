
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
    pnpm install

# Lint all packages
lint:
    pnpm -r run lint

# Fix lint issues in all packages  
lint-fix:
    pnpm -r run lint:fix

# Build all Node.js packages
build-node:
    pnpm -r run build

# Typecheck all TypeScript packages
typecheck:
    pnpm -r run typecheck

# Build Rust API
build-api:
    cd api.tapped.ai && cargo build --release

# Build Rust venue-enrichment
build-venue:
    cd venue-enrichment && cargo build --release

# Build all Rust projects
build-rust: build-api build-venue

# Build everything
build-all: build-node build-rust

# Run Flutter app (iOS simulator)
flutter-ios:
    cd com.intheloopstudio && flutter run

# Run Flutter app (Android)
flutter-android:
    cd com.intheloopstudio && flutter run -d android

# Dev server for main web app
dev-app:
    cd app.tapped.ai && pnpm dev

# Dev server for a specific package
dev package:
    cd {{package}} && pnpm dev

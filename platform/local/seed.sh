#!/usr/bin/env bash
# Resets the local Postgres serving tables to the synthetic fixtures in seed.sql.
set -euo pipefail
DATABASE_URL=${DATABASE_URL:-postgres://tapped:tapped@localhost:5432/tapped_local}
API=${TAPPED_API_URL:-http://localhost:8080}
case "$DATABASE_URL" in
  *localhost*|*127.0.0.1*|*@postgres:*) ;;
  *) echo "refusing to seed non-local DATABASE_URL" >&2; exit 1 ;;
esac
# The API applies migrations at boot; wait until it reports ready before seeding.
for _ in $(seq 1 60); do curl -sf "$API/health/ready" >/dev/null && break; sleep 1; done
psql -q -v ON_ERROR_STOP=1 "$DATABASE_URL" -f "$(dirname "$0")/seed.sql"
echo "seeded $DATABASE_URL"

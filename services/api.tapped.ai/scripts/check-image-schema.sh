#!/usr/bin/env bash
# Read-only preflight used for both rollout and rollback. Never starts the image/migrator.
set -euo pipefail
image="${1:?API image is required}"
version="$(docker exec tapped-postgres-1 psql -X -U tapped -d tapped -At -c 'SELECT coalesce(max(version),0) FROM _sqlx_migrations WHERE success')"
[[ "$version" =~ ^[0-9]{1,14}$ ]] || { echo 'Invalid production migration ledger' >&2; exit 1; }
[[ "$(docker image inspect "$image" --format '{{ index .Config.Labels "io.tapped.datastore" }}')" == postgres ]] || exit 1
epoch="$(docker image inspect "$image" --format '{{ index .Config.Labels "io.tapped.schema_epoch" }}')"
if (( 10#$version >= 20261024000000 )) && [[ "$epoch" != 20261024010000 ]]; then
  echo 'Image predates the Postgres serving schema' >&2
  exit 1
fi
if (( 10#$version >= 20261028000000 )); then
  bundle="$(docker image inspect "$image" --format '{{ index .Config.Labels "io.tapped.migration_bundle" }}')"
  [[ "$bundle" =~ ^[0-9]{14}$ ]] || { echo 'Image has no embedded migration-bundle declaration' >&2; exit 1; }
  if (( 10#$bundle < 10#$version )); then
    echo 'Image predates the applied scraper migrations; refusing rollout/rollback' >&2
    exit 1
  fi
fi

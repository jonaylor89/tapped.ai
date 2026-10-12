#!/usr/bin/env bash
# Smoke test of the local stack: emulator sign-in, public reads, own writes, cross-user rejection.
set -euo pipefail
API=${TAPPED_API_URL:-http://localhost:8080}
AUTH=${FIREBASE_AUTH_EMULATOR_HOST:-localhost:9099}
case "$API" in http://localhost*|http://127.0.0.1*) ;; *) echo "refusing non-local API $API" >&2; exit 1 ;; esac
failures=0

check() {
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (expected $2, got $3)"; failures=$((failures + 1)); fi
}

token() {
  curl -sf "http://$AUTH/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=local" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"local-password\",\"returnSecureToken\":true}" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["idToken"])'
}

status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

ALICE=$(token alice@example.test)

check "ready" 200 "$(status "$API/health/ready")"
check "public profile" 200 "$(status "$API/app/v1/users/username/alice_local")"
check "public profile hides email" "" "$(curl -s "$API/app/v1/users/username/alice_local" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("email") or "")')"
check "public opportunity" 200 "$(status "$API/app/v1/opportunities/local-opp-friday")"
check "auth required" 401 "$(status "$API/app/v1/data/users/local-alice")"
check "own profile" 200 "$(status -H "Authorization: Bearer $ALICE" "$API/app/v1/data/users/local-alice")"
check "own bookings" 200 "$(status -H "Authorization: Bearer $ALICE" "$API/app/v1/data/bookings?requesteeId=local-alice")"
check "edit own profile" 200 "$(status -X PUT -H "Authorization: Bearer $ALICE" -H 'Content-Type: application/json' \
  -d '{"id":"local-alice","username":"alice_local","bio":"Edited by smoke.sh"}' "$API/app/v1/data/users/local-alice")"
check "edit other profile" 403 "$(status -X PUT -H "Authorization: Bearer $ALICE" -H 'Content-Type: application/json' \
  -d '{"id":"local-bluebird","username":"bluebird_local","bio":"hijacked"}' "$API/app/v1/data/users/local-bluebird")"
check "search finds seed" true "$(curl -s -X POST -H 'Content-Type: application/json' -d '{"q":"alice"}' \
  "$API/app/v1/public/search/users" | grep -q local-alice && echo true || echo false)"

exit "$failures"

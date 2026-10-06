# Tapped Infrastructure - Hetzner Cloud

The Tapped API, Typesense search engine, and imgproxy image resizer are hosted on a Hetzner Cloud VPS behind Cloudflare Tunnel. The VPS has no publicly reachable TCP ports; administration uses Tailscale SSH.

## Server Details

- **Provider**: Hetzner Cloud
- **IP**: `46.225.133.198`
- **OS**: Ubuntu 24.04 LTS
- **RAM**: 4 GB
- **Disk**: 40 GB
- **Deployment**: Docker Compose at `/opt/tapped/`

| Service | Domain | Internal Port |
|---------|--------|---------------|
| API | `https://api.tapped.ai` | 3000 |
| Typesense | `https://search.tapped.ai` | 8108 |
| imgproxy | `https://img.tapped.ai` | 8080 |
| Cloudflare Tunnel | — | Outbound-only connector |

## Connect

```bash
tailscale ssh root@tapped-prod
```

## Manage Services

### Check status
```bash
cd /opt/tapped && docker compose ps
```

### View logs
```bash
docker compose logs -f           # all services
docker compose logs -f api       # API only
docker compose logs -f typesense # Typesense only
docker compose logs -f cloudflared # Cloudflare Tunnel only
```

### Restart
```bash
cd /opt/tapped && docker compose restart
```

### Deploy a new API version

`.github/workflows/deploy-api.yml` automatically deploys successful `main` builds of the Rust workflow. It builds one immutable Docker image tagged with the commit SHA and deploys that same image to both `api` and `mail-worker`.

The workflow can also be started manually with **Actions → Deploy API → Run workflow**.

Images are published to the private GitHub Container Registry package `ghcr.io/jonaylor89/tapped-api`. The workflow uses its short-lived `GITHUB_TOKEN` to push the image and authenticate the production VPS for the corresponding pull, so no long-lived registry credential is required.

The GitHub `Production` environment needs these repository or environment secrets:

| Secret | Purpose |
|---|---|
| `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client ID |
| `TS_OAUTH_SECRET` | Tailscale OAuth client secret |

The Tailscale OAuth client must be allowed to create ephemeral devices with `tag:github-actions`. Tailnet grants and SSH policy must allow that tag to reach `tapped-prod` on port 22 and use Tailscale SSH as `root` without an interactive check.

The production Compose file reads the shared API image from `API_IMAGE` in `/opt/tapped/.env`. The deploy workflow updates that value atomically, pulls the image, recreates `api` and `mail-worker`, and checks `https://api.tapped.ai/health`. A failed container start or health check restores the previous image.

For an emergency manual deployment:

```bash
tailscale ssh root@tapped-prod
cd /opt/tapped
# Update API_IMAGE in .env to an immutable image tag, then:
docker compose pull api mail-worker
docker compose up -d --no-deps api mail-worker
```

## Memory budget

The VPS has 4 GB and no swap headroom to spare, so every long-running container has a hard `mem_limit` in `docker-compose.prod.yml`. A container that hits its limit is OOM-killed and restarted (`restart: unless-stopped`) instead of starving the API.

| Service | `mem_limit` | `mem_reservation` | Notes |
|---------|-------------|-------------------|-------|
| typesense | 1 GB | 512 MB | Holds the whole index in RAM; restarts reload it from `/opt/typesense/data`, so search is unavailable for a while after an OOM kill. |
| imgproxy | 768 MB | — | Two workers (`IMGPROXY_WORKERS`). |
| api | 512 MB | 256 MB | The response cache is in-process. |
| mail-worker | 256 MB | 64 MB | Holds one email's attachments at a time. |

That leaves about 1.5 GB for the OS, Docker, cloudflared and the page cache. Before raising a limit, check what the containers actually use:

```bash
docker stats --no-stream
vmstat 1 5
docker inspect --format '{{.Name}} OOMKilled={{.State.OOMKilled}} restarts={{.RestartCount}}' $(docker compose ps -q)
```

If Typesense grows past its limit, grow the VPS rather than taking memory from the API.

The deploy workflow only recreates `api` and `mail-worker`. Apply a changed Typesense limit by hand (`docker compose up -d typesense`), which restarts search.

## API edge caching

The public document routes (`/app/v1/users/username/{username}` and `/app/v1/opportunities/{opportunity_id}`) send `Cache-Control: public, max-age=60, s-maxage=300, stale-while-revalidate=600` on a 200 and `public, max-age=30, s-maxage=60` on a 404. Every other API response is uncached.

Cloudflare doesn't cache extensionless URLs by default, so these headers only take effect with a cache rule (one-time setup):

- **tapped.ai zone → Caching → Cache Rules**: create a rule for `Hostname equals api.tapped.ai` and `URI Path starts with /app/v1/users/username/` or `URI Path starts with /app/v1/opportunities/`.
- Settings: *Eligible for cache*, *Edge TTL: use cache-control header if present, bypass cache if not*, *Browser TTL: respect origin*.

A cached response keeps the `X-Request-Id` of the origin request that filled the cache. Check `cf-cache-status` before searching the logs for it.

## Request logs and latency

The API logs JSON lines (bunyan format) to stdout. Every request gets an `X-Request-Id`: the client's if it sends a valid one (the iOS app sends a UUID per request), otherwise a generated UUID. The ID is echoed on the response, and error bodies also carry their own `error_id`.

- **Per route:** one `[HTTP_REQUEST - EVENT] request completed` line per request, with `request_id`, `method`, `matched_path` (the route template, e.g. `/app/v1/places/:place_id`), `status`, `latency_ms` and `user_id`.
- **Per dependency:** each downstream call is a span whose `[<NAME> - END]` line has `elapsed_milliseconds`, a `dependency` field (`firestore`, `typesense`, `openai`, `stream`, `google_places`, `spotify`, `slack`, `postmark`, `google_jwks`) and the parent request's `request_id`.

For example, p50/p95 per route over the last hour:

```bash
docker compose logs --since 1h --no-log-prefix api \
  | jq -cR 'fromjson? | select(.msg | endswith("request completed")) | {key: .matched_path, ms: .latency_ms}' \
  | jq -rs 'group_by(.key)[] | (map(.ms) | sort) as $ms
      | "\(.[0].key) p50=\($ms[length * 0.5 | floor])ms p95=\($ms[length * 0.95 | floor])ms n=\($ms | length)"'
```

For a dependency, select `.dependency != null and (.msg | endswith("- END]"))` and use `{key: .dependency, ms: .elapsed_milliseconds}`. There is no metrics endpoint; the logs are the source.

## Image resizing (img.tapped.ai)

`imgproxy` resizes Firebase Storage images on request and Cloudflare caches each variant at the edge, so the VPS only processes an image once per size. Clients rewrite Firebase Storage download URLs to

```
https://img.tapped.ai/unsafe/<preset>/<base64url(source URL)>
```

- **Presets only.** `IMGPROXY_ONLY_PRESETS` rejects arbitrary sizes, so nobody can bust the cache with random dimensions. `w<N>` fits the image to N px wide; `sq<N>` crops it to an N×N square. All output is WebP.
- **One source.** `IMGPROXY_ALLOWED_SOURCES` only allows the `in-the-loop-306520.appspot.com` bucket, so the proxy can't be pointed at other hosts. Source URLs aren't signed because the iOS app can't keep a key secret.
- **Mirrored ladder.** The preset list in `docker-compose.prod.yml` is mirrored in `apps/app.tapped.ai/src/lib/image-loader.ts` and `com.intheloopstudio/Packages/TappedDomain/Sources/TappedDomain/ImageProxy.swift`. Add a preset to the server before any client uses it.

### One-time Cloudflare setup

1. **Zero Trust → Networks → Tunnels → (tapped tunnel) → Public hostnames:** add `img.tapped.ai` → `HTTP` → `imgproxy:8080`.
2. **tapped.ai zone → Caching → Cache Rules:** create a rule for `Hostname equals img.tapped.ai` with *Eligible for cache*, *Edge TTL: use cache-control header if present*, and *Browser TTL: respect origin*. imgproxy sends `Cache-Control: max-age=31536000`. Without this rule Cloudflare won't cache the URLs, because they have no file extension.

### Deploy or update imgproxy

The API deploy workflow syncs `docker-compose.prod.yml` but only restarts `api` and `mail-worker`, so start or update imgproxy by hand:

```bash
tailscale ssh root@tapped-prod
cd /opt/tapped
docker compose pull imgproxy
docker compose up -d imgproxy cloudflared
curl -sI "https://img.tapped.ai/unsafe/w256/$(printf '%s' '<firebase download URL>' | base64 | tr '+/' '-_' | tr -d '=\n')"
```

## Backup

### Export Typesense data
```bash
# From your local machine
scp -r root@46.225.133.198:/opt/typesense/data ./typesense-backup-$(date +%Y%m%d)
```

## Environment Variables

Services that connect to Typesense and the API use these env vars:

| Variable | Value |
|----------|-------|
| `TYPESENSE_HOST` | `search.tapped.ai` |
| `TYPESENSE_PORT` | `443` |
| `TYPESENSE_PROTOCOL` | `https` |
| `TYPESENSE_SEARCH_API_KEY` | (stored in GCP Secret Manager: `typesense-api-key`) |
| `NEXT_PUBLIC_TAPPED_API_URL` | `https://api.tapped.ai` (optional, the default) |

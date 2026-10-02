# Tapped Infrastructure - Hetzner Cloud

The Tapped API and Typesense search engine are hosted on a Hetzner Cloud VPS behind Cloudflare Tunnel. The VPS has no publicly reachable TCP ports; administration uses Tailscale SSH.

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

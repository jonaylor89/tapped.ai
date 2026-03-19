# Tapped Infrastructure - Hetzner Cloud

The Tapped API and Typesense search engine are hosted on a Hetzner Cloud VPS behind Caddy (auto-HTTPS).

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
| Caddy (reverse proxy) | — | 80/443 |

## Connect

```bash
ssh root@46.225.133.198
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
docker compose logs -f caddy     # Caddy only
```

### Restart
```bash
cd /opt/tapped && docker compose restart
```

### Deploy a new API version
```bash
# On your laptop (from repo root):
docker buildx build --platform linux/amd64 -t jonaylor/api.tapped.ai:latest --push ./services/api.tapped.ai

# On the VPS:
cd /opt/tapped && docker compose pull api && docker compose up -d
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
| `NEXT_PUBLIC_API_URL` | `https://api.tapped.ai` |

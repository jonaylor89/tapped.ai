# Typesense Infrastructure - Hetzner Cloud

Typesense search engine is hosted on a Hetzner Cloud VPS.

## Server Details

- **Provider**: Hetzner Cloud
- **IP**: `46.225.133.198`
- **OS**: Ubuntu 24.04 LTS
- **RAM**: 4 GB
- **Disk**: 40 GB
- **Typesense Version**: 0.25.2
- **Data Directory**: `/opt/typesense/data`
- **Port**: 8108

## Connect

```bash
ssh root@46.225.133.198
```

## Manage Typesense

### Check status
```bash
docker ps
curl http://localhost:8108/health
```

### View logs
```bash
docker logs typesense -f
```

### Restart
```bash
docker restart typesense
```

### Stop / Start
```bash
docker stop typesense
docker start typesense
```

## Backup

### Export data
```bash
# From your local machine
scp -r root@46.225.133.198:/opt/typesense/data ./typesense-backup-$(date +%Y%m%d)
```

## Environment Variables

Services that connect to Typesense use these env vars:

| Variable | Value |
|----------|-------|
| `TYPESENSE_HOST` | `46.225.133.198` |
| `TYPESENSE_PORT` | `8108` |
| `TYPESENSE_PROTOCOL` | `http` |
| `TYPESENSE_SEARCH_API_KEY` | (stored in GCP Secret Manager: `typesense-api-key`) |

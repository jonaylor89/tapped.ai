# Tapped Infrastructure - Hetzner Cloud
#
# Services are deployed via Docker Compose on a Hetzner VPS (not managed by Terraform).
# Caddy handles reverse proxy + auto-HTTPS.
#
# Server: 46.225.133.198
# OS: Ubuntu 24.04
# Deployment dir: /opt/tapped/
#
# Domains:
#   https://api.tapped.ai      → Rust API (port 3000)
#
# Connect via SSH:
#   ssh root@46.225.133.198
#
# Health checks:
#   curl https://api.tapped.ai/health

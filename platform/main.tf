# Typesense Infrastructure - Hetzner Cloud
#
# Typesense is deployed on a Hetzner Cloud VPS (not managed by Terraform).
#
# Server: 46.225.133.198
# OS: Ubuntu 24.04
# Typesense version: 0.25.2
# Data directory: /opt/typesense/data
# Port: 8108
#
# Connect via SSH:
#   ssh root@46.225.133.198
#
# Docker command running on the server:
#   docker run -d --name typesense --restart on-failure \
#     -p 8108:8108 -v /opt/typesense/data:/data \
#     typesense/typesense:0.25.2 \
#     --data-dir /data --api-key=<API_KEY> --enable-cors
#
# Health check:
#   curl http://46.225.133.198:8108/health

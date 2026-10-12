#!/usr/bin/env bash
# Self-signed localhost cert for the stub's TLS listener (the Stream iOS SDK only speaks https/wss).
# Pass a simulator UDID to also trust it there.
set -euo pipefail
dir="$(cd "$(dirname "$0")" && pwd)/.certs"
mkdir -p "$dir"
if [ ! -f "$dir/stub.pem" ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" -addext "extendedKeyUsage=serverAuth" \
    -keyout "$dir/stub-key.pem" -out "$dir/stub.pem" 2>/dev/null
fi
if [ $# -gt 0 ]; then xcrun simctl keychain "$1" add-root-cert "$dir/stub.pem"; fi
echo "$dir/stub.pem"

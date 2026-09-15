#!/bin/sh
set -eu
echo "cloudflared: waiting for /data/cloudflare.token (paste in setup UI)…"
while [ ! -s /data/cloudflare.token ]; do
  sleep 2
done
TOKEN=$(tr -d '\n\r' < /data/cloudflare.token)
exec /usr/local/bin/cloudflared tunnel --no-autoupdate run --token "$TOKEN"

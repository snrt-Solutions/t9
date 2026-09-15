# Self-hosting

## Purpose

Run `aesmsd` so browsers and the iOS app can reach the same origin advertised in `AESMS_BASE_URL` — for production that is **https://app.aesms.io** via Cloudflare Tunnel.

## Docker (supported path)

From `deploy/`:

```bash
cp .env.example .env
# Set CLOUDFLARE_TUNNEL_TOKEN, AESMS_BASE_URL=https://app.aesms.io, AESMS_DB_KEY=...
docker compose up -d --build
```

Services:

| Service | Role |
|---------|------|
| `aesms` | Application; listens on **8080** inside the container; `expose` only (no host `ports`) |
| `cloudflared` | Official Cloudflare image; `TUNNEL_TOKEN` from `CLOUDFLARE_TUNNEL_TOKEN` |

Both join Compose network `aesms-net`. Volume `aesms-data` → `/data`. User `aesms` (uid 10001).

Public hostname routing (`app.aesms.io` → `http://aesms:8080`) is configured in Cloudflare Zero Trust — see [Cloudflare Tunnel](../integrations/cloudflare-tunnel.md).

Optional loopback admin (not public):

```bash
docker compose -f docker-compose.yml -f docker-compose.local.yml up -d --build
# http://127.0.0.1:8080/setup.html
```

## Environment

See [README.md](../../../README.md#configuration) and [deploy/.env.example](../../../deploy/.env.example).

Required for private-origin HTTPS:

- `CLOUDFLARE_TUNNEL_TOKEN` — Tunnel token from Zero Trust (never commit)
- `AESMS_BASE_URL=https://app.aesms.io`
- `AESMS_DB_KEY` ≥ 16 characters (or complete setup once via local compose override)

Internet-facing nodes should also set `AESMS_TURNSTILE_SITE_KEY` / `AESMS_TURNSTILE_SECRET`. Per-source rate limits are on by default (`AESMS_RATE_LIMIT_DISABLED=1` to opt out).

## Local binary

```bash
export AESMS_DB_KEY='dev-only-change-me!!'
export AESMS_DATA=./data
export AESMS_LISTEN=:8080
export AESMS_BASE_URL=http://127.0.0.1:8080
./scripts/sync-web.sh   # if you edit web/
cd server && go run ./cmd/aesmsd
```

## TLS

Default production path: [Cloudflare Tunnel](../integrations/cloudflare-tunnel.md). The daemon does not serve HTTPS. Origin traffic on `aesms-net` is HTTP. Do not publish host `:8080` publicly alongside the tunnel.

## Files in `AESMS_DATA`

| File | When |
|------|------|
| `aesms.db.sealed` | Always after a successful boot/mutation |
| `aesms.db.keyfp` | Key fingerprint helper |
| `.aesms.work.db` | Only while process is up |

`.gitignore` already ignores `data/`, `*.sealed`, and `deploy/.env`.

## Related Documentation

- [Database encryption](database-encryption.md)
- [Operator status](../functionalities/operator-status.md)
- [Cloudflare Tunnel](../integrations/cloudflare-tunnel.md)
- [deploy/.env.example](../../../deploy/.env.example)

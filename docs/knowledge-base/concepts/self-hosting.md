# Self-hosting

## Purpose

Run `t9d` so browsers and the iOS app can reach the same origin advertised in `T9_BASE_URL` — for production that is **https://t9.snrt.tech** via Cloudflare Tunnel.

## Docker (supported path)

From `deploy/`:

```bash
cp .env.example .env
# Set CLOUDFLARE_TUNNEL_TOKEN, T9_BASE_URL=https://t9.snrt.tech, T9_DB_KEY=...
docker compose up -d --build
```

Services:

| Service | Role |
|---------|------|
| `t9` | Application; listens on **8080** inside the container; `expose` only (no host `ports`) |
| `cloudflared` | Official Cloudflare image; `TUNNEL_TOKEN` from `CLOUDFLARE_TUNNEL_TOKEN` |

Both join Compose network `t9-net`. Volume `t9-data` → `/data`. User `t9` (uid 10001).

Public hostname routing (`t9.snrt.tech` → `http://t9:8080`) is configured in Cloudflare Zero Trust — see [Cloudflare Tunnel](../integrations/cloudflare-tunnel.md).

Optional loopback admin (not public):

```bash
docker compose -f docker-compose.yml -f docker-compose.local.yml up -d --build
# http://127.0.0.1:8080/setup.html
```

## Environment

See [README.md](../../../README.md#configuration) and [deploy/.env.example](../../../deploy/.env.example).

Required for private-origin HTTPS:

- `CLOUDFLARE_TUNNEL_TOKEN` — Tunnel token from Zero Trust (never commit)
- `T9_BASE_URL=https://t9.snrt.tech`
- `T9_DB_KEY` ≥ 16 characters (or complete setup once via local compose override)

Internet-facing nodes should also set `T9_TURNSTILE_SITE_KEY` / `T9_TURNSTILE_SECRET`. Per-source rate limits are on by default (`T9_RATE_LIMIT_DISABLED=1` to opt out).

## Local binary

```bash
export T9_DB_KEY='dev-only-change-me!!'
export T9_DATA=./data
export T9_LISTEN=:8080
export T9_BASE_URL=http://127.0.0.1:8080
./scripts/sync-web.sh   # if you edit web/
cd server && go run ./cmd/t9d
```

## TLS

Default production path: [Cloudflare Tunnel](../integrations/cloudflare-tunnel.md). The daemon does not serve HTTPS. Origin traffic on `t9-net` is HTTP. Do not publish host `:8080` publicly alongside the tunnel.

## Files in `T9_DATA`

| File | When |
|------|------|
| `t9.db.sealed` | Always after a successful boot/mutation |
| `t9.db.keyfp` | Key fingerprint helper |
| `.t9.work.db` | Only while process is up |

`.gitignore` already ignores `data/`, `*.sealed`, and `deploy/.env`.

## Related Documentation

- [Database encryption](database-encryption.md)
- [Operator status](../functionalities/operator-status.md)
- [Cloudflare Tunnel](../integrations/cloudflare-tunnel.md)
- [deploy/.env.example](../../../deploy/.env.example)

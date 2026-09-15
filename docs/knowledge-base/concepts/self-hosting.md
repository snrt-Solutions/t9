# Self-hosting

## Purpose

Run `t9d` so browsers and the iOS app can reach the same origin advertised in `T9_BASE_URL`.

## Docker (supported path)

From `deploy/`:

```bash
cp .env.example .env   # set T9_DB_KEY; optional Turnstile keys for public create
docker compose up --build
```

Service `t9` publishes `${T9_PORT:-8080}:8080`, volume `t9-data` → `/data`, user `t9` (uid 10001). Image is CGO-free, Alpine, copies `web/` into embed at build. A `cloudflared` sidecar is always defined and activates when a tunnel token is present.

When Cloudflare Tunnel is the only public path, bind the published port to loopback so origin traffic cannot bypass the edge WAF:

```yaml
ports:
  - "127.0.0.1:${T9_PORT:-8080}:8080"
```

## Environment

See the table in [README.md](../../../README.md#configuration). Required: `T9_DB_KEY` ≥ 16 characters. Keep it backup-safe; rotation without the old key needs `T9_RESET_DB` and **destroys** mailbox state.

`T9_BASE_URL` must be the URL users type into the iOS app and that appears in `release_url`. Wrong values produce pending links that point at localhost behind a tunnel.

Internet-facing nodes should set `T9_TURNSTILE_SITE_KEY` and `T9_TURNSTILE_SECRET`. Without the secret, create captcha is skipped (local/dev). Per-source rate limits are on by default; set `T9_RATE_LIMIT_DISABLED=1` only for deliberate opt-out.

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

Put a proxy or [Cloudflare Tunnel](../integrations/cloudflare-tunnel.md) in front. The daemon does not serve HTTPS. Prefer Tunnel + Cloudflare WAF for public exposure; do not dual-publish a public `:8080` alongside the tunnel.

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

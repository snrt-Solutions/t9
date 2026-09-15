# Cloudflare Tunnel

## Purpose

Expose `t9d` with HTTPS and a public hostname without opening a port on the host firewall. The Compose stack always defines a `cloudflared` sidecar; it waits for a tunnel token written by setup (or env) and stays idle until that token exists.

## User or Business Value

Home or lab nodes can serve create/release pages and the mailbox API to a signed iOS app on cellular, using Cloudflare as TLS terminator and as the lightweight edge WAF / DDoS layer.

## Main Flow

1. Create a tunnel in Cloudflare Zero Trust.
2. Route a hostname to `http://t9:8080` (same Docker network as the `t9` service).
3. Complete setup UI (or set `T9_BASE_URL`) so `/data/cloudflare.token` (or equivalent) is present for the sidecar.
4. `docker compose up --build` from `deploy/` starts `t9` and `cloudflared`.

The sidecar `depends_on: t9`. It is not required for local-only use (no token → no public hostname).

## Edge WAF and availability

When the public URL is on Cloudflare:

- Enable **WAF managed rules** and **Bot Fight Mode** (Free-tier options where available) on the hostname.
- Prefer Cloudflare rate-limiting / Bot Management for volumetric abuse; `t9d` still applies hard per-source limits as a second line.
- Set Cloudflare Turnstile site/secret keys (`T9_TURNSTILE_SITE_KEY`, `T9_TURNSTILE_SECRET`) so account create is challenged.
- Publish the container port only on loopback when Tunnel is the sole public path, e.g. in Compose:

```yaml
ports:
  - "127.0.0.1:${T9_PORT:-8080}:8080"
```

Do not dual-expose a public host port and Tunnel — that bypasses the edge WAF.

## Rules

- Tunnel provider can observe connection metadata (threat model: curious CDN). Ciphertext remains opaque; usernames and sizes may still leak at HTTP layer depending on TLS termination.
- `T9_BASE_URL` must match the public hostname or iOS release links and `/v1/info` will advertise the wrong origin.
- Token belongs under the data volume / setup UI (gitignored), never in the image.
- `t9d` trusts `CF-Connecting-IP` only when the immediate TCP peer is private or loopback (typical Docker → app path).

## Edge Cases

- Empty tunnel token leaves `cloudflared` unable to establish a public route; local `127.0.0.1:8080` still works.
- Older docs mentioning `docker compose --profile tunnel` are obsolete — the sidecar is always defined.

## Code Locations

- `deploy/docker-compose.yml` service `cloudflared`
- `deploy/cloudflared.Dockerfile`, `deploy/cloudflared-entrypoint.sh`
- `deploy/.env.example`
- `server/internal/ratelimit` (Client-IP + budgets)
- `server/internal/captcha` (Turnstile)

## Related Documentation

- [Self-hosting](../concepts/self-hosting.md)
- [Trust boundaries](../concepts/trust-boundaries.md)
- [Operator status](../functionalities/operator-status.md)
- [Account creation](../functionalities/account-creation.md)
- [THREAT_MODEL.md](../../THREAT_MODEL.md)

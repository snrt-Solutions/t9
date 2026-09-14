# Cloudflare Tunnel

## Purpose

Expose `t9d` with HTTPS and a public hostname without opening a port on the host firewall. Optional Compose profile `tunnel`.

## User or Business Value

Home or lab nodes can serve create/release pages and the mailbox API to a signed iOS app on cellular, using Cloudflare as TLS terminator.

## Main Flow

1. Create a tunnel in Cloudflare Zero Trust.
2. Route a hostname to `http://t9:8080` (same Docker network as the `t9` service) or `http://host.docker.internal:8080`.
3. Set `CLOUDFLARE_TUNNEL_TOKEN` and `T9_BASE_URL=https://your.hostname` in `deploy/.env`.
4. `docker compose --profile tunnel up --build` starts `cloudflare/cloudflared:latest` with `tunnel --no-autoupdate run` and `TUNNEL_TOKEN`.

The sidecar `depends_on: t9`. It is not required for local-only use.

## Rules

- Tunnel provider can observe connection metadata (threat model: curious CDN). Ciphertext remains opaque; usernames and sizes may still leak at HTTP layer depending on TLS termination.
- `T9_BASE_URL` must match the public hostname or iOS release links and `/v1/info` will advertise the wrong origin.
- Token belongs in `deploy/.env` (gitignored), never in the image.

## Edge Cases

- Profile is opt-in; `docker compose up` without `--profile tunnel` does not start cloudflared.
- Empty `CLOUDFLARE_TUNNEL_TOKEN` with the profile enabled will not establish a tunnel.

## Code Locations

- `deploy/docker-compose.yml` service `cloudflared`
- `deploy/.env.example`

## Related Documentation

- [Self-hosting](../concepts/self-hosting.md)
- [Trust boundaries](../concepts/trust-boundaries.md)
- [Operator status](../functionalities/operator-status.md)
- [THREAT_MODEL.md](../../THREAT_MODEL.md)

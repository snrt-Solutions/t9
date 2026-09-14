# Operator status UI

## Purpose

Show public health and capability flags so an operator (or a tunnel check) can confirm `t9d` is up without offering a login.

## User or Business Value

Cloudflare / reverse-proxy smoke tests and humans can read fingerprint, base URL, and product flags (`web_login: false`, `fetch_once: true`, …) from a browser.

## Main Flow

`/status.html` fetches `/v1/health` and `/v1/info` in parallel (`credentials: omit`) and renders:

- Health ok/down
- Base URL
- Server fingerprint
- Fetch-once, web login, PII flags
- Max graphemes and message TTL hours

This is not an admin console: no account list, no message inspector, no key material.

## Entry Points

- `GET /status.html` (embedded static)
- `GET /v1/health`
- `GET /v1/info`

## Rules

- Both JSON endpoints are unauthenticated.
- Health returns `{ok: true, time: RFC3339 UTC}`.
- Info includes `name: "t9"`, `fingerprint`, `base_url`, `message_ttl_h: 24`, `max_graphemes: 160`, `web_login: false`, `pii: false`, `fetch_once: true`, `one_device: true`.
- No cookies.

## Edge Cases

- If `T9_BASE_URL` is wrong, status still loads locally but `release_url` values from device login will point at the misconfigured origin.
- Fingerprint is stable for a given sealed database (derived from `meta.server_id`). Wiping the DB mints a new identity; existing contact QRs will mismatch.

## Data Involved

`meta.server_id` → published fingerprint. Config `BaseURL`.

## Dependencies

- `webembed.Handler`
- `store.Fingerprint`

## Code Locations

- `web/status.html`
- `server/internal/api/api.go` — `handleHealth`, `handleInfo`
- `server/internal/webembed/embed.go`

## Related Documentation

- [Self-hosting](../concepts/self-hosting.md)
- [Cloudflare Tunnel](../integrations/cloudflare-tunnel.md)
- [Application architecture](../concepts/application-architecture.md)

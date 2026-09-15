# Cloudflare Tunnel

## Purpose

Expose `aesmsd` at **https://app.aesms.io** with HTTPS terminated by Cloudflare. The origin stays private: no host port publish, no router port-forward. Traffic path:

```text
Internet
    │
    ▼
https://app.aesms.io
    │
    ▼
Cloudflare (TLS + optional WAF)
    │
    │ Cloudflare Tunnel
    ▼
cloudflared  (Compose service)
    │
    │ http://aesms:8080  (Docker network only)
    ▼
aesms  (AeSMS.io application container)
```

## Prerequisites

- Docker + Docker Compose v2
- Domain `aesms.io` on Cloudflare DNS (hostname `app.aesms.io`)
- Cloudflare Zero Trust access (to create a Tunnel)
- A machine that can run Compose (home lab / VPS) with outbound HTTPS to Cloudflare (no inbound ports required)

## Application details (this repo)

| Item | Value |
|------|--------|
| Compose service | `aesms` |
| Internal listen | `AESMS_LISTEN=:8080` → port **8080** |
| Compose reachability | `http://aesms:8080` on network `aesms-net` |
| Host publish | **none** (default). Optional loopback via `docker-compose.local.yml` |
| Health | `GET /v1/health` (Compose healthcheck) |
| Tunnel client | Official image `cloudflare/cloudflared:latest` |
| Token env | `CLOUDFLARE_TUNNEL_TOKEN` → mapped to `TUNNEL_TOKEN` |

## 1. Create the Cloudflare Tunnel

1. Open [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) → **Networks** → **Tunnels** (or **Access** → **Tunnels**, depending on UI).
2. **Create a tunnel** → choose **Cloudflared**.
3. Name it (e.g. `aesms`).
4. Copy the **Tunnel token** (long string). You will put it only in `deploy/.env` — never in git.

## 2. Public hostname (required Dashboard step)

Still in the tunnel configuration, add a **Public Hostname**:

| Field | Value |
|-------|--------|
| Subdomain | `app` |
| Domain | `aesms.io` |
| Type | `HTTP` |
| URL | `http://aesms:8080` |

Notes:

- Service name `aesms` is the Compose service name (Docker DNS on `aesms-net`).
- Port `8080` matches `AESMS_LISTEN` / Dockerfile `EXPOSE`.
- Scheme is **HTTP** internally; Cloudflare terminates **HTTPS** for clients.
- Leave **No TLS Verify** irrelevant (origin is plain HTTP).

Save the public hostname. Cloudflare will create/update the DNS record for `app.aesms.io` as a **proxied** CNAME to the tunnel (orange cloud).

## 3. DNS check

In Cloudflare Dashboard → **DNS** → `aesms.io`:

- Record for `app` should exist, **Proxied** (orange cloud), pointing at the tunnel target Cloudflare manages.
- Do **not** create an A/AAAA to your home public IP for this hostname if you want private-origin only.

If the hostname was added under the tunnel UI, DNS is usually automatic. If not, add the CNAME Cloudflare shows for that tunnel and keep proxy **on**.

## 4. Configure environment (secrets you must set)

```bash
cd deploy
cp .env.example .env
```

Edit `deploy/.env` (gitignored):

```env
CLOUDFLARE_TUNNEL_TOKEN=<paste tunnel token from Zero Trust>
AESMS_BASE_URL=https://app.aesms.io
AESMS_DB_KEY=<at least 16 characters, keep backup-safe>
```

Optional but recommended for public create:

```env
AESMS_TURNSTILE_SITE_KEY=...
AESMS_TURNSTILE_SECRET=...
```

**Secrets you configure yourself (never commit):**

- `CLOUDFLARE_TUNNEL_TOKEN`
- `AESMS_DB_KEY`
- Turnstile keys (if used)
- APNs credentials (if used)

## 5. Start

```bash
cd deploy
docker compose up -d --build
```

Compose refuses to start `cloudflared` if `CLOUDFLARE_TUNNEL_TOKEN` is unset (required substitution).

Verify containers:

```bash
docker compose ps
docker compose logs -f cloudflared
docker compose logs -f aesms
```

Healthy `cloudflared` logs mention a registered connection / tunnel; they must **not** print the token.

## 6. Test reachability

```bash
curl -fsS https://app.aesms.io/v1/health
curl -fsS https://app.aesms.io/v1/info
```

Expect JSON with `"ok": true` and `"base_url":"https://app.aesms.io"`.

Confirm the origin is **not** public on the host:

```bash
# On the Docker host — nothing should listen on 0.0.0.0:8080 for aesms
ss -ltn | grep 8080 || true
# From the internet / another network, http://YOUR-PUBLIC-IP:8080 must fail
```

## 7. Optional local admin (loopback only)

First-boot via browser on the Docker host without using the public hostname:

```bash
cd deploy
docker compose -f docker-compose.yml -f docker-compose.local.yml up -d --build
```

Then open `http://127.0.0.1:8080/setup.html`. This binds **127.0.0.1 only** — still not a router port-forward. Prefer env (`AESMS_DB_KEY` + `AESMS_BASE_URL`) for production so the default compose stays port-free.

## 8. Edge WAF (recommended)

On the Cloudflare zone for `app.aesms.io`:

- Enable **WAF** managed rules / **Bot Fight Mode** where available
- Keep proxy orange-clouded
- Set Turnstile for account create (`AESMS_TURNSTILE_*`)

## Troubleshooting

| Symptom | Check |
|---------|--------|
| `CLOUDFLARE_TUNNEL_TOKEN` error on compose | Token missing in `deploy/.env` |
| `cloudflared` restart loop | Invalid/expired token; recreate token in Zero Trust |
| 502 Bad Gateway | Public hostname URL wrong (must be `http://aesms:8080`); `aesms` not on same network; app still in setup / crash |
| Wrong release links | `AESMS_BASE_URL` must be `https://app.aesms.io` |
| Decrypt / auth failed on boot | Wrong `AESMS_DB_KEY`; restore key or one-shot `AESMS_RESET_DB=1` then unset |
| Setup UI unreachable | Default compose has **no** host ports — use `.env` boot or `docker-compose.local.yml` |

### cloudflared logs

```bash
cd deploy
docker compose logs -f cloudflared
docker compose logs --tail=200 cloudflared
```

### Restart policies

Both services use `restart: unless-stopped`. `cloudflared` `depends_on: aesms` waits for **start**, not health — so a slow app boot does not block the tunnel client from starting.

## Security (private origin)

- No `ports:` on `aesms` in the default compose file — only `expose: "8080"` on `aesms-net`
- No router port-forward required or desired
- Token only in `deploy/.env` (gitignored); not in images or compose literals
- TLS only at Cloudflare; origin speaks HTTP on the private Docker network
- Do not dual-publish a public host port alongside the tunnel

## Code locations

- [`deploy/docker-compose.yml`](../../deploy/docker-compose.yml) — `aesms` + `cloudflared` + `aesms-net`
- [`deploy/docker-compose.local.yml`](../../deploy/docker-compose.local.yml) — optional loopback publish
- [`deploy/.env.example`](../../deploy/.env.example)
- [`deploy/Dockerfile`](../../deploy/Dockerfile) — app listens on 8080

## Related documentation

- [Self-hosting](../concepts/self-hosting.md)
- [Trust boundaries](../concepts/trust-boundaries.md)
- [THREAT_MODEL.md](../../THREAT_MODEL.md)
- [README.md](../../README.md)

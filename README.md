# T-9

Private **fetch-once** messaging. Self-host the Go mailbox; use the **signed iOS app** for ciphertext. Browsers create accounts, enroll TOTP, and **release** pending device logins — they never get a mailbox session.

## Quick start (Docker)

```bash
cd deploy
cp .env.example .env   # set a long T9_DB_KEY
# optional: set T9_BASE_URL to your public URL
docker compose up --build
```

Open [http://127.0.0.1:8080](http://127.0.0.1:8080) → create account → scan TOTP QR → confirm.

### Cloudflare Tunnel (no public IP)

1. Create a tunnel in Zero Trust and point hostname → `http://t9:8080` (Docker network) or `http://host.docker.internal:8080`.
2. Put the token in `deploy/.env` as `CLOUDFLARE_TUNNEL_TOKEN=...`
3. Set `T9_BASE_URL=https://your.hostname`
4. Start with the tunnel profile:

```bash
docker compose --profile tunnel up --build
```

## Local Go (dev)

Requires Go 1.22+:

```bash
export T9_DB_KEY='dev-only-change-me!!'
export T9_DATA=./data
export T9_LISTEN=:8080
export T9_BASE_URL=http://127.0.0.1:8080
cd server && go run ./cmd/t9d
```

Tests: `cd server && go test ./...`

## Product rules (short)

- **160** Unicode graphemes max per message  
- **Fetch-once** + **24h** TTL purge  
- **One device** per account  
- **No web login / no account cookies**  
- **No PII** (no email/phone)  
- Contacts only via **physical QR** in the app  
- DB at rest sealed with **`T9_DB_KEY`**

## Threat model (summary)

Password theft alone cannot bind a mailbox: device login stays `pending` until **username + TOTP** release on the web. The server is a blind mailbox (ciphertext + delivery metadata). Private keys stay on device (Keychain / encrypted backup). See [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) and [docs/PROTOCOL.md](docs/PROTOCOL.md).

## Layout

| Path | Role |
|------|------|
| `server/` | `t9d` API + embedded web |
| `web/` | Create / release / operator UI source |
| `deploy/` | Dockerfile + Compose + optional cloudflared |
| `ios/` | SwiftUI MVP (signed app) |
| `docs/` | Protocol + threat model |

## iOS

Open `ios/T9.xcodeproj` in Xcode, set your Team for signing, run on a device/simulator. Configure server URL → usr/pw → approve release on the web → mailbox / QR contacts / backup.

## Limitations (MVP)

- App Attest not enforced yet (assertion placeholder)
- No Android, APNs, groups, or media
- DB encryption is whole-file AES-GCM seal (pure Go), not SQLCipher pages — documented in PROTOCOL.md
- Working SQLite exists while the process runs

## License

Unlicense — see [LICENSE](LICENSE).

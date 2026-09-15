# T-9 Threat Model

## Assets

- Account password verifier (Argon2id)
- TOTP secret (encrypted at rest)
- Device session token (hash at rest; plaintext only in app / one-shot poll)
- Message ciphertext (blind mailbox)
- Client identity private keys (Keychain + optional passphrase backup)
- Local contact graph (device only)

## Adversaries

| Adversary | Goal | Mitigations |
|-----------|------|-------------|
| Network eavesdropper | Read mail / steal tokens | TLS (terminate at tunnel/reverse proxy); E2E ciphertext |
| Malicious server operator | Read mail / impersonate | Blind mailbox; no private keys server-side; operator still sees metadata (who→whom, sizes, times) |
| Password thief | Bind attacker device | Web TOTP **release gate**; password alone leaves login `pending` |
| Stolen browser cookie | Hijack account | **No web account sessions / cookies** |
| Disk theft (offline host) | Dump DB | `T9_DB_KEY` sealed SQLite + column crypto |
| Compromised unsigned client | Forge device bind | MVP relies on signed distribution; App Attest later |
| Curious CDN / Tunnel provider | Observe traffic | Still ciphertext; metadata leakage possible |
| Signup bot / scripted create | Exhaust usernames, burn CPU on Argon2 | Cloudflare Turnstile on `POST /v1/accounts`; unknown-JSON rejection; per-source rate limits |
| Request flood / cheap DoS | Exhaust CPU/bandwidth | In-process per-source rate limits (auth heavy before Argon2); Cloudflare WAF / Bot Fight when Tunnel is the public edge; bind host port to localhost when Tunnel-only |

## Explicit non-goals (MVP)

- Hiding traffic analysis / metadata from the server
- Multi-device concurrent sessions
- Federation / cross-server contacts
- Perfect forward secrecy beyond per-message seal
- APNs push (polling for now)
- Multi-instance shared rate-limit state (single-node limiter)

## Trust boundaries

1. **Browser** — untrusted for mailbox. May create accounts and release devices.
2. **Signed iOS app** — holds keys + device token; only path to ciphertext APIs.
3. **Server** — enforces authz, TTL, fetch-once; must not learn plaintext.
4. **Physical proximity** — contact QR exchange; no server address book.
5. **Edge (Cloudflare Tunnel)** — may terminate TLS and supply `CF-Connecting-IP`. `t9d` trusts that header only when the immediate peer is private/loopback (Docker/tunnel hop).

## Residual risks

- Weak TOTP UX (phishing of codes on release page)
- Until App Attest: assertion is best-effort
- Working SQLite plaintext while process is live (RAM/disk forensics on a running node)
- Backup passphrase strength determines offline key safety
- Incomplete TOTP enrollments are deleted (timeout, cancel, or replace); they must not park a username
- Without Turnstile keys, create remains open (dev default); internet-facing nodes should set keys
- Dual-exposing `:8080` publicly while also using Tunnel bypasses edge WAF

## Audit notes

- Prefer reading `docs/PROTOCOL.md` + `server/internal/{api,store,crypto,ratelimit,captcha}`
- Integration tests assert: no account cookies, mailbox rejects non-device tokens, pending cannot fetch until release, sealed DB lacks SQLite magic without key, unknown JSON rejected, captcha fail-closed when configured, 429 on auth bursts
- No telemetry by design

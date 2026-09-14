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

## Explicit non-goals (MVP)

- Hiding traffic analysis / metadata from the server
- Multi-device concurrent sessions
- Federation / cross-server contacts
- Perfect forward secrecy beyond per-message seal
- APNs push (polling for now)

## Trust boundaries

1. **Browser** — untrusted for mailbox. May create accounts and release devices.
2. **Signed iOS app** — holds keys + device token; only path to ciphertext APIs.
3. **Server** — enforces authz, TTL, fetch-once; must not learn plaintext.
4. **Physical proximity** — contact QR exchange; no server address book.

## Residual risks

- Weak TOTP UX (phishing of codes on release page)
- Until App Attest: assertion is best-effort
- Working SQLite plaintext while process is live (RAM/disk forensics on a running node)
- Backup passphrase strength determines offline key safety
- One-device revoke-then-rebind needs user diligence

## Audit notes

- Prefer reading `docs/PROTOCOL.md` + `server/internal/{api,store,crypto}`
- Integration tests assert: no account cookies, mailbox rejects non-device tokens, pending cannot fetch until release, sealed DB lacks SQLite magic without key
- No telemetry by design

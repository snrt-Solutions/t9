# AeSMS.io Protocol

Self-hosted, fetch-once, E2E mailbox. Same-server only. No PII. No web account sessions.

## Identity

| Concept | Rule |
|--------|------|
| Username | Opaque handle `[A-Za-z0-9_]{3,32}` — not an email |
| Password | Argon2id hash on server |
| TOTP | Mandatory; secret sealed in DB under `AESMS_DB_KEY` |
| Device | One bound signed app per account |
| Web | Create + TOTP enroll + release pending login only |

## Flows

### Account create (web)

1. `POST /v1/accounts` `{username,password}` → `{totp_secret,totp_uri,totp_qr_png,enroll_expires_at}` (account **inactive**)
2. User scans QR / enrolls authenticator
3. `POST /v1/accounts/totp/confirm` `{username,code}` → account **active**
4. Response always has `"session": null`. No `Set-Cookie`.

If TOTP is **not** confirmed, the row is deleted and the username is free again:

- Re-`POST /v1/accounts` with the same handle replaces the unfinished enrollment
- `POST /v1/accounts/abandon` `{username,password}` deletes an inactive enrollment immediately
- Leaving the create page (beacon) or **Cancel** does the same
- Background purge deletes inactive rows at `enroll_expires_at` (15 minutes)
- Confirm after expiry also deletes the leftover row (`404`)

Active accounts are never removed this way.

### Device bind (app + web release)

1. App: `POST /v1/device/login` `{username,password,device_id,assertion}` → `{pending_id,status:"pending"}`
2. App polls `GET /v1/device/login/{pending_id}`
3. Browser: `POST /v1/device/release` `{username,code,pending_id,action:"approve"|"deny"}` (TOTP only; no password; no cookie retained)
4. On approve, server mints a **device token** (stored hashed). Next successful poll returns `device_token` **once**.
5. App stores token; uses `Authorization: Bearer <device_token>` on mailbox routes only.

`assertion` is a signed-app placeholder in MVP (App Attest planned later). Empty assertions are rejected.

### Revoke

- Device: `POST /v1/device/revoke` with Bearer device token
- Or web-style: body `{username,code}` with valid TOTP (still no session)

### Messages

- `POST /v1/messages` device token only  
  `{to_username, ciphertext (b64), graphemes (1..160), pubkey?}`
- `GET /v1/messages` device token only — **fetch-and-delete** all non-expired messages for that account
- Max **160 Unicode graphemes** (client authoritative count; server rejects out of range)
- Unfetched messages expire after **24h** (background purge)

### Public

- `GET /v1/health`
- `GET /v1/info` — `fingerprint`, `base_url`, capability flags (`web_login:false`, `pii:false`, `fetch_once:true`)

## Contact QR (client-local)

```
aesms://contact?u=<username>&pk=<base64url-curve25519-pubkey>&srv=<server-fingerprint>
```

Scanning creates a **local** contact only. Server never stores the contact graph. Apps should warn on `srv` mismatch vs configured server fingerprint.

## E2E crypto (client)

- Identity: X25519 keypair (CryptoKit / NaCl box)
- Seal plaintext (≤160 graphemes) to recipient pubkey before `POST /v1/messages`
- Server stores opaque ciphertext only

## Local backup (client)

Encrypted archive of identity keys + contacts (not the device token):

1. Format `T9BK1` + 16-byte salt + 12-byte nonce + AES-256-GCM ciphertext/tag
2. MVP KDF: passphrase + salt → **120,000 iterations of SHA-256** (interim; Argon2 preferred when available on-device)
3. Restore on a new device still requires **web release** to obtain a fresh device token

## Database encryption at rest

- Env: **`AESMS_DB_KEY`** (required, ≥16 chars)
- Persistent file: `AESMS_DATA/aesms.db.sealed` = magic `AESMS1\n` + AES-256-GCM(HKDF(AESMS_DB_KEY,"aesms-db-file-v1"), sqlite_bytes)
- TOTP secrets also column-encrypted with a separate HKDF key (`t9-column-v1`)
- While `aesmsd` runs, a process-local working SQLite file may exist under `AESMS_DATA`; it is removed on clean shutdown. Disk images of a powered-off host should only see the sealed blob.

This is **not** SQLCipher page encryption; it is whole-file seal + sensitive-column encryption, chosen for a pure-Go, CGO-free, auditable binary.

## Capability matrix

| Action | Web browser | Pending login | Device token |
|--------|-------------|---------------|--------------|
| Create account / TOTP | yes | — | — |
| Release / deny pending | yes (usr+TOTP) | — | — |
| Send / fetch ciphertext | no | no | yes |
| Read plaintext | never (no keys) | never | only with local keys |

## Errors of note

- PII field names (`email`, `phone`, …) → `400`
- Message routes without valid device Bearer → `401`
- Pending used as mailbox credential → `401`

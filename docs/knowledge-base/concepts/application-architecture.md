# Application architecture

## Purpose

Describe how the three surfaces (daemon, embedded web, iOS app) fit together so changes land in the right package.

## Layout

```text
t9/
  server/cmd/t9d          process: config → store.Open → purge goroutine → HTTP
  server/internal/api     routes, cookie filter, JSON handlers
  server/internal/store   SQLite schema, seal/unseal, domain operations
  server/internal/crypto  Argon2id, AES-GCM, HKDF, tokens
  server/internal/auth    username/password/TOTP/PII/QR
  server/internal/purge   1-minute expired-mail and enrollment cleanup
  server/internal/webembed  go:embed static UI
  web/                    HTML/CSS/JS source (sync or Docker COPY into embed)
  ios/T9                  SwiftUI client
  deploy/                 container + optional cloudflared
```

`main` loads env, opens the store (decrypts `t9.db.sealed` into `.t9.work.db`), starts purge, serves `api.Handler()` which wraps the mux in a filter that **deletes `Set-Cookie` on every response**.

## Request path

1. Public JSON under `/v1/…`
2. Static: `/` → `index.html`, `/release.html`, `/status.html`, `/assets/…` remapped onto the embed FS

Body limit is 1 MiB. JSON is parsed twice: once as `map[string]any` for PII key rejection, once into the typed struct.

## Process data

While running: plaintext working SQLite (max one connection). After mutations, `SealNow` checkpoints and writes `t9.db.sealed`. On SIGINT/SIGTERM, HTTP shutdown (10s) then `store.Close` seals and unlinks the working file.

## Client architecture

`AppState` phases: `server` → `credentials` → `waitingRelease` → `mailbox`. Device token in Keychain restores straight to mailbox. Networking is `APIClient` actor. Crypto is `KeyStore`. Files are `LocalStore`.

## Related Documentation

- [Self-hosting](self-hosting.md)
- [Database encryption](database-encryption.md)
- [No web sessions](no-web-sessions.md)
- [../../README.md](../../README.md)

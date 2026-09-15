# Database encryption

## Purpose

Explain what `AESMS_DB_KEY` actually protects, and what it does not.

## Two layers

1. **Whole-file seal.** Persistent path `AESMS_DATA/aesms.db.sealed` = magic `AESMS1\n` + AES-256-GCM of the SQLite file bytes. File key = HKDF-SHA256(`AESMS_DB_KEY`, info `aesms-db-file-v1`). AAD is the magic string.
2. **TOTP column encryption.** `accounts.totp_enc` is AES-GCM with HKDF info `t9-column-v1` and AAD `totp`.

Passwords are Argon2id hashes, not encrypted. Device tokens are SHA-256 hex. Message bodies are already client ciphertext.

## Lifecycle

`store.Open`:

- Optional `AESMS_RESET_DB` deletes sealed file + `aesms.db.keyfp`
- Decrypts sealed bytes into `.aesms.work.db` (mode 0600)
- Opens modernc.org/sqlite (CGO-free), max 1 connection, DELETE journal
- Migrates schema, ensures `server_id`, seals once, writes key fingerprint (first 8 bytes of SHA-256 of the master, hex)

Mutations call `SealNow` (WAL checkpoint best-effort, read working file, atomic rename of `.sealed.tmp`). `Close` seals, closes DB, unlinks working file and `-wal`/`-shm`.

`aesms.db.keyfp` stores that fingerprint so a wrong key can be diagnosed as mismatch vs corruption.

## What this is not

Not SQLCipher. Not page-level encryption. Not protection against a **running** node: the working SQLite is plaintext on disk for the process lifetime, and keys sit in RAM. Threat model: disk theft of a powered-off host; not a fully memory-safe enclave.

Tests assert the sealed blob has no `SQLite format 3` header and no raw TOTP secret.

## Related Documentation

- [Self-hosting](self-hosting.md)
- [Trust boundaries](trust-boundaries.md)
- [THREAT_MODEL.md](../../THREAT_MODEL.md)
- [PROTOCOL.md](../../PROTOCOL.md) (database encryption at rest)

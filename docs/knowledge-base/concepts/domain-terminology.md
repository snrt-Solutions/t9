# Domain terminology

Short glossary for the mailbox. Prefer these words in docs and UI copy.

| Term | Meaning |
|------|---------|
| **t9d** | The Go daemon (`server/cmd/t9d`) |
| **Mailbox** | Server-side ciphertext store with fetch-once + TTL |
| **Blind mailbox** | Operator sees metadata, not plaintext |
| **Handle / username** | Opaque `[A-Za-z0-9_]{3,32}` account name |
| **Inactive enrollment** | Account row after create, before TOTP confirm |
| **Release** | Web TOTP approve/deny of a pending device login |
| **Pending id** | UUID of an in-flight bind; not a mailbox credential |
| **Device token** | Bearer secret minted on approve, stored hashed, issued once on poll |
| **Assertion** | App-integrity placeholder (non-empty string in MVP) |
| **Fetch-once** | GET messages returns then deletes |
| **Grapheme** | Extended grapheme cluster; max 160 per message |
| **Contact QR** | `t9://contact?u&pk&srv` local-only address book entry |
| **Fingerprint** | Public hex id of this server database |
| **Sealed DB** | `t9.db.sealed` AES-GCM wrap of SQLite bytes |
| **Working DB** | `.t9.work.db` plaintext SQLite while `t9d` runs |
| **T9_DB_KEY** | Master secret (≥16 chars) for file seal + TOTP column crypto |
| **Keep locally** | Decrypted inbox copies on device after fetch |

## Related Documentation

- [Identity model](identity-model.md)
- [Fetch-once and TTL](fetch-once-and-ttl.md)
- [../index.md](../index.md)

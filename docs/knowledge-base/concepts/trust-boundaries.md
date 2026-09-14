# Trust boundaries

## Purpose

State who is trusted with which secrets. Matches [THREAT_MODEL.md](../../THREAT_MODEL.md); this page is the short operational version.

## Four boundaries

1. **Browser** — types passwords (create/abandon) and TOTP (confirm/release/revoke). Must not receive device tokens or ciphertext. Implemented via no cookies + device-only mailbox routes.
2. **Signed iOS app** — holds X25519 private key, device token, contacts, decrypted keep. MVP treats a non-empty `assertion` as “signed app”; App Attest is **not** checked, so an unsigned clone can still call the API if it has the password (bind still needs TOTP release).
3. **Server / operator** — sees usernames, password hashes, metadata (sender username, recipient id, ciphertext size, timestamps), pending device ids. Must not see plaintext or identity private keys. A malicious operator can drop, delay, or correlate mail.
4. **Physical proximity** — QR contact exchange. The server is not an introduction service.

## TLS

`t9d` speaks HTTP. Confidentiality on the wire depends on the reverse proxy or Cloudflare Tunnel in front. E2E ciphertext still helps if TLS is terminated by a curious proxy; metadata may leak.

## Adversary cheatsheet

| Adversary | Blocked by |
|-----------|------------|
| Network eavesdropper | TLS + E2E |
| Password thief | TOTP release gate |
| Stolen browser cookie | No cookies |
| Disk theft (host off) | `T9_DB_KEY` sealed file |
| Unsigned client (MVP) | Only weakly; attestation later |
| Malicious operator | Blind ciphertext; not metadata |

## Related Documentation

- [No web sessions](no-web-sessions.md)
- [Database encryption](database-encryption.md)
- [Device binding](../functionalities/device-binding.md)
- [THREAT_MODEL.md](../../THREAT_MODEL.md)

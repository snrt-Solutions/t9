# Encrypted local backup

## Purpose

Export identity keys and the local contact list as a passphrase-sealed blob the user can paste elsewhere. Restore reconstructs keys and contacts on a device. It does **not** restore the mailbox session; a fresh web release is still required.

## User or Business Value

A lost phone need not mean lost X25519 identity and QR-collected contacts. The host still never sees private keys. Stolen backups are only as strong as the passphrase and the MVP KDF.

## Main Flow

**Export**

1. Settings: enter passphrase, tap Export.
2. App packs JSON `{v:1, priv, pub, contacts}` (contacts JSON as base64).
3. Random 16-byte salt; key = SHA-256 iterated 120,000 times over `passphrase || salt`.
4. AES-GCM seal. File layout: magic `T9BK1` (5 bytes) + salt + 12-byte nonce + ciphertext + 16-byte tag.
5. UI shows standard base64 of that blob for copy.

**Restore**

1. Paste blob, same passphrase, tap Restore.
2. Open AES-GCM, decode keys + contacts, write them back locally.
3. User must still complete [device binding](device-binding.md) for a new `device_token`.

## Entry Points

- iOS `SettingsView` export / restore
- `LocalStore.exportBackup` / `importBackup`

No server endpoint.

## Rules

- Device token is **not** part of the archive (it is Keychain-only and server-hashed).
- Exchange history / kept inbox messages are **not** included in the backup payload (only identity + contacts).
- KDF is iterated SHA-256, documented as interim. PROTOCOL.md matches this implementation (not Argon2).
- Empty or wrong passphrase fails AES-GCM open (`badFormat` or CryptoKit error).

## Edge Cases

- Restoring keys onto a phone that already has a different identity overwrites the local pair used for decrypt — old ciphertext sealed to the previous pubkey will not open.
- Weak passphrases are a residual risk called out in the threat model.
- Backup is a paste blob, not iCloud / Files export UI.

## Data Involved

Magic `T9BK1`. Payload version `v: 1`. Fields `priv`, `pub` (base64 raw X25519), `contacts` (base64 of JSON `[Contact]`).

## Dependencies

- CryptoKit `AES.GCM`, `SHA256`
- Keychain identity keys (`identity_x25519_priv` / `_pub`)
- `LocalStore` Application Support files

## Code Locations

- `ios/AeSMS/Services/LocalStore.swift`
- `ios/AeSMS/Views/SettingsView.swift`
- `ios/AeSMS/Services/Keychain.swift`, `ios/AeSMS/Services/Crypto.swift`

## Related Documentation

- [Contact exchange](contact-exchange.md)
- [Device binding](device-binding.md)
- [Device revocation](device-revocation.md)
- [Trust boundaries](../concepts/trust-boundaries.md)
- [PROTOCOL.md](../../PROTOCOL.md) (local backup section)

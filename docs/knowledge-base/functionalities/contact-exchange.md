# Contact exchange

## Purpose

Build a local address book by exchanging a QR payload in person. The mailbox never stores who knows whom. Each contact carries a username, an X25519 public key, and the server fingerprint that minted the QR.

## User or Business Value

No directory, no invites, no “add by email.” Sealed mail is only practical after you have the other party’s public key. Fingerprints make it obvious when a QR came from a different `aesmsd` instance.

## Main Flow

1. Bound app loads identity from Keychain (or creates an X25519 pair).
2. Contacts screen renders a QR for:

   ```
   aesms://contact?u=<username>&pk=<base64-x25519-pubkey>&srv=<server-fingerprint>
   ```

3. The other person pastes that URI into “paste / scan payload” (camera scan is stubbed in this MVP).
4. App parses `scheme=aesms`, `host=contact`, query `u`, `pk`, `srv`.
5. Contact is appended to `contacts.json` unless that username already exists.
6. If `srv` ≠ the configured server’s `GET /v1/info` fingerprint, UI shows a warning but still saves the contact (flagged by color).

Composer refuses to send unless the `to` field matches a saved contact (case-insensitive).

## Entry Points

- iOS `ContactsView` (`myQR()`, `addFromPayload()`)
- `GET /v1/info` — `fingerprint` used for mismatch warnings
- Send path in `ComposerView` (contact lookup)

There is **no** HTTP contact API.

## Rules

- Server must not persist a contact graph (none of the SQL tables are an address book).
- `accounts.pubkey` may be updated when sending a message; that is a sender hint, not a directory.
- Duplicate username on add is ignored (first entry kept).
- Missing `u` or `pk` → `missing fields`.
- Unparseable payload → `bad payload`.
- Same-server only: protocol does not define cross-host delivery. A mismatched `srv` is a warning, not a hard block.

## Edge Cases

- Live camera / AVFoundation is not wired; Info.plist already has a camera usage string for a future signed build.
- PROTOCOL.md describes `pk` as base64url; the iOS client uses **standard base64** for CryptoKit raw keys and percent-encodes them in the URI. Interop clients should accept what this app emits.
- Contacts survive app relaunch via Application Support `AeSMS/contacts.json`. They are not on the server, so a new phone needs QR exchange again or a [local backup](encrypted-backup.md).

## Data Involved

`Contact`: `username`, `pubkey`, `serverFingerprint`, `addedAt`. Identity: `id = username + "|" + pubkey`.

Server identity: `meta.server_id` random token, published as first 16 hex chars of SHA-256 (`FingerprintHex`).

## Dependencies

- iOS CoreImage QR generator, `KeyStore.publicKeyB64()`
- `LocalStore.saveContacts` / `loadContacts`
- Server fingerprint from `store.ensureServerIdentity`

## Code Locations

- `ios/AeSMS/Views/ContactsView.swift`
- `ios/AeSMS/Models/Models.swift`
- `ios/AeSMS/Services/LocalStore.swift`
- `ios/AeSMS/Views/ComposerView.swift`
- `server/internal/store/store.go` (`ensureServerIdentity`)
- `server/internal/api/api.go` (`handleInfo`)

## Related Documentation

- [Messaging](messaging.md)
- [Encrypted local backup](encrypted-backup.md)
- [Identity model](../concepts/identity-model.md)
- [Trust boundaries](../concepts/trust-boundaries.md)

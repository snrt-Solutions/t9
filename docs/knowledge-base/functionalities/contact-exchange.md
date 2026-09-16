# Contact exchange

## Purpose

Build a local address book via a **proximity pair handshake**. The mailbox never stores a durable who-knows-whom graph. Each contact carries a username, an X25519 public key, and the server fingerprint observed at pair time.

## User or Business Value

No directory, no invites, no “add by email.” Sealed mail needs the other party’s public key. Rotating short-TTL pair codes make a leaked or photographed QR useless after expiry or rotation.

## Main Flow

1. Bound app loads identity from Keychain (or creates an X25519 pair).
2. Contacts screen mints a pair offer (`POST /v1/pair/offer`) and renders a rotating QR (~45s) for:

   ```
   aesms://pair?c=<opaque-code>&srv=<server-fingerprint>
   ```

3. Offerer polls `GET /v1/pair/offer` (~2s).
4. Peer scans with **Scan QR** (or pastes) and claims `POST /v1/pair/claim` with their pubkey.
5. Claimer receives offerer’s `{username,pubkey}` and saves a local contact.
6. Offerer’s next poll returns `{status:"claimed", peer:{username,pubkey}}` **once**; both sides now have each other.
7. Server stores only a hashed code + ephemeral intros; the row is deleted after the offerer’s one-shot poll (or purge on TTL).
8. Tapping the URI under My pair QR copies the current `aesms://pair?…` link.

Composer **To** is a dropdown of local contacts (no free-text directory).

Legacy paste of `aesms://contact?u&pk&srv` still imports a contact without handshake (transition only).

## Entry Points

- iOS `ContactsView` (offer rotate/poll, claim, copy) + `QRScannerView`
- `POST /v1/pair/offer`, `GET /v1/pair/offer`, `POST /v1/pair/claim` (device Bearer)
- `GET /v1/info` — `fingerprint` for `srv=` and mismatch warnings
- `ComposerView` contact Menu

## Rules

- Server must not persist a contact graph; `pair_offers` is ephemeral relay only.
- Codes are stored as SHA-256 hashes; plaintext code appears only in the QR / API create response.
- Offer TTL default **60s**; client rotates ~**45s**. Rotation invalidates prior codes.
- One active unclaimed offer per account; claimed-but-unpolled blocks rotation until poll.
- Cannot claim your own offer. Duplicate local username on add is ignored.
- `srv` mismatch → warning, contact still saved (flagged color).

## Edge Cases

- Camera permission on first scan (`NSCameraUsageDescription`).
- Expired or rotated codes → claim fails (`410` / `404`); photo of an old QR is useless.
- Contacts live in Application Support `AeSMS/contacts.json` (or [local backup](encrypted-backup.md)), not on the server.

## Data Involved

`Contact`: `username`, `pubkey`, `serverFingerprint`, `addedAt`.

`pair_offers`: hashed code, offerer/claimer intros, `expires_at` — deleted after consume/purge.

## Dependencies

- iOS CoreImage QR, AVFoundation scan, `KeyStore.publicKeyB64()`, `APIClient` pair methods
- `LocalStore.saveContacts` / `loadContacts`
- `store.UpsertPairOffer` / `ClaimPairOffer` / `PollPairOffer`

## Code Locations

- `ios/AeSMS/Views/ContactsView.swift`
- `ios/AeSMS/Views/QRScannerView.swift`
- `ios/AeSMS/Views/ComposerView.swift`
- `ios/AeSMS/Services/APIClient.swift`
- `server/internal/store/store.go`
- `server/internal/api/api.go` (`handlePairOfferCreate`, `handlePairOfferPoll`, `handlePairClaim`)

## Related Documentation

- [Messaging](messaging.md)
- [Encrypted local backup](encrypted-backup.md)
- [Identity model](../concepts/identity-model.md)
- [Trust boundaries](../concepts/trust-boundaries.md)

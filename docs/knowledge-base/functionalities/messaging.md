# Fetch-once messaging

## Purpose

Move a short sealed note from one bound device to another through a blind mailbox. The server stores ciphertext, sender username, and expiry. A successful fetch deletes the rows. Unfetched mail dies after 24 hours.

## User or Business Value

Recipients get mail without leaving a host-side archive. Operators cannot read plaintext. Message length stays in SMS-like 160-grapheme territory on purpose.

## Main Flow

**Send (iOS composer)**

1. User picks a local contact username and types ≤160 graphemes.
2. App looks up that contact’s X25519 public key (server has no address book).
3. App seals UTF-8 plaintext: ephemeral X25519 + HKDF-SHA256 (salt `t9-msg-v1`) + AES-GCM. Wire bytes: `ephemeral_pub (32) || nonce (12) || ciphertext || tag (16)`.
4. `POST /v1/messages` with Bearer device token, `to_username`, base64 `ciphertext`, `graphemes`, optional sender `pubkey`.
5. Server checks token, grapheme range 1–160, ciphertext non-empty and ≤4096 bytes, recipient exists and is active. Optionally stores sender pubkey on the sender account. Inserts the message with `expires_at = now + 24h`. Returns `id` and `expires_at`.

**Fetch (iOS inbox)**

1. `GET /v1/messages` with Bearer device token.
2. Server selects non-expired messages for that account, returns them, **deletes those rows**.
3. App decrypts with the local identity private key, keeps copies in `kept-messages.json`. Undecryptable payloads become the placeholder `«undecryptable»`.

## Entry Points

- `POST /v1/messages`
- `GET /v1/messages`
- iOS `ComposerView`, `InboxView`
- Purge runner: `DELETE FROM messages WHERE expires_at <= now` every minute

## Rules

- Mailbox routes require a valid **device** Bearer token (`requireDevice`). Missing/invalid → `401`.
- `graphemes` is client-authoritative; server only rejects out of `1..160`. It does not re-count ciphertext as text.
- Recipient unknown or inactive → `404 recipient not found`.
- Ciphertext must be valid standard base64, length 1–4096 after decode.
- Fetch order is `created_at ASC`. Inbox UI prepends newly fetched items.
- Successful GET is destructive even if the client fails to decrypt afterward.
- There is no mark-as-read, no pagination, no server-side search.

## Edge Cases

- Sending to a username that is not in local contacts is blocked in the iOS UI (`scan their QR first`). The HTTP API will still accept a send if you know the username — E2E then requires the correct pubkey; otherwise the recipient sees undecryptable bytes.
- Optional `pubkey` on send updates `accounts.pubkey` for the sender; it is not used by the server to encrypt.
- Fetching twice in a row returns an empty list the second time (`TestFetchOnceDeletes`).
- Expired rows are skipped by fetch and removed by purge; they are never delivered late.
- `plain_hint` exists on the Go request struct but is unused; grapheme enforcement is the `graphemes` field.

## Data Involved

Table `messages`: `id`, `recipient_account_id`, `sender_username`, `ciphertext` (blob), `created_at`, `expires_at`.

GET payload:

```json
{
  "messages": [
    {
      "id": "…",
      "from_username": "alice",
      "ciphertext": "<standard base64>",
      "created_at": "RFC3339"
    }
  ]
}
```

Local `LocalMessage`: id, from username, plaintext, createdAt, keptLocally.

## Dependencies

- `store.InsertMessage`, `FetchAndDelete`, `PurgeExpired`
- iOS `KeyStore.seal` / `open`, `APIClient.postMessage` / `fetchMessages`
- `auth.MaxMessageGraphemes` (160)
- Swift `String.count` as extended grapheme clusters; server `GraphemeCount` exists for other uses but is not applied to ciphertext

## Code Locations

- `server/internal/api/api.go` — `handlePostMessage`, `handleGetMessages`
- `server/internal/store/store.go` — insert / fetch-and-delete / purge
- `server/internal/purge/purge.go`
- `ios/T9/Services/Crypto.swift`, `ios/T9/Views/ComposerView.swift`, `ios/T9/Views/InboxView.swift`
- Tests: `TestMessagesRejectNonDeviceToken`, `TestFetchOnceDeletes`

## Related Documentation

- [Contact exchange](contact-exchange.md)
- [Fetch-once and TTL](../concepts/fetch-once-and-ttl.md)
- [Device binding](device-binding.md)
- [PROTOCOL.md](../../PROTOCOL.md)

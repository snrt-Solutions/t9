# Fetch-once and TTL

## Purpose

Mail is a hot potato. The host is not an archive. Two independent deletion paths exist: **read** and **time**.

## Fetch-once

`GET /v1/messages` loads all non-expired rows for the authenticated account, then deletes them by id before returning. A second GET is empty. If the client crashes after the HTTP success, those ciphertexts are gone from the server; only a local `kept-messages.json` copy remains if the app already wrote it.

There is no ack protocol, no retry queue, no “peek.”

## TTL

Each insert sets `expires_at = now + 24h` (`config.MessageTTL`). Fetch ignores expired rows. A purge goroutine every minute (`config.PurgeEvery`) deletes expired messages, marks expired pendings `denied`, and removes expired **inactive** enrollments.

## Client keep

The iOS inbox stores decrypted `LocalMessage` values locally after a successful fetch. That is the only history. It is not synced, not backed up in the T9BK1 blob, and not visible to `aesmsd`.

## Why 160 graphemes

The product is SMS-shaped notes, not attachments. Server trusts the client-supplied `graphemes` integer (1–160) and a 4096-byte ciphertext cap. It does not decode UTF-8 from the sealed blob.

## Related Documentation

- [Messaging](../functionalities/messaging.md)
- [Account creation](../functionalities/account-creation.md) (enrollment TTL is a different 15-minute clock)
- [PROTOCOL.md](../../PROTOCOL.md)

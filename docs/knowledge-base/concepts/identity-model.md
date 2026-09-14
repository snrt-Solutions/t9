# Identity model

## Purpose

Define what an “account” is in T-9, and what it is not.

## Handles, not people

A username is an opaque token `[A-Za-z0-9_]{3,32}`, unique `COLLATE NOCASE`. It is not an email, not a phone, not a display name. API bodies that include PII-shaped keys are rejected before business logic.

There is no password reset flow, no recovery email, no user profile document on the server.

## Authenticators stacked

| Factor | Where it lives | What it unlocks |
|--------|----------------|-----------------|
| Password | Argon2id hash on server | Starting a **pending** device login; abandoning incomplete enrollments |
| TOTP | Column-encrypted on server; codes on the user’s authenticator app | Activating the account; **releasing** a pending device; web-style revoke |
| Device token | SHA-256 on server; plaintext in iOS Keychain | Send / fetch ciphertext only |
| X25519 identity | Device Keychain only | Encrypt/decrypt message bodies |

Password without TOTP cannot finish a bind. TOTP without the app cannot read mail. The app without release cannot obtain a device token.

## One device

`device_sessions.account_id` is UNIQUE. A new approved bind deletes the previous session. Concurrent multi-device is an explicit non-goal.

## Server fingerprint

Each database has `meta.server_id`. Public fingerprint is the first 8 bytes of SHA-256, hex (16 characters). Contact QRs carry `srv=` so clients can warn on host mismatch. Wiping data changes identity.

## Client identity vs account

The X25519 pair is not registered as a first-class server object except optionally as `accounts.pubkey` when sending. Losing the device without a [backup](../functionalities/encrypted-backup.md) means others can still send to the old pubkey, but this phone will not decrypt.

## Related Documentation

- [Account creation](../functionalities/account-creation.md)
- [Device binding](../functionalities/device-binding.md)
- [Domain terminology](domain-terminology.md)
- [PROTOCOL.md](../../PROTOCOL.md)

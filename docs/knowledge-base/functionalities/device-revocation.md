# Device revocation

## Purpose

Drop the bound device session so mailbox Bearer tokens stop working. Used when a phone is lost, replaced, or the owner wants to unbind without waiting for a new approval to replace the unique session row.

## User or Business Value

Compromise of a device token is containable. Revocation does not delete the account, TOTP secret, or undelivered ciphertext (until TTL / fetch).

## Main Flow

Two equivalent gates, both `POST /v1/device/revoke`:

1. **From the app:** `Authorization: Bearer <device_token>`. Server hashes the token, deletes the matching `device_sessions` row. iOS then clears local token state.
2. **From the web (stateless):** JSON `{username, code}` with valid TOTP. Server deletes the session for that account. `"session": null`.

A later [device bind](device-binding.md) approval also deletes the previous session (one-device unique constraint).

## Entry Points

- `POST /v1/device/revoke`
- iOS Settings “Revoke device token”
- Web has no dedicated revoke page; a client can still call the API with username + TOTP

## Rules

- Bearer path: unknown token → `401 invalid token`.
- TOTP path: bad username treated as `401 invalid credentials`; bad code → `401 invalid totp`.
- TOTP path still issues no cookies.
- Revoke does not purge messages waiting for that account.
- Identity keys on device are local; revoke does not wipe Keychain unless the app does so after a successful call.

## Edge Cases

- After revoke, `GET /v1/messages` with the old token is `401`.
- Approving a new pending bind is enough to invalidate the old device even without an explicit revoke.
- Empty JSON body on the Bearer path is fine (iOS sends `{}`).

## Data Involved

Deletes from `device_sessions` by `token_hash` or `account_id`.

## Dependencies

- `store.RevokeByToken`, `store.RevokeByAccount`
- `auth.ValidateTOTP`
- `APIClient.revoke`

## Code Locations

- `server/internal/api/api.go` — `handleDeviceRevoke`
- `server/internal/store/store.go` — `RevokeByToken`, `RevokeByAccount`
- `ios/T9/Views/SettingsView.swift`, `ios/T9/Services/APIClient.swift`

## Related Documentation

- [Device binding](device-binding.md)
- [No web sessions](../concepts/no-web-sessions.md)
- [Encrypted local backup](encrypted-backup.md)

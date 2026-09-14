# Device binding and web release

## Purpose

Attach exactly one signed-app session to an active account. Password login from the app is not enough: a human must approve the pending bind on the website with a live TOTP code. The mailbox credential is a device token that appears once on poll.

## User or Business Value

A stolen password cannot silently take over the inbox. The browser that approves the bind still cannot read mail. Replacing a phone invalidates the previous device.

## Main Flow

1. iOS app `POST /v1/device/login` with `username`, `password`, `device_id`, and a non-empty `assertion`.
2. Server checks the account is active and the password verifies. It inserts a `pending_device_logins` row (`status=pending`, 15-minute TTL) and returns `202` with `pending_id`, `expires_at`, and `release_url`.
3. App polls `GET /v1/device/login/{pending_id}` about every 1.5s.
4. Owner opens `/release.html?pending_id=…`, enters username + TOTP, chooses approve or deny (`POST /v1/device/release`). No password, no cookie.
5. On **approve**: any existing `device_sessions` row for that account is deleted; a new 32-byte token is minted; only the SHA-256 hash is stored long-term; plaintext is written to `token_once` on the pending row.
6. Next successful poll returns `status: approved` and `device_token` **once**, then clears `token_once`.
7. App stores the token in Keychain and enters the mailbox.

On **deny**, pollers see `denied` and never receive a token.

## Entry Points

- `POST /v1/device/login`
- `GET /v1/device/login/{id}`
- `POST /v1/device/release`
- iOS: `CredentialsView` → `WaitingReleaseView`
- Web: `/release.html`

## Rules

- `device_id` required, length 1–128.
- Empty `assertion` → `400 assertion required`. MVP accepts any non-empty string (iOS sends `t9-ios-mvp-signed-placeholder`). App Attest is not verified.
- Inactive account → `403 account not active`.
- Bad username/password → `401 invalid credentials` (no user enumeration distinction beyond that).
- Release TOTP must match the account that owns the pending row; mismatch of pending vs username → `403 pending mismatch`.
- `action` must be `approve`, `allow`, or `deny`.
- Already resolved pending → `409 already resolved`.
- Expired pending → `410 pending expired`.
- `device_sessions.account_id` is UNIQUE: a new approval replaces the previous device.
- Pending id is not a mailbox credential (`401` if used as Bearer).
- Release responses include `"session": null`. `Set-Cookie` is stripped globally.

## Edge Cases

- Second poll after approve must not re-issue `device_token`.
- Creating a new pending does not automatically deny earlier still-valid pendings for the same account (only expired ones are marked denied at insert time). Operators should treat the web release `pending_id` as the source of truth.
- Poll of unknown id → `404`.
- Approving a second device silently invalidates the first token (one-device policy).
- Pending TTL is 15 minutes; purge also marks expired pendings `denied`.

## Data Involved

`pending_device_logins`: `id`, `account_id`, `device_id`, `assertion`, `status` (`pending` | `approved` | `denied`), `token_once`, `expires_at`, `created_at`.

`device_sessions`: `id`, `account_id` (unique), `device_id`, `token_hash`, `created_at`.

Login response: `pending_id`, `status`, `expires_at`, `release_url`.

Poll response: `pending_id`, `status`, optional `device_token` + `token_type: "device"`.

## Dependencies

- `crypto.VerifyPassword`, `crypto.RandomToken`, `crypto.HashToken`
- `auth.ValidateTOTP`
- `store.CreatePendingLogin`, `ConsumePendingPoll`, `ReleasePending`, `LookupDeviceToken`
- iOS `APIClient.deviceLogin` / `pollPending`, Keychain key `device_token`

## Code Locations

- `server/internal/api/api.go` — login, poll, release, `requireDevice`
- `server/internal/store/store.go` — pending and session tables
- `ios/T9/Services/APIClient.swift`, `ios/T9/Views/WaitingReleaseView.swift`, `ios/T9/App/AppState.swift`
- `web/release.html`
- Tests: `TestPendingCannotFetchUntilReleased`, `TestNoAccountSessionCookiesOnWebFlows`

## Related Documentation

- [Account creation](account-creation.md)
- [Messaging](messaging.md)
- [Device revocation](device-revocation.md)
- [No web sessions](../concepts/no-web-sessions.md)
- [Trust boundaries](../concepts/trust-boundaries.md)
- [THREAT_MODEL.md](../../THREAT_MODEL.md)

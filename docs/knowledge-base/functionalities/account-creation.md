# Account creation and TOTP enrollment

## Purpose

Register an opaque username with a password and a mandatory TOTP secret, then activate the account only after the owner confirms a live authenticator code. Until confirmation, the handle is not owned.

## User or Business Value

Operators get accounts without collecting email or phone. Users get a second factor that later gates every device bind. Incomplete sign-ups do not squat usernames.

## Main Flow

1. Browser `POST /v1/accounts` with `username` and `password`.
2. Server validates the handle and password, hashes the password (Argon2id), generates a TOTP key (issuer `T9`, 6 digits, 30s, SHA1), and stores an **inactive** row with the TOTP secret column-encrypted.
3. Response includes `totp_secret`, `totp_uri`, a PNG QR as `totp_qr_png` (data URL), `enroll_expires_at`, `active: false`, and `"session": null`.
4. User scans the QR or types the secret into an authenticator.
5. Browser `POST /v1/accounts/totp/confirm` with `username` and `code`.
6. Server decrypts the secret, validates TOTP, sets `active=1`, clears enrollment expiry. Still `"session": null`.

The create page (`web/index.html`) also lets the user cancel, which calls abandon so the username is free immediately.

## Entry Points

- `POST /v1/accounts`
- `POST /v1/accounts/totp/confirm`
- `POST /v1/accounts/abandon`
- Web UI: `/` (`web/index.html`)
- Background: purge job deletes inactive rows whose `enroll_expires_at` has passed

## Rules

- Username: `[A-Za-z0-9_]{3,32}`, case-insensitive uniqueness, no `@`.
- Password: 10–128 characters.
- JSON must not contain PII-shaped keys (`email`, `phone`, and similar) — `400`.
- Creating the same username while an **inactive** enrollment exists **replaces** that row (new TOTP secret).
- Creating the same username when the account is **active** → `409 username taken`.
- Confirm on an already-active account → `409 already active`.
- Confirm after enrollment expiry deletes the leftover row and returns `404`.
- Invalid TOTP → `401 invalid totp`.
- Abandon requires username + password, only for inactive rows. Wrong password → `401`. Already active → `409`. Missing inactive row is treated as success (`released: true`) so cancel is idempotent.
- No `Set-Cookie`. Fetch from the web UI uses `credentials: "omit"`.

## Edge Cases

- Leaving the create page while enrollment is open sends a beacon `POST /v1/accounts/abandon` so the handle is not parked.
- Confirm after the 15-minute window looks like “account not found” because the row is deleted.
- Purge can free usernames even if the browser never comes back.
- Active accounts are never deleted by enroll timeout, abandon, or recreate.

## Data Involved

Table `accounts`: `id`, `username`, `password_hash`, `totp_enc`, `active`, `pubkey`, `created_at`, `enroll_expires_at`.

Create response fields: `account_id`, `username`, `totp_secret`, `totp_uri`, `totp_qr_png`, `active`, `enroll_expires_at`, `session` (always null).

## Dependencies

- `auth.ValidateUsername` / `ValidatePassword` / `GenerateTOTP` / `ValidateTOTP` / `TOTPQRDataURL`
- `crypto.HashPassword` / `VerifyPassword`
- `store.CreateAccountInactive` / `ConfirmTOTP` / `AbandonEnrollment`
- `github.com/pquerna/otp` and QR PNG via `boombuler/barcode`

## Code Locations

- `server/internal/api/api.go` — `handleCreateAccount`, `handleConfirmTOTP`, `handleAbandonEnrollment`
- `server/internal/store/store.go` — inactive create, confirm, abandon, purge of expired enrollments
- `server/internal/auth/auth.go`, `server/internal/auth/qr.go`
- `web/index.html`, `web/js/t9.js`
- Tests: `TestUnfinishedEnrollmentReleasesUsername`, `TestPIIRejected` in `server/internal/api/api_test.go`

## Related Documentation

- [Device binding](device-binding.md)
- [Identity model](../concepts/identity-model.md)
- [No web sessions](../concepts/no-web-sessions.md)
- [TOTP authenticators](../integrations/totp-authenticators.md)
- [PROTOCOL.md](../../PROTOCOL.md)

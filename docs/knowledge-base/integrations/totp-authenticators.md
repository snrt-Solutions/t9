# TOTP authenticators

## Purpose

AeSMS.io has no built-in authenticator. Enrollment emits a standard `otpauth` key that any TOTP app can hold. Those codes are the web-side gate for account activation, device release, and optional revoke.

## Parameters

Generated with `pquerna/otp`:

- Issuer: `AeSMS`
- Account name: username
- Period: 30 seconds
- Digits: 6
- Algorithm: SHA1 (TOTP default)

The create API also returns a PNG QR as a `data:image/png;base64,…` URL so the web UI does not load a third-party QR library.

## Where codes are required

| Action | TOTP |
|--------|------|
| `POST /v1/accounts/totp/confirm` | yes |
| `POST /v1/device/release` | yes (no password) |
| `POST /v1/device/revoke` without Bearer | yes |
| Device login from the app | no (password + later release) |
| Send/fetch mail | no (device token) |

## UX risks

The threat model flags phishing of codes on the release page. There is no WebAuthn. Lost authenticator + lost backup is account loss (no email recovery).

Create UI copy mentions Aegis, 2FAS, and iOS Passwords as examples; any RFC 6238 app that scans `otpauth://` works.

## Related Documentation

- [Account creation](../functionalities/account-creation.md)
- [Device binding](../functionalities/device-binding.md)
- [Identity model](../concepts/identity-model.md)

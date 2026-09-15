# No web sessions

## Purpose

The website is a challenge surface, not a logged-in client. This concept is enforced in HTTP middleware, JSON contracts, and the browser fetch helper.

## Why

If the browser held a mailbox credential, XSS, shared computers, and “just open the inbox on the laptop” would bypass the signed-app + TOTP-release design. AeSMS.io makes that state impossible rather than “please do not log in.”

## Rules in code

- Every response goes through `cookieFilter`, which deletes `Set-Cookie` in `WriteHeader` and `Write`.
- Account create, TOTP confirm, abandon, and release JSON include `"session": null`.
- `web/js/aesms.js` uses `credentials: "omit"`.
- Mailbox handlers call `requireDevice`, which only accepts `Authorization: Bearer` tokens that hash to `device_sessions`.
- A pending id used as Bearer is not a session (`401`).
- Integration tests fail the suite if `Set-Cookie` appears on create/health/info/release.

## What the browser *can* do

Create accounts, enroll TOTP, approve/deny pending binds, call revoke with username+TOTP, view `/status.html`. Those actions are one-shot POSTs with secrets the user types.

## What it cannot do

Send or fetch ciphertext. Retain an account cookie. Receive a device token (that plaintext is only on the poll channel to the app).

## Related Documentation

- [Device binding](../functionalities/device-binding.md)
- [Account creation](../functionalities/account-creation.md)
- [Trust boundaries](trust-boundaries.md)
- [THREAT_MODEL.md](../../THREAT_MODEL.md)

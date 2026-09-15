# iOS MVP

SwiftUI client for T-9. **Full Xcode is required** (App Store → Xcode). This repo cannot be launched from Command Line Tools alone.

1. Install Xcode, open **`T9.xcodeproj`**, set Development Team, Run on **iPhone Simulator**.
2. Server URL: `http://127.0.0.1:8080` (Simulator shares the Mac network).
3. Create the account + TOTP in Safari on the Mac, then Approve on `/release.html`.

Until Xcode is installed, use the device stand-in:

```bash
./scripts/dev-local.sh
./t9dev login   # then Approve in the browser
./t9dev fetch
```

Product protocol, threat model, and feature docs live in the repo knowledge base:

- [T-9 README](../README.md)
- [Protocol](../docs/PROTOCOL.md)
- [Knowledge base](../docs/knowledge-base/index.md) — especially [device binding](../docs/knowledge-base/functionalities/device-binding.md), [messaging](../docs/knowledge-base/functionalities/messaging.md), [contacts](../docs/knowledge-base/functionalities/contact-exchange.md), and [backup](../docs/knowledge-base/functionalities/encrypted-backup.md)

## Screens

1. Unlock (Face ID / device passcode) whenever the mailbox opens
2. Server URL
3. Username / password → wait for web release
4. Inbox (fetch-once + live SSE while foregrounded)
5. Composer (160 grapheme meter)
6. Contacts — show my QR / paste-or-scan payload
7. Settings — encrypted backup/restore, lock, revoke

## Notes

- Keychain holds identity keys + device token
- E2E uses CryptoKit X25519 + AES-GCM (`t9-msg-v1`)
- Online push: SSE `/v1/events` while the app is open; optional APNs when server has `T9_APNS_*` and a device token is registered
- App lock uses LocalAuthentication (Face ID / Touch ID / passcode)
- Live camera QR scan is stubbed: paste `t9://contact?…` payloads (wire AVFoundation in a signed distribution build)
- App Attest not implemented — assertion is a placeholder string (`t9-ios-mvp-signed-placeholder`)
- Backup KDF is iterated SHA-256 (120k), not Argon2
- Bundle id `app.t9.messenger`; no Apple Developer secrets are bundled

Optional: regenerate the Xcode project with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.

# iOS MVP

SwiftUI client for T-9. Open **`T9.xcodeproj`** in Xcode 15+ (iOS 17), set your Development Team, then run on a device or simulator.

Product protocol, threat model, and feature docs live in the repo knowledge base:

- [T-9 README](../README.md)
- [Protocol](../docs/PROTOCOL.md)
- [Knowledge base](../docs/knowledge-base/index.md) — especially [device binding](../docs/knowledge-base/functionalities/device-binding.md), [messaging](../docs/knowledge-base/functionalities/messaging.md), [contacts](../docs/knowledge-base/functionalities/contact-exchange.md), and [backup](../docs/knowledge-base/functionalities/encrypted-backup.md)

## Screens

1. Server URL
2. Username / password → wait for web release
3. Inbox (fetch-once)
4. Composer (160 grapheme meter)
5. Contacts — show my QR / paste-or-scan payload
6. Settings — encrypted backup/restore, revoke

## Notes

- Keychain holds identity keys + device token
- E2E uses CryptoKit X25519 + AES-GCM (`t9-msg-v1`)
- Live camera QR scan is stubbed: paste `t9://contact?…` payloads (wire AVFoundation in a signed distribution build)
- App Attest not implemented — assertion is a placeholder string (`t9-ios-mvp-signed-placeholder`)
- Backup KDF is iterated SHA-256 (120k), not Argon2
- Bundle id `app.t9.messenger`; no Apple Developer secrets are bundled

Optional: regenerate the Xcode project with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.

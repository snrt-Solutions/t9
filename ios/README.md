# iOS MVP

SwiftUI client for T-9. Open **`T9.xcodeproj`** in Xcode 15+ (iOS 17), set your Development Team, then run.

## Screens

1. Server URL  
2. Username / password → wait for web release  
3. Inbox (fetch-once)  
4. Composer (160 grapheme meter)  
5. Contacts — show my QR / paste-or-scan payload  
6. Settings — encrypted backup/restore, revoke  

## Notes

- Keychain holds identity keys + device token  
- E2E uses CryptoKit X25519 + AES-GCM  
- Live camera QR scan is stubbed: paste `t9://contact?…` payloads (wire AVFoundation in a signed distribution build)  
- App Attest not implemented — assertion is a placeholder string  
- No Apple Developer secrets are bundled  

Optional: regenerate the Xcode project with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.

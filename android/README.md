# Android MVP

Kotlin + Jetpack Compose client for AeSMS.io. Sideload the debug APK for device testing.

## Requirements

- JDK 17+ (`JAVA_HOME`)
- Android SDK with `platforms;android-35` and `build-tools;35.0.0`
- Set `sdk.dir` in `local.properties` (not committed)

## Build a test APK

```bash
cd android
# local.properties must point at your SDK, e.g.:
# sdk.dir=/usr/local/share/android-commandlinetools
./gradlew assembleDebug
```

APK path:

```
app/build/outputs/apk/debug/app-debug.apk
```

Install on a device/emulator:

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Or copy the APK to the phone and open it (allow “install unknown apps”).

Debug package id: `io.aesms.app.debug`

## Screens

1. Unlock (biometrics / device credential) whenever the mailbox opens
2. Server URL (HTTPS required; HTTP only for localhost / `10.0.2.2`)
3. Username / password → wait for web release
4. Inbox (fetch-once + live SSE while foregrounded)
5. Composer (160 grapheme meter)
6. Contacts — pair QR + paste `aesms://pair?…` / legacy `aesms://contact?…`
7. Settings — encrypted backup/restore, lock, revoke

## Notes

- EncryptedSharedPreferences holds identity keys + device token
- E2E uses X25519 + AES-GCM (`aesms-msg-v2`, with `aesms-msg-v1` open for older mail)
- Online push: SSE `/v1/events` while the app is open (no FCM in MVP)
- App Attest / Play Integrity not implemented — assertion is `aesms-android-mvp-signed-placeholder`
- Backup KDF is iterated SHA-256 (120k), matching iOS
- Camera QR scan is paste-only in this MVP
- Emulator loopback to host Mac: `http://10.0.2.2:8080`

Product protocol and threat model: [docs/PROTOCOL.md](../docs/PROTOCOL.md), [docs/THREAT_MODEL.md](../docs/THREAT_MODEL.md).

# AeSMS.io knowledge base

AeSMS.io is a self-hosted **fetch-once** mailbox. The Go daemon (`aesmsd`) stores ciphertext and delivery metadata. The signed iOS app holds identity keys and the only credential that can send or fetch mail. The embedded website creates accounts, enrolls TOTP, and releases pending device logins — it never issues a mailbox session.

This knowledge base describes behavior that exists in the current repository. It is not a roadmap.

## Major functional areas

1. **Accounts** — opaque usernames, passwords, mandatory TOTP, unfinished enrollment cleanup
2. **Device bind** — pending login, web TOTP release, one-shot device token, one device per account
3. **Mailbox** — sealed send, fetch-and-delete, 24h expiry
4. **Contacts** — local QR payloads, no server address book
5. **Device-local backup and revoke** — passphrase archive, token revocation

## Functionalities

- [Account creation and TOTP enrollment](functionalities/account-creation.md)
- [Device binding and web release](functionalities/device-binding.md)
- [Fetch-once messaging](functionalities/messaging.md)
- [Contact exchange](functionalities/contact-exchange.md)
- [Encrypted local backup](functionalities/encrypted-backup.md)
- [Device revocation](functionalities/device-revocation.md)
- [Operator status UI](functionalities/operator-status.md)

## Concepts

- [Application architecture](concepts/application-architecture.md)
- [Identity model](concepts/identity-model.md)
- [Domain terminology](concepts/domain-terminology.md)
- [No web sessions](concepts/no-web-sessions.md)
- [Fetch-once and TTL](concepts/fetch-once-and-ttl.md)
- [Database encryption](concepts/database-encryption.md)
- [Trust boundaries](concepts/trust-boundaries.md)
- [Self-hosting](concepts/self-hosting.md)

## Integrations

- [Cloudflare Tunnel](integrations/cloudflare-tunnel.md)
- [TOTP authenticators](integrations/totp-authenticators.md)

## Canonical specs

Wire protocol and product rules: [../PROTOCOL.md](../PROTOCOL.md).  
Adversaries and residual risk: [../THREAT_MODEL.md](../THREAT_MODEL.md).  
GitHub-facing overview: [../../README.md](../../README.md).

## Scope and assumptions

- Source of truth is `server/` and `ios/`, plus `web/` as embedded by `aesmsd`.
- App Attest, Android, APNs, groups, media, and federation are **not** implemented; they are mentioned only as gaps.
- Contact pairing uses rotating `aesms://pair` codes (60s TTL, one-shot claim); AVFoundation scan + paste.
- Backup key derivation is iterated SHA-256, not Argon2, despite earlier protocol wording (corrected in PROTOCOL.md).
- Timings (15m pending, 15m enroll, 24h mail, 1m purge) are compiled defaults in `server/internal/config`, not environment variables.

# AeSMS.io documentation

This folder is the written contract for the mailbox: what the product does, how the wire protocol works, who is trusted, and how each feature behaves in the current tree.

Start here if you are:

- **Running a node** — [../README.md](../README.md) (quick start, env, Docker, tunnel)
- **Implementing a client** — [PROTOCOL.md](PROTOCOL.md)
- **Reviewing security** — [THREAT_MODEL.md](THREAT_MODEL.md)
- **Changing server or iOS behavior** — [knowledge-base/index.md](knowledge-base/index.md)

## Protocol and threat model

| File | What it covers |
|------|----------------|
| [PROTOCOL.md](PROTOCOL.md) | Identity rules, HTTP flows, contact QR, client E2E, at-rest DB seal, capability matrix |
| [THREAT_MODEL.md](THREAT_MODEL.md) | Assets, adversaries, trust boundaries, MVP non-goals, residual risk |

Those two documents are the canonical *product* spec. If a knowledge-base page and PROTOCOL disagree, treat PROTOCOL as the intended wire contract and file a fix — except where the knowledge base cites a newer implementation detail (for example the MVP backup KDF).

## Knowledge base

[knowledge-base/index.md](knowledge-base/index.md) is a maintainer-oriented map: one page per major functionality, plus shared concepts and integrations.

It is generated from this repository as it exists today (Go `aesmsd` + SwiftUI iOS MVP). It does not invent Android, App Attest enforcement, APNs, or federation.

## Client notes

iOS build and screen list live next to the Xcode project: [../ios/README.md](../ios/README.md).

## Scope

Documentation describes **this MVP**, including known gaps (placeholder assertions, paste-only QR, iterated-SHA256 backup KDF, whole-file DB seal). Historical plans that are not in the tree are labeled as such or omitted.

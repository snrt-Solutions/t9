import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "aesms.serverURL") }
    }
    @Published var phase: Phase = .server
    @Published var username: String = ""
    @Published var deviceToken: String?
    @Published var pendingID: String?
    @Published var statusLine: String = ""
    @Published var contacts: [Contact] = []
    @Published var inbox: [LocalMessage] = []
    @Published var fingerprint: String = ""
    @Published var unlocked: Bool = false
    @Published var pushOnline: Bool = false

    let keys = KeyStore()
    let store = LocalStore()
    let api = APIClient()
    let events = EventStream()

    enum Phase: Equatable {
        case server
        case credentials
        case waitingRelease
        case mailbox
    }

    init() {
        serverURL = UserDefaults.standard.string(forKey: "aesms.serverURL") ?? "http://127.0.0.1:8080"
        contacts = store.loadContacts()
        inbox = store.loadKeptMessages()
        if let tok = Keychain.get("device_token"), !tok.isEmpty {
            deviceToken = tok
            phase = .mailbox
            username = UserDefaults.standard.string(forKey: "aesms.username") ?? ""
        }
        _ = keys.loadOrCreateIdentity()
        PushService.shared.onToken = { [weak self] hex in
            Task { @MainActor in
                await self?.registerPushToken(hex)
            }
        }
    }

    func saveUsername(_ u: String) {
        username = u
        UserDefaults.standard.set(u, forKey: "aesms.username")
    }

    func lockMailbox() {
        unlocked = false
    }

    func startPushIfNeeded() {
        guard phase == .mailbox, let tok = deviceToken else { return }
        PushService.shared.configure()
        events.start(base: serverURL, token: tok) { [weak self] in
            Task { @MainActor in
                self?.statusLine = "new message"
                await self?.fetchInboxQuiet()
            }
        }
        pushOnline = true
    }

    func stopPush() {
        Task { await events.stop() }
        pushOnline = false
    }

    func registerPushToken(_ hex: String) async {
        guard let tok = deviceToken else { return }
        do {
            try await api.registerPushToken(base: serverURL, token: tok, pushToken: hex)
        } catch {
            statusLine = "push token: \(error.localizedDescription)"
        }
    }

    func fetchInboxQuiet() async {
        guard let tok = deviceToken else { return }
        do {
            let res = try await api.fetchMessages(base: serverURL, token: tok)
            let iso = ISO8601DateFormatter()
            for wire in res.messages {
                guard let data = Data(base64Encoded: wire.ciphertext) else { continue }
                let plain = (try? keys.open(ciphertext: data)) ?? "«undecryptable»"
                let when = wire.created_at.flatMap { iso.date(from: $0) } ?? Date()
                let local = LocalMessage(
                    id: wire.id,
                    fromUsername: wire.from_username,
                    plaintext: plain,
                    createdAt: when,
                    keptLocally: true
                )
                if !inbox.contains(where: { $0.id == local.id }) {
                    inbox.insert(local, at: 0)
                }
            }
            store.saveKeptMessages(inbox)
        } catch {
            statusLine = error.localizedDescription
        }
    }

    /// Local-only: server ciphertext is already gone after fetch.
    func deleteMessage(id: String) {
        inbox.removeAll { $0.id == id }
        store.saveKeptMessages(inbox)
    }

    /// Keep a copy of an outbound message in the peer's chat thread.
    func recordOutbound(id: String, toUsername: String, plaintext: String) {
        let local = LocalMessage(
            id: id,
            fromUsername: toUsername,
            plaintext: plaintext,
            createdAt: Date(),
            keptLocally: true,
            outbound: true
        )
        if !inbox.contains(where: { $0.id == local.id }) {
            inbox.insert(local, at: 0)
            store.saveKeptMessages(inbox)
        }
    }

    /// Local-only: remove every kept message in the chat with this peer.
    func deleteChat(fromUsername: String) {
        let key = fromUsername.lowercased()
        inbox.removeAll { $0.fromUsername.lowercased() == key }
        store.saveKeptMessages(inbox)
    }

    func chatSummaries() -> [ChatSummary] {
        let groups = Dictionary(grouping: inbox) { $0.fromUsername.lowercased() }
        return groups.values.compactMap { msgs -> ChatSummary? in
            guard let latest = msgs.max(by: { $0.createdAt < $1.createdAt }) else { return nil }
            return ChatSummary(
                username: latest.fromUsername,
                latest: latest,
                count: msgs.count
            )
        }
        .sorted { $0.latest.createdAt > $1.latest.createdAt }
    }

    func messages(fromUsername: String) -> [LocalMessage] {
        let key = fromUsername.lowercased()
        return inbox
            .filter { $0.fromUsername.lowercased() == key }
            .sorted { $0.createdAt < $1.createdAt }
    }
}

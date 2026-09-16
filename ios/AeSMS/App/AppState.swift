import Foundation
import SwiftUI
import Combine
import UIKit
import UserNotifications

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
    /// Message IDs fetched but not yet opened in a chat thread.
    @Published private(set) var unreadIDs: Set<String> = []

    let keys = KeyStore()
    let store = LocalStore()
    let api = APIClient()
    let events = EventStream()

    private static let unreadKey = "aesms.unreadIDs"

    enum Phase: Equatable {
        case server
        case credentials
        case waitingRelease
        case mailbox
    }

    var unreadTotal: Int { unreadIDs.count }

    init() {
        serverURL = UserDefaults.standard.string(forKey: "aesms.serverURL") ?? "http://127.0.0.1:8080"
        contacts = store.loadContacts()
        inbox = store.loadKeptMessages()
        unreadIDs = Set(UserDefaults.standard.stringArray(forKey: Self.unreadKey) ?? [])
        let kept = Set(inbox.map(\.id))
        unreadIDs = unreadIDs.intersection(kept)
        persistUnread()
        syncAppBadge()

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
        PushService.shared.onRemoteWake = { [weak self] in
            guard let self else { return 0 }
            return await self.fetchInboxQuiet()
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
        let base = serverURL
        Task {
            await events.start(base: base, token: tok) { [weak self] in
                Task { @MainActor in
                    self?.statusLine = "new message"
                    _ = await self?.fetchInboxQuiet()
                }
            }
            await MainActor.run { self.pushOnline = true }
        }
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

    /// Fetch mailbox. Marks newly kept inbound messages unread and updates badges.
    /// Returns count of newly unread messages.
    @discardableResult
    func fetchInboxQuiet() async -> Int {
        guard let tok = deviceToken else { return 0 }
        var newlyUnread = 0
        do {
            let res = try await api.fetchMessages(base: serverURL, token: tok)
            let iso = ISO8601DateFormatter()
            for wire in res.messages {
                guard let data = Data(base64URLOrStdEncoded: wire.ciphertext) else { continue }
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
                    if !local.outbound {
                        unreadIDs.insert(local.id)
                        newlyUnread += 1
                    }
                }
            }
            store.saveKeptMessages(inbox)
            if newlyUnread > 0 {
                persistUnread()
                statusLine = newlyUnread == 1 ? "1 new message" : "\(newlyUnread) new messages"
            }
            syncAppBadge()
        } catch {
            statusLine = error.localizedDescription
        }
        return newlyUnread
    }

    func unreadCount(forUsername username: String) -> Int {
        let key = username.lowercased()
        return inbox.reduce(0) { acc, msg in
            guard !msg.outbound,
                  msg.fromUsername.lowercased() == key,
                  unreadIDs.contains(msg.id) else { return acc }
            return acc + 1
        }
    }

    func markChatRead(username: String) {
        let key = username.lowercased()
        let ids = inbox
            .filter { !$0.outbound && $0.fromUsername.lowercased() == key }
            .map(\.id)
        guard !ids.isEmpty else { return }
        var changed = false
        for id in ids where unreadIDs.contains(id) {
            unreadIDs.remove(id)
            changed = true
        }
        if changed {
            persistUnread()
            syncAppBadge()
        }
    }

    func syncAppBadge() {
        let n = unreadTotal
        UNUserNotificationCenter.current().setBadgeCount(n) { _ in }
        UIApplication.shared.applicationIconBadgeNumber = n
    }

    private func persistUnread() {
        UserDefaults.standard.set(Array(unreadIDs), forKey: Self.unreadKey)
    }

    /// Local-only: server ciphertext is already gone after fetch.
    func deleteMessage(id: String) {
        inbox.removeAll { $0.id == id }
        if unreadIDs.remove(id) != nil {
            persistUnread()
            syncAppBadge()
        }
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
        let removed = inbox.filter { $0.fromUsername.lowercased() == key }.map(\.id)
        inbox.removeAll { $0.fromUsername.lowercased() == key }
        var changed = false
        for id in removed where unreadIDs.contains(id) {
            unreadIDs.remove(id)
            changed = true
        }
        if changed {
            persistUnread()
            syncAppBadge()
        }
        store.saveKeptMessages(inbox)
    }

    func chatSummaries() -> [ChatSummary] {
        let groups = Dictionary(grouping: inbox) { $0.fromUsername.lowercased() }
        return groups.values.compactMap { msgs -> ChatSummary? in
            guard let latest = msgs.max(by: { $0.createdAt < $1.createdAt }) else { return nil }
            let unread = msgs.reduce(0) { acc, m in
                (!m.outbound && unreadIDs.contains(m.id)) ? acc + 1 : acc
            }
            return ChatSummary(
                username: latest.fromUsername,
                latest: latest,
                count: msgs.count,
                unreadCount: unread
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

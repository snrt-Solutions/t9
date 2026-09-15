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
            for wire in res.messages {
                guard let data = Data(base64Encoded: wire.ciphertext) else { continue }
                let plain = (try? keys.open(ciphertext: data)) ?? "«undecryptable»"
                let local = LocalMessage(
                    id: wire.id,
                    fromUsername: wire.from_username,
                    plaintext: plain,
                    createdAt: Date(),
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
}

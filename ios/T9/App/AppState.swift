import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "t9.serverURL") }
    }
    @Published var phase: Phase = .server
    @Published var username: String = ""
    @Published var deviceToken: String?
    @Published var pendingID: String?
    @Published var statusLine: String = ""
    @Published var contacts: [Contact] = []
    @Published var inbox: [LocalMessage] = []
    @Published var fingerprint: String = ""

    let keys = KeyStore()
    let store = LocalStore()
    let api = APIClient()

    enum Phase: Equatable {
        case server
        case credentials
        case waitingRelease
        case mailbox
    }

    init() {
        serverURL = UserDefaults.standard.string(forKey: "t9.serverURL") ?? "http://127.0.0.1:8080"
        contacts = store.loadContacts()
        if let tok = Keychain.get("device_token"), !tok.isEmpty {
            deviceToken = tok
            phase = .mailbox
            username = UserDefaults.standard.string(forKey: "t9.username") ?? ""
        }
        _ = keys.loadOrCreateIdentity()
    }

    func saveUsername(_ u: String) {
        username = u
        UserDefaults.standard.set(u, forKey: "t9.username")
    }
}

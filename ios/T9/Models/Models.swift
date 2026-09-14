import Foundation

struct Contact: Codable, Identifiable, Hashable {
    var id: String { username + "|" + pubkey }
    var username: String
    var pubkey: String
    var serverFingerprint: String
    var addedAt: Date
}

struct LocalMessage: Codable, Identifiable, Hashable {
    var id: String
    var fromUsername: String
    var plaintext: String
    var createdAt: Date
    var keptLocally: Bool
}

struct ServerInfo: Codable {
    var name: String?
    var base_url: String?
    var fingerprint: String?
    var max_graphemes: Int?
    var web_login: Bool?
    var fetch_once: Bool?
}

struct CreateAccountResponse: Codable {
    var totp_secret: String?
    var totp_uri: String?
}

struct PendingLoginResponse: Codable {
    var pending_id: String
    var status: String
    var release_url: String?
    var expires_at: String?
}

struct PollResponse: Codable {
    var pending_id: String?
    var status: String
    var device_token: String?
    var token_type: String?
}

struct MessagesResponse: Codable {
    var messages: [WireMessage]
}

struct WireMessage: Codable {
    var id: String
    var from_username: String
    var ciphertext: String
    var created_at: String?
}

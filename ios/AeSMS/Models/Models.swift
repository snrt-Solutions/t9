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
    /// Other party in the chat (inbound sender or outbound recipient).
    var fromUsername: String
    var plaintext: String
    var createdAt: Date
    var keptLocally: Bool
    /// True when this device sent the message (local-only history).
    var outbound: Bool

    init(
        id: String,
        fromUsername: String,
        plaintext: String,
        createdAt: Date,
        keptLocally: Bool,
        outbound: Bool = false
    ) {
        self.id = id
        self.fromUsername = fromUsername
        self.plaintext = plaintext
        self.createdAt = createdAt
        self.keptLocally = keptLocally
        self.outbound = outbound
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        fromUsername = try c.decode(String.self, forKey: .fromUsername)
        plaintext = try c.decode(String.self, forKey: .plaintext)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        keptLocally = try c.decode(Bool.self, forKey: .keptLocally)
        outbound = try c.decodeIfPresent(Bool.self, forKey: .outbound) ?? false
    }
}

struct ChatSummary: Identifiable, Hashable {
    var id: String { username.lowercased() }
    var username: String
    var latest: LocalMessage
    var count: Int
}

struct ServerInfo: Codable {
    var name: String?
    var base_url: String?
    var fingerprint: String?
    var max_graphemes: Int?
    var web_login: Bool?
    var fetch_once: Bool?
    var setup_needed: Bool?
    var push: Bool?
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

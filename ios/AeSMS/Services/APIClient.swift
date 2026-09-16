import Foundation

actor APIClient {
    struct APIError: Error, LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    func getInfo(base: String) async throws -> ServerInfo {
        try await get(base: base, path: "/v1/info")
    }

    func deviceLogin(base: String, username: String, password: String, deviceID: String) async throws -> PendingLoginResponse {
        try await post(base: base, path: "/v1/device/login", body: [
            "username": username,
            "password": password,
            "device_id": deviceID,
            "assertion": "aesms-ios-mvp-signed-placeholder",
        ])
    }

    func pollPending(base: String, id: String) async throws -> PollResponse {
        try await get(base: base, path: "/v1/device/login/\(id)")
    }

    func postMessage(base: String, token: String, to: String, ciphertextB64: String, graphemes: Int, pubkey: String) async throws -> String {
        struct PostResp: Decodable { var id: String? }
        let resp: PostResp = try await post(
            base: base,
            path: "/v1/messages",
            body: [
                "to_username": to,
                "ciphertext": ciphertextB64,
                "graphemes": graphemes,
                "pubkey": pubkey,
            ],
            token: token
        )
        return resp.id ?? UUID().uuidString
    }

    func fetchMessages(base: String, token: String) async throws -> MessagesResponse {
        try await get(base: base, path: "/v1/messages", token: token)
    }

    func revoke(base: String, token: String) async throws {
        var req = URLRequest(url: url(base, "/v1/device/revoke"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(message: "revoke failed")
        }
    }

    func registerPushToken(base: String, token: String, pushToken: String) async throws {
        struct Ok: Decodable { var ok: Bool? }
        let _: Ok = try await post(
            base: base,
            path: "/v1/device/push-token",
            body: ["push_token": pushToken],
            token: token
        )
    }

    func createPairOffer(base: String, token: String, pubkey: String) async throws -> PairOfferResponse {
        try await post(
            base: base,
            path: "/v1/pair/offer",
            body: ["pubkey": pubkey],
            token: token
        )
    }

    func pollPairOffer(base: String, token: String) async throws -> PairPollResponse {
        try await get(base: base, path: "/v1/pair/offer", token: token)
    }

    func claimPairOffer(base: String, token: String, code: String, pubkey: String) async throws -> PairClaimResponse {
        try await post(
            base: base,
            path: "/v1/pair/claim",
            body: ["code": code, "pubkey": pubkey],
            token: token
        )
    }

    private func url(_ base: String, _ path: String) -> URL {
        let trimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: trimmed + path)!
    }

    private func get<T: Decodable>(base: String, path: String, token: String? = nil) async throws -> T {
        var req = URLRequest(url: url(base, path))
        req.httpMethod = "GET"
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return try await decode(req)
    }

    private func post<T: Decodable>(base: String, path: String, body: [String: Any], token: String? = nil) async throws -> T {
        var req = URLRequest(url: url(base, path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await decode(req)
    }

    private func decode<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError(message: "no response") }
        if !(200..<300).contains(http.statusCode) {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? String {
                throw APIError(message: err)
            }
            throw APIError(message: "HTTP \(http.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

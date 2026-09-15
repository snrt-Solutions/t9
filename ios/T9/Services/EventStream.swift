import Foundation

/// Online push: long-lived SSE to /v1/events. Triggers inbox refresh when a message lands.
actor EventStream {
    private var task: Task<Void, Never>?

    func start(base: String, token: String, onMessage: @escaping @Sendable () -> Void) {
        stop()
        task = Task {
            while !Task.isCancelled {
                do {
                    try await listen(base: base, token: token, onMessage: onMessage)
                } catch {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func listen(base: String, token: String, onMessage: @escaping @Sendable () -> Void) async throws {
        let trimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + "/v1/events") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 3600

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        for try await line in bytes.lines {
            if Task.isCancelled { return }
            if line.hasPrefix("event: message") || line.contains("\"event\":\"message\"") {
                onMessage()
            }
        }
    }
}

import SwiftUI

struct WaitingReleaseView: View {
    @EnvironmentObject var app: AppState
    @State private var dots = 0
    @State private var timer: Timer?

    var body: some View {
        ScreenChrome(
            title: "Approve on the site",
            subtitle: "Open the release page, enter username + live TOTP, and approve this pending ID."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                FieldLabel(text: "Pending ID")
                Text(app.pendingID ?? "-")
                    .font(T9Theme.font(13, .medium))
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(T9Theme.surface)
                    .overlay(Rectangle().stroke(T9Theme.hair, lineWidth: T9Theme.stroke))

                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Rectangle()
                            .fill(i == dots % 3 ? T9Theme.teal : T9Theme.ink.opacity(0.2))
                            .frame(width: 10, height: 10)
                            .animation(T9Theme.ease, value: dots)
                    }
                    Text("polling")
                        .font(T9Theme.font(12))
                        .foregroundStyle(T9Theme.muted)
                }

                if let id = app.pendingID {
                    Text("\(app.serverURL)/release.html?pending_id=\(id)")
                        .font(T9Theme.font(11))
                        .foregroundStyle(T9Theme.accent)
                        .textSelection(.enabled)
                }

                Text(app.statusLine)
                    .font(T9Theme.font(12))
                    .foregroundStyle(T9Theme.muted)

                GhostButton(title: "Cancel") {
                    stop()
                    app.phase = .credentials
                }
            }
        }
        .onAppear { start() }
        .onDisappear { stop() }
    }

    private func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                dots += 1
                await poll()
            }
        }
        Task { await poll() }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() async {
        guard let id = app.pendingID else { return }
        do {
            let res = try await app.api.pollPending(base: app.serverURL, id: id)
            app.statusLine = "status \(res.status)"
            if res.status == "approved", let tok = res.device_token, !tok.isEmpty {
                Keychain.set("device_token", value: tok)
                app.deviceToken = tok
                stop()
                app.unlocked = false
                app.phase = .mailbox
            } else if res.status == "denied" {
                app.statusLine = "denied on web"
                stop()
            }
        } catch {
            app.statusLine = error.localizedDescription
        }
    }
}

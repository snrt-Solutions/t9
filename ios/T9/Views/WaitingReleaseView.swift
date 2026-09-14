import SwiftUI

struct WaitingReleaseView: View {
    @EnvironmentObject var app: AppState
    @State private var dots = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Eyebrow(text: "Awaiting web release")
            Text("Approve on the site")
                .font(T9Theme.font(32, .bold))
            Text("Open the release page, enter your username + live TOTP, and approve this pending ID.")
                .foregroundStyle(T9Theme.muted)

            T9Theme.bezel {
                VStack(alignment: .leading, spacing: 14) {
                    Text("PENDING ID")
                        .font(T9Theme.font(11, .semibold))
                        .tracking(1.4)
                        .foregroundStyle(T9Theme.muted)
                    Text(app.pendingID ?? "—")
                        .font(T9Theme.font(13, .medium))
                        .textSelection(.enabled)

                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { i in
                            Rectangle()
                                .fill(i == dots % 3 ? T9Theme.teal : T9Theme.accent.opacity(0.35))
                                .frame(width: 8, height: 8)
                                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
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

                    Button("Cancel") {
                        stop()
                        app.phase = .credentials
                    }
                    .foregroundStyle(T9Theme.muted)
                }
            }
            Spacer()
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

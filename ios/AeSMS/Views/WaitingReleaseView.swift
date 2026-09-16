import SwiftUI
import UIKit

struct WaitingReleaseView: View {
    @EnvironmentObject var app: AppState
    @State private var dots = 0
    @State private var timer: Timer?
    @State private var copiedHint = false

    var body: some View {
        ScrollView {
            ScreenChrome(
                title: "Approve on the site",
                subtitle: "Open the release page, enter username + live TOTP, and approve this pending ID."
            ) {
                VStack(alignment: .leading, spacing: T9Theme.space2) {
                    VStack(alignment: .leading, spacing: 8) {
                        FieldLabel(text: "Pending ID")
                        Button {
                            copyPendingID()
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(app.pendingID ?? "-")
                                    .font(T9Theme.font(13, .medium))
                                    .foregroundStyle(T9Theme.ink)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(copiedHint ? "Copied" : "Copy")
                                    .font(T9Theme.font(12, .semibold))
                                    .foregroundStyle(copiedHint ? T9Theme.teal : T9Theme.accent)
                            }
                            .padding(14)
                            .frame(minHeight: 48)
                            .background(T9Theme.surface)
                            .overlay(Rectangle().stroke(T9Theme.hair.opacity(0.55), lineWidth: T9Theme.stroke))
                        }
                        .buttonStyle(.plain)
                        .disabled(app.pendingID == nil)
                        .accessibilityHint("Copies the pending ID to the clipboard")
                    }

                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(i == dots % 3 ? T9Theme.teal : T9Theme.ink.opacity(0.18))
                                .frame(width: 8, height: 8)
                                .animation(T9Theme.ease, value: dots)
                        }
                        Text("Polling for approval")
                            .font(T9Theme.font(13))
                            .foregroundStyle(T9Theme.muted)
                    }
                    .padding(.top, 4)

                    if let id = app.pendingID {
                        Text("\(app.serverURL)/release.html?pending_id=\(id)")
                            .font(T9Theme.font(12))
                            .foregroundStyle(T9Theme.accent)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !app.statusLine.isEmpty {
                        Text(app.statusLine)
                            .font(T9Theme.font(13))
                            .foregroundStyle(T9Theme.muted)
                    }

                    GhostButton(title: "Cancel") {
                        stop()
                        app.phase = .credentials
                    }
                }
            }
            .padding(.top, T9Theme.space2)
            .padding(.bottom, T9Theme.space3)
        }
        .onAppear { start() }
        .onDisappear { stop() }
    }

    private func copyPendingID() {
        guard let id = app.pendingID, !id.isEmpty else { return }
        UIPasteboard.general.string = id
        copiedHint = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedHint = false
        }
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

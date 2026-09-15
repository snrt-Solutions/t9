import SwiftUI

struct LockGateView: View {
    @EnvironmentObject var app: AppState
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        ZStack {
            T9Theme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                Text("T-9")
                    .font(T9Theme.font(36, .bold))
                Text("Locked")
                    .font(T9Theme.font(22, .semibold))
                Text("Unlock with \(AppLock.biometryLabel) or your device passcode to open the mailbox.")
                    .font(T9Theme.font(15))
                    .foregroundStyle(T9Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(title: busy ? "…" : "Unlock", tint: T9Theme.accent, busy: busy) {
                    Task { await unlock() }
                }

                if failed {
                    Text("Authentication failed")
                        .font(T9Theme.font(13))
                        .foregroundStyle(T9Theme.warn)
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: 420, alignment: .leading)
        }
        .task { await unlock() }
    }

    private func unlock() async {
        busy = true
        defer { busy = false }
        let ok = await AppLock.authenticate()
        failed = !ok
        if ok {
            app.unlocked = true
        }
    }
}

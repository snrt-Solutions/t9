import SwiftUI

struct LockGateView: View {
    @EnvironmentObject var app: AppState
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        ZStack {
            T9Theme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: T9Theme.space3) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AeSMS")
                        .font(T9Theme.font(32, .bold))
                        .foregroundStyle(T9Theme.ink)
                    Text("Locked")
                        .font(T9Theme.font(20, .semibold))
                        .foregroundStyle(T9Theme.ink)
                    Text("Unlock with \(AppLock.biometryLabel) or your device passcode to open the mailbox.")
                        .font(T9Theme.font(15))
                        .foregroundStyle(T9Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }

                PrimaryButton(title: busy ? "Unlocking…" : "Unlock", tint: T9Theme.accent, busy: busy) {
                    Task { await unlock() }
                }

                if failed {
                    Text("Authentication failed")
                        .font(T9Theme.font(13))
                        .foregroundStyle(T9Theme.warn)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, T9Theme.pageInset)
            .padding(.top, T9Theme.space4)
            .frame(maxWidth: 440, alignment: .leading)
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

import SwiftUI

enum T9Theme {
    static let bg = Color(red: 0.91, green: 0.914, blue: 0.929)
    static let bg2 = Color(red: 0.957, green: 0.961, blue: 0.973)
    static let ink = Color(red: 0.071, green: 0.078, blue: 0.102)
    static let muted = Color(red: 0.361, green: 0.388, blue: 0.439)
    static let accent = Color(red: 0.102, green: 0.361, blue: 1.0)
    static let teal = Color(red: 0.0, green: 0.639, blue: 0.553)
    static let warn = Color(red: 0.769, green: 0.361, blue: 0.102)
    static let ease = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.55)

    static func bezel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.98))
                    .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            )
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.black.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
            )
    }
}

struct T9Background: View {
    var body: some View {
        LinearGradient(
            colors: [T9Theme.bg2, T9Theme.bg],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(
            RadialGradient(
                colors: [T9Theme.accent.opacity(0.12), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
        )
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(2)
            .foregroundStyle(T9Theme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.65)))
            .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
    }
}

struct IslandButton: View {
    let title: String
    var tint: Color = T9Theme.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                ZStack {
                    Circle().fill(Color.white.opacity(0.16))
                    Text("↗").font(.system(size: 13, weight: .bold))
                }
                .frame(width: 30, height: 30)
            }
            .foregroundStyle(.white)
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .padding(.vertical, 10)
            .background(Capsule().fill(tint))
        }
        .buttonStyle(.plain)
        .scaleEffect(1)
    }
}

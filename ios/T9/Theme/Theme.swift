import SwiftUI

enum T9Theme {
    static let bg = Color(red: 0.925, green: 0.925, blue: 0.925)
    static let ink = Color(red: 0.067, green: 0.067, blue: 0.067)
    static let muted = Color(red: 0.29, green: 0.29, blue: 0.29)
    static let accent = Color(red: 0.102, green: 0.361, blue: 1.0)
    static let teal = Color(red: 0.0, green: 0.522, blue: 0.435)
    static let warn = Color(red: 0.769, green: 0.361, blue: 0.102)
    static let ease = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.45)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Cascadia Code", size: size).weight(weight)
    }

    static func bezel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
    }
}

struct T9Background: View {
    var body: some View {
        T9Theme.bg.ignoresSafeArea()
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(T9Theme.font(10, .semibold))
            .tracking(1.6)
            .foregroundStyle(T9Theme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
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
                    .font(T9Theme.font(15, .semibold))
                Text("↗")
                    .font(T9Theme.font(13, .bold))
                    .frame(width: 26, height: 26)
                    .overlay(Rectangle().stroke(Color.white.opacity(0.5), lineWidth: 1))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(tint)
            .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

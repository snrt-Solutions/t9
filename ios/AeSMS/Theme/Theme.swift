import SwiftUI

/// Cascadia boxy system: sharp corners, hairline structure, no nested fake frames.
enum T9Theme {
    static let bg = Color(red: 0.925, green: 0.925, blue: 0.925)
    static let surface = Color.white
    static let ink = Color(red: 0.067, green: 0.067, blue: 0.067)
    static let muted = Color(red: 0.29, green: 0.29, blue: 0.29)
    static let accent = Color(red: 0.102, green: 0.361, blue: 1.0)
    static let teal = Color(red: 0.0, green: 0.522, blue: 0.435)
    static let warn = Color(red: 0.769, green: 0.361, blue: 0.102)
    static let hair = Color.black
    static let ease = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.45)
    static let stroke: CGFloat = 2

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Cascadia Code", size: size).weight(weight)
    }
}

struct T9Background: View {
    var body: some View {
        T9Theme.bg.ignoresSafeArea()
    }
}

struct ScreenChrome<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(T9Theme.font(28, .bold))
                    .foregroundStyle(T9Theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(T9Theme.font(14))
                        .foregroundStyle(T9Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(T9Theme.hair).frame(height: T9Theme.stroke)
            }

            content()
                .padding(.top, 18)
        }
    }
}

struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(T9Theme.font(11, .semibold))
            .tracking(1.4)
            .foregroundStyle(T9Theme.muted)
    }
}

struct T9FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(T9Theme.font(15, .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(T9Theme.surface)
            .overlay(Rectangle().stroke(T9Theme.hair, lineWidth: T9Theme.stroke))
    }
}

extension View {
    func t9Field() -> some View {
        modifier(T9FieldStyle())
    }
}

/// Single surface panel. One outer stroke only (no nested bezel).
struct SurfacePanel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T9Theme.surface)
            .overlay(Rectangle().stroke(T9Theme.hair, lineWidth: T9Theme.stroke))
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(T9Theme.hair.opacity(0.2))
            .frame(height: 1)
    }
}

struct PrimaryButton: View {
    let title: String
    var tint: Color = T9Theme.ink
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(T9Theme.font(15, .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if busy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.85)
                        .frame(width: 28, height: 28)
                } else {
                    Text("↗")
                        .font(T9Theme.font(13, .bold))
                        .frame(width: 28, height: 28)
                        .overlay(Rectangle().stroke(Color.white.opacity(0.45), lineWidth: 1))
                }
            }
            .foregroundStyle(.white)
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
            .background(tint)
            .overlay(Rectangle().stroke(T9Theme.hair, lineWidth: T9Theme.stroke))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.85 : 1)
        .scaleEffect(busy ? 0.99 : 1)
        .animation(T9Theme.ease, value: busy)
    }
}

struct GhostButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(T9Theme.font(14, .medium))
                .foregroundStyle(T9Theme.muted)
        }
        .buttonStyle(.plain)
    }
}

// Compatibility aliases used while views migrate
typealias IslandButton = PrimaryButtonCompat

struct PrimaryButtonCompat: View {
    let title: String
    var tint: Color = T9Theme.ink
    let action: () -> Void

    var body: some View {
        PrimaryButton(title: title, tint: tint, action: action)
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
            .overlay(Rectangle().stroke(T9Theme.hair, lineWidth: T9Theme.stroke))
    }
}

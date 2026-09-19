import SwiftUI
import UIKit

/// AeSMS.io CI — IBM Plex Mono, sharp corners, purposeful structure.
/// Primary #0B0B0B · Accent #0066FF · Background #F4F4F4 · Secondary #9AA0A6
enum T9Theme {
    static let bg = Color(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF4 / 255)
    static let surface = Color.white
    static let ink = Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0B / 255)
    static let muted = Color(red: 0x9A / 255, green: 0xA0 / 255, blue: 0xA6 / 255)
    static let accent = Color(red: 0x00 / 255, green: 0x66 / 255, blue: 1.0)
    /// Success / live — same as accent in the CI (no teal token).
    static let teal = accent
    static let warn = Color(red: 0.769, green: 0.361, blue: 0.102)
    static let hair = ink
    static let ease = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.45)

    static let stroke: CGFloat = 1
    static let rule: CGFloat = 1.5

    static let space1: CGFloat = 8
    static let space2: CGFloat = 16
    static let space3: CGFloat = 24
    static let space4: CGFloat = 32
    static let pageInset: CGFloat = 20

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black:
            name = "IBMPlexMono-SemiBold"
        case .medium:
            name = "IBMPlexMono-Medium"
        default:
            name = "IBMPlexMono-Regular"
        }
        return .custom(name, size: size)
    }
}

struct T9Background: View {
    var body: some View {
        T9Theme.bg.ignoresSafeArea()
    }
}

/// Page title + optional subtitle. Soft bottom rule separates chrome from content.
struct ScreenChrome<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(T9Theme.font(26, .bold))
                    .foregroundStyle(T9Theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(T9Theme.font(14))
                        .foregroundStyle(T9Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, T9Theme.space2)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(T9Theme.hair.opacity(0.35))
                    .frame(height: T9Theme.rule)
            }

            content()
                .padding(.top, T9Theme.space3)
        }
        .padding(.horizontal, T9Theme.pageInset)
    }
}

struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(T9Theme.font(11, .semibold))
            .tracking(1.2)
            .foregroundStyle(T9Theme.muted)
    }
}

struct T9FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(T9Theme.font(15, .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(minHeight: 48)
            .background(T9Theme.surface)
            .overlay(Rectangle().stroke(T9Theme.hair.opacity(0.55), lineWidth: T9Theme.stroke))
    }
}

extension View {
    func t9Field() -> some View {
        modifier(T9FieldStyle())
    }

    /// Drag-to-dismiss plus a keyboard accessory Done control.
    /// Wraps in a NavigationStack so the keyboard toolbar has a host.
    func t9KeyboardDismiss() -> some View {
        NavigationStack {
            self
                .scrollDismissesKeyboard(.interactively)
                .toolbar(.hidden, for: .navigationBar)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            Keyboard.dismiss()
                        }
                        .font(T9Theme.font(15, .semibold))
                        .foregroundStyle(T9Theme.accent)
                    }
                }
        }
    }
}

enum Keyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

struct SurfacePanel<Content: View>: View {
    var padding: CGFloat = T9Theme.space2
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T9Theme.surface)
            .overlay(Rectangle().stroke(T9Theme.hair.opacity(0.45), lineWidth: T9Theme.stroke))
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(T9Theme.hair.opacity(0.12))
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
            HStack(spacing: 10) {
                Text(title)
                    .font(T9Theme.font(15, .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if busy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, T9Theme.space2)
            .frame(minHeight: 48)
            .background(tint)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.85 : 1)
        .animation(T9Theme.ease, value: busy)
    }
}

struct SecondaryButton: View {
    let title: String
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(T9Theme.font(15, .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if busy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(T9Theme.ink)
                        .scaleEffect(0.85)
                }
            }
            .foregroundStyle(T9Theme.ink)
            .padding(.horizontal, T9Theme.space2)
            .frame(minHeight: 48)
            .background(T9Theme.surface)
            .overlay(Rectangle().stroke(T9Theme.hair.opacity(0.55), lineWidth: T9Theme.stroke))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.85 : 1)
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
                .frame(minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

struct EmptyStateBlock: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(T9Theme.font(16, .semibold))
                .foregroundStyle(T9Theme.ink)
            if let detail {
                Text(detail)
                    .font(T9Theme.font(14))
                    .foregroundStyle(T9Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, T9Theme.space4)
    }
}

struct StatusBadge: View {
    let text: String
    var tone: Color = T9Theme.teal

    var body: some View {
        Text(text.uppercased())
            .font(T9Theme.font(10, .semibold))
            .tracking(1.2)
            .foregroundStyle(tone)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tone.opacity(0.1))
    }
}

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
            .tracking(1.4)
            .foregroundStyle(T9Theme.muted)
    }
}

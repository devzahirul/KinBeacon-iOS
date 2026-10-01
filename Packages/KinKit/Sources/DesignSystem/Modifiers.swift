public import SwiftUI

public extension View {
    /// The standard card: surface fill, continuous corners, a hairline border in dark mode and a soft shadow in light.
    func kinCard(padding: CGFloat = KinSpace.md, radius: CGFloat = KinRadius.lg) -> some View {
        modifier(CardModifier(padding: padding, radius: radius))
    }

    func kinScreenBackground() -> some View {
        background(KinColor.background.ignoresSafeArea())
    }
}

struct CardModifier: ViewModifier {
    let padding: CGFloat
    let radius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KinColor.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(KinColor.separator.opacity(colorScheme == .dark ? 1 : 0.6), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 10, y: 4)
    }
}

// MARK: - Buttons

public struct KinPrimaryButtonStyle: ButtonStyle {
    public enum Role { case brand, danger, success }

    var role: Role
    @Environment(\.isEnabled) private var isEnabled

    public init(role: Role = .brand) {
        self.role = role
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.kinHeadline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, KinSpace.md)
            .background(fill.opacity(isEnabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: KinRadius.md, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
            .contentShape(Rectangle())
    }

    private var fill: Color {
        switch role {
        case .brand: KinColor.brand
        case .danger: KinColor.danger
        case .success: KinColor.success
        }
    }
}

public struct KinSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.kinHeadline)
            .foregroundStyle(KinColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(KinColor.surfaceMuted, in: RoundedRectangle(cornerRadius: KinRadius.md, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

public extension ButtonStyle where Self == KinPrimaryButtonStyle {
    static var kinPrimary: KinPrimaryButtonStyle {
        KinPrimaryButtonStyle()
    }

    static var kinDanger: KinPrimaryButtonStyle {
        KinPrimaryButtonStyle(role: .danger)
    }
}

public extension ButtonStyle where Self == KinSecondaryButtonStyle {
    static var kinSecondary: KinSecondaryButtonStyle {
        KinSecondaryButtonStyle()
    }
}

/// Plain pressable rows/tiles: dims on press, keeps the full frame tappable.
public struct KinPressableStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == KinPressableStyle {
    static var kinPressable: KinPressableStyle {
        KinPressableStyle()
    }
}

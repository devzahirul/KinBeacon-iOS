public import SwiftUI
import UIKit

/// Semantic color tokens. Every surface and text color adapts to dark mode and Increase Contrast; feature code
/// never uses a raw hex value.
public enum KinColor {
    public static let background = dynamic(light: 0xF4F6FB, dark: 0x0B0D13)
    public static let surface = dynamic(light: 0xFFFFFF, dark: 0x161922)
    public static let surfaceMuted = dynamic(light: 0xF0F2F8, dark: 0x1E2230)
    public static let separator = dynamic(light: 0xE6E9F2, dark: 0x272C3A)

    public static let textPrimary = dynamic(light: 0x111827, dark: 0xF3F4F8)
    public static let textSecondary = dynamic(light: 0x5B6475, dark: 0xA3AABA)
    public static let textTertiary = dynamic(light: 0x8A92A3, dark: 0x6F7787)

    public static let brand = dynamic(light: 0x5145E5, dark: 0x8B83FF)
    public static let brandSoft = dynamic(light: 0xEEEDFF, dark: 0x262451)
    public static let brandDeep = dynamic(light: 0x3B30C4, dark: 0x6D63F5)
    public static let info = dynamic(light: 0x2563EB, dark: 0x5B8DF6)
    public static let infoSoft = dynamic(light: 0xE8F0FF, dark: 0x1B2747)

    public static let success = dynamic(light: 0x16A34A, dark: 0x34D399)
    public static let successSoft = dynamic(light: 0xE6F6EC, dark: 0x13291F)
    public static let danger = dynamic(light: 0xE5383B, dark: 0xFF6B6E)
    public static let dangerSoft = dynamic(light: 0xFDECEC, dark: 0x3A1A1C)
    public static let warning = dynamic(light: 0xF59E0B, dark: 0xFBBF24)
    public static let warningSoft = dynamic(light: 0xFEF4E2, dark: 0x3A2C10)

    /// Gradient pairs for avatars and app tiles, indexed by `palette`.
    public static func palette(_ index: Int) -> [Color] {
        let pairs: [(UInt32, UInt32)] = [
            (0xFFB38A, 0xFF7EB3), // peach → pink
            (0x7CC8FF, 0x5B7CFA), // sky → blue
            (0xF58529, 0xDD2A7B), // instagram-ish
            (0xB79CFF, 0x7B61FF), // lavender → violet
            (0x4ADE80, 0x16A34A), // green
            (0xFF5A5F, 0xE11D48), // red
            (0x94A3B8, 0x475569), // slate
            (0xFDE047, 0x22C55E), // yellow → green
        ]
        let pair = pairs[((index % pairs.count) + pairs.count) % pairs.count]
        return [Color(hex: pair.0), Color(hex: pair.1)]
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

public extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Spacing and radius scale (4-pt grid).
public enum KinSpace {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

public enum KinRadius {
    public static let sm: CGFloat = 10
    public static let md: CGFloat = 14
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 26
}

/// Type ramp built on Dynamic Type text styles — every font scales with the user's setting.
public extension Font {
    static let kinLargeTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let kinTitle = Font.system(.title2, design: .rounded).weight(.bold)
    static let kinHeadline = Font.system(.headline, design: .rounded)
    static let kinBody = Font.system(.body)
    static let kinCallout = Font.system(.callout)
    static let kinSubheadline = Font.system(.subheadline)
    static let kinFootnote = Font.system(.footnote)
    static let kinCaption = Font.system(.caption)
    static let kinMetric = Font.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit()
    static let kinSection = Font.system(.title3, design: .rounded).weight(.semibold)
}

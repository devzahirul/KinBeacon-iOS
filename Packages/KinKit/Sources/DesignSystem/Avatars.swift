public import Domain
public import SwiftUI

/// Emoji-on-gradient avatar with an optional ring and status badge. Pure vector — no image decoding on the map.
public struct AvatarView: View {
    let avatar: Avatar
    let size: CGFloat
    var ring: Color?
    var badgeSymbol: String?

    public init(_ avatar: Avatar, size: CGFloat = 44, ring: Color? = nil, badgeSymbol: String? = nil) {
        self.avatar = avatar
        self.size = size
        self.ring = ring
        self.badgeSymbol = badgeSymbol
    }

    public var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: KinColor.palette(avatar.palette), startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(avatar.emoji)
                .font(.system(size: size * 0.56))
                .minimumScaleFactor(0.5)
        }
        .frame(width: size, height: size)
        .padding(ring == nil ? 0 : size * 0.06)
        .background {
            if let ring {
                Circle().fill(.white).overlay(Circle().strokeBorder(ring, lineWidth: max(2, size * 0.05)))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let badgeSymbol {
                Image(systemName: badgeSymbol)
                    .font(.system(size: size * 0.2, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.36, height: size * 0.36)
                    .background(KinColor.brand, in: Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .offset(x: size * 0.04, y: size * 0.04)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Rounded-square app tile (stand-in for real app icons, which FamilyControls only renders through `Label(token)`).
public struct AppIconView: View {
    let app: AppDescriptor
    let size: CGFloat

    public init(_ app: AppDescriptor, size: CGFloat = 44) {
        self.app = app
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: KinColor.palette(app.palette), startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: app.symbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel(app.name)
    }
}

/// Battery glyph + percentage, colour-coded.
public struct BatteryIndicator: View {
    let battery: BatteryState

    public init(_ battery: BatteryState) {
        self.battery = battery
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(tint, KinColor.textTertiary)
            Text(battery.level, format: .percent.precision(.fractionLength(0)))
                .font(.kinFootnote.monospacedDigit())
                .foregroundStyle(KinColor.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Battery \(Int(battery.level * 100)) percent\(battery.isCharging ? ", charging" : "")"))
    }

    private var symbol: String {
        if battery.isCharging {
            return "battery.100percent.bolt"
        }
        switch battery.level {
        case ..<0.15: return "battery.0percent"
        case ..<0.4: return "battery.25percent"
        case ..<0.65: return "battery.50percent"
        case ..<0.9: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var tint: Color {
        battery.isLow ? KinColor.danger : KinColor.success
    }
}

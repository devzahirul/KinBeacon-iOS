public import SwiftUI

/// A rounded icon "well" used at the leading edge of rows and cards.
public struct IconBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat
    var filled: Bool

    public init(_ symbol: String, tint: Color, size: CGFloat = 40, filled: Bool = false) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
        self.filled = filled
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(filled ? .white : tint)
            .frame(width: size, height: size)
            .background(
                filled ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.14)),
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// Settings-style navigation row: icon, title, subtitle, trailing accessory and chevron.
public struct StatusRow<Trailing: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String?
    var showsChevron: Bool
    @ViewBuilder var trailing: Trailing

    public init(
        symbol: String,
        tint: Color,
        title: String,
        subtitle: String? = nil,
        showsChevron: Bool = true,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.showsChevron = showsChevron
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: KinSpace.sm) {
            IconBadge(symbol, tint: tint, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.kinHeadline).foregroundStyle(KinColor.textPrimary)
                if let subtitle {
                    Text(subtitle).font(.kinFootnote).foregroundStyle(KinColor.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: KinSpace.xs)
            trailing
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(KinColor.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, KinSpace.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Groups rows into one card. Separate rows with `RowDivider()` (`Group(subviews:)` would do it automatically but
/// is iOS 18+, and the deployment target is iOS 17).
public struct RowGroup<Content: View>: View {
    @ViewBuilder var content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) { content }
            .kinCard(padding: KinSpace.md)
            .padding(.vertical, 0)
    }
}

/// Inset hairline between rows of a `RowGroup`.
public struct RowDivider: View {
    var inset: CGFloat

    public init(inset: CGFloat = 50) {
        self.inset = inset
    }

    public var body: some View {
        Rectangle().fill(KinColor.separator).frame(height: 0.5).padding(.leading, inset)
    }
}

public struct SectionHeader: View {
    let title: String
    var action: (title: String, perform: () -> Void)?

    public init(_ title: String, action: (title: String, perform: () -> Void)? = nil) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.kinSection).foregroundStyle(KinColor.textPrimary).accessibilityAddTraits(.isHeader)
            Spacer()
            if let action {
                Button(action.title, action: action.perform).font(.kinSubheadline.weight(.semibold)).tint(KinColor.brand)
            }
        }
    }
}

/// Large square quick action ("Request More Time", "Check In", "SOS").
public struct QuickActionTile: View {
    public enum Style { case filled(Color), tinted(Color) }

    let symbol: String
    let title: String
    let style: Style
    let action: () -> Void

    public init(symbol: String, title: String, style: Style, action: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: KinSpace.xs) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .frame(height: 30)
                Text(title)
                    .font(.kinSubheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(.vertical, KinSpace.sm)
            .padding(.horizontal, KinSpace.xs)
            .background(background, in: RoundedRectangle(cornerRadius: KinRadius.lg, style: .continuous))
        }
        .buttonStyle(.kinPressable)
    }

    private var foreground: Color {
        switch style {
        case .filled: .white
        case let .tinted(color): color
        }
    }

    private var background: AnyShapeStyle {
        switch style {
        case let .filled(color): AnyShapeStyle(color.gradient)
        case let .tinted(color): AnyShapeStyle(color.opacity(0.13))
        }
    }
}

/// Smaller action button used under the map card ("Directions", "Check In", ...).
public struct ActionChip: View {
    let symbol: String
    let title: String
    var isProminent: Bool
    var isOn: Bool
    let action: () -> Void

    public init(symbol: String, title: String, isProminent: Bool = false, isOn: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.isProminent = isProminent
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3.weight(.semibold))
                Text(title).font(.kinCaption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(isProminent ? .white : KinColor.brand)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                isProminent ? AnyShapeStyle(KinColor.brand.gradient) :
                    AnyShapeStyle(isOn ? KinColor.brand.opacity(0.22) : KinColor.brandSoft),
                in: RoundedRectangle(cornerRadius: KinRadius.md, style: .continuous)
            )
        }
        .buttonStyle(.kinPressable)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Selectable pill used for the extra-time options.
public struct ChoiceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.kinHeadline)
                .foregroundStyle(isSelected ? KinColor.brand : KinColor.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    isSelected ? KinColor.brandSoft : KinColor.surfaceMuted,
                    in: RoundedRectangle(cornerRadius: KinRadius.md, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: KinRadius.md, style: .continuous)
                        .strokeBorder(isSelected ? KinColor.brand : .clear, lineWidth: 2)
                }
        }
        .buttonStyle(.kinPressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Red "blocked" chip for restricted categories.
public struct CategoryChip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    public init(title: String, symbol: String, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label {
                Text(title).font(.kinSubheadline.weight(.medium))
            } icon: {
                Image(systemName: isOn ? "nosign" : symbol)
            }
            .foregroundStyle(isOn ? KinColor.danger : KinColor.textSecondary)
            .padding(.horizontal, KinSpace.sm)
            .padding(.vertical, KinSpace.xs)
            .background(isOn ? KinColor.dangerSoft : KinColor.surfaceMuted, in: Capsule())
        }
        .buttonStyle(.kinPressable)
        .accessibilityValue(isOn ? Text("Blocked") : Text("Allowed"))
    }
}

/// Thin rounded progress bar.
public struct ProgressBar: View {
    let value: Double
    var tint: Color

    public init(value: Double, tint: Color = KinColor.brand) {
        self.value = value
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(KinColor.surfaceMuted)
                Capsule().fill(tint.gradient).frame(width: max(6, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}

/// Text editor with placeholder and a live character counter ("0/200").
public struct CountedTextEditor: View {
    @Binding var text: String
    let placeholder: String
    let limit: Int

    public init(text: Binding<String>, placeholder: String, limit: Int) {
        _text = text
        self.placeholder = placeholder
        self.limit = limit
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .font(.kinBody)
                .frame(minHeight: 92)
                .onChange(of: text) { _, newValue in
                    if newValue.count > limit {
                        text = String(newValue.prefix(limit))
                    }
                }
            if text.isEmpty {
                Text(placeholder)
                    .font(.kinBody)
                    .foregroundStyle(KinColor.textTertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .padding(KinSpace.sm)
        .padding(.bottom, KinSpace.md)
        .background(KinColor.surface, in: RoundedRectangle(cornerRadius: KinRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KinRadius.md, style: .continuous).strokeBorder(KinColor.separator, lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            Text("\(text.count)/\(limit)")
                .font(.kinCaption.monospacedDigit())
                .foregroundStyle(KinColor.textTertiary)
                .padding(KinSpace.sm)
                .accessibilityLabel(Text("\(text.count) of \(limit) characters"))
        }
    }
}

/// Inline error/info banner.
public struct InlineBanner: View {
    public enum Kind { case error, info, success }

    let kind: Kind
    let message: String

    public init(_ kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    public var body: some View {
        Label {
            Text(message).font(.kinSubheadline).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        .foregroundStyle(tint)
        .padding(KinSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: KinRadius.md, style: .continuous))
    }

    private var symbol: String {
        switch kind {
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch kind {
        case .error: KinColor.danger
        case .info: KinColor.info
        case .success: KinColor.success
        }
    }
}

/// Weekday circle selector (M T W T F S S).
public struct WeekdayToggle: View {
    let label: String
    let accessibilityName: String
    let isOn: Bool
    let action: () -> Void

    public init(label: String, accessibilityName: String, isOn: Bool, action: @escaping () -> Void) {
        self.label = label
        self.accessibilityName = accessibilityName
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .font(.kinSubheadline.weight(.semibold))
                .foregroundStyle(isOn ? .white : KinColor.textSecondary)
                .frame(width: 40, height: 40)
                .background(isOn ? AnyShapeStyle(KinColor.brand.gradient) : AnyShapeStyle(KinColor.surfaceMuted), in: Circle())
        }
        .buttonStyle(.kinPressable)
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Centered placeholder for empty and error states.
public struct StateMessageView: View {
    let symbol: String
    let title: String
    let message: String
    var retry: (() -> Void)?

    public init(symbol: String, title: String, message: String, retry: (() -> Void)? = nil) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("Try again", action: retry).buttonStyle(.borderedProminent).tint(KinColor.brand)
            }
        }
    }
}

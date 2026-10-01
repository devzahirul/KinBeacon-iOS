public import SwiftUI

/// Hero card with a vector landscape (hills + trees) like the design's illustrated banners.
/// Drawn with shapes, so it costs no asset bytes, stays crisp at any size and adapts to dark mode.
public struct HeroCard: View {
    public enum Tone { case success, brand, danger }

    let tone: Tone
    let symbol: String
    let title: String
    let subtitle: String

    public init(tone: Tone, symbol: String, title: String, subtitle: String) {
        self.tone = tone
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack(spacing: KinSpace.md) {
            ShieldGlyph(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.kinTitle).foregroundStyle(KinColor.textPrimary)
                Text(subtitle).font(.kinSubheadline).foregroundStyle(KinColor.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(KinSpace.lg)
        .padding(.bottom, KinSpace.xs)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .background {
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(colors: [soft, KinColor.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                if tone != .danger {
                    Landscape(tint: tint).frame(height: 64).opacity(0.9)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: KinRadius.lg, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: KinRadius.lg, style: .continuous).strokeBorder(tint.opacity(0.15), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch tone {
        case .success: KinColor.success
        case .brand: KinColor.brand
        case .danger: KinColor.danger
        }
    }

    private var soft: Color {
        switch tone {
        case .success: KinColor.successSoft
        case .brand: KinColor.brandSoft
        case .danger: KinColor.dangerSoft
        }
    }
}

/// A shield with a symbol, rendered with a gradient and a soft glow.
public struct ShieldGlyph: View {
    let symbol: String
    let tint: Color
    var size: CGFloat

    public init(symbol: String = "checkmark", tint: Color, size: CGFloat = 60) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        ZStack {
            Image(systemName: "shield.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(tint.gradient)
                .shadow(color: tint.opacity(0.35), radius: 8, y: 4)
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .heavy))
                .foregroundStyle(.white)
                .offset(y: -size * 0.03)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Stylised rolling hills with a few trees.
struct Landscape: View {
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack(alignment: .bottom) {
                Hill(phase: 0.15, amplitude: 0.45).fill(tint.opacity(0.12))
                Hill(phase: 0.6, amplitude: 0.3).fill(tint.opacity(0.18))
                ForEach(Array(trees.enumerated()), id: \.offset) { _, tree in
                    Tree(tint: tint)
                        .frame(width: tree.size * 0.55, height: tree.size)
                        .position(x: width * tree.x, y: height - tree.size / 2 - height * 0.12)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var trees: [(x: Double, size: Double)] {
        [(0.62, 26), (0.7, 36), (0.8, 30), (0.9, 42), (0.96, 28)]
    }
}

struct Hill: Shape {
    var phase: Double
    var amplitude: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        let crest = rect.maxY - rect.height * amplitude
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * amplitude * 0.4))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: crest),
            control1: CGPoint(x: rect.width * (0.3 + phase), y: crest - rect.height * 0.35),
            control2: CGPoint(x: rect.width * (0.55 + phase / 2), y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct Tree: View {
    let tint: Color

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(tint.opacity(0.55).gradient)
            Rectangle().fill(tint.opacity(0.4)).frame(width: 2, height: 6)
        }
    }
}

public import Routing
public import Session
public import SwiftUI
import CoreImage.CIFilterBuiltins
import DesignSystem
import Domain
import KinCore

public struct FamilyView: View {
    let store: FamilyStore
    let navigate: (ParentRoute) -> Void
    @Binding var showsInvite: Bool

    public init(store: FamilyStore, showsInvite: Binding<Bool>, navigate: @escaping (ParentRoute) -> Void) {
        self.store = store
        _showsInvite = showsInvite
        self.navigate = navigate
    }

    public var body: some View {
        List {
            if let snapshot = store.snapshot {
                Section {
                    ForEach(snapshot.members) { member in
                        Button {
                            if member.role == .child {
                                navigate(.childDetail(member.id))
                            }
                        } label: {
                            MemberRow(member: member, snapshot: snapshot)
                        }
                        .disabled(member.role != .child)
                        .accessibilityIdentifier("family.member.\(member.name)")
                    }
                    Button { showsInvite = true } label: {
                        Label("Add a child’s device", systemImage: "plus.circle.fill").font(.kinHeadline).foregroundStyle(KinColor.brand)
                    }
                } header: {
                    Text(snapshot.familyName)
                }
                Section("Safe places") {
                    ForEach(snapshot.places) { place in
                        Label {
                            VStack(alignment: .leading) {
                                Text(place.name).font(.kinHeadline)
                                Text(place.address).font(.kinFootnote).foregroundStyle(KinColor.textSecondary)
                            }
                        } icon: {
                            Image(systemName: place.kind.symbol).foregroundStyle(KinColor.brand)
                        }
                    }
                }
            }
        }
        .navigationTitle("Family")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { navigate(.settings) } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("family.settings")
            }
        }
        .sheet(isPresented: $showsInvite) { InviteSheet() }
    }
}

struct MemberRow: View {
    let member: FamilyMember
    let snapshot: FamilySnapshot

    var body: some View {
        HStack(spacing: KinSpace.sm) {
            AvatarView(member.avatar, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.role == .parent ? "\(member.name) (\(member.displayName))" : member.name).font(.kinHeadline)
                    .foregroundStyle(KinColor.textPrimary)
                Text(snapshot.locationTitle(for: member.id)).font(.kinFootnote).foregroundStyle(KinColor.textSecondary)
                if !snapshot.alerts(for: member.id).isEmpty {
                    Label("Needs attention", systemImage: "exclamationmark.triangle.fill").font(.kinCaption.weight(.semibold))
                        .foregroundStyle(KinColor.danger)
                }
            }
            Spacer()
            if let battery = snapshot.status(member.id)?.battery {
                BatteryIndicator(battery)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Pairing: the child's device enters the code (or scans the QR) during onboarding. The code is short-lived and
/// single-use server-side; the QR carries the same code plus the family's public key fingerprint.
struct InviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = PairingCode.generate()

    var body: some View {
        NavigationStack {
            VStack(spacing: KinSpace.lg) {
                Text("On your child’s device, install KinBeacon, choose “This is my child’s device”, then scan this code or type it in.")
                    .font(.kinSubheadline)
                    .foregroundStyle(KinColor.textSecondary)
                    .multilineTextAlignment(.center)
                if let image = QRCode.image(for: "kinbeacon://pair/\(code.digits)") {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .padding(KinSpace.md)
                        .background(.white, in: RoundedRectangle(cornerRadius: KinRadius.lg))
                        .accessibilityLabel("Pairing QR code")
                }
                Text(code.formatted)
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                    .kerning(4)
                    .textSelection(.enabled)
                    .accessibilityLabel(Text("Pairing code \(code.digits.map(String.init).joined(separator: " "))"))
                Text("Expires in 10 minutes").font(.kinFootnote).foregroundStyle(KinColor.textTertiary)
                Spacer()
                ShareLink(item: "Join our family on KinBeacon with code \(code.formatted)") {
                    Label("Share code", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.kinPrimary)
            }
            .padding(KinSpace.lg)
            .navigationTitle("Add a child")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

public struct PairingCode: Equatable, Sendable {
    public let digits: String

    public static func generate() -> PairingCode {
        PairingCode(digits: (0 ..< 6).map { _ in String(Int.random(in: 0 ... 9)) }.joined())
    }

    public var formatted: String {
        "\(digits.prefix(3)) \(digits.suffix(3))"
    }
}

enum QRCode {
    static func image(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

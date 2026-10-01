public import Domain
public import Routing
public import Session
public import SwiftUI
import CoreImage.CIFilterBuiltins
import DesignSystem
import KinCore

public struct FamilyView: View {
    let store: FamilyStore
    let navigate: (ParentRoute) -> Void
    /// `nil` in the demo: the invite sheet then shows a sample code.
    let invite: ((NewChild) async throws -> ChildInvite)?
    let places: (any PlaceService)?
    let removeChild: ((MemberID) async throws -> Void)?
    @Binding var showsInvite: Bool
    @State private var pendingRemoval: FamilyMember?
    @State private var editingPlace: Place?
    @State private var placeError: String?

    public init(
        store: FamilyStore,
        showsInvite: Binding<Bool>,
        invite: ((NewChild) async throws -> ChildInvite)? = nil,
        places: (any PlaceService)? = nil,
        removeChild: ((MemberID) async throws -> Void)? = nil,
        navigate: @escaping (ParentRoute) -> Void
    ) {
        self.removeChild = removeChild
        self.store = store
        _showsInvite = showsInvite
        self.invite = invite
        self.places = places
        self.navigate = navigate
    }

    public var body: some View {
        List {
            if let snapshot = store.snapshot {
                membersSection(snapshot)
                placesSection(snapshot)
            } else {
                ProgressView()
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
        .sheet(isPresented: $showsInvite) { InviteSheet(invite: invite) }
        .sheet(item: $editingPlace) { place in
            PlaceEditor(place: place) { edited in
                try await places?.save(edited)
            }
        }
        .alert(placeError ?? "", isPresented: Binding(get: { placeError != nil }, set: {
            if !$0 {
                placeError = nil
            }
        })) {}
    }

    private func membersSection(_ snapshot: FamilySnapshot) -> some View {
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
                .swipeActions {
                    if member.role == .child, removeChild != nil {
                        Button("Remove", systemImage: "person.crop.circle.badge.minus", role: .destructive) { pendingRemoval = member }
                    }
                }
            }
            Button { showsInvite = true } label: {
                Label("Add a child’s device", systemImage: "plus.circle.fill").font(.kinHeadline).foregroundStyle(KinColor.brand)
            }
            .accessibilityIdentifier("family.addChild")
        } header: {
            Text(snapshot.familyName)
        }
    }

    private func placesSection(_ snapshot: FamilySnapshot) -> some View {
        Section {
            ForEach(snapshot.places) { place in
                Button {
                    if places != nil {
                        editingPlace = place
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text(place.name).font(.kinHeadline).foregroundStyle(KinColor.textPrimary)
                            Text(place.address.isEmpty ? String(localized: "\(Int(place.radius)) m radius") : place.address)
                                .font(.kinFootnote)
                                .foregroundStyle(KinColor.textSecondary)
                        }
                    } icon: {
                        Image(systemName: place.kind.symbol).foregroundStyle(KinColor.brand)
                    }
                }
                .swipeActions {
                    if let places {
                        Button("Delete", role: .destructive) {
                            Task {
                                do { try await places.deletePlace(place.id) } catch { placeError = error.localizedDescription }
                            }
                        }
                    }
                }
            }
            if places != nil {
                Button { editingPlace = Self.newPlace(near: snapshot) } label: {
                    Label("Add a safe place", systemImage: "mappin.and.ellipse").foregroundStyle(KinColor.brand)
                }
                .accessibilityIdentifier("family.addPlace")
            }
        } header: {
            Text("Safe places")
        } footer: {
            Text("You’ll get arrival and departure alerts for these places. Geofences keep working when the app is closed.")
        }
    }

    static func newPlace(near snapshot: FamilySnapshot) -> Place {
        let center = snapshot.statuses.values.compactMap(\.location?.coordinate).first ?? Coordinate(
            latitude: 37.7749,
            longitude: -122.4194
        )
        return Place(id: PlaceID(rawValue: UUID().uuidString.lowercased()), name: "", kind: .home, coordinate: center, address: "")
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
                Text(statusLine).font(.kinFootnote).foregroundStyle(KinColor.textSecondary)
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

    private var statusLine: String {
        if member.role == .child, member.deviceModel == nil, snapshot.status(member.id) == nil {
            return String(localized: "Waiting for their device to join")
        }
        return snapshot.locationTitle(for: member.id)
    }
}

/// Adds a child: the parent describes the child, the server creates the member + default controls and returns a
/// single-use code valid for 10 minutes. The child's device enters (or scans) it during onboarding.
struct InviteSheet: View {
    let invite: ((NewChild) async throws -> ChildInvite)?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var age = 10
    @State private var grade = 4
    @State private var emoji = "👧"
    @State private var result: ChildInvite?
    @State private var demoCode = PairingCode.generate()
    @State private var isWorking = false
    @State private var error: String?

    private let emojis = ["👧", "👦", "🧒", "👧🏽", "👦🏽", "👧🏿", "👦🏿", "👧🏼", "👦🏼"]

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    CodeView(code: result.formattedCode, digits: result.code, expiresAt: result.expiresAt)
                } else if invite == nil {
                    CodeView(code: demoCode.formatted, digits: demoCode.digits, expiresAt: Date().addingTimeInterval(600))
                } else {
                    form
                }
            }
            .navigationTitle("Add a child")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private var form: some View {
        Form {
            Section {
                TextField("Child’s name", text: $name).textInputAutocapitalization(.words).accessibilityIdentifier("invite.name")
                Stepper("Age: \(age)", value: $age, in: 3 ... 18)
                Stepper("Grade: \(grade)", value: $grade, in: 0 ... 12)
            }
            Section("Avatar") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(emojis.enumerated()), id: \.offset) { index, item in
                            Button { emoji = item } label: {
                                AvatarView(Avatar(emoji: item, palette: index % 8), size: 48, ring: emoji == item ? KinColor.brand : nil)
                            }
                            .accessibilityLabel(Text("Avatar \(index + 1)"))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if let error {
                Section { InlineBanner(.error, message: error) }
            }
            Section {
                Button {
                    Task { await create() }
                } label: {
                    if isWorking {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Create pairing code").frame(maxWidth: .infinity)
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                .accessibilityIdentifier("invite.create")
            } footer: {
                Text("School Mode starts with sensible defaults (school days 8:00–15:15). You can change everything later in Controls.")
            }
        }
    }

    private func create() async {
        guard let invite else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let palette = (emojis.firstIndex(of: emoji) ?? 0) % 8
            let child = NewChild(
                name: name.trimmingCharacters(in: .whitespaces),
                age: age,
                grade: grade,
                avatar: Avatar(emoji: emoji, palette: palette)
            )
            result = try await invite(child)
        } catch {
            self.error = (error as? KinError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct CodeView: View {
    let code: String
    let digits: String
    let expiresAt: Date

    var body: some View {
        VStack(spacing: KinSpace.lg) {
            Text("On your child’s device, install KinBeacon, choose “This is my child’s device”, then enter this code.")
                .font(.kinSubheadline)
                .foregroundStyle(KinColor.textSecondary)
                .multilineTextAlignment(.center)
            if let image = QRCode.image(for: "kinbeacon://pair/\(digits)") {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(KinSpace.md)
                    .background(.white, in: RoundedRectangle(cornerRadius: KinRadius.lg))
                    .accessibilityLabel("Pairing QR code")
            }
            Text(code)
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .kerning(4)
                .textSelection(.enabled)
                .accessibilityLabel(Text("Pairing code \(digits.map(String.init).joined(separator: " "))"))
                .accessibilityIdentifier("invite.code")
            Text("Expires \(expiresAt, style: .relative)").font(.kinFootnote).foregroundStyle(KinColor.textTertiary)
            Spacer()
            ShareLink(item: String(localized: "Join our family on KinBeacon with code \(code)")) {
                Label("Share code", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.kinPrimary)
        }
        .padding(KinSpace.lg)
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

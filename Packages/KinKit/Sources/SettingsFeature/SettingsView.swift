public import Domain
public import SwiftUI
import DesignSystem
import Routing

public struct SettingsView: View {
    public struct Info: Sendable {
        public var memberName: String
        public var role: MemberRole
        public var familyName: String
        public var isDemo: Bool
        public var supportsLiveScreenTime: Bool
        public var version: String

        public init(memberName: String, role: MemberRole, familyName: String, isDemo: Bool, supportsLiveScreenTime: Bool, version: String) {
            self.memberName = memberName
            self.role = role
            self.familyName = familyName
            self.isDemo = isDemo
            self.supportsLiveScreenTime = supportsLiveScreenTime
            self.version = version
        }
    }

    let info: Info
    @Binding var liveScreenTime: Bool
    let switchRole: () -> Void
    let signOut: () async -> Void
    let deleteAccount: (() async throws -> Void)?
    /// Child device, live: the apps allowed during School Mode (Apple keeps app identities on-device).
    let schoolApps: Binding<AppSelection>?
    @State private var confirmsSignOut = false
    @State private var confirmsDelete = false
    @State private var isWorking = false
    @State private var error: String?
    @Environment(\.viewFactories) private var factories

    public init(
        info: Info,
        liveScreenTime: Binding<Bool>,
        switchRole: @escaping () -> Void,
        signOut: @escaping () async -> Void,
        deleteAccount: (() async throws -> Void)? = nil,
        schoolApps: Binding<AppSelection>? = nil
    ) {
        self.info = info
        _liveScreenTime = liveScreenTime
        self.switchRole = switchRole
        self.signOut = signOut
        self.deleteAccount = deleteAccount
        self.schoolApps = schoolApps
    }

    public var body: some View {
        List {
            Section {
                LabeledContent("Name", value: info.memberName)
                LabeledContent("Role", value: info.role == .parent ? String(localized: "Parent") : String(localized: "Child"))
                LabeledContent("Family", value: info.familyName)
            }
            if info.role == .child, info.supportsLiveScreenTime {
                Section {
                    Toggle("Enforce with Screen Time", isOn: $liveScreenTime)
                } footer: {
                    Text(
                        """
                        Blocks apps on this iPhone with Apple’s Screen Time during School \
                        Mode. Off by default so the demo never restricts your own phone.
                        """
                    )
                }
            }
            if let schoolApps {
                Section {
                    NavigationLink {
                        factories.appPicker(schoolApps).navigationTitle("School Mode apps")
                    } label: {
                        Label("Apps allowed during School Mode", systemImage: "checkmark.app")
                    }
                } footer: {
                    Text("Choose these together with your parent. Apple keeps the list of installed apps private to this iPhone.")
                }
            }
            Section("Privacy") {
                Label("Location is shared only with your family", systemImage: "location.circle")
                Label("Location history is deleted after 30 days", systemImage: "clock.arrow.circlepath")
                Label("No ads, no tracking, no data sale", systemImage: "hand.raised")
                Link(destination: URL(string: "https://github.com/devzahirul/KinBeacon-iOS/blob/main/docs/PRIVACY.md")!) {
                    Label("Privacy policy", systemImage: "doc.text")
                }
                Link(destination: URL(string: "https://github.com/devzahirul/KinBeacon-iOS/blob/main/docs/SUPPORT.md")!) {
                    Label("Help & support", systemImage: "questionmark.bubble")
                }
            }
            if info.isDemo {
                Section {
                    Button(
                        "Switch to \(info.role == .parent ? "child" : "parent") view",
                        systemImage: "arrow.left.arrow.right",
                        action: switchRole
                    )
                    .accessibilityIdentifier("settings.switchRole")
                } header: {
                    Text("Demo")
                } footer: {
                    Text("The demo runs a simulated family on this device — no account or server needed.")
                }
            }
            Section {
                Button(info.isDemo ? String(localized: "Restart onboarding") : String(localized: "Sign out"), role: .destructive) {
                    confirmsSignOut = true
                }
                .accessibilityIdentifier("settings.signOut")
                if deleteAccount != nil {
                    Button("Delete account", role: .destructive) { confirmsDelete = true }
                        .accessibilityIdentifier("settings.deleteAccount")
                }
                if let error {
                    InlineBanner(.error, message: error)
                }
            } footer: {
                Text("KinBeacon \(info.version)")
            }
        }
        .tint(KinColor.brand)
        .disabled(isWorking)
        .overlay {
            if isWorking {
                ProgressView()
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Are you sure?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
            Button(info.isDemo ? String(localized: "Restart onboarding") : String(localized: "Sign out"), role: .destructive) {
                Task {
                    isWorking = true
                    await signOut()
                    isWorking = false
                }
            }
        }
        .confirmationDialog(deleteTitle, isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task {
                    isWorking = true
                    defer { isWorking = false }
                    do {
                        try await deleteAccount?()
                    } catch {
                        self.error = (error as? KinError)?.errorDescription ?? error.localizedDescription
                    }
                }
            }
        } message: {
            Text(deleteMessage)
        }
    }
}

extension SettingsView {
    var deleteTitle: String {
        String(localized: "Delete your KinBeacon account?")
    }

    var deleteMessage: String {
        info.role == .parent
            ?
            String(
                localized: """
                If you are the only parent, your whole family — children, places, history and controls — \
                is permanently deleted.
                """
            )
            : String(localized: "This device leaves the family and its history is deleted. Your parent will see that it left.")
    }
}

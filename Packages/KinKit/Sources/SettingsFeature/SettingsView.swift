public import Domain
public import SwiftUI
import DesignSystem

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
    let signOut: () -> Void
    @State private var confirmsSignOut = false

    public init(info: Info, liveScreenTime: Binding<Bool>, switchRole: @escaping () -> Void, signOut: @escaping () -> Void) {
        self.info = info
        _liveScreenTime = liveScreenTime
        self.switchRole = switchRole
        self.signOut = signOut
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
            Section("Privacy") {
                Label("Location is shared only with your family", systemImage: "location.circle")
                Label("Location history is deleted after 30 days", systemImage: "clock.arrow.circlepath")
                Label("No ads, no tracking, no data sale", systemImage: "hand.raised")
                Link(destination: URL(string: "https://github.com/devzahirul/KinBeacon-iOS/blob/main/docs/PRIVACY.md")!) {
                    Label("Privacy policy", systemImage: "doc.text")
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
                Button(info.isDemo ? "Restart onboarding" : "Leave family", role: .destructive) { confirmsSignOut = true }
            } footer: {
                Text("KinBeacon \(info.version)")
            }
        }
        .tint(KinColor.brand)
        .navigationTitle("Settings")
        .confirmationDialog("Are you sure?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
            Button(info.isDemo ? "Restart onboarding" : "Leave family", role: .destructive, action: signOut)
        }
    }
}

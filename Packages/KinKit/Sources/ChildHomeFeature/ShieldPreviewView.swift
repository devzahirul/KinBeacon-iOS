public import Routing
public import ScreenTimeShared
public import SwiftUI
import DesignSystem
import Domain
import KinCore
import Session

/// In-app replica of the system shield, rendered from the same `ShieldCopy` the ShieldConfiguration extension
/// uses. On a device with Screen Time authorised, the real shield appears over the blocked app itself.
public struct ShieldPreviewView: View {
    let appName: String
    let policy: SharedPolicy?
    let navigate: (ChildRoute) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(appName: String, policy: SharedPolicy?, navigate: @escaping (ChildRoute) -> Void) {
        self.appName = appName
        self.policy = policy
        self.navigate = navigate
    }

    public var body: some View {
        let content = ShieldCopy.content(appName: appName, policy: policy, now: .now)
        VStack(spacing: KinSpace.lg) {
            Spacer()
            AppIconView(AppDescriptor(id: "preview", name: appName, symbol: "camera.aperture", palette: 2), size: 96)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            Text(content.title)
                .font(.kinTitle)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("shield.title")
            Text(content.subtitle.components(separatedBy: "\n").first ?? "")
                .font(.kinBody)
                .foregroundStyle(KinColor.textSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: KinSpace.sm) {
                IconBadge("graduationcap.fill", tint: KinColor.info, size: 44)
                Text(content.subtitle.components(separatedBy: "\n").dropFirst().joined()).font(.kinSubheadline)
                    .foregroundStyle(KinColor.textSecondary)
            }
            .padding(KinSpace.md)
            .background(KinColor.infoSoft, in: RoundedRectangle(cornerRadius: KinRadius.lg, style: .continuous))
            Spacer()
            if let primary = content.primaryButton {
                Button(primary) { navigate(.requestTime(appName: appName)) }
                    .buttonStyle(.kinPrimary)
                    .accessibilityIdentifier("shield.request")
            }
            Button(content.secondaryButton) { dismiss() }.buttonStyle(.kinSecondary)
        }
        .padding(KinSpace.lg)
        .kinScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}

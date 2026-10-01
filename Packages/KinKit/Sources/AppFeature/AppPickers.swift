import DemoBackend
import DesignSystem
import Domain
import Routing
import ScreenTimeKit
import SwiftUI

enum AppPickers {
    static func factories(live: Bool) -> ViewFactories {
        var report: (@MainActor @Sendable () -> AnyView)?
        #if canImport(DeviceActivity) && os(iOS)
            if live {
                report = { AnyView(SystemUsageReport()) }
            }
        #endif
        return ViewFactories(
            appPicker: { selection in
                #if canImport(FamilyControls) && os(iOS)
                    if live {
                        return AnyView(SystemAppPicker(selection: selection))
                    }
                #endif
                return AnyView(DemoAppPicker(selection: selection))
            },
            usageReport: report
        )
    }
}

/// Demo stand-in for `FamilyActivityPicker` (which only works on a device with Screen Time authorised).
struct DemoAppPicker: View {
    @Binding var selection: AppSelection

    var body: some View {
        List(DemoData.appCatalog) { app in
            let isOn = selection.apps.contains { $0.id == app.id }
            Button {
                if isOn {
                    selection.apps.removeAll { $0.id == app.id }
                } else {
                    selection.apps.append(app)
                }
            } label: {
                HStack(spacing: KinSpace.sm) {
                    AppIconView(app, size: 34)
                    Text(app.name).foregroundStyle(KinColor.textPrimary)
                    Spacer()
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isOn ? KinColor.brand : KinColor.textTertiary)
                        .font(.title3)
                }
            }
            .accessibilityAddTraits(isOn ? .isSelected : [])
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Onboarding before a runtime exists: real prompts on device, no-ops in the simulator/tests.
struct OnboardingPermissions: PermissionsProviding {
    func currentReport() async -> PermissionHealthReport {
        .healthy
    }

    func request(_ kind: PermissionKind) async -> PermissionState {
        guard !AppContainer.isSimulator else { return .granted }
        switch kind {
        case .notifications:
            let granted = await LocalNotificationPresenterBridge.requestAuthorization()
            return granted ? .granted : .denied
        default:
            // Location & Screen Time prompts are requested by the child runtime's providers, in context.
            return .notDetermined
        }
    }
}

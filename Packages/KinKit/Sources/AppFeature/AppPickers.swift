import DemoBackend
import DesignSystem
import Domain
import Routing
import ScreenTimeKit
import SwiftUI

enum AppPickers {
    enum Context { case demo, parentLive, childLive }

    static func factories(_ context: Context) -> ViewFactories {
        var report: (@MainActor @Sendable () -> AnyView)?
        #if canImport(DeviceActivity) && os(iOS)
            switch context {
            case .parentLive: report = { AnyView(SystemUsageReport(children: true)) }
            case .childLive: report = { AnyView(SystemUsageReport()) }
            case .demo: report = nil
            }
        #endif
        return ViewFactories(
            appPicker: { selection in
                switch context {
                case .demo:
                    return AnyView(DemoAppPicker(selection: selection))
                case .parentLive:
                    return AnyView(ChildDeviceAppsNotice())
                case .childLive:
                    #if canImport(FamilyControls) && os(iOS)
                        return AnyView(SystemAppPicker(selection: selection))
                    #else
                        return AnyView(DemoAppPicker(selection: selection))
                    #endif
                }
            },
            usageReport: report
        )
    }
}

/// Apple's app identities (`ApplicationToken`) are encrypted per device, so a selection made on the parent's iPhone
/// can't be enforced on the child's. The allow-list is therefore chosen on the child's device.
struct ChildDeviceAppsNotice: View {
    var body: some View {
        ContentUnavailableView {
            Label("Choose apps on your child’s iPhone", systemImage: "iphone.and.arrow.forward")
        } description: {
            Text(
                """
                For privacy, Apple keeps each device’s app list on that device. On your child’s iPhone \
                open KinBeacon › Settings › Apps allowed during School Mode and pick them together.
                """
            )
        }
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

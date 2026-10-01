public import Domain
public import SwiftUI

/// Views a feature needs but must not build itself (they live in platform modules). Injected through the
/// environment by the composition root; previews and tests get harmless defaults.
public struct ViewFactories: Sendable {
    /// The app picker: Apple's `FamilyActivityPicker` on device, a demo catalogue elsewhere.
    public var appPicker: @MainActor @Sendable (Binding<AppSelection>) -> AnyView
    /// Apple's privacy-sandboxed usage report (DeviceActivityReport extension), when Screen Time is live.
    public var usageReport: (@MainActor @Sendable () -> AnyView)?

    public init(
        appPicker: @escaping @MainActor @Sendable (Binding<AppSelection>) -> AnyView,
        usageReport: (@MainActor @Sendable () -> AnyView)? = nil
    ) {
        self.appPicker = appPicker
        self.usageReport = usageReport
    }

    public static let placeholder = ViewFactories { _ in AnyView(Text("App picker unavailable")) }
}

public extension EnvironmentValues {
    @Entry var viewFactories: ViewFactories = .placeholder
}

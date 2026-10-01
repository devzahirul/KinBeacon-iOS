#if canImport(DeviceActivity) && os(iOS)
    public import SwiftUI
    import DeviceActivity
    import Foundation

    /// Hosts the `KinBeaconReport` extension's scene. The numbers are computed and drawn inside Apple's sandbox —
    /// KinBeacon's process only ever sees pixels, never the child's raw usage data.
    public struct SystemUsageReport: View {
        public init() {}

        public var body: some View {
            DeviceActivityReport(
                DeviceActivityReport.Context("Total Activity"),
                filter: DeviceActivityFilter(segment: .daily(during: Calendar.current.dateInterval(of: .day, for: .now) ?? DateInterval()))
            )
            .frame(minHeight: 96)
        }
    }
#endif

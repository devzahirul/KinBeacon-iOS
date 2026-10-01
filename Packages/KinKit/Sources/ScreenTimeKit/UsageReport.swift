#if canImport(DeviceActivity) && os(iOS)
    public import SwiftUI
    import DeviceActivity
    import Foundation

    /// Hosts the `KinBeaconReport` extension's scene. The numbers are computed and drawn inside Apple's sandbox —
    /// KinBeacon's process only ever sees pixels, never the child's raw usage data.
    public struct SystemUsageReport: View {
        /// `true` on a parent's device: Family Sharing children's usage (their devices must have granted `.child`
        /// authorization).
        let children: Bool

        public init(children: Bool = false) {
            self.children = children
        }

        public var body: some View {
            DeviceActivityReport(
                DeviceActivityReport.Context("Total Activity"),
                filter: DeviceActivityFilter(
                    segment: .hourly(during: Calendar.current.dateInterval(of: .day, for: .now) ?? DateInterval()),
                    users: children ? .children : .all,
                    devices: .all
                )
            )
            .frame(minHeight: 520)
        }
    }
#endif

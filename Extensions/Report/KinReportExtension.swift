import DeviceActivity
import ExtensionKit
import SwiftUI

/// Screen Time usage is privacy-sandboxed: raw `DeviceActivityResults` are only readable inside this extension and
/// can only leave it as pixels. The app embeds `DeviceActivityReport(.totalActivity)`; the numbers never touch
/// KinBeacon's process or servers.
@main
struct KinReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TotalActivityReport { TotalActivityView(summary: $0) }
    }
}

extension DeviceActivityReport.Context {
    static let totalActivity = Self("Total Activity")
}

nonisolated struct TotalActivityReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .totalActivity
    let content: (String) -> TotalActivityView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> String {
        var total: TimeInterval = 0
        for await activity in data {
            for await segment in activity.activitySegments {
                total += segment.totalActivityDuration
            }
        }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: total) ?? "0m"
    }
}

struct TotalActivityView: View {
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Screen time today").font(.subheadline).foregroundStyle(.secondary)
            Text(summary).font(.system(.largeTitle, design: .rounded).weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

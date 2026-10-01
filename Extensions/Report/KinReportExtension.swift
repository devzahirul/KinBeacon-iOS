import Charts
import DeviceActivity
import ExtensionKit
import FamilyControls
import ManagedSettings
import SwiftUI

/// Screen Time usage is privacy-sandboxed: raw `DeviceActivityResults` are only readable inside this extension and
/// can only leave it as pixels. The app embeds `DeviceActivityReport(.totalActivity)`; the numbers never touch
/// KinBeacon's process or servers.
@main
struct KinReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TotalActivityReport { UsageReportView(summary: $0) }
    }
}

extension DeviceActivityReport.Context {
    static let totalActivity = Self("Total Activity")
}

/// What the report renders. Built entirely inside the extension.
nonisolated struct UsageSummary {
    struct App: Identifiable {
        let id: String
        let token: ApplicationToken?
        let name: String
        let duration: TimeInterval
        let pickups: Int
    }

    var total: TimeInterval = 0
    var hourly: [Int: TimeInterval] = [:]
    var apps: [App] = []
    var pickups = 0
}

nonisolated struct TotalActivityReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .totalActivity
    let content: (UsageSummary) -> UsageReportView

    /// The host asks for hourly segments of today, so each segment is one hour of the chart.
    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> UsageSummary {
        var summary = UsageSummary()
        var apps: [String: UsageSummary.App] = [:]
        let calendar = Calendar.current
        for await device in data {
            for await segment in device.activitySegments {
                summary.total += segment.totalActivityDuration
                let hour = calendar.component(.hour, from: segment.dateInterval.start)
                summary.hourly[hour, default: 0] += segment.totalActivityDuration
                summary.pickups += segment.totalPickupsWithoutApplicationActivity
                for await category in segment.categories {
                    for await activity in category.applications {
                        let application = activity.application
                        let key = application.bundleIdentifier ?? application.localizedDisplayName ?? UUID().uuidString
                        let previous = apps[key]
                        apps[key] = UsageSummary.App(
                            id: key,
                            token: application.token,
                            name: application.localizedDisplayName ?? application.bundleIdentifier ?? "App",
                            duration: (previous?.duration ?? 0) + activity.totalActivityDuration,
                            pickups: (previous?.pickups ?? 0) + activity.numberOfPickups
                        )
                        summary.pickups += activity.numberOfPickups
                    }
                }
            }
        }
        summary.apps = apps.values.filter { $0.duration >= 60 }.sorted { $0.duration > $1.duration }
        return summary
    }
}

nonisolated struct UsageReportView: View {
    let summary: UsageSummary

    @MainActor var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Screen time today").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Text(Self.format(summary.total)).font(.system(.largeTitle, design: .rounded).weight(.bold))
                if summary.pickups > 0 {
                    Text("\(summary.pickups) pickups").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Chart(0 ..< 24, id: \.self) { hour in
                BarMark(
                    x: .value("Hour", hour),
                    y: .value("Minutes", (summary.hourly[hour] ?? 0) / 60),
                    width: .fixed(7)
                )
                .foregroundStyle(Color(red: 0.32, green: 0.27, blue: 0.9).gradient)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text(Self.hourLabel(hour))
                        }
                    }
                }
            }
            .chartXScale(domain: -0.5 ... 23.5)
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
            .frame(height: 130)
            if summary.apps.isEmpty {
                Text("No app usage recorded yet today.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Most used").font(.headline)
                let maximum = max(summary.apps.first?.duration ?? 1, 1)
                ForEach(summary.apps.prefix(6)) { app in
                    HStack(spacing: 12) {
                        Group {
                            if let token = app.token {
                                Label(token).labelStyle(.iconOnly)
                            } else {
                                Image(systemName: "app.fill").foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                if let token = app.token {
                                    Label(token).labelStyle(.titleOnly).font(.subheadline.weight(.semibold)).lineLimit(1)
                                } else {
                                    Text(app.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                }
                                Spacer()
                                Text(Self.format(app.duration)).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            GeometryReader { proxy in
                                Capsule().fill(Color(red: 0.32, green: 0.27, blue: 0.9).gradient)
                                    .frame(width: max(6, proxy.size.width * app.duration / maximum), height: 6)
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func format(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? "0m"
    }

    static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(.dateTime.hour())
    }
}

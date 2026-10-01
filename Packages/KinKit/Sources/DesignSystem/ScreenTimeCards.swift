public import Domain
public import SwiftUI
import Charts
import KinCore

/// Total + change + bar chart. Shared by the parent and child Activity screens.
public struct ScreenTimeChartCard: View {
    let summary: ScreenTimeSummary
    let comparisonLabel: String

    public init(summary: ScreenTimeSummary, comparisonLabel: String) {
        self.summary = summary
        self.comparisonLabel = comparisonLabel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KinSpace.sm) {
            Text("Screen Time").font(.kinSubheadline.weight(.semibold)).foregroundStyle(KinColor.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: KinSpace.sm) {
                Text(KinFormat.duration(.seconds(summary.totalMinutes * 60)))
                    .font(.kinMetric)
                    .foregroundStyle(KinColor.textPrimary)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("activity.total")
                if let change = summary.change {
                    Label {
                        Text("\(abs(change), format: .percent.precision(.fractionLength(0))) \(comparisonLabel)")
                    } icon: {
                        Image(systemName: change <= 0 ? "arrow.down" : "arrow.up")
                    }
                    .font(.kinFootnote.weight(.semibold))
                    .foregroundStyle(change <= 0 ? KinColor.success : KinColor.danger)
                }
            }
            if summary.range != .day {
                Text("Daily average \(KinFormat.duration(.seconds(summary.dailyAverage() * 60)))").font(.kinFootnote)
                    .foregroundStyle(KinColor.textSecondary)
            }
            chart
        }
        .kinCard()
    }

    private var chart: some View {
        Chart(summary.buckets) { bucket in
            BarMark(
                x: .value("Time", bucket.start, unit: summary.range == .day ? .hour : .day),
                y: .value("Minutes", bucket.minutes),
                width: .ratio(0.6)
            )
            .foregroundStyle(KinColor.brand.gradient)
            .cornerRadius(3)
            if summary.range != .day, summary.dailyLimitMinutes > 0 {
                RuleMark(y: .value("Limit", summary.dailyLimitMinutes))
                    .foregroundStyle(KinColor.danger.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
        }
        .chartXAxis {
            if summary.range == .day {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour())
                }
            } else {
                AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                    AxisValueLabel(format: summary.range == .week ? .dateTime.weekday(.narrow) : .dateTime.day())
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minutes = value.as(Int.self) {
                        Text(KinFormat.duration(.seconds(minutes * 60)))
                    }
                }
            }
        }
        .frame(height: 150)
        .accessibilityLabel(Text("Usage chart"))
        .accessibilityValue(Text(KinFormat.duration(.seconds(summary.totalMinutes * 60))))
    }
}

public struct TopAppsCard: View {
    let apps: [AppUsage]

    public init(apps: [AppUsage]) {
        self.apps = apps
    }

    public var body: some View {
        let maximum = max(apps.map(\.minutes).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: KinSpace.sm) {
            Text("Top Apps").font(.kinSection)
            ForEach(apps) { usage in
                HStack(spacing: KinSpace.sm) {
                    AppIconView(usage.app, size: 32)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(usage.app.name).font(.kinSubheadline.weight(.semibold))
                            Spacer()
                            Text(KinFormat.duration(.seconds(usage.minutes * 60))).font(.kinFootnote.monospacedDigit())
                                .foregroundStyle(KinColor.textSecondary)
                        }
                        ProgressBar(value: Double(usage.minutes) / Double(maximum))
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if apps.isEmpty {
                Text("No app usage yet.").font(.kinSubheadline).foregroundStyle(KinColor.textSecondary)
            }
        }
        .kinCard()
    }
}

/// "‹ Today, Apr 17 ›"
public struct PeriodNavigator: View {
    let title: String
    let canGoForward: Bool
    let step: (Int) -> Void

    public init(title: String, canGoForward: Bool, step: @escaping (Int) -> Void) {
        self.title = title
        self.canGoForward = canGoForward
        self.step = step
    }

    public var body: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Previous period")
            Spacer()
            Text(title).font(.kinHeadline).contentTransition(.numericText())
            Spacer()
            Button { step(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(!canGoForward)
                .accessibilityLabel("Next period")
        }
        .tint(KinColor.textPrimary)
        .sensoryFeedback(.selection, trigger: title)
    }
}

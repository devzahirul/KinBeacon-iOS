public import Session
public import SwiftUI
import DesignSystem
import Domain
import KinCore
import Routing

public struct ChildActivityView: View {
    let store: CompanionStore
    @State private var model: ActivityModel
    @Environment(\.viewFactories) private var factories

    public init(store: CompanionStore, model: ActivityModel) {
        self.store = store
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KinSpace.md) {
                Picker("Range", selection: $model.range) {
                    ForEach(ScreenTimeRange.allCases) { Text($0.childTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                PeriodNavigator(title: model.periodTitle, canGoForward: model.canGoForward) { model.step($0) }
                if let report = factories.usageReport, model.range == .day {
                    report().kinCard(padding: 0)
                    Text("Shown by Apple’s Screen Time. If it stays empty, turn on Device protection in Help.")
                        .font(.kinFootnote)
                        .foregroundStyle(KinColor.textSecondary)
                }
                switch model.phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                case .failed(.privateToScreenTime):
                    if factories.usageReport == nil {
                        InlineBanner(.info, message: KinError.privateToScreenTime.errorDescription ?? "")
                    }
                case let .failed(error):
                    InlineBanner(.error, message: error.errorDescription ?? "")
                case let .loaded(summary):
                    usageCard(summary)
                    if summary.range != .day {
                        ScreenTimeChartCard(summary: summary, comparisonLabel: model.comparisonLabel)
                    }
                }
                if let mode = store.activeMode {
                    HStack(spacing: KinSpace.sm) {
                        IconBadge("clock.fill", tint: KinColor.warning, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next break at \(KinFormat.time(mode.until))").font(.kinHeadline)
                            Text("Then apps will be available again.").font(.kinFootnote).foregroundStyle(KinColor.textSecondary)
                        }
                    }
                    .kinCard()
                }
                timeline
            }
            .padding(KinSpace.md)
        }
        .kinScreenBackground()
        .navigationTitle("Activity")
        .task(id: model.loadKey(member: store.dashboard?.member.id)) {
            guard let member = store.dashboard?.member.id else { return }
            await model.load(member: member)
        }
    }

    private func usageCard(_ summary: ScreenTimeSummary) -> some View {
        let dailyAverage = summary.dailyAverage()
        return VStack(alignment: .leading, spacing: KinSpace.sm) {
            HStack(alignment: .top) {
                Image(systemName: "chart.bar.fill").font(.system(size: 36)).foregroundStyle(KinColor.info.gradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.range == .day ? "Screen time used" : "Daily average").font(.kinSubheadline.weight(.semibold))
                    Text(KinFormat.duration(.seconds(dailyAverage * 60))).font(.kinMetric)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Daily limit").font(.kinCaption).foregroundStyle(KinColor.textSecondary)
                    Text(KinFormat.duration(.seconds(summary.dailyLimitMinutes * 60))).font(.kinSubheadline.weight(.semibold))
                }
            }
            ProgressBar(
                value: summary.dailyLimitMinutes > 0 ? Double(dailyAverage) / Double(summary.dailyLimitMinutes) : 0,
                tint: KinColor.info
            )
        }
        .kinCard()
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Activity").font(.kinSection).padding(.bottom, KinSpace.sm)
            let events = store.dashboard?.recentActivity ?? []
            if events.isEmpty {
                Text("Nothing yet today.").font(.kinSubheadline).foregroundStyle(KinColor.textSecondary)
            }
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                HStack(alignment: .top, spacing: KinSpace.sm) {
                    VStack(spacing: 0) {
                        Circle().fill(KinColor.info).frame(width: 10, height: 10).padding(.top, 15)
                        if index < events.count - 1 {
                            Rectangle().fill(KinColor.info.opacity(0.3)).frame(width: 2)
                        }
                    }
                    .frame(width: 10)
                    IconBadge(event.symbol, tint: KinColor.info, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.kinSubheadline.weight(.semibold))
                        Text(event.subtitle).font(.kinFootnote).foregroundStyle(KinColor.textSecondary)
                    }
                    Spacer()
                    Text(KinFormat.time(event.timestamp)).font(.kinCaption).foregroundStyle(KinColor.textTertiary)
                }
                .padding(.bottom, KinSpace.sm)
                .accessibilityElement(children: .combine)
            }
        }
        .kinCard()
    }
}

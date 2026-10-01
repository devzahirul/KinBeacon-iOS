public import SwiftUI
import DesignSystem
import Domain
import KinCore

public struct RequestTimeView: View {
    @State private var model: RequestTimeModel
    @FocusState private var messageFocused: Bool

    public init(model: RequestTimeModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KinSpace.lg) {
                header
                if let mode = model.activeMode {
                    HStack(alignment: .top, spacing: KinSpace.sm) {
                        IconBadge(mode.kind.symbol, tint: KinColor.info, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(mode.kind.modeTitle) is active").font(.kinHeadline)
                            Text("Your apps are limited until \(KinFormat.time(mode.until)). You can request extra time below.")
                                .font(.kinFootnote)
                                .foregroundStyle(KinColor.textSecondary)
                        }
                    }
                    .padding(KinSpace.md)
                    .background(KinColor.infoSoft, in: RoundedRectangle(cornerRadius: KinRadius.lg, style: .continuous))
                }
                content
            }
            .padding(KinSpace.md)
            .animation(.smooth, value: model.phase)
        }
        .scrollDismissesKeyboard(.interactively)
        .kinScreenBackground()
        .navigationTitle("Request More Time")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(trigger: model.phase) { _, new in
            switch new {
            case .approved: .success
            case .failed: .error
            case .waiting: .impact
            default: nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: KinSpace.md) {
            Image(systemName: "clock.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(KinColor.info.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Request More Time").font(.kinTitle)
                Text("Need a little extra time? Send a request to \(model.guardianName).").font(.kinSubheadline)
                    .foregroundStyle(KinColor.textSecondary)
            }
        }
        .kinCard()
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case let .waiting(request):
            StatusPanel(
                symbol: "paperplane.fill",
                tint: KinColor.brand,
                title: String(localized: "Request sent"),
                message: String(localized: "Asked for \(request.option.title). We’ll tell you as soon as \(model.guardianName) answers.")
            )
            .accessibilityIdentifier("request.waiting")
            ProgressView().frame(maxWidth: .infinity)
        case let .approved(until):
            StatusPanel(
                symbol: "checkmark.circle.fill",
                tint: KinColor.success,
                title: String(localized: "Approved!"),
                message: String(localized: "Your apps are unlocked until \(KinFormat.time(until)). Enjoy!")
            )
            .accessibilityIdentifier("request.approved")
            Button("Done") { model.startOver() }.buttonStyle(.kinSecondary)
        case .denied:
            StatusPanel(
                symbol: "hand.raised.fill",
                tint: KinColor.warning,
                title: String(localized: "Not this time"),
                message: String(localized: "\(model.guardianName) said maybe later.")
            )
            Button("OK") { model.startOver() }.buttonStyle(.kinSecondary)
        default:
            form
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: KinSpace.md) {
            Text("How much extra time do you need?").font(.kinHeadline)
            HStack(spacing: KinSpace.sm) {
                ForEach(ExtraTimeOption.allCases) { option in
                    ChoiceChip(option.title, isSelected: model.option == option) { model.option = option }
                        .accessibilityIdentifier("request.option.\(option.minutes)")
                }
            }
            .sensoryFeedback(.selection, trigger: model.option)
            Text("Optional message to \(model.guardianName)").font(.kinHeadline)
            CountedTextEditor(
                text: $model.message,
                placeholder: String(localized: "Tell them why you need more time… (e.g. finishing homework)"),
                limit: TimeRequestPolicy.maxMessageLength
            )
            .focused($messageFocused)
            if case let .failed(message) = model.phase {
                InlineBanner(.error, message: message)
            }
            Button {
                messageFocused = false
                Task { await model.send() }
            } label: {
                if model.phase == .sending {
                    ProgressView().tint(.white)
                } else {
                    Text("Send Request")
                }
            }
            .buttonStyle(.kinPrimary)
            .disabled(!model.canSend)
            .accessibilityIdentifier("request.send")
        }
    }
}

/// Big status panel for success / waiting / declined states.
struct StatusPanel: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: KinSpace.sm) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: title)
            Text(title).font(.kinTitle)
            Text(message).font(.kinSubheadline).foregroundStyle(KinColor.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(KinSpace.xl)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: KinRadius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

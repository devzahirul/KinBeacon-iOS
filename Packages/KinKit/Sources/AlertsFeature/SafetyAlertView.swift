public import SwiftUI
import DesignSystem
import Domain
import KinCore

public struct SafetyAlertView: View {
    @State private var model: SafetyAlertModel
    @Environment(\.dismiss) private var dismiss

    public init(model: SafetyAlertModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            if let alert = model.alert, let child = model.child {
                VStack(alignment: .leading, spacing: KinSpace.lg) {
                    header(alert, child: child)
                    VStack(alignment: .leading, spacing: KinSpace.sm) {
                        Text("Affected child").font(.kinHeadline)
                        HStack(spacing: KinSpace.sm) {
                            AvatarView(child.avatar, size: 48)
                            VStack(alignment: .leading) {
                                Text(child.name).font(.kinHeadline)
                                Text([child.subtitle, child.deviceModel].compactMap(\.self).joined(separator: " · ")).font(.kinFootnote)
                                    .foregroundStyle(KinColor.textSecondary)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: KinSpace.xs) {
                        Text("What this means").font(.kinHeadline)
                        Text(alert.explanation(childName: child.name)).font(.kinBody).foregroundStyle(KinColor.textSecondary)
                    }
                    if model.permission != nil {
                        HStack(spacing: KinSpace.sm) {
                            IconBadge("gearshape.fill", tint: KinColor.textSecondary, size: 34)
                            Text("This may have happened accidentally or after a device update.").font(.kinFootnote)
                                .foregroundStyle(KinColor.textSecondary)
                        }
                        .kinCard(padding: KinSpace.sm)
                    }
                    actions(alert, child: child)
                }
                .padding(KinSpace.md)
                .animation(.smooth, value: model.fixState)
                .animation(.smooth, value: model.isResolved)
            } else {
                StateMessageView(
                    symbol: "checkmark.shield",
                    title: String(localized: "All clear"),
                    message: String(localized: "This alert has been resolved.")
                )
            }
        }
        .kinScreenBackground()
        .navigationTitle("Safety Alert")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: model.isResolved)
    }

    private func header(_ alert: SafetyAlert, child: FamilyMember) -> some View {
        let tint = model.isResolved ? KinColor.success : KinColor.danger
        return VStack(alignment: .leading, spacing: KinSpace.sm) {
            HStack(alignment: .top, spacing: KinSpace.sm) {
                Image(systemName: model.isResolved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(tint.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.isResolved ? String(localized: "Fixed — all good again") : alert.title)
                        .font(.kinTitle)
                        .foregroundStyle(tint)
                        .accessibilityIdentifier("alert.title")
                    Text(alert.summary(childName: child.name)).font(.kinSubheadline).foregroundStyle(KinColor.textPrimary)
                    Text(alert.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.kinFootnote)
                        .foregroundStyle(KinColor.textSecondary)
                }
            }
        }
        .padding(KinSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            model.isResolved ? KinColor.successSoft : KinColor.dangerSoft,
            in: RoundedRectangle(cornerRadius: KinRadius.lg, style: .continuous)
        )
    }

    private func actions(_ alert: SafetyAlert, child: FamilyMember) -> some View {
        VStack(spacing: KinSpace.sm) {
            switch (model.isResolved, model.fixState) {
            case (true, _):
                Button("Done") { dismiss() }.buttonStyle(.kinPrimary)
            case (false, .sent):
                InlineBanner(
                    .info,
                    message: String(localized: "We sent a reminder to \(child.name)’s device. This page updates as soon as it’s fixed.")
                )
                ProgressView().frame(maxWidth: .infinity)
            case let (false, .failed(message)):
                InlineBanner(.error, message: message)
                fixButton(child)
            default:
                if alert.isFixableRemotely {
                    fixButton(child)
                }
                Button("Not now") { dismiss() }.buttonStyle(.kinSecondary)
            }
        }
    }

    private func fixButton(_ child: FamilyMember) -> some View {
        Button {
            Task { await model.fix() }
        } label: {
            if model.fixState == .sending {
                ProgressView().tint(.white)
            } else {
                Label("Fix on \(child.name)’s device", systemImage: "gearshape.fill")
            }
        }
        .buttonStyle(.kinDanger)
        .disabled(model.fixState == .sending)
        .accessibilityIdentifier("alert.fix")
    }
}

public struct TimeRequestView: View {
    @State private var model: TimeRequestModel
    @Environment(\.dismiss) private var dismiss

    public init(model: TimeRequestModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            if let request = model.request, let child = model.child {
                VStack(spacing: KinSpace.lg) {
                    AvatarView(child.avatar, size: 84, ring: KinColor.brand.opacity(0.3))
                    VStack(spacing: KinSpace.xs) {
                        Text("\(child.name) is asking for \(request.option.title)").font(.kinTitle).multilineTextAlignment(.center)
                        if let app = request.appName {
                            Text("To keep using \(app)").font(.kinSubheadline).foregroundStyle(KinColor.textSecondary)
                        }
                        Text(KinFormat.relative(request.createdAt)).font(.kinFootnote).foregroundStyle(KinColor.textTertiary)
                    }
                    if let message = request.message {
                        Text("“\(message)”")
                            .font(.kinBody.italic())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .kinCard()
                    }
                    outcomeView(child: child)
                }
                .padding(KinSpace.md)
            } else {
                StateMessageView(
                    symbol: "clock.badge.checkmark",
                    title: String(localized: "Already answered"),
                    message: String(localized: "This request is no longer waiting.")
                )
            }
        }
        .kinScreenBackground()
        .navigationTitle("Extra Time")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: model.outcome)
    }

    @ViewBuilder
    private func outcomeView(child: FamilyMember) -> some View {
        switch model.outcome {
        case let .approved(until):
            InlineBanner(.success, message: String(localized: "Approved. \(child.name)’s apps unlock until \(KinFormat.time(until))."))
            Button("Done") { dismiss() }.buttonStyle(.kinPrimary)
        case .denied:
            InlineBanner(.info, message: String(localized: "Declined. We’ll let \(child.name) know."))
            Button("Done") { dismiss() }.buttonStyle(.kinPrimary)
        case let .failed(message):
            InlineBanner(.error, message: message)
            buttons
        case nil:
            buttons
        }
    }

    private var buttons: some View {
        VStack(spacing: KinSpace.sm) {
            Button("Approve") { Task { await model.respond(approve: true) } }
                .buttonStyle(.kinPrimary)
                .accessibilityIdentifier("request.approve")
            Button("Not now") { Task { await model.respond(approve: false) } }
                .buttonStyle(.kinSecondary)
        }
        .disabled(model.isWorking)
    }
}

public import Domain
public import Observation
public import Session
public import SwiftUI
import DesignSystem
import Foundation
import KinCore

@MainActor
@Observable
public final class CheckInModel {
    public enum Phase: Equatable {
        case composing
        case sending
        case sent(CheckIn)
        case failed(String)
    }

    public var selected: CheckInKind?
    public var message = ""
    public private(set) var phase: Phase = .composing

    @ObservationIgnored private let actions: any CompanionActions
    @ObservationIgnored public let store: CompanionStore

    public init(store: CompanionStore, actions: any CompanionActions) {
        self.store = store
        self.actions = actions
    }

    public var guardianName: String {
        store.dashboard?.guardianName ?? String(localized: "your family")
    }

    public func send() async {
        guard let selected else {
            phase = .failed(String(localized: "Pick how you’re doing first."))
            return
        }
        phase = .sending
        do {
            let checkIn = try await actions.sendCheckIn(selected, message: TimeRequestPolicy.normalizedMessage(message))
            phase = .sent(checkIn)
            message = ""
        } catch {
            phase = .failed((error as? KinError)?.errorDescription ?? error.localizedDescription)
        }
    }

    public func reset() {
        selected = nil
        phase = .composing
    }
}

public struct CheckInView: View {
    @State private var model: CheckInModel

    public init(model: CheckInModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KinSpace.lg) {
                HStack(spacing: KinSpace.md) {
                    Image(systemName: "ellipsis.message.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(KinColor.info.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check In").font(.kinTitle)
                        Text("Let your family know how you’re doing. It only takes a few seconds.").font(.kinSubheadline)
                            .foregroundStyle(KinColor.textSecondary)
                    }
                }
                .kinCard()
                if case let .sent(checkIn) = model.phase {
                    sent(checkIn)
                } else {
                    form
                }
            }
            .padding(KinSpace.md)
            .animation(.smooth, value: model.phase)
        }
        .scrollDismissesKeyboard(.interactively)
        .kinScreenBackground()
        .navigationTitle("Check In")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(trigger: model.phase) { _, new in
            if case .sent = new {
                return .success
            }
            if case .failed = new {
                return .error
            }
            return nil
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: KinSpace.md) {
            Text("Quick Check-In").font(.kinSection)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: KinSpace.sm), GridItem(.flexible())], spacing: KinSpace.sm) {
                ForEach(CheckInKind.allCases) { kind in
                    CheckInTile(kind: kind, isSelected: model.selected == kind) { model.selected = kind }
                }
            }
            .sensoryFeedback(.selection, trigger: model.selected)
            Text("Add a message (optional)").font(.kinHeadline)
            CountedTextEditor(
                text: $model.message,
                placeholder: String(localized: "Anything else you want to share?"),
                limit: TimeRequestPolicy.maxMessageLength
            )
            if case let .failed(message) = model.phase {
                InlineBanner(.error, message: message)
            }
            Button {
                Task { await model.send() }
            } label: {
                if model.phase == .sending {
                    ProgressView().tint(.white)
                } else {
                    Text("Send Check-In")
                }
            }
            .buttonStyle(KinPrimaryButtonStyle(role: model.selected == .needHelp ? .danger : .brand))
            .disabled(model.selected == nil || model.phase == .sending)
            .accessibilityIdentifier("checkin.send")
        }
    }

    private func sent(_ checkIn: CheckIn) -> some View {
        VStack(spacing: KinSpace.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(KinColor.success)
                .symbolEffect(.bounce, value: checkIn.id)
            Text("Check-in sent").font(.kinTitle)
            Text("\(model.guardianName) will see “\(checkIn.kind.title)” right away.").font(.kinSubheadline)
                .foregroundStyle(KinColor.textSecondary).multilineTextAlignment(.center)
            Button("Done") { model.reset() }.buttonStyle(.kinSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(KinSpace.xl)
        .kinCard()
        .accessibilityIdentifier("checkin.sent")
    }
}

struct CheckInTile: View {
    let kind: CheckInKind
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: kind.symbol).font(.system(size: 30, weight: .semibold)).foregroundStyle(tint)
                Text(kind.title).font(.kinHeadline).foregroundStyle(KinColor.textPrimary)
                Text(kind.subtitle).font(.kinCaption).foregroundStyle(KinColor.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 112)
            .background(tint.opacity(isSelected ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: KinRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: KinRadius.lg, style: .continuous).strokeBorder(isSelected ? tint : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.kinPressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("checkin.\(kind.rawValue)")
    }

    private var tint: Color {
        switch kind {
        case .imOK: KinColor.success
        case .pickedUp, .onMyWay: KinColor.info
        case .needHelp: KinColor.danger
        }
    }
}

public import Domain
public import Observation
public import Session
public import SwiftUI
import DesignSystem
import Foundation
import KinCore

@MainActor
@Observable
public final class SOSModel {
    public enum Phase: Equatable {
        case idle
        case sending
        case sent(SOSEvent)
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    @ObservationIgnored private let actions: any CompanionActions
    @ObservationIgnored public let store: CompanionStore

    public init(store: CompanionStore, actions: any CompanionActions) {
        self.store = store
        self.actions = actions
    }

    public func send() async {
        guard phase != .sending else { return }
        phase = .sending
        do {
            phase = try await .sent(actions.sendSOS())
        } catch {
            phase = .failed((error as? KinError)?.errorDescription ?? error.localizedDescription)
        }
    }

    public func reset() {
        phase = .idle
    }
}

/// Hold-to-send SOS. A deliberate 3-second hold prevents pocket dials; VoiceOver users get an explicit
/// "Send SOS" action with a confirmation instead of a gesture they can't perform reliably.
public struct SOSView: View {
    @State private var model: SOSModel
    @State private var isPressing = false
    @State private var confirmsAccessibleSend = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public static let holdDuration: Double = 3

    public init(model: SOSModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        VStack(spacing: KinSpace.xl) {
            Spacer()
            switch model.phase {
            case let .sent(event):
                sent(event)
            default:
                prompt
            }
            Spacer()
        }
        .padding(KinSpace.lg)
        .frame(maxWidth: .infinity)
        .kinScreenBackground()
        .navigationTitle("SOS")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.warning, trigger: isPressing) { _, new in new }
        .sensoryFeedback(trigger: model.phase) { _, new in
            if case .sent = new {
                return .success
            }
            return nil
        }
        .confirmationDialog("Send SOS to your family?", isPresented: $confirmsAccessibleSend, titleVisibility: .visible) {
            Button("Send SOS", role: .destructive) { Task { await model.send() } }
        }
    }

    private var prompt: some View {
        VStack(spacing: KinSpace.lg) {
            Text("Hold the button for 3 seconds").font(.kinTitle).multilineTextAlignment(.center)
            Text("Your family gets an urgent alert with your live location and battery level.")
                .font(.kinSubheadline)
                .foregroundStyle(KinColor.textSecondary)
                .multilineTextAlignment(.center)
            ZStack {
                Circle().fill(KinColor.danger.opacity(0.12)).frame(width: 240, height: 240)
                Circle()
                    .trim(from: 0, to: isPressing ? 1 : 0)
                    .stroke(KinColor.danger, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 226, height: 226)
                    .animation(isPressing ? .linear(duration: Self.holdDuration) : .easeOut(duration: 0.2), value: isPressing)
                Circle()
                    .fill(KinColor.danger.gradient)
                    .frame(width: 190, height: 190)
                    .scaleEffect(isPressing && !reduceMotion ? 0.94 : 1)
                    .shadow(color: KinColor.danger.opacity(0.4), radius: 20, y: 8)
                    .overlay {
                        if model.phase == .sending {
                            ProgressView().tint(.white).controlSize(.large)
                        } else {
                            VStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40, weight: .bold))
                                Text("SOS").font(.system(.largeTitle, design: .rounded).weight(.heavy))
                            }
                            .foregroundStyle(.white)
                        }
                    }
            }
            .onLongPressGesture(minimumDuration: Self.holdDuration) {
                Task { await model.send() }
            } onPressingChanged: { pressing in
                isPressing = pressing
            }
            .accessibilityElement()
            .accessibilityLabel("SOS")
            .accessibilityHint("Sends an urgent alert to your family")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { confirmsAccessibleSend = true }
            .accessibilityIdentifier("sos.button")
            if case let .failed(message) = model.phase {
                InlineBanner(.error, message: message)
            }
            Label("If you’re in danger, call 911", systemImage: "phone.fill").font(.kinFootnote).foregroundStyle(KinColor.textSecondary)
        }
    }

    private func sent(_ event: SOSEvent) -> some View {
        VStack(spacing: KinSpace.md) {
            Image(systemName: "checkmark.shield.fill").font(.system(size: 64)).foregroundStyle(KinColor.success)
            Text("SOS sent").font(.kinLargeTitle)
            Text(
                "\(model.store.dashboard?.guardianName ?? String(localized: "Your family")) has your location. Stay where you are if it’s safe."
            )
            .font(.kinBody)
            .foregroundStyle(KinColor.textSecondary)
            .multilineTextAlignment(.center)
            Text("Sent at \(KinFormat.time(event.createdAt))").font(.kinFootnote).foregroundStyle(KinColor.textTertiary)
            Button("I’m safe now") { model.reset() }.buttonStyle(.kinSecondary)
        }
        .accessibilityIdentifier("sos.sent")
    }
}

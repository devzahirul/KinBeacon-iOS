public import SwiftUI
import DesignSystem
import Domain
import UIKit

public struct OnboardingView: View {
    @State private var model: OnboardingModel

    public init(model: OnboardingModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack(path: $model.path) {
            WelcomeStep(model: model)
                .navigationDestination(for: OnboardingModel.Step.self) { step in
                    switch step {
                    case .welcome: WelcomeStep(model: model)
                    case .parentAccount: ParentAccountStep(model: model)
                    case .familyName: FamilyNameStep(model: model)
                    case .pairing: PairingStep(model: model)
                    case .demoRole: DemoRoleStep(model: model)
                    case let .permission(kind): PermissionStep(model: model, kind: kind)
                    }
                }
        }
        .tint(KinColor.brand)
    }
}

struct WelcomeStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: KinSpace.lg) {
            Spacer()
            ShieldGlyph(symbol: "location.fill", tint: KinColor.brand, size: 96)
            VStack(spacing: KinSpace.xs) {
                Text("KinBeacon").font(.kinLargeTitle)
                Text("Peace of mind for the whole family").font(.kinBody).foregroundStyle(KinColor.textSecondary)
            }
            VStack(alignment: .leading, spacing: KinSpace.md) {
                feature(
                    "map.fill",
                    String(localized: "Live location"),
                    String(localized: "See where everyone is, with arrival alerts for school and home.")
                )
                feature(
                    "graduationcap.fill",
                    String(localized: "School Mode"),
                    String(localized: "Focus during class with Apple’s Screen Time protections.")
                )
                feature(
                    "bell.badge.fill",
                    String(localized: "Check-ins & SOS"),
                    String(localized: "One tap to say “I’m OK” — or to get help fast.")
                )
            }
            .padding(.vertical, KinSpace.md)
            Spacer()
            VStack(spacing: KinSpace.sm) {
                Button("I’m a parent") { model.choose(.parent) }
                    .buttonStyle(.kinPrimary)
                    .accessibilityIdentifier("onboarding.parent")
                Button("This is my child’s device") { model.choose(.child) }
                    .buttonStyle(.kinSecondary)
                    .accessibilityIdentifier("onboarding.child")
                if model.supportsAccounts {
                    Button("Try the demo — no account needed") { model.chooseDemo() }
                        .font(.kinSubheadline.weight(.semibold))
                        .padding(.top, KinSpace.xs)
                        .accessibilityIdentifier("onboarding.demo")
                } else {
                    Text("Demo build: a simulated family, no account needed.").font(.kinCaption).foregroundStyle(KinColor.textTertiary)
                }
            }
        }
        .padding(KinSpace.lg)
        .kinScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func feature(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: KinSpace.md) {
            IconBadge(symbol, tint: KinColor.brand, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.kinHeadline)
                Text(subtitle).font(.kinSubheadline).foregroundStyle(KinColor.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct FamilyNameStep: View {
    @Bindable var model: OnboardingModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KinSpace.lg) {
            Text("Name your family").font(.kinLargeTitle)
            Text("This is what your children see when they join.").foregroundStyle(KinColor.textSecondary)
            TextField("Family name", text: $model.familyName)
                .font(.kinTitle)
                .textInputAutocapitalization(.words)
                .submitLabel(.continue)
                .focused($focused)
                .padding(KinSpace.md)
                .background(KinColor.surface, in: RoundedRectangle(cornerRadius: KinRadius.md))
                .onSubmit { Task { await model.submitFamilyName() } }
            VStack(alignment: .leading, spacing: KinSpace.xs) {
                Text("Your children will see you as").font(.kinSubheadline).foregroundStyle(KinColor.textSecondary)
                Picker("Relationship", selection: $model.relationship) {
                    ForEach(OnboardingModel.relationships, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if let error = model.errorMessage {
                InlineBanner(.error, message: error)
            }
            Spacer()
            Button {
                Task { await model.submitFamilyName() }
            } label: {
                if model.isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text("Continue")
                }
            }
            .buttonStyle(.kinPrimary)
            .disabled(model.familyName.trimmingCharacters(in: .whitespaces).isEmpty || model.isWorking)
            .accessibilityIdentifier("onboarding.continue")
        }
        .padding(KinSpace.lg)
        .kinScreenBackground()
        .onAppear { focused = true }
    }
}

/// Parent account: create or sign in (email + password; Supabase Auth).
struct ParentAccountStep: View {
    @Bindable var model: OnboardingModel
    @FocusState private var field: Field?

    enum Field { case name, email, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KinSpace.lg) {
                Text(model.isCreatingAccount ? "Create your parent account" : "Welcome back").font(.kinLargeTitle)
                Picker("Mode", selection: $model.isCreatingAccount) {
                    Text("Create account").tag(true)
                    Text("Sign in").tag(false)
                }
                .pickerStyle(.segmented)
                VStack(spacing: KinSpace.sm) {
                    if model.isCreatingAccount {
                        field("Your name", text: $model.parentName, content: .name, focus: .name)
                            .textInputAutocapitalization(.words)
                    }
                    field("Email", text: $model.email, content: .emailAddress, focus: .email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password (8+ characters)", text: $model.password)
                        .textContentType(.password)
                        .focused($field, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await model.submitAccount() } }
                        .padding(KinSpace.md)
                        .background(KinColor.surface, in: RoundedRectangle(cornerRadius: KinRadius.md))
                        .accessibilityIdentifier("onboarding.password")
                }
                if let error = model.errorMessage {
                    InlineBanner(.error, message: error)
                }
                Button {
                    field = nil
                    Task { await model.submitAccount() }
                } label: {
                    if model.isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text(model.isCreatingAccount ? "Create account" : "Sign in")
                    }
                }
                .buttonStyle(.kinPrimary)
                .disabled(model.isWorking)
                .accessibilityIdentifier("onboarding.submitAccount")
                Text(
                    """
                    Your family’s data is private to your family and protected by row-level security. You can \
                    delete your account anytime in Settings.
                    """
                )
                .font(.kinFootnote)
                .foregroundStyle(KinColor.textSecondary)
            }
            .padding(KinSpace.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .kinScreenBackground()
        .onAppear { field = model.isCreatingAccount ? .name : .email }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>, content: UITextContentType, focus: Field) -> some View {
        TextField(title, text: text)
            .textContentType(content)
            .focused($field, equals: focus)
            .submitLabel(.next)
            .padding(KinSpace.md)
            .background(KinColor.surface, in: RoundedRectangle(cornerRadius: KinRadius.md))
    }
}

/// "Try the demo": pick which side of the simulated family to explore.
struct DemoRoleStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: KinSpace.lg) {
            Text("Explore the demo").font(.kinLargeTitle)
            Text("A simulated family runs on this device — nothing is shared and no permissions are needed.")
                .foregroundStyle(KinColor.textSecondary)
            Button { model.startDemo(as: .parent) } label: {
                StatusRow(
                    symbol: "person.fill",
                    tint: KinColor.brand,
                    title: String(localized: "Parent’s view"),
                    subtitle: String(localized: "Family map, School Mode controls, activity and alerts")
                )
            }
            .buttonStyle(.kinPressable)
            .kinCard()
            .accessibilityIdentifier("onboarding.demoParent")
            Button { model.startDemo(as: .child) } label: {
                StatusRow(
                    symbol: "figure.child",
                    tint: KinColor.info,
                    title: String(localized: "Child’s view"),
                    subtitle: String(localized: "Check-ins, extra-time requests, SOS and help")
                )
            }
            .buttonStyle(.kinPressable)
            .kinCard()
            .accessibilityIdentifier("onboarding.demoChild")
            Spacer()
        }
        .padding(KinSpace.lg)
        .kinScreenBackground()
    }
}

struct PairingStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: KinSpace.lg) {
            Text("Join your family").font(.kinLargeTitle)
            Text("Ask your parent to open KinBeacon › Family › Add a child’s device, then enter the code.")
                .foregroundStyle(KinColor.textSecondary)
            TextField("123 456", text: $model.pairingCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .multilineTextAlignment(.center)
                .padding(KinSpace.md)
                .background(KinColor.surface, in: RoundedRectangle(cornerRadius: KinRadius.md))
                .accessibilityIdentifier("onboarding.code")
            if let error = model.errorMessage {
                InlineBanner(.error, message: error)
            }
            if model.isDemo {
                Button("Use demo code") { model.pairingCode = "482913" }.font(.kinSubheadline)
            }
            Spacer()
            Button {
                Task { await model.submitPairingCode() }
            } label: {
                if model.isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text("Join")
                }
            }
            .buttonStyle(.kinPrimary)
            .disabled(!model.isPairingCodeComplete || model.isWorking)
            .accessibilityIdentifier("onboarding.join")
        }
        .padding(KinSpace.lg)
        .kinScreenBackground()
    }
}

struct PermissionStep: View {
    let model: OnboardingModel
    let kind: PermissionKind

    var body: some View {
        VStack(spacing: KinSpace.lg) {
            Spacer()
            Image(systemName: kind.symbol)
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 112, height: 112)
                .background(KinColor.brand.gradient, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            Text(title).font(.kinLargeTitle).multilineTextAlignment(.center)
            Text(kind.rationale).font(.kinBody).foregroundStyle(KinColor.textSecondary).multilineTextAlignment(.center)
            Spacer()
            Button {
                Task { await model.request(kind) }
            } label: {
                if model.isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text("Continue")
                }
            }
            .buttonStyle(.kinPrimary)
            .accessibilityIdentifier("onboarding.allow")
            Button("Not now") { model.skip(kind) }
                .font(.kinSubheadline)
                .foregroundStyle(KinColor.textSecondary)
        }
        .padding(KinSpace.lg)
        .kinScreenBackground()
    }

    private var title: String {
        switch kind {
        case .location: String(localized: "Share your location with family")
        case .notifications: String(localized: "Get the alerts that matter")
        case .screenTime: String(localized: "Turn on School Mode")
        case .backgroundRefresh: String(localized: "Stay up to date")
        }
    }
}

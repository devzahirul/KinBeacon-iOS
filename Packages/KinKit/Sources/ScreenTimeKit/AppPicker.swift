#if canImport(FamilyControls) && os(iOS)
    public import Domain
    public import SwiftUI
    import FamilyControls
    import Foundation

    /// Apple's privacy-preserving app picker. The selection comes back as opaque tokens — the app never learns which
    /// apps are installed — which we persist as encoded data inside `AppSelection`.
    public struct SystemAppPicker: View {
        @Binding private var selection: AppSelection
        @State private var familySelection: FamilyActivitySelection

        public init(selection: Binding<AppSelection>) {
            _selection = selection
            let decoded = selection.wrappedValue.familyActivitySelection.flatMap { try? JSONDecoder().decode(
                FamilyActivitySelection.self,
                from: $0
            ) }
            _familySelection = State(initialValue: decoded ?? FamilyActivitySelection())
        }

        public var body: some View {
            FamilyActivityPicker(selection: $familySelection)
                .onChange(of: familySelection) { _, newValue in
                    selection.familyActivitySelection = try? JSONEncoder().encode(newValue)
                }
        }
    }
#endif

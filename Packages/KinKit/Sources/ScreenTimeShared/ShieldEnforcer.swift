#if canImport(ManagedSettings) && os(iOS)
    public import Foundation
    import Domain
    import FamilyControls
    import KinCore
    import ManagedSettings

    /// Applies or clears shields for a policy. Shared by the app (immediate apply after a change) and the
    /// DeviceActivityMonitor extension (schedule boundaries while the app isn't running), so both make the identical
    /// decision from the identical `SharedPolicy`.
    ///
    /// Each mode writes to its own named `ManagedSettingsStore`. Stores are additive and persist across reboots, so
    /// clearing one mode can never accidentally lift another mode's restrictions.
    public struct ShieldEnforcer: Sendable {
        public init() {}

        public func enforce(_ policy: SharedPolicy?, at date: Date, calendar: Calendar = .current) {
            guard let policy else {
                clearAll()
                return
            }
            let active = policy.activeMode(at: date, calendar: calendar)
            for kind in ControlModeKind.allCases {
                let store = Self.store(for: kind)
                guard let active, active.kind == kind, !active.isPaused(at: date), let mode = policy.configuration.mode(kind) else {
                    store.clearAllSettings()
                    continue
                }
                apply(mode, configuration: policy.configuration, deviceAllowedApps: policy.deviceAllowedApps, to: store)
            }
        }

        public func clearAll() {
            ControlModeKind.allCases.forEach { Self.store(for: $0).clearAllSettings() }
        }

        /// Allow-list enforcement: every app category is shielded except the mode's allowed apps and the
        /// "Always Allowed" set. Allow-lists fail closed — a newly installed game is blocked by default.
        private func apply(
            _ mode: ModeSettings,
            configuration: ControlsConfiguration,
            deviceAllowedApps: AppSelection?,
            to store: ManagedSettingsStore
        ) {
            let allowed = Self.tokens(mode.allowedApps)
                .union(Self.tokens(configuration.alwaysAllowed))
                .union(Self.tokens(deviceAllowedApps ?? AppSelection()))
            store.shield.applicationCategories = .all(except: allowed)
            store.shield.webDomainCategories = .all()
            switch configuration.webFilter {
            case .off: store.webContent.blockedByFilter = nil
            case .limitAdultWebsites: store.webContent.blockedByFilter = .auto()
            case .allowedWebsitesOnly: store.webContent.blockedByFilter = .specific([])
            }
            // A child can't delete the app (and its protections) while a mode is active.
            store.application.denyAppRemoval = true
        }

        static func store(for kind: ControlModeKind) -> ManagedSettingsStore {
            ManagedSettingsStore(named: ManagedSettingsStore.Name(ActivityNames.store(for: kind)))
        }

        static func tokens(_ selection: AppSelection) -> Set<ApplicationToken> {
            guard let data = selection.familyActivitySelection,
                  let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return [] }
            return decoded.applicationTokens
        }
    }
#endif

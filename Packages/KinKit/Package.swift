// swift-tools-version: 6.0
//
// KinKit — every line of product code lives here. The app target and the four Screen Time extensions are thin shells.
//
// Layering (arrows = "depends on"; nothing points upward, features never import each other):
//
//   AppFeature ─┬─► *Feature ──► Routing · Session ─► DesignSystem ─► Domain ─► KinCore
//               ├─► LocationKit · ScreenTimeKit · Messaging · Permissions · SyncEngine   (platform adapters)
//               ├─► KinStore (SwiftData) · SupabaseBackend · Networking (URLSession) · DemoBackend (data adapters)
//               └─► ScreenTimeShared ◄── Screen Time extensions (Monitor / Shield / ShieldAction / Report)
//
// • `Domain` is pure Swift: models, policies and the service protocols every adapter implements. All business rules
//   (schedules, upload policy, permission health, command verification, …) are unit-tested there without a simulator.
// • Platform frameworks (CoreLocation, FamilyControls, UserNotifications, SwiftData) are each confined to ONE module,
//   so a framework migration (e.g. MapKit → Google Maps, APNs → FCM) touches a single module.
// • Extensions link only `ScreenTimeShared` (+ Domain/KinCore): DeviceActivityMonitor extensions run under a ~6 MB
//   memory ceiling, so they must never pull in SwiftUI feature code or SwiftData.

import PackageDescription

let strictSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    // Zero-warning policy for our own code.
    .unsafeFlags(["-warnings-as-errors"]),
]

extension Target {
    static func module(_ name: String, dependencies: [Target.Dependency] = []) -> Target {
        .target(name: name, dependencies: dependencies, swiftSettings: strictSettings)
    }

    static func feature(_ name: String, extra: [Target.Dependency] = []) -> Target {
        .module(name, dependencies: ["KinCore", "Domain", "DesignSystem", "Routing", "Session"] + extra)
    }

    static func tests(_ name: String, dependencies: [Target.Dependency]) -> Target {
        .testTarget(name: name, dependencies: dependencies + ["TestSupport"], swiftSettings: strictSettings)
    }
}

let features = [
    "OnboardingFeature", "FamilyMapFeature", "ChildProfileFeature", "ControlsFeature", "ParentActivityFeature",
    "FamilyFeature", "AlertsFeature", "ChildHomeFeature", "RequestTimeFeature", "CheckInFeature",
    "ChildActivityFeature", "HelpFeature", "SettingsFeature",
]

let package = Package(
    name: "KinKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AppFeature", targets: ["AppFeature"]),
        .library(name: "ScreenTimeShared", targets: ["ScreenTimeShared"]),
        // Linked by the app-hosted unit-test bundle so the package tests also run on a physical iPhone.
        .library(name: "KinKitTesting", targets: [
            "KinCore", "Domain", "ScreenTimeShared", "KinStore", "Networking", "DemoBackend", "SupabaseBackend", "SyncEngine",
            "LocationKit", "ScreenTimeKit", "Messaging", "Permissions", "DesignSystem", "Routing", "Session",
            "TestSupport",
        ] + features),
    ],
    dependencies: [
        // The only third-party dependency, confined to the SupabaseBackend module.
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.55.0"),
    ],
    targets: [
        // MARK: Core

        .module("KinCore"),
        .module("Domain", dependencies: ["KinCore"]),
        .module("ScreenTimeShared", dependencies: ["KinCore", "Domain"]),

        // MARK: Data adapters

        .module("KinStore", dependencies: ["KinCore", "Domain"]),
        .module("Networking", dependencies: ["KinCore", "Domain"]),
        .module("DemoBackend", dependencies: ["KinCore", "Domain"]),
        .target(
            name: "SupabaseBackend",
            dependencies: [
                "KinCore", "Domain",
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            swiftSettings: strictSettings
        ),
        .module("SyncEngine", dependencies: ["KinCore", "Domain"]),

        // MARK: Platform adapters

        .module("LocationKit", dependencies: ["KinCore", "Domain"]),
        .module("ScreenTimeKit", dependencies: ["KinCore", "Domain", "ScreenTimeShared"]),
        .module("Messaging", dependencies: ["KinCore", "Domain"]),
        .module("Permissions", dependencies: ["KinCore", "Domain"]),

        // MARK: UI foundation

        .module("DesignSystem", dependencies: ["KinCore", "Domain"]),
        .module("Routing", dependencies: ["KinCore", "Domain", "DesignSystem"]),
        // Shared observable app state (family snapshot, child dashboard) consumed by several features.
        .module("Session", dependencies: ["KinCore", "Domain"]),

        // MARK: Features

        .feature("OnboardingFeature"),
        .feature("FamilyMapFeature"),
        .feature("ChildProfileFeature"),
        .feature("ControlsFeature"),
        .feature("ParentActivityFeature"),
        .feature("FamilyFeature"),
        .feature("AlertsFeature"),
        .feature("ChildHomeFeature", extra: ["ScreenTimeShared"]),
        .feature("RequestTimeFeature"),
        .feature("CheckInFeature"),
        .feature("ChildActivityFeature"),
        .feature("HelpFeature"),
        .feature("SettingsFeature"),

        // MARK: Composition root

        .module("AppFeature", dependencies: [
            "KinCore", "Domain", "DesignSystem", "Routing", "Session", "ScreenTimeShared",
            "KinStore", "Networking", "DemoBackend", "SupabaseBackend", "SyncEngine",
            "LocationKit", "ScreenTimeKit", "Messaging", "Permissions",
        ] + features.map { Target.Dependency(stringLiteral: $0) }),

        // MARK: Tests

        .module("TestSupport", dependencies: ["KinCore", "Domain"]),
        .tests("DomainTests", dependencies: ["Domain", "KinCore"]),
        .tests("DataTests", dependencies: ["Domain", "KinCore", "KinStore", "Networking", "DemoBackend", "SyncEngine", "SupabaseBackend"]),
        .tests("PlatformTests", dependencies: ["Domain", "KinCore", "Messaging", "ScreenTimeShared", "LocationKit"]),
        .tests("FeatureTests", dependencies: [
            "Domain", "KinCore", "Routing", "Session", "DemoBackend",
            "ControlsFeature", "RequestTimeFeature", "CheckInFeature", "ChildHomeFeature", "FamilyMapFeature",
            "AlertsFeature", "ParentActivityFeature", "OnboardingFeature", "HelpFeature",
        ]),
    ]
)

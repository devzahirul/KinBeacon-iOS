public import os

/// Structured logging with one `Logger` per subsystem area.
///
/// `os.Logger` is used instead of `print` because it is near-free when a level is disabled, redacts dynamic values by
/// default (`privacy: .private`), and shows up in Console.app / `log stream` with the category as a filter:
///
///     xcrun simctl spawn booted log stream --level debug --predicate 'subsystem == "com.lynkto.kinbeacon"'
///
/// Coordinates and member names are always logged as `.private` — a family-safety app must never leak a child's
/// location into a sysdiagnose.
public enum Log {
    public static let subsystem = "com.lynkto.kinbeacon"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let launch = Logger(subsystem: subsystem, category: "launch")
    public static let location = Logger(subsystem: subsystem, category: "location")
    public static let screenTime = Logger(subsystem: subsystem, category: "screentime")
    public static let push = Logger(subsystem: subsystem, category: "push")
    public static let sync = Logger(subsystem: subsystem, category: "sync")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let storage = Logger(subsystem: subsystem, category: "storage")
    public static let background = Logger(subsystem: subsystem, category: "background")
    public static let permissions = Logger(subsystem: subsystem, category: "permissions")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}

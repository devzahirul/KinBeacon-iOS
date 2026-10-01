# Performance playbook

How KinBeacon's performance is measured, where the hooks are, and the exact commands to reproduce every number in
the README. Rule of the project: **no performance claim without a measurement from a real device.**

## 1. Measured baseline (iPhone 13, iOS 26.7, Release)

| Metric | Value | How |
|---|---|---|
| Cold launch → first frame, parent role | **442 ms** avg (404–506 ms, 5 runs, RSD 7.9 %) | `make perf` (`XCTApplicationLaunchMetric`) |
| Cold launch → first frame, child role | **400 ms** avg (353–444 ms, 5 runs, RSD 9.6 %) | `make perf` |
| Embedded dynamic frameworks | **0** | `otool -L KinBeacon.app/KinBeacon` |
| `.app` size (uncompressed, unthinned) | 14 MB; each Screen Time extension 1.8 MB, report extension 160 KB | `du -sh` on the Release product |
| Incremental Debug build after editing a feature file | 3.7 s (Apple M1) | `scripts`-style timing, see §6 |
| Incremental Debug build after a body-only edit in `Domain` | 4.0 s | dependents are not recompiled when the module interface is unchanged |
| Unit test suite | 100 tests / 20 suites in 0.54 s, on device | `make test-unit` |

Apple's guidance is "first frame within 400 ms" on the oldest supported device. The child role meets it and the parent
role is ~10 % over, because it builds the MapKit scene on the first frame. That is the next optimisation target (see §7).

## 2. Signposts (Instruments → Points of Interest / os_signpost)

All intervals use `Perf` (`OSSignposter`, category `.pointsOfInterest`) and are **compiled into Release** on purpose,
so a TestFlight build can be profiled with real data.

| Signpost | Where | What it tells you |
|---|---|---|
| `launch.delegate` | `KinAppDelegate.init` | composition-root construction (UserDefaults + launch args only) |
| `launch.container` / `launch.runtime` | `AppContainer` | building the role's object graph (no I/O allowed here) |
| `launch.didFinishLaunching` | app delegate | notification categories + APNs registration |
| `launch.firstFrame` (event) | `KinRootView.onAppear` | the frame users see |
| `storage.open` | `DeferredDatabase` | SwiftData `ModelContainer` creation, **off the main thread, after first frame** |
| `sync.flush` | `SyncEngine.drain` | outbox flush duration (one radio wake-up) |
| `network.request` | `APIClient.perform` | per-request latency |

Record a launch:

```bash
xcrun xctrace record --template 'App Launch' --device <udid> --launch -- com.lynkto.kinbeacon
```

## 3. Instruments templates used

| Problem | Template | What to look for |
|---|---|---|
| Slow launch | **App Launch** | time before `launch.firstFrame`; dyld time (should be tiny — 0 dylibs) |
| Main-thread CPU | **Time Profiler** (with "Hide system libraries") | anything > 2 ms on main during scroll / map pan |
| Janky SwiftUI | **SwiftUI** template → *View Body* + *View Properties* | bodies re-evaluating on every location tick |
| Hitches | **Animation Hitches** | commit/render hitches while the member card animates |
| Memory | **Allocations** + **Leaks**, Xcode **Memory Graph** | retain cycles in long-lived runtimes / stores |
| Battery | **Power Profiler** (device) / Xcode Organizer → Energy | GPS time, cellular wake-ups while the child app is backgrounded |
| Extensions | Allocations attached to `KinBeaconMonitor` | DeviceActivityMonitor has a ~6 MB ceiling |

## 4. Field data

`MetricsReporter` subscribes to **MetricKit** (`MXMetricManager`) and logs launch histograms, hang-rate histograms and
crash/hang diagnostics. Production would forward the payloads to the backend; Xcode Organizer shows the same data for
App Store builds (Launch Time, Hangs, Energy, Disk Writes).

Live logs (coordinates are `.private`):

```bash
# device: Console.app, filter subsystem:com.lynkto.kinbeacon
xcrun simctl spawn booted log stream --level debug --predicate 'subsystem == "com.lynkto.kinbeacon"'
```

## 5. Background & push debugging

```bash
# Fire the BGAppRefresh handler immediately (pause the app in lldb first):
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.lynkto.kinbeacon.refresh"]

# Deliver a silent remote command to a simulator:
xcrun simctl push booted com.lynkto.kinbeacon payload.json   # payload format: docs/API.md

# Location: Xcode → Debug → Simulate Location (GPX), or Settings → Developer → Location on device.
# Network: Settings → Developer → Network Link Conditioner ("Very Bad Network") to watch the outbox retry.
```

## 6. Build-time hygiene

- 29 SPM modules. Features never import each other, so editing a screen recompiles one module and relinks.
- `InternalImportsByDefault`: a module's dependencies don't leak into its clients' interfaces, so fewer modules
  rebuild when an implementation detail changes.
- Find slow type-checking: add `-Xfrontend -warn-long-expression-type-checking=150` to `OTHER_SWIFT_FLAGS` (Debug).
  It caught one >1 s expression in a test, which was split into typed sub-expressions.
- Measure: Xcode → Product → Perform Action → *Build With Timing Summary*, or `xcodebuild -showBuildTimingSummary`.

## 7. What made it fast, and what's next

Done:
1. Nothing heavy in `init`: the container reads three `UserDefaults` keys. Services are built per role and started from
   `.task {}` **after** the first frame.
2. SwiftData is opened on a detached utility task (`DeferredDatabase`) in parallel with the first frame. Callers await it
   only if they need it.
3. Zero third-party code and static linking, so there is no dyld work beyond system libraries.
4. Vector avatars and app tiles (emoji + gradient, SF Symbols): no image decoding on the map's critical path.
5. `@Observable` property-level tracking. A location tick re-renders only views that read `snapshot`. Map pins are
   `Equatable` value views.
6. `FamilyStore` holds one backend subscription that fans out to every screen (`Broadcaster`), not one per screen.

Next:
- Parent cold launch: render the member card with a cached snapshot and defer `Map` creation by one frame
  (placeholder tiles) to bring it under 400 ms.
- Ship a baseline file for `LaunchPerformanceTests`, so CI fails on a >10 % regression.

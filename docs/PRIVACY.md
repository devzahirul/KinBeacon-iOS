# KinBeacon privacy summary

KinBeacon is a family-safety app. It processes sensitive data — a child's location and app-usage limits — so the
design rule is **collect the minimum, keep it the shortest, share it only inside the family**.

| Data | Why | Where it lives | Retention |
|---|---|---|---|
| Precise location | live map, arrival/leave alerts, SOS | device (SwiftData) + family server | 30 days, then deleted on device (`pruneHistory`) and server |
| Check-ins, SOS, extra-time requests + optional messages | the feature itself | device outbox → server | 90 days |
| Permission health (on/off flags only) | tamper alerts for parents | server | latest value only |
| Battery level | "location may stop updating" warnings | server | latest value only |
| Screen-time usage | parent reports | **never leaves Apple's DeviceActivityReport extension sandbox** | n/a |
| App identities chosen in the picker | School Mode allow-list | opaque `ApplicationToken`s on device | until changed |

- No advertising SDKs, no analytics SDKs, no tracking (`NSPrivacyTracking = false` in `PrivacyInfo.xcprivacy`).
- Logs mark coordinates and names `.private`; they never appear in sysdiagnoses.
- Remote commands are signed per device; a leaked push credential cannot unlock a child's apps.
- Permissions are requested one at a time, after an explanation screen, never at first launch.

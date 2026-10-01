# KinBeacon HTTP API contract

The production adapter (`Packages/KinKit/Sources/Networking/RESTBackend.swift`) speaks this contract. The demo
backend (`DemoBackend`) implements the same Swift protocols in-process, so the app runs without a server.

Conventions
- JSON, `snake_case` keys, ISO-8601 dates. `Authorization: Bearer <device token>` on every call.
- Every POST that creates something carries `Idempotency-Key` (the entity's UUID) — the client's outbox retries
  safely; the server must return the original result for a repeated key.
- `401/403` → device must re-pair. `429` and `5xx` are retried with capped, jittered exponential backoff.

## Parent device

| Method | Path | Body / query | Response |
|---|---|---|---|
| GET | `/v1/family` | – | `FamilySnapshot` |
| GET | `/v1/family/stream` | `Accept: text/event-stream` | SSE: `snapshot`, `timeRequest`, `checkIn`, `alert`, `activity` |
| GET | `/v1/children/{id}/controls` | – | `ControlsConfiguration` |
| PUT | `/v1/children/{id}/controls` | `ControlsConfiguration` | saved configuration with new `revision` |
| GET | `/v1/requests?status=pending` | – | `[TimeRequest]` |
| POST | `/v1/requests/{id}/response` | `{ "approve": true }` | `TimeRequest` |
| POST | `/v1/children/{id}/commands` | `RemoteCommand.Action` | 202 — server signs and delivers via APNs |
| POST | `/v1/alerts/{id}/resolve` | – | 204 |
| GET | `/v1/members/{id}/screen-time` | `range=day\|week\|month&anchor=` | `ScreenTimeSummary` |
| GET | `/v1/members/{id}/activity` | `limit=` | `[ActivityEvent]` |
| GET | `/v1/members/{id}/visits` | `day=` | `[PlaceVisit]` |

## Child device

| Method | Path | Body | Notes |
|---|---|---|---|
| GET | `/v1/me/dashboard` | – | `ChildDashboard` |
| GET | `/v1/me/stream` | SSE | `dashboard`, `timeRequest` |
| GET | `/v1/me/controls` | – | applied by `ScreenTimeKit`; stale `revision`s are ignored on device |
| GET | `/v1/me/requests` | – | `[TimeRequest]` |
| GET | `/v1/me/commands` | – | missed commands; fetched by the BGAppRefresh heartbeat |
| POST | `/v1/me/locations` | `[LocationSample]` | batched + thinned on device |
| POST | `/v1/me/check-ins` | `CheckIn` | `need_help` fans out as a time-sensitive push |
| POST | `/v1/me/requests` | `TimeRequest` | |
| POST | `/v1/me/sos` | `SOSEvent` | highest outbox priority |
| PUT | `/v1/me/permissions` | `PermissionHealthReport` | server diffs → "Location permission turned off" alerts |
| PUT | `/v1/me/battery` | `BatteryState` | |

## Remote commands (APNs)

Silent push, `apns-push-type: background`, `apns-priority: 5`:

```json
{
  "aps": { "content-available": 1 },
  "kin": { "command": { "id": "…uuid…", "target": "member-emma", "action": { "locateNow": {} },
                        "issuedAt": 1790000000, "expiresAt": 1790000300, "signature": "base64 HMAC-SHA256" } }
}
```

The signature is HMAC-SHA256 over the canonical JSON (sorted keys, integer timestamps, empty signature) with the
per-device key exchanged at pairing. See `CommandAuthenticator` and its tests.

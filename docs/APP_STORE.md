# App Store submission package

Everything App Store Connect asks for, ready to paste. Items marked **(you)** need the account holder.

## Status

| Item | State |
|---|---|
| Live backend (Supabase, RLS, Realtime) | ✅ applied, 19 pgTAP RLS tests pass |
| Real accounts, family, pairing, delete account | ✅ verified on iPhone 13 by UI tests against the live backend |
| Privacy manifest, purpose strings, App Privacy answers | ✅ below |
| 6.9" screenshots (1320×2868) | ✅ `docs/appstore/screenshots` (`make appstore-screenshots`) |
| Family Controls **Distribution** entitlement | ⏳ **(you)** request at https://developer.apple.com/contact/request/family-controls-distribution — required for TestFlight/App Store builds of the app *and* its 4 extensions |
| App record in App Store Connect | ⏳ **(you)** bundle ID `com.lynkto.kinbeacon` |
| APNs key for background push | ⏳ **(you)** see `supabase/README.md` → Push notifications |
| Archive + upload | `make export`, then Xcode Organizer / Transporter (after the entitlement is approved) |

## Listing

- **Name:** KinBeacon: Family Safety
- **Subtitle:** Location, School Mode & SOS
- **Category:** Lifestyle (secondary: Utilities)
- **Age rating:** 4+ (no objectionable content; location sharing is disclosed in privacy answers)
- **Price:** Free
- **Support URL:** https://github.com/devzahirul/KinBeacon-iOS/blob/main/docs/SUPPORT.md
- **Privacy policy URL:** https://github.com/devzahirul/KinBeacon-iOS/blob/main/docs/PRIVACY.md
- **Keywords:** family,location,parental controls,school mode,screen time,kids,safety,check in,sos,geofence

**Promotional text**
> Know your kids got to school, keep class time focused, and let them reach you in one tap — privately, with Apple's Screen Time.

**Description**
> KinBeacon keeps your family connected and focused — without spying.
>
> FAMILY MAP
> • See where everyone is, with arrival and departure alerts for home, school and other safe places.
> • Battery-smart: location updates slow down automatically when the phone is low on battery.
>
> SCHOOL MODE, POWERED BY APPLE SCREEN TIME
> • Schedule School, Homework and Bedtime modes. Only the apps you allow are available.
> • Kids can ask for 15, 30 or 60 extra minutes; you approve right from the notification.
> • App usage stays inside Apple's privacy sandbox — not even our servers see it.
>
> CHECK-INS & SOS
> • One tap for "I'm OK", "Picked up", "On my way" — or "Need help", which reaches you even in Focus.
> • Hold-to-send SOS shares live location and battery level with the family.
>
> PEACE OF MIND
> • Get alerted if location sharing or Screen Time access is turned off, and fix it remotely.
> • Location history is deleted after 30 days. No ads. No tracking. No data sale.
>
> Try the built-in demo — no account needed.

## App Privacy ("nutrition label")

Data **linked to the user**, used for **App Functionality** only, **not used for tracking**:
- Location → Precise Location
- Contact Info → Name, Email Address
- User Content → Other User Content (check-in and request messages)
- Identifiers → User ID, Device ID (push token)

Not collected: Health, Financial, Browsing/Search History, Purchases, Diagnostics sent off-device, Usage Data
(screen time is processed only by Apple's Screen Time on-device). Tracking: **No**.

## App Review information

**Sign-in required:** No — tap **"Try the demo — no account needed"** on the first screen, then *Parent's view* or
*Child's view*. To test real accounts, create one with any email (no verification step).

**Notes for the reviewer**
> KinBeacon is a family-safety / parental-control app.
> • Demo: first screen → "Try the demo" runs a simulated family on the device (map, School Mode, requests, SOS, alerts).
> • Real use needs two devices: a parent creates an account → Family → "Add a child's device" shows a 6-digit code →
>   on the second device choose "This is my child's device" and enter the code.
> • Family Controls (Screen Time) is used only on the child's device, after the parent sets it up, to apply School /
>   Homework / Bedtime restrictions the parent configured. The DeviceActivityReport extension shows usage on-device; the
>   data never leaves Apple's sandbox.
> • Background location ("Always") is used only on the paired child's device (and optionally the parent's) for the
>   family map, arrival/departure alerts for safe places and SOS. Updates are batched and reduced on low battery.
> • Account deletion: Settings → Delete account.

## Guideline checklist

| Guideline | How KinBeacon complies |
|---|---|
| 2.1 App completeness | real backend, no placeholder content; demo mode clearly labeled |
| 2.5.4 Background modes | `location` (child safety, geofences), `remote-notification` (wake for parent commands), `fetch` (heartbeat) — each used by a shipped feature |
| 4.2 Minimum functionality | full parent and child experiences |
| 5.1.1 Data collection | purpose strings, permission priming, no data required beyond functionality |
| 5.1.1(v) Account deletion | Settings → Delete account (deletes the family when the last parent leaves) |
| 5.1.2 Data use and sharing | data shared only inside the family; no third-party SDKs |
| 5.4 VPN/MDM / parental controls | uses Apple's FamilyControls APIs (not MDM, not VPN); Family Controls Distribution entitlement requested |
| Kids | parent-controlled; children never create accounts or enter contact info |

## Build & upload

```bash
make bump          # increments the build number
make export        # Release archive + App Store .ipa in build/export (needs the Distribution entitlement)
```
Upload `build/export/KinBeacon.ipa` with Transporter or Xcode → Organizer → Distribute App.

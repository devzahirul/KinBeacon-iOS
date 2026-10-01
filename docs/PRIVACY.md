# KinBeacon privacy policy

_Last updated: 1 October 2026_

KinBeacon is a family-safety app. It processes sensitive information — a child's location and Screen Time
restrictions — so our rule is **collect the minimum, keep it the shortest, share it only inside the family**.
We do not sell data, show ads, or track you across apps or websites.

## What we collect and why

| Data | Why | Who can see it | Retention |
|---|---|---|---|
| Parent name and email address | your account and sign-in | you | until you delete your account |
| Child's first name, age, grade, avatar | shown to the family | your family | until removed or account deleted |
| Precise location of paired child devices | live map, arrival/leave alerts, SOS | your family | **30 days**, then automatically deleted (on device and server) |
| Check-ins, SOS, extra-time requests and their optional messages | the features themselves | your family | until the family is deleted |
| Permission status (on/off) and battery level of child devices | "location permission turned off" and low-battery alerts | your family | latest value only |
| Push notification token | delivering notifications | nobody (system use) | until the app is removed |
| Screen-time usage | parent reports | **never collected** — Apple's Screen Time renders it inside its privacy sandbox | — |
| Apps chosen for School Mode | enforcement | stays on the child's device as Apple's opaque tokens | — |

## How it's protected
- Encrypted in transit (TLS) and at rest by our hosting provider (Supabase, AWS).
- Row-level security: an account can only ever read its own family's records.
- Logs never contain coordinates or names.
- Remote commands can only be issued by a parent of the same family.

## Children
KinBeacon is set up and controlled by a parent. Children's accounts are created only by redeeming a code their parent
generated; no email address or other contact information is collected from children.

## Your choices
- Turn location sharing off at any time in iOS Settings (the family is notified).
- Delete your account in Settings → *Delete account*. Deleting the last parent deletes the whole family's data.
- Questions: see [Support](SUPPORT.md).

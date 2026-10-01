# KinBeacon backend (Supabase)

| Path | What it is |
|---|---|
| `migrations/20261001000001_kinbeacon.sql` | `kinbeacon` schema: 13 tables, Row Level Security, server-owned revisions, 30-day location retention, RPCs (`create_family`, `create_child_invite`, `redeem_pairing_code`, `respond_to_request`, `delete_my_account`), Realtime publication |
| `migrations/20261001000002_fix_avatar_defaults.sql` | Unicode-escaped avatar defaults |
| `migrations/20261001000003_push_webhooks.sql` | Postgres → Edge Function triggers for APNs (apply after the function is deployed) |
| `functions/push/index.ts` | APNs fan-out: actionable request notifications, time-sensitive alerts, silent command "doorbells" |
| `tests/kinbeacon_rls_test.sql` | 19 pgTAP assertions (RLS isolation, single-use pairing codes, no self-approval, account deletion). Runs in a transaction, so it is safe on the hosted project |

## Security model
- Only `authenticated` users; `anon` has no grants on the schema.
- Every table has RLS: members see their own family; only parents change controls, places and answer requests;
  a child device writes only its own member's rows; pairing codes are never readable by clients.
- Multi-row operations are `SECURITY DEFINER` functions with `search_path = ''`.
- Pairing: 6-digit, single-use, 10-minute codes; 5 failed attempts per 10 minutes per account.
- Remote commands are rows (RLS: only a family parent can insert, only the target device can read/ack). The APNs push
  carries no command — it only wakes the device, which then fetches over its authenticated connection.

## Set up
1. SQL Editor → run `migrations/…0001` then `…0002`. (If you copy via the macOS clipboard, use
   `LC_ALL=en_US.UTF-8 pbcopy < file` — the default clipboard encoding corrupts non-ASCII literals.)
2. Integrations → Data API → Settings → Exposed schemas: add `kinbeacon`.
3. Authentication → Email: "Confirm email" off for frictionless onboarding (or on — the app shows "check your inbox").
4. Run `tests/kinbeacon_rls_test.sql` in the SQL Editor — expect 19 `ok` rows.
5. App: `Config/Supabase.local.xcconfig` with `SUPABASE_HOST` and the **publishable** key.

## Push notifications (APNs)
1. developer.apple.com → Keys → create an **APNs** key; note Key ID and Team ID, download the `.p8`.
2. Edge Functions → Deploy `push` (paste `functions/push/index.ts`, or `supabase functions deploy push --no-verify-jwt`).
3. Edge Functions → Secrets: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` (contents of the .p8), `APNS_BUNDLE_ID`
   (`com.lynkto.kinbeacon`), `WEBHOOK_SECRET` (random).
4. Run `migrations/…0003` with `<WEBHOOK_SECRET>` replaced.
Without these steps the app still works while open (Realtime) and catches up through Background App Refresh.

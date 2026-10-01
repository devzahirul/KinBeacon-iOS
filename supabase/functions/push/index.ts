// KinBeacon push fan-out (Supabase Edge Function, Deno).
//
// Called by Postgres database webhooks (see migrations/20261001000003_push_webhooks.sql) on inserts/updates of
// commands, time_requests, check_ins and alerts. Looks up the recipients' APNs tokens with the service role and sends:
//   • commands      → silent "doorbell" push to the target device (content-available; no command in the payload —
//                     the device fetches it over its authenticated, RLS-protected connection)
//   • time_requests → parents: actionable "asked for 15 min" (category KIN_TIME_REQUEST); child: approved/declined
//   • check_ins     → parents: "Emma: I'm OK" (Need help → time-sensitive)
//   • alerts        → parents: safety alert (time-sensitive)
//
// Secrets (Dashboard → Edge Functions → Secrets): APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY (the .p8 contents),
// APNS_BUNDLE_ID (com.lynkto.kinbeacon), WEBHOOK_SECRET (random string, also stored in the webhook header).
import { createClient } from "jsr:@supabase/supabase-js@2";

type Row = Record<string, unknown>;
interface WebhookPayload {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  schema: string;
  record: Row;
  old_record: Row | null;
}

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  db: { schema: "kinbeacon" },
});

Deno.serve(async (request) => {
  if (request.headers.get("x-webhook-secret") !== Deno.env.get("WEBHOOK_SECRET")) {
    return new Response("forbidden", { status: 403 });
  }
  const payload = (await request.json()) as WebhookPayload;
  const messages = await plan(payload);
  const results = await Promise.all(messages.map(({ userIDs, push }) => sendToUsers(userIDs, push)));
  return Response.json({ sent: results.flat().length });
});

interface Push {
  aps: Record<string, unknown>;
  [key: string]: unknown;
  pushType: "alert" | "background";
  priority: 5 | 10;
}

async function plan({ table, type, record, old_record }: WebhookPayload): Promise<{ userIDs: string[]; push: Push }[]> {
  const familyID = record.family_id as string;
  switch (table) {
    case "commands": {
      const target = await memberUserID(record.target as string);
      return target ? [{ userIDs: [target], push: { aps: { "content-available": 1 }, kin: { wake: "commands" }, pushType: "background", priority: 5 } }] : [];
    }
    case "time_requests": {
      const child = await member(record.member_id as string);
      if (type === "INSERT") {
        return [{
          userIDs: await parentUserIDs(familyID),
          push: {
            aps: {
              alert: { title: `${child?.name ?? "Your child"} asked for ${minutes(record.minutes as number)}`, body: (record.message as string) ?? "Tap to approve or decline." },
              category: "KIN_TIME_REQUEST", sound: "default", "thread-id": `requests-${record.member_id}`,
            },
            requestID: record.id, memberID: record.member_id, pushType: "alert", priority: 10,
          },
        }];
      }
      if (old_record?.status === "pending" && record.status !== "pending" && child?.user_id) {
        const approved = record.status === "approved";
        return [{
          userIDs: [child.user_id],
          push: {
            aps: { alert: { title: approved ? "Extra time approved 🎉" : "Not this time", body: approved ? "Your apps are unlocked for a bit." : "Your request was declined." }, sound: "default" },
            pushType: "alert", priority: 10,
          },
        }, { userIDs: [child.user_id], push: { aps: { "content-available": 1 }, kin: { wake: "requests" }, pushType: "background", priority: 5 } }];
      }
      return [];
    }
    case "check_ins": {
      const child = await member(record.member_id as string);
      const urgent = record.kind === "needHelp";
      return [{
        userIDs: await parentUserIDs(familyID),
        push: {
          aps: {
            alert: { title: `${child?.name ?? "Your child"}: ${checkInTitle(record.kind as string)}`, body: (record.message as string) ?? "" },
            sound: "default", "interruption-level": urgent ? "time-sensitive" : "passive", "thread-id": `checkins-${record.member_id}`,
          },
          memberID: record.member_id, pushType: "alert", priority: urgent ? 10 : 5,
        },
      }];
    }
    case "alerts": {
      if (type !== "INSERT") return [];
      const child = await member(record.member_id as string);
      return [{
        userIDs: await parentUserIDs(familyID),
        push: {
          aps: {
            alert: { title: alertTitle(record.kind as string), body: `${child?.name ?? "Your child"} needs your attention.` },
            sound: "default", category: "KIN_SAFETY_ALERT", "interruption-level": "time-sensitive",
          },
          alertID: record.id, memberID: record.member_id, pushType: "alert", priority: 10,
        },
      }];
    }
    default:
      return [];
  }
}

async function member(id: string) {
  const { data } = await supabase.from("members").select("name,user_id").eq("id", id).maybeSingle();
  return data as { name: string; user_id: string | null } | null;
}

async function memberUserID(id: string) {
  return (await member(id))?.user_id ?? null;
}

async function parentUserIDs(familyID: string): Promise<string[]> {
  const { data } = await supabase.from("members").select("user_id").eq("family_id", familyID).eq("role", "parent");
  return (data ?? []).map((row) => row.user_id as string).filter(Boolean);
}

async function sendToUsers(userIDs: string[], { pushType, priority, ...payload }: Push) {
  if (userIDs.length === 0) return [];
  const { data: tokens } = await supabase.from("device_tokens").select("token,environment,user_id").in("user_id", userIDs);
  const jwt = await providerToken();
  return Promise.all((tokens ?? []).map(async ({ token, environment, user_id }) => {
    const host = environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    const response = await fetch(`https://${host}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": Deno.env.get("APNS_BUNDLE_ID")!,
        "apns-push-type": pushType,
        "apns-priority": String(priority),
        "apns-expiration": String(Math.floor(Date.now() / 1000) + 3600),
      },
      body: JSON.stringify(payload),
    });
    // 410 Unregistered: the app was deleted — forget the token.
    if (response.status === 410) await supabase.from("device_tokens").delete().eq("token", token).eq("user_id", user_id);
    return response.status;
  }));
}

// APNs provider token (ES256 JWT), cached for 50 minutes as Apple recommends (valid for 60).
let cachedToken: { value: string; issuedAt: number } | null = null;
async function providerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now - cachedToken.issuedAt < 3000) return cachedToken.value;
  const pem = Deno.env.get("APNS_PRIVATE_KEY")!.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const key = await crypto.subtle.importKey("pkcs8", Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const encode = (value: unknown) => btoa(JSON.stringify(value)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
  const unsigned = `${encode({ alg: "ES256", kid: Deno.env.get("APNS_KEY_ID") })}.${encode({ iss: Deno.env.get("APNS_TEAM_ID"), iat: now })}`;
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned)));
  const value = `${unsigned}.${btoa(String.fromCharCode(...signature)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_")}`;
  cachedToken = { value, issuedAt: now };
  return value;
}

const minutes = (value: number) => (value >= 60 ? "1 hour" : `${value} min`);
const checkInTitle = (kind: string) => ({ imOK: "I'm OK", pickedUp: "Picked up", onMyWay: "On my way", needHelp: "Need help" } as Record<string, string>)[kind] ?? kind;
const alertTitle = (kind: string) => ({
  locationPermissionOff: "Location permission turned off", notificationsOff: "Notifications turned off",
  deviceProtectionOff: "Screen Time access removed", sos: "SOS alert", needHelp: "Asked for help", lowBattery: "Battery is low",
} as Record<string, string>)[kind] ?? "Safety alert";

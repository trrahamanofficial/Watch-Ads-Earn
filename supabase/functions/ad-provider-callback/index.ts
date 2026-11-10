// Generic signed-callback adapter for providers that support HMAC-SHA256
// over the exact raw HTTP request body. Do not enable until the selected
// provider's official docs confirm this signature format and payload mapping.
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const encoder = new TextEncoder();
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const secret = Deno.env.get("AD_PROVIDER_WEBHOOK_SECRET");
  const provider = Deno.env.get("AD_PROVIDER_NAME");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const secretKeysRaw = Deno.env.get("SUPABASE_SECRET_KEYS");

  // Fail closed: no secret means no credits can be issued.
  if (!secret || !provider || !supabaseUrl || !secretKeysRaw) {
    return json({ error: "Callback integration is not configured" }, 503);
  }

  const signatureHeader = req.headers.get("x-provider-signature") ?? "";
  const rawBody = await req.text();
  if (rawBody.length > 16_384) return json({ error: "Payload too large" }, 413);

  const supplied = signatureHeader.startsWith("sha256=")
    ? signatureHeader.slice(7).toLowerCase()
    : "";
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, encoder.encode(rawBody)),
  );
  if (!supplied || !safeEqual(supplied, toHex(digest))) {
    return json({ error: "Invalid signature" }, 401);
  }

  let event: Record<string, unknown>;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  // This is an internal normalized contract, NOT a provider-specific parser.
  // Map the selected provider's documented fields here only after approval.
  const eventId = typeof event.event_id === "string" ? event.event_id.trim() : "";
  const userId = typeof event.user_id === "string" ? event.user_id.trim() : "";
  const offerId = typeof event.offer_id === "string" ? event.offer_id.trim() : "";
  const points = Number(event.points);
  if (
    event.status !== "completed" ||
    !eventId ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(userId) ||
    !offerId ||
    !Number.isSafeInteger(points) ||
    points < 1 ||
    points > 10_000
  ) {
    return json({ error: "Invalid or incomplete completion event" }, 400);
  }

  let secretKeys: Record<string, string>;
  try {
    secretKeys = JSON.parse(secretKeysRaw);
  } catch {
    return json({ error: "Server key configuration error" }, 503);
  }
  const supabaseSecret = secretKeys.default;
  if (!supabaseSecret) return json({ error: "Server key missing" }, 503);

  const admin = createClient(supabaseUrl, supabaseSecret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await admin.rpc("process_verified_ad_callback", {
    p_provider: provider,
    p_event_id: eventId,
    p_user_id: userId,
    p_offer_id: offerId,
    p_points: points,
  });
  if (error) {
    console.error("Verified callback processing failed", error.message);
    return json({ error: "Could not process callback" }, 500);
  }
  return json({ ok: true, result: data });
});

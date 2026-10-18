import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Helper to convert base64url
function base64url(input: string | Uint8Array): string {
  let str = "";
  if (typeof input === "string") {
    str = btoa(input);
  } else {
    let binary = "";
    const bytes = new Uint8Array(input);
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    str = btoa(binary);
  }
  return str.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// Generates Google OAuth2 Access Token from Service Account using Web Crypto
async function getGoogleAccessToken(serviceAccount: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claimSet = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  const encodedHeader = base64url(JSON.stringify(header));
  const encodedClaimSet = base64url(JSON.stringify(claimSet));
  const unsignedToken = `${encodedHeader}.${encodedClaimSet}`;

  // Parse RSA private key
  const pem = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binaryKey = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(unsignedToken)
  );

  const signedJwt = `${unsignedToken}.${base64url(new Uint8Array(signature))}`;

  // Exchange JWT for Access Token
  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: signedJwt,
    }),
  });

  const tokenData = await tokenRes.json();
  if (!tokenRes.ok) {
    throw new Error(`Google Auth Failed: ${JSON.stringify(tokenData)}`);
  }
  return tokenData.access_token;
}

serve(async (req) => {
  // CORS Headers
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // 1. Parse payload
    const { title, body, type = "GENERAL", deep_link = "/notifications", target_user_id } = await req.json();

    if (!title || !body) {
      return new Response(JSON.stringify({ error: "title and body are required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 2. Read Service Account secret
    const rawSecret = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
    if (!rawSecret) {
      throw new Error("FIREBASE_SERVICE_ACCOUNT secret not configured in Supabase");
    }
    const serviceAccount = JSON.parse(rawSecret);

    // 3. Get Google OAuth2 token for FCM
    const accessToken = await getGoogleAccessToken(serviceAccount);

    // 4. Query active target device tokens
    let query = supabase.from("notification_tokens").select("fcm_token, user_id").eq("is_active", true);
    if (target_user_id) {
      query = query.eq("user_id", target_user_id);
    }
    const { data: tokens, error: tokenError } = await query;

    if (tokenError) throw tokenError;

    if (!tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ message: "No active device tokens found to send." }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 5. Store central notification in database
    const { data: notifData } = await supabase.from("notifications").insert({
      title,
      body,
      type,
      deep_link,
      target_type: target_user_id ? "USER" : "ALL",
      target_user_id: target_user_id || null,
    }).select().single();

    // 6. Send push to each token via FCM v1 API
    const projectId = serviceAccount.project_id;
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
    const results = [];

    for (const item of tokens) {
      const fcmPayload = {
        message: {
          token: item.fcm_token,
          notification: { title, body },
          data: {
            deep_link: deep_link || "/home",
            notification_type: type,
            notification_id: notifData?.id || "",
          },
          android: {
            priority: "high",
            notification: {
              channel_id: "unihub_general_channel",
              sound: "default",
            },
          },
        },
      };

      const pushRes = await fetch(fcmUrl, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(fcmPayload),
      });

      const pushData = await pushRes.json();
      results.push({ token: item.fcm_token, ok: pushRes.ok, response: pushData });

      // If token is unregistered or invalid, mark it inactive in DB
      if (!pushRes.ok && pushData?.error?.details?.some((d: any) => d.errorCode === "UNREGISTERED")) {
        await supabase.from("notification_tokens").update({ is_active: false }).eq("fcm_token", item.fcm_token);
      }
    }

    return new Response(JSON.stringify({ success: true, count: tokens.length, results }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

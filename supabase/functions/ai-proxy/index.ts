import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------------------------------------------------------------------------
// Env validation — fail fast if any required var is missing
// ---------------------------------------------------------------------------
const REQUIRED_ENVS = [
  "PRIMARY_URL",
  "PRIMARY_KEYS",
  "FALLBACK_URL",
  "FALLBACK_KEY",
  "SUPABASE_URL",
  "SUPABASE_SERVICE_ROLE_KEY",
] as const;

function getEnv(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing env: ${name}`);
  return v;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const MODEL_MAP: Record<string, string> = {
  fast: "gemini-3.7-flash",
  coding: "claude-sonnet-5",
  math: "deepseek-v4-pro-max",
  pdf: "gemini-3.1-pro",
};

const QUOTA_LIMITS: Record<string, { heavy: number; fast: number }> = {
  free: { heavy: 5, fast: 20 },
  student: { heavy: 50, fast: 200 },
  pro: { heavy: 100, fast: Infinity },
};

// Which counter does each mode consume?
const MODE_COUNTER: Record<string, "heavy_count" | "fast_count"> = {
  fast: "fast_count",
  coding: "heavy_count",
  math: "heavy_count",
  pdf: "heavy_count",
};

const FALLBACK_STATUSES = new Set([429, 503, 402, 403]);
const UPSTREAM_TIMEOUT_MS = 8000;

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function jsonError(message: string, status: number): Response {
  return new Response(message, { status, headers: { ...corsHeaders } });
}

function resolveModel(mode: string): string {
  const model = MODEL_MAP[mode];
  if (!model) throw Object.assign(new Error("Invalid mode"), { status: 400 });
  return model;
}

function pickPrimaryKey(userId: string): string {
  const raw = getEnv("PRIMARY_KEYS");
  const keys = raw.split(",").map((k) => k.trim()).filter(Boolean);
  if (keys.length === 0) throw new Error("PRIMARY_KEYS is empty");
  if (keys.length === 1) return keys[0];
  let hash = 0;
  for (const c of userId) hash = ((hash << 5) - hash + c.charCodeAt(0)) | 0;
  return keys[Math.abs(hash) % keys.length];
}

function damascusDate(): string {
  return new Date().toLocaleDateString("en-CA", {
    timeZone: "Asia/Damascus",
  });
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------
serve(async (req: Request): Promise<Response> => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonError("Method not allowed", 405);
  }

  // Validate envs early
  for (const key of REQUIRED_ENVS) {
    if (!Deno.env.get(key)) return jsonError(`Missing env: ${key}`, 500);
  }

  const supabaseUrl = getEnv("SUPABASE_URL");
  const serviceRoleKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");
  const primaryUrl = getEnv("PRIMARY_URL");
  const fallbackUrl = getEnv("FALLBACK_URL");
  const fallbackKey = getEnv("FALLBACK_KEY");

  // Supabase clients
  // - anon client with user JWT for auth verification
  // - service-role client for DB reads/writes (bypasses RLS)
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return jsonError("Unauthorized", 401);
  }
  const jwt = authHeader.replace("Bearer ", "").trim();
  if (!jwt) return jsonError("Unauthorized", 401);

  // Verify user via auth.getUser
  const anonClient = createClient(supabaseUrl, serviceRoleKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });

  const { data: userData, error: userError } = await anonClient.auth.getUser(
    jwt,
  );
  if (userError || !userData?.user) {
    return jsonError("Unauthorized", 401);
  }
  const userId: string = userData.user.id;

  // Service-role client for DB operations
  const db = createClient(supabaseUrl, serviceRoleKey);

  // ---- 1. Subscription check ----
  const { data: isValid, error: validError } = await db.rpc(
    "is_subscription_valid",
    { p_user_id: userId },
  );
  if (validError) {
    console.error("is_subscription_valid error:", validError);
    return jsonError("Subscription check failed", 500);
  }
  if (!isValid) {
    return jsonError("Subscription expired", 403);
  }

  // Fetch plan for quota logic
  const { data: profile, error: profileError } = await db
    .from("profiles")
    .select("plan")
    .eq("id", userId)
    .single();

  if (profileError || !profile) {
    console.error("profile fetch error:", profileError);
    return jsonError("Profile not found", 500);
  }
  const plan: string = profile.plan;

  // ---- Parse body ----
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return jsonError("Invalid JSON body", 400);
  }

  const mode = body["mode"] as string | undefined;
  if (!mode || typeof mode !== "string") {
    return jsonError("Invalid mode", 400);
  }

  let model: string;
  try {
    model = resolveModel(mode);
  } catch (e: unknown) {
    const err = e as { status?: number; message?: string };
    return jsonError(err.message ?? "Invalid mode", err.status ?? 400);
  }

  const chatId = body["chat_id"] as string | undefined;
  if (!chatId || typeof chatId !== "string") {
    return jsonError("Missing chat_id", 400);
  }

  const messages = body["messages"] as unknown;
  if (!Array.isArray(messages) || messages.length === 0) {
    return jsonError("Missing messages", 400);
  }

  // Verify chat belongs to user
  const { data: chat, error: chatError } = await db
    .from("chats")
    .select("id")
    .eq("id", chatId)
    .eq("user_id", userId)
    .single();

  if (chatError || !chat) {
    return jsonError("Chat not found", 404);
  }

  // ---- 2. Daily quota check ----
  const today = damascusDate();
  const limits = QUOTA_LIMITS[plan] ?? QUOTA_LIMITS["free"];
  const counterField = MODE_COUNTER[mode] ?? "heavy_count";

  // Read or create daily_usage row
  let usage: { heavy_count: number; fast_count: number } | null = null;

  const { data: existingUsage, error: usageError } = await db
    .from("daily_usage")
    .select("heavy_count, fast_count")
    .eq("user_id", userId)
    .eq("date", today)
    .maybeSingle();

  if (usageError) {
    console.error("daily_usage read error:", usageError);
    return jsonError("Quota check failed", 500);
  }

  if (existingUsage) {
    usage = existingUsage;
  } else {
    const { data: inserted, error: insertError } = await db
      .from("daily_usage")
      .insert({ user_id: userId, date: today, heavy_count: 0, fast_count: 0 })
      .select("heavy_count, fast_count")
      .single();

    if (insertError) {
      // Race condition: another request inserted concurrently — re-read
      const { data: retry } = await db
        .from("daily_usage")
        .select("heavy_count, fast_count")
        .eq("user_id", userId)
        .eq("date", today)
        .single();
      if (retry) {
        usage = retry;
      } else {
        console.error("daily_usage insert error:", insertError);
        return jsonError("Quota check failed", 500);
      }
    } else {
      usage = inserted;
    }
  }

  // Check limits
  if (usage) {
    if (
      (counterField === "heavy_count" && usage.heavy_count >= limits.heavy) ||
      (counterField === "fast_count" && usage.fast_count >= limits.fast)
    ) {
      return jsonError("Daily quota exceeded", 429);
    }
  }

  // ---- 3 & 4. Build upstream body + pick key ----
  const primaryKey = pickPrimaryKey(userId);

  // Build upstream request body — forward messages + model + streaming
  const upstreamBody = JSON.stringify({
    model,
    messages,
    stream: true,
    streaming: true,
  });

  // Extract last user message for persistence
  const lastUserMsg = [...messages].reverse().find(
    (m: unknown) =>
      typeof m === "object" && m !== null &&
      (m as Record<string, unknown>)["role"] === "user",
  ) as Record<string, unknown> | undefined;
  const userContent: string =
    (lastUserMsg?.["content"] as string | undefined) ?? "";

  // ---- 5. Primary request ----
  let upstreamResponse: Response | null = null;
  let usedFallback = false;

  async function fetchPrimary(): Promise<Response> {
    return await fetch(primaryUrl, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${primaryKey}`,
        "Content-Type": "application/json",
      },
      body: upstreamBody,
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
  }

  async function fetchFallback(): Promise<Response> {
    return await fetch(fallbackUrl, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${fallbackKey}`,
        "Content-Type": "application/json",
      },
      body: upstreamBody,
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
  }

  try {
    upstreamResponse = await fetchPrimary();
  } catch (e: unknown) {
    const err = e as { name?: string };
    if (err?.name === "TimeoutError") {
      console.warn("Primary timeout — trying fallback");
      try {
        upstreamResponse = await fetchFallback();
        usedFallback = true;
      } catch (fe) {
        console.error("Fallback also failed (timeout path):", fe);
        return jsonError("Upstream error", 502);
      }
    } else {
      console.error("Primary fetch error:", e);
      return jsonError("Upstream error", 502);
    }
  }

  // Check if primary returned fallback-eligible status
  if (
    upstreamResponse && !usedFallback &&
    FALLBACK_STATUSES.has(upstreamResponse.status)
  ) {
    console.warn(
      `Primary returned ${upstreamResponse.status} — trying fallback`,
    );
    try {
      const fbRes = await fetchFallback();
      upstreamResponse = fbRes;
      usedFallback = true;
    } catch (fe) {
      console.error("Fallback fetch error:", fe);
      return jsonError("Upstream error", 502);
    }
  }

  if (!upstreamResponse) {
    return jsonError("Upstream error", 502);
  }

  // If fallback also returned error status, propagate
  if (!upstreamResponse.ok) {
    const errText = await upstreamResponse.text().catch(() => "");
    console.error(
      `Upstream error ${upstreamResponse.status}:`,
      errText.slice(0, 500),
    );
    return new Response(errText || "Upstream error", {
      status: upstreamResponse.status >= 400 && upstreamResponse.status < 600
        ? upstreamResponse.status
        : 502,
      headers: { ...corsHeaders },
    });
  }

  // ---- 7. Stream passthrough + persist after success ----
  // We tee the stream: one branch goes to the client immediately,
  // the other is consumed to collect the full assistant text for DB persistence.
  // To avoid buffering the entire response before sending, we use TransformStream
  // that accumulates text while forwarding chunks.

  if (!upstreamResponse.body) {
    return jsonError("Upstream returned empty body", 502);
  }

  let assistantText = "";
  const decoder = new TextDecoder();

  const transform = new TransformStream<Uint8Array, Uint8Array>({
    transform(chunk, controller) {
      // Forward chunk to client immediately
      controller.enqueue(chunk);

      // Accumulate assistant text from SSE data
      try {
        const text = decoder.decode(chunk, { stream: true });
        const lines = text.split("\n");
        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed.startsWith("data:")) continue;
          const payload = trimmed.slice(5).trim();
          if (payload === "[DONE]") continue;
          try {
            const json = JSON.parse(payload);
            const delta: string | undefined =
              json?.choices?.[0]?.delta?.content ??
                json?.choices?.[0]?.message?.content ??
                json?.delta?.text ??
                json?.content ??
                undefined;
            if (typeof delta === "string") assistantText += delta;
          } catch {
            // Not JSON — ignore
          }
        }
      } catch {
        // Decode error — ignore
      }
    },

    async flush() {
      // Persist only after stream completes successfully
      if (!assistantText) return;

      try {
        const { error: incError } = await db
          .from("daily_usage")
          .update(
            counterField === "heavy_count"
              ? { heavy_count: (usage!.heavy_count + 1) }
              : { fast_count: (usage!.fast_count + 1) },
          )
          .eq("user_id", userId)
          .eq("date", today);

        if (incError) console.error("Failed to increment usage:", incError);

        // Save messages
        const { error: msgError } = await db.from("messages").insert([
          {
            chat_id: chatId,
            user_id: userId,
            role: "user",
            content: userContent,
          },
          {
            chat_id: chatId,
            user_id: userId,
            role: "assistant",
            content: assistantText,
          },
        ]);

        if (msgError) console.error("Failed to save messages:", msgError);
      } catch (e) {
        console.error("Post-stream persist error:", e);
      }
    },
  });

  const streamedBody = upstreamResponse.body.pipeThrough(transform);

  // Build SSE response headers
  const responseHeaders: Record<string, string> = {
    ...corsHeaders,
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    "Connection": "keep-alive",
  };

  // Forward relevant upstream headers if present
  const upstreamContentType = upstreamResponse.headers.get("content-type");
  if (upstreamContentType?.includes("text/event-stream")) {
    responseHeaders["Content-Type"] = "text/event-stream";
  }

  return new Response(streamedBody, {
    status: 200,
    headers: responseHeaders,
  });
});

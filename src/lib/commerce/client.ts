import { supabase } from "@/integrations/supabase/client";

type Method = "GET" | "POST";

async function getAuthHeaders(idempotencyKey?: string): Promise<Record<string, string>> {
  const supabaseUrl = String(import.meta.env.VITE_SUPABASE_URL || "").trim();
  const anonKey = String(
    import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || import.meta.env.VITE_SUPABASE_ANON_KEY || "",
  ).trim();
  if (!supabaseUrl || !anonKey) throw new Error("missing_supabase_env");

  const sessionRes = await supabase.auth.getSession();
  const token = sessionRes.data.session?.access_token;
  if (!token) throw new Error("missing_user_session");

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    apikey: anonKey,
    Authorization: `Bearer ${token}`,
  };
  if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;
  return headers;
}

async function request(path: string, method: Method, body?: Record<string, unknown>, idempotencyKey?: string) {
  const supabaseUrl = String(import.meta.env.VITE_SUPABASE_URL || "").trim();
  const headers = await getAuthHeaders(idempotencyKey);
  const url = `${supabaseUrl}/functions/v1/commerce${path}`;
  const resp = await fetch(url, {
    method,
    headers,
    body: method === "POST" ? JSON.stringify(body || {}) : undefined,
  });

  const text = await resp.text();
  let parsed: any = {};
  try {
    parsed = text ? JSON.parse(text) : {};
  } catch {
    parsed = { error: text || "invalid_json_response" };
  }

  if (!resp.ok) {
    const error = String(parsed?.error || parsed?.error_code || `commerce_http_${resp.status}`);
    const err = new Error(error);
    (err as any).payload = parsed;
    (err as any).status = resp.status;
    throw err;
  }

  return parsed;
}

export async function getCommerceCredits() {
  return await request("/me/credits", "GET");
}

export async function getCommerceLedger(limit = 50, beforeId?: number) {
  const qs = beforeId ? `?limit=${Math.max(1, limit)}&before_id=${beforeId}` : `?limit=${Math.max(1, limit)}`;
  return await request(`/me/ledger${qs}`, "GET");
}

export async function executeCommerceTool(args: {
  toolCode: "surprise_gen" | "edit_studio" | "camera_control" | "layer_decomposition" | "psd_to_umg" | "umg_to_verse";
  payload: Record<string, unknown>;
  requestId?: string;
  idempotencyKey?: string;
}) {
  const requestId = args.requestId || crypto.randomUUID();
  const idempotencyKey = args.idempotencyKey || crypto.randomUUID();
  return await request(
    "/tools/execute",
    "POST",
    {
      tool_code: args.toolCode,
      payload: args.payload,
      request_id: requestId,
      idempotency_key: idempotencyKey,
    },
    idempotencyKey,
  );
}

export async function reverseCommerceOperation(args: {
  operationId: string;
  reason?: string;
  idempotencyKey?: string;
}) {
  const idempotencyKey = args.idempotencyKey || crypto.randomUUID();
  return await request(
    "/tools/reverse",
    "POST",
    {
      operation_id: args.operationId,
      reason: args.reason || "client_reversal",
      idempotency_key: idempotencyKey,
    },
    idempotencyKey,
  );
}

export async function createSubscriptionCheckout(idempotencyKey = crypto.randomUUID()) {
  return await request(
    "/billing/subscription/checkout",
    "POST",
    {
      plan_code: "pro",
      idempotency_key: idempotencyKey,
    },
    idempotencyKey,
  );
}

export async function listCreditPacks() {
  return await request("/billing/packs", "GET");
}

export async function createPackCheckout(packCode: "pack_250" | "pack_650" | "pack_1400", idempotencyKey = crypto.randomUUID()) {
  return await request(
    `/billing/packs/${packCode}/checkout`,
    "POST",
    {
      idempotency_key: idempotencyKey,
    },
    idempotencyKey,
  );
}

export async function adminGetCommerceUser(userId: string) {
  return await request(`/admin/user/${encodeURIComponent(userId)}`, "GET");
}

export async function adminGrantCredits(args: {
  userId: string;
  walletType: "extra_wallet" | "weekly_wallet" | "free_monthly";
  credits: number;
  reason: string;
  idempotencyKey?: string;
}) {
  const idempotencyKey = args.idempotencyKey || crypto.randomUUID();
  return await request(
    "/admin/credits/grant",
    "POST",
    {
      user_id: args.userId,
      wallet_type: args.walletType,
      credits: args.credits,
      reason: args.reason,
      idempotency_key: idempotencyKey,
    },
    idempotencyKey,
  );
}

export async function adminDebitCredits(args: {
  userId: string;
  walletType: "extra_wallet" | "weekly_wallet" | "free_monthly";
  credits: number;
  reason: string;
  idempotencyKey?: string;
}) {
  const idempotencyKey = args.idempotencyKey || crypto.randomUUID();
  return await request(
    "/admin/credits/debit",
    "POST",
    {
      user_id: args.userId,
      wallet_type: args.walletType,
      credits: args.credits,
      reason: args.reason,
      idempotency_key: idempotencyKey,
    },
    idempotencyKey,
  );
}

export async function adminSetAbuseReview(args: {
  userId: string;
  action: "approve" | "review" | "block";
  reason?: string;
  idempotencyKey?: string;
}) {
  const idempotencyKey = args.idempotencyKey || crypto.randomUUID();
  return await request(
    `/admin/user/${encodeURIComponent(args.userId)}/abuse-review`,
    "POST",
    {
      action: args.action,
      reason: args.reason || "",
      idempotency_key: idempotencyKey,
    },
    idempotencyKey,
  );
}

export async function adminSetSuspension(args: {
  userId: string;
  suspend: boolean;
  idempotencyKey?: string;
}) {
  const idempotencyKey = args.idempotencyKey || crypto.randomUUID();
  return await request(
    `/admin/user/${encodeURIComponent(args.userId)}/suspend`,
    "POST",
    {
      suspend: args.suspend,
      idempotency_key: idempotencyKey,
    },
    idempotencyKey,
  );
}

// PRIVIO — relais des appels de groupe (lot 9.4, ADR-052) : Cloudflare Realtime (SFU).
//
// POST /functions/v1/call-sfu   (jeton de l'utilisateur), corps JSON :
//   { action: "push", call_id, sdp, tracks: [{ mid, kind: "audio"|"video" }], fresh? }
//       publie ma voix (et mon image) au relais ; « fresh » : nouvelle liaison (reconnexion),
//       donc nouvelle session au relais. Renvoie la réponse du relais ({ sdp }).
//   { action: "pull", call_id, tracks: [{ session, name }] }
//       demande les pistes d'autres personnes de l'appel. Renvoie l'offre du relais
//       ({ sdp, tracks: [{ mid, session, name, error? }] }), à accepter par « answer ».
//   { action: "answer", call_id, sdp }       réponse à l'offre du relais.
//   { action: "close", call_id, mids: [] }   arrête des pistes reçues (personne partie).
//
// Toutes les vérifications passent par la base au nom de l'utilisateur : être dans l'appel,
// ne demander que les pistes de personnes du même appel. La clé du relais reste ici, jamais
// dans l'application ; la base ne garde que les identifiants de session et de pistes.

import { ApiError, json, registerEndpoint, rpc, serviceHeaders, userHeaders } from "../_shared/supabase.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NAME = /^[A-Za-z0-9_-]{1,64}$/;
const SESSION = /^[A-Za-z0-9_-]{1,128}$/;
const MID = /^[A-Za-z0-9_-]{1,32}$/;
const MAX_SDP = 65536;

const STATUS: Record<string, number> = {
  AUTH_REQUIRED: 401,
  CALL_NOT_FOUND: 403,
  SFU_FORBIDDEN: 403,
  BODY_INVALID: 422,
  SFU_NOT_CONFIGURED: 503,
  SFU_FAILED: 502,
};
const fail = (code: string) => json(STATUS[code] ?? 500, { error: code });

interface Body {
  action?: string;
  call_id?: string;
  sdp?: string;
  fresh?: boolean;
  tracks?: { mid?: string; kind?: string; session?: string; name?: string }[];
  mids?: string[];
}

interface Me {
  session: string | null;
  user_id: string;
}

/** Appel au relais Cloudflare ; l'erreur du relais devient SFU_FAILED. */
async function sfu(path: string, method: string, body?: unknown): Promise<Record<string, unknown>> {
  const app = Deno.env.get("CLOUDFLARE_REALTIME_APP_ID") ?? "";
  const token = Deno.env.get("CLOUDFLARE_REALTIME_APP_TOKEN") ?? "";
  const res = await fetch(`https://rtc.live.cloudflare.com/v1/apps/${encodeURIComponent(app)}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const out = await res.json().catch(() => ({})) as Record<string, unknown>;
  if (!res.ok || typeof out.errorCode === "string") {
    console.error(`call-sfu: ${method} ${path.replace(/[A-Za-z0-9_-]{20,}/g, "…")} → ${res.status} ${out.errorCode ?? ""}`);
    throw new ApiError("SFU_FAILED", res.status);
  }
  return out;
}

function randomName(kind: string): string {
  const b = crypto.getRandomValues(new Uint8Array(9));
  return `${kind}-${Array.from(b, (x) => x.toString(36).padStart(2, "0")).join("")}`.slice(0, 40);
}

const sdpOf = (v: unknown) => {
  const d = v as { sdp?: unknown; type?: unknown } | undefined;
  return typeof d?.sdp === "string" ? d.sdp : null;
};

Deno.serve(async (req) => {
  await registerEndpoint();
  if (req.method !== "POST") return json(405, { error: "METHOD_NOT_ALLOWED" });
  if (!(req.headers.get("Authorization") ?? "").startsWith("Bearer ")) return fail("AUTH_REQUIRED");
  const body = await req.json().catch(() => null) as Body | null;
  const callId = body?.call_id ?? "";
  if (!body || !UUID.test(callId)) return fail("BODY_INVALID");

  try {
    switch (body.action) {
      case "push":
        return await push(req, callId, body);
      case "pull":
        return await pull(req, callId, body);
      case "answer":
        return await answer(req, callId, body);
      case "close":
        return await close(req, callId, body);
      default:
        return fail("BODY_INVALID");
    }
  } catch (e) {
    if (e instanceof ApiError) return fail(e.code);
    console.error("call-sfu: erreur inattendue");
    return json(503, { error: "UNAVAILABLE" });
  }
});

function configured(): boolean {
  return !!Deno.env.get("CLOUDFLARE_REALTIME_APP_ID") && !!Deno.env.get("CLOUDFLARE_REALTIME_APP_TOKEN");
}

/** Vérifie que l'utilisateur est dans l'appel (et peut recevoir ces sessions). */
async function me(req: Request, callId: string, sessions: string[] = []): Promise<Me> {
  return await rpc<Me>("group_call_sfu", { p_call_id: callId, p_sessions: sessions }, userHeaders(req));
}

async function push(req: Request, callId: string, body: Body): Promise<Response> {
  const tracks = body.tracks ?? [];
  if (typeof body.sdp !== "string" || body.sdp.length > MAX_SDP || tracks.length < 1 || tracks.length > 2 ||
    tracks.some((t) => !MID.test(t.mid ?? "") || !["audio", "video"].includes(t.kind ?? ""))) {
    return fail("BODY_INVALID");
  }
  const who = await me(req, callId);
  if (!configured()) return fail("SFU_NOT_CONFIGURED");
  let session = body.fresh === true ? null : who.session;
  if (!session) {
    const created = await sfu("/sessions/new", "POST");
    session = typeof created.sessionId === "string" ? created.sessionId : null;
    if (!session || !SESSION.test(session)) throw new ApiError("SFU_FAILED", 502);
  }
  const named = tracks.map((t) => ({ mid: t.mid!, kind: t.kind!, name: randomName(t.kind!) }));
  const out = await sfu(`/sessions/${session}/tracks/new`, "POST", {
    sessionDescription: { type: "offer", sdp: body.sdp },
    tracks: named.map((t) => ({ location: "local", mid: t.mid, trackName: t.name })),
  });
  const sdp = sdpOf(out.sessionDescription);
  if (!sdp) throw new ApiError("SFU_FAILED", 502);
  await rpc("group_call_set_sfu", {
    p_user_id: who.user_id,
    p_call_id: callId,
    p_session: session,
    p_tracks: Object.fromEntries(named.map((t) => [t.kind, t.name])),
  }, serviceHeaders());
  return json(200, { sdp, session });
}

async function pull(req: Request, callId: string, body: Body): Promise<Response> {
  const tracks = body.tracks ?? [];
  if (tracks.length < 1 || tracks.length > 16 ||
    tracks.some((t) => !SESSION.test(t.session ?? "") || !NAME.test(t.name ?? ""))) {
    return fail("BODY_INVALID");
  }
  const who = await me(req, callId, [...new Set(tracks.map((t) => t.session!))]);
  if (!configured()) return fail("SFU_NOT_CONFIGURED");
  if (!who.session) return fail("BODY_INVALID");
  const out = await sfu(`/sessions/${who.session}/tracks/new`, "POST", {
    tracks: tracks.map((t) => ({ location: "remote", sessionId: t.session, trackName: t.name })),
  });
  const list = Array.isArray(out.tracks) ? out.tracks as Record<string, unknown>[] : [];
  return json(200, {
    sdp: sdpOf(out.sessionDescription),
    renegotiate: out.requiresImmediateRenegotiation === true,
    tracks: list.map((t) => ({
      mid: typeof t.mid === "string" ? t.mid : null,
      session: t.sessionId ?? null,
      name: t.trackName ?? null,
      error: typeof t.errorCode === "string" ? t.errorCode : undefined,
    })),
  });
}

async function answer(req: Request, callId: string, body: Body): Promise<Response> {
  if (typeof body.sdp !== "string" || body.sdp.length > MAX_SDP) return fail("BODY_INVALID");
  const who = await me(req, callId);
  if (!configured()) return fail("SFU_NOT_CONFIGURED");
  if (!who.session) return fail("BODY_INVALID");
  await sfu(`/sessions/${who.session}/renegotiate`, "PUT", {
    sessionDescription: { type: "answer", sdp: body.sdp },
  });
  return json(200, { ok: true });
}

async function close(req: Request, callId: string, body: Body): Promise<Response> {
  const mids = body.mids ?? [];
  if (mids.length < 1 || mids.length > 16 || mids.some((m) => !MID.test(m))) return fail("BODY_INVALID");
  const who = await me(req, callId);
  if (!configured()) return fail("SFU_NOT_CONFIGURED");
  if (!who.session) return fail("BODY_INVALID");
  await sfu(`/sessions/${who.session}/tracks/close`, "PUT", {
    tracks: mids.map((mid) => ({ mid })),
    force: true,
  });
  return json(200, { ok: true });
}

// PRIVIO — envoi d'un message vocal (lot 3.1).
//
// POST /functions/v1/voice-send?conversation_id=…&client_msg_id=…[&reply_to_id=…][&ttl_seconds=…]
//      [&waveform=12,40,…] (lot 4.5 : profil sonore, 8 à 64 valeurs de 0 à 100)
// Corps : le fichier audio/mp4 (AAC), 30 s au plus. En-têtes : jeton de l'utilisateur.
//
// 1. réservation au nom de l'utilisateur (session active, membre, non bloqué, anti-abus) ;
// 2. MESURE du fichier par le serveur (durée réelle, taille, son AAC uniquement) ;
// 3. dépôt dans le bucket privé « voice » avec la clé de service ;
// 4. validation (service), puis publication du message au nom de l'utilisateur.
// Idempotent : un renvoi avec le même client_msg_id renvoie le même message.

import { MediaError, measureAudio } from "../_shared/mp4.ts";
import {
  ApiError,
  json,
  registerEndpoint,
  rpc,
  serviceHeaders,
  SUPABASE_URL,
  userHeaders,
} from "../_shared/supabase.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HARD_MAX_BYTES = 1048576; // limite du bucket ; la politique peut être plus stricte

const STATUS: Record<string, number> = {
  AUTH_REQUIRED: 401,
  NOT_MEMBER: 403,
  BLOCKED: 403,
  MEDIA_TOO_LARGE: 413,
  RATE_LIMITED: 429,
  VOICE_TOO_LONG: 422,
  VOICE_TOO_SHORT: 422,
  MEDIA_INVALID: 422,
  BODY_INVALID: 422,
  TTL_INVALID: 422,
  REPLY_NOT_FOUND: 422,
  IDEMPOTENCY_CONFLICT: 409,
  MEDIA_NOT_FOUND: 409,
};

const fail = (code: string) => json(STATUS[code] ?? 500, { error: code });

/** Profil sonore « 12,40,… » : 8 à 64 entiers de 0 à 100 ; undefined si absent, null si invalide. */
export function parseWaveform(raw: string | null): number[] | null | undefined {
  if (raw === null || raw === "") return undefined;
  const parts = raw.split(",");
  if (parts.length < 8 || parts.length > 64) return null;
  const values = parts.map((p) => (/^\d{1,3}$/.test(p) ? Number(p) : NaN));
  return values.every((v) => Number.isInteger(v) && v >= 0 && v <= 100) ? values : null;
}

interface Prepared {
  path: string | null;
  state: string;
  message_id: string | null;
}

interface Limits {
  voice_max_seconds: number;
  voice_max_bytes: number;
}

async function publish(req: Request, params: Record<string, unknown>) {
  const rows = await rpc<Record<string, unknown>[]>("send_voice_message", params, userHeaders(req));
  return json(200, rows[0]);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "METHOD_NOT_ALLOWED" });
  await registerEndpoint();
  if (!(req.headers.get("Authorization") ?? "").startsWith("Bearer ")) return fail("AUTH_REQUIRED");

  const q = new URL(req.url).searchParams;
  const conversationId = q.get("conversation_id") ?? "";
  const clientMsgId = q.get("client_msg_id") ?? "";
  const replyToId = q.get("reply_to_id");
  const ttlRaw = q.get("ttl_seconds");
  const ttl = ttlRaw === null ? null : Number(ttlRaw);
  const waveform = parseWaveform(q.get("waveform"));
  if (waveform === null) return fail("BODY_INVALID");
  if (
    !UUID.test(conversationId) || !UUID.test(clientMsgId) ||
    (replyToId !== null && !UUID.test(replyToId)) ||
    (ttl !== null && !Number.isInteger(ttl))
  ) {
    return fail("BODY_INVALID");
  }
  const declared = Number(req.headers.get("Content-Length") ?? "0");
  if (declared > HARD_MAX_BYTES) return fail("MEDIA_TOO_LARGE");

  const sendParams = {
    p_conversation_id: conversationId,
    p_client_msg_id: clientMsgId,
    p_reply_to_id: replyToId,
    p_ttl_seconds: ttl,
  };

  try {
    // 1. Réservation au nom de l'utilisateur (vérifie aussi son jeton et sa session).
    const [prep] = await rpc<Prepared[]>(
      "prepare_voice_message",
      { p_conversation_id: conversationId, p_client_msg_id: clientMsgId },
      userHeaders(req),
    );
    if (prep.state === "sent") return await publish(req, sendParams);
    if (!prep.path) return fail("MEDIA_NOT_FOUND");
    // Lot 7.3b : vue unique, demandée avant la publication (le message en hérite).
    if (q.get("view_once") === "1") {
      await rpc("mark_media_view_once", { p_client_msg_id: clientMsgId }, userHeaders(req));
    }

    // 2. Mesure par le serveur.
    const bytes = new Uint8Array(await req.arrayBuffer());
    const limits = await rpc<Limits>("voice_limits", {}, serviceHeaders());
    if (bytes.byteLength === 0) return fail("MEDIA_INVALID");
    if (bytes.byteLength > Math.min(limits.voice_max_bytes, HARD_MAX_BYTES)) return fail("MEDIA_TOO_LARGE");
    const { durationMs } = measureAudio(bytes);
    if (durationMs > limits.voice_max_seconds * 1000 + 500) return fail("VOICE_TOO_LONG");
    if (durationMs < 500) return fail("VOICE_TOO_SHORT");

    // 3. Dépôt privé (écrase un essai précédent interrompu).
    const up = await fetch(`${SUPABASE_URL}/storage/v1/object/voice/${prep.path}`, {
      method: "POST",
      headers: { ...serviceHeaders(), "Content-Type": "audio/mp4", "x-upsert": "true" },
      body: bytes,
    });
    if (!up.ok) {
      await up.body?.cancel();
      return json(503, { error: "STORAGE_UNAVAILABLE" });
    }
    await up.body?.cancel();

    // 4. Validation (service) puis publication (utilisateur).
    await rpc("commit_voice_upload", {
      p_path: prep.path,
      p_duration_ms: durationMs,
      p_bytes: bytes.byteLength,
      ...(waveform ? { p_waveform: waveform } : {}),
    }, serviceHeaders());
    return await publish(req, sendParams);
  } catch (e) {
    if (e instanceof MediaError || e instanceof ApiError) return fail(e.code);
    if (e instanceof RangeError) return fail("MEDIA_INVALID");
    return json(500, { error: "UNKNOWN" });
  }
});

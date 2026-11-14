// PRIVIO — envoi d'un GIF (lot 7.3b).
//
// POST /functions/v1/gif-send?conversation_id=…&client_msg_id=…&slug=…[&reply_to_id=…][&ttl_seconds=…][&filter=g|pg13]
// 1. réservation au nom de l'utilisateur (idempotent par client_msg_id) ;
// 2. le serveur demande le GIF à KLIPY (clé côté serveur) et télécharge le fichier, depuis
//    les seuls serveurs de KLIPY, 4 Mo au plus, GIF ou WebP vérifié ;
// 3. dépôt dans le compartiment privé « gifs » ; 4. validation (service) puis publication.
// Le destinataire ne contacte jamais KLIPY ; le GIF s'efface avec le message.

import { contentFilter, fetchLimited, item, KlipyError, pick, sniffImage } from "../_shared/klipy.ts";
import {
  ApiError,
  json,
  rpc,
  serviceHeaders,
  uploadObject,
  userHeaders,
} from "../_shared/supabase.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SLUG = /^[A-Za-z0-9_-]{1,200}$/;
const MAX_BYTES = 4194304;

const STATUS: Record<string, number> = {
  AUTH_REQUIRED: 401,
  NOT_MEMBER: 403,
  BLOCKED: 403,
  POSTING_RESTRICTED: 403,
  RATE_LIMITED: 429,
  MEDIA_TOO_LARGE: 413,
  MEDIA_INVALID: 422,
  BODY_INVALID: 422,
  TTL_INVALID: 422,
  REPLY_NOT_FOUND: 422,
  IDEMPOTENCY_CONFLICT: 409,
  MEDIA_NOT_FOUND: 409,
  GIF_NOT_FOUND: 404,
  GIF_UNAVAILABLE: 503,
};
const fail = (code: string) => json(STATUS[code] ?? 500, { error: code });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "METHOD_NOT_ALLOWED" });
  if (!(req.headers.get("Authorization") ?? "").startsWith("Bearer ")) return fail("AUTH_REQUIRED");
  const q = new URL(req.url).searchParams;
  const conversationId = q.get("conversation_id") ?? "";
  const clientMsgId = q.get("client_msg_id") ?? "";
  const slug = q.get("slug") ?? "";
  const replyToId = q.get("reply_to_id");
  const ttlRaw = q.get("ttl_seconds");
  const ttl = ttlRaw === null ? null : Number(ttlRaw);
  if (
    !UUID.test(conversationId) || !UUID.test(clientMsgId) || !SLUG.test(slug) ||
    (replyToId !== null && !UUID.test(replyToId)) || (ttl !== null && !Number.isInteger(ttl))
  ) {
    return fail("BODY_INVALID");
  }
  const user = userHeaders(req);
  const publish = async () => {
    const rows = await rpc<Record<string, unknown>[]>("send_gif_message", {
      p_conversation_id: conversationId,
      p_client_msg_id: clientMsgId,
      p_reply_to_id: replyToId,
      p_ttl_seconds: ttl,
    }, user);
    return json(200, rows[0]);
  };
  try {
    const [prep] = await rpc<{ path: string | null; state: string }[]>(
      "prepare_gif_message",
      { p_conversation_id: conversationId, p_client_msg_id: clientMsgId },
      user,
    );
    if (prep.state === "sent") return await publish();
    if (!prep.path) return fail("MEDIA_NOT_FOUND");
    if (prep.state === "reserved") {
      const customerId = await rpc<string>("gif_customer_id", {}, user);
      const gif = await item(slug, customerId, contentFilter(q.get("filter")));
      const r = pick(gif, ["md", "sm", "hd"]);
      if (!r) return fail("GIF_NOT_FOUND");
      const bytes = await fetchLimited(r.url, MAX_BYTES);
      if (!bytes) return fail("MEDIA_TOO_LARGE");
      const img = sniffImage(bytes);
      if (!img || img.width < 1 || img.height < 1 || Math.max(img.width, img.height) > 2048) {
        return fail("MEDIA_INVALID");
      }
      if (!await uploadObject("gifs", prep.path, bytes, img.type)) {
        return json(503, { error: "STORAGE_UNAVAILABLE" });
      }
      await rpc("commit_gif_upload", {
        p_path: prep.path,
        p_width: img.width,
        p_height: img.height,
        p_bytes: bytes.byteLength,
      }, serviceHeaders());
    }
    return await publish();
  } catch (e) {
    if (e instanceof KlipyError) return fail(e.code);
    if (e instanceof ApiError) return fail(e.code);
    return fail("GIF_UNAVAILABLE");
  }
});

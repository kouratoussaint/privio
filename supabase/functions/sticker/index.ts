// PRIVIO — autocollants personnels (lot 7.4).
//
// POST /functions/v1/sticker?action=add[&shareable=1]          corps : PNG ou WebP (512 px, 512 Ko)
// POST /functions/v1/sticker?action=remove&id=…
// POST /functions/v1/sticker?action=send&conversation_id=…&client_msg_id=…&sticker_id=…
//                                       [&reply_to_id=…][&ttl_seconds=…]
// POST /functions/v1/sticker?action=save&message_id=…           ajouter un autocollant reçu
//
// Toutes les vérifications passent par la base au nom de l'utilisateur (jeton) ; la clé de
// service ne sert qu'à déposer, recopier ou effacer les fichiers du compartiment privé
// « stickers ». Un autocollant envoyé est une copie propre au message : elle s'efface avec
// lui (purge des médias) ; la collection reste lisible par son propriétaire seul.

import { sniffImage } from "../_shared/klipy.ts";
import {
  ApiError,
  json,
  registerEndpoint,
  rpc,
  serviceHeaders,
  SUPABASE_URL,
  uploadObject,
  userHeaders,
} from "../_shared/supabase.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_BYTES = 524288;
const BUCKET = "stickers";

const STATUS: Record<string, number> = {
  AUTH_REQUIRED: 401,
  NOT_MEMBER: 403,
  BLOCKED: 403,
  POSTING_RESTRICTED: 403,
  GROUP_CLOSED: 403,
  RATE_LIMITED: 429,
  STICKER_LIMIT: 409,
  STICKER_NOT_FOUND: 404,
  STICKER_NOT_SHAREABLE: 403,
  MESSAGE_NOT_FOUND: 404,
  MESSAGE_EXPIRED: 410,
  MESSAGE_DELETED: 410,
  MEDIA_TOO_LARGE: 413,
  MEDIA_INVALID: 422,
  BODY_INVALID: 422,
  TTL_INVALID: 422,
  REPLY_NOT_FOUND: 422,
  IDEMPOTENCY_CONFLICT: 409,
  MEDIA_NOT_FOUND: 409,
};
const fail = (code: string) => json(STATUS[code] ?? 500, { error: code });

/** PNG (en-tête IHDR) ou WebP ; dimensions lues dans le fichier. */
export function sniffSticker(b: Uint8Array): { type: string; width: number; height: number } | null {
  const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (b.length > 24 && png.every((v, i) => b[i] === v)) {
    const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
    return { type: "image/png", width: dv.getUint32(16), height: dv.getUint32(20) };
  }
  const img = sniffImage(b);
  return img && img.type === "image/webp" ? img : null;
}

async function copyObject(from: string, to: string): Promise<boolean> {
  const res = await fetch(`${SUPABASE_URL}/storage/v1/object/copy`, {
    method: "POST",
    headers: { ...serviceHeaders(), "Content-Type": "application/json" },
    body: JSON.stringify({ bucketId: BUCKET, sourceKey: from, destinationKey: to }),
  });
  await res.body?.cancel();
  // Déjà copié (renvoi après une coupure) : sans conséquence.
  return res.ok || res.status === 409;
}

async function removeObject(path: string): Promise<void> {
  const res = await fetch(`${SUPABASE_URL}/storage/v1/object/${BUCKET}`, {
    method: "DELETE",
    headers: { ...serviceHeaders(), "Content-Type": "application/json" },
    body: JSON.stringify({ prefixes: [path] }),
  });
  await res.body?.cancel();
}

async function objectSize(path: string): Promise<number> {
  const res = await fetch(`${SUPABASE_URL}/storage/v1/object/info/${BUCKET}/${path}`, {
    headers: serviceHeaders(),
  });
  if (!res.ok) {
    await res.body?.cancel();
    return 0;
  }
  const info = await res.json() as { size?: number; metadata?: { size?: number } };
  return Number(info.size ?? info.metadata?.size ?? 0);
}

Deno.serve(async (req) => {
  await registerEndpoint();
  if (req.method !== "POST") return json(405, { error: "METHOD_NOT_ALLOWED" });
  if (!(req.headers.get("Authorization") ?? "").startsWith("Bearer ")) return fail("AUTH_REQUIRED");
  const q = new URL(req.url).searchParams;
  const user = userHeaders(req);
  try {
    switch (q.get("action")) {
      case "add": {
        if (Number(req.headers.get("Content-Length") ?? "0") > MAX_BYTES) return fail("MEDIA_TOO_LARGE");
        const bytes = new Uint8Array(await req.arrayBuffer());
        if (bytes.byteLength > MAX_BYTES) return fail("MEDIA_TOO_LARGE");
        const img = sniffSticker(bytes);
        if (!img || img.width < 1 || img.height < 1 || Math.max(img.width, img.height) > 512) {
          return fail("MEDIA_INVALID");
        }
        const [r] = await rpc<{ id: string; path: string }[]>(
          "reserve_sticker",
          { p_shareable: q.get("shareable") === "1" },
          user,
        );
        if (!await uploadObject(BUCKET, r.path, bytes, img.type)) {
          return json(503, { error: "STORAGE_UNAVAILABLE" });
        }
        await rpc("commit_sticker", {
          p_id: r.id,
          p_width: img.width,
          p_height: img.height,
          p_bytes: bytes.byteLength,
        }, serviceHeaders());
        return json(200, {
          id: r.id,
          path: r.path,
          shareable: q.get("shareable") === "1",
          width: img.width,
          height: img.height,
        });
      }
      case "remove": {
        const id = q.get("id") ?? "";
        if (!UUID.test(id)) return fail("BODY_INVALID");
        const path = await rpc<string>("remove_sticker", { p_id: id }, user);
        await removeObject(path);
        return json(200, { removed: true });
      }
      case "send": {
        const conversationId = q.get("conversation_id") ?? "";
        const clientMsgId = q.get("client_msg_id") ?? "";
        const stickerId = q.get("sticker_id") ?? "";
        const replyToId = q.get("reply_to_id");
        const ttlRaw = q.get("ttl_seconds");
        const ttl = ttlRaw === null ? null : Number(ttlRaw);
        if (
          !UUID.test(conversationId) || !UUID.test(clientMsgId) || !UUID.test(stickerId) ||
          (replyToId !== null && !UUID.test(replyToId)) || (ttl !== null && !Number.isInteger(ttl))
        ) {
          return fail("BODY_INVALID");
        }
        const [prep] = await rpc<{ path: string | null; source: string | null; state: string }[]>(
          "prepare_sticker_message",
          { p_conversation_id: conversationId, p_client_msg_id: clientMsgId, p_sticker_id: stickerId },
          user,
        );
        if (prep.state === "reserved" && prep.path && prep.source) {
          if (!await copyObject(prep.source, prep.path)) return json(503, { error: "STORAGE_UNAVAILABLE" });
          const size = await objectSize(prep.path);
          await rpc("commit_sticker_message", { p_path: prep.path, p_bytes: size || 1 }, serviceHeaders());
        }
        const rows = await rpc<Record<string, unknown>[]>("send_sticker_message", {
          p_conversation_id: conversationId,
          p_client_msg_id: clientMsgId,
          p_sticker_id: stickerId,
          p_reply_to_id: replyToId,
          p_ttl_seconds: ttl,
        }, user);
        return json(200, rows[0]);
      }
      case "save": {
        const messageId = q.get("message_id") ?? "";
        if (!UUID.test(messageId)) return fail("BODY_INVALID");
        const [r] = await rpc<
          { id: string; path: string; source: string; width: number; height: number }[]
        >(
          "prepare_save_sticker",
          { p_message_id: messageId },
          user,
        );
        if (!await copyObject(r.source, r.path)) return json(503, { error: "STORAGE_UNAVAILABLE" });
        await rpc("commit_sticker", {
          p_id: r.id,
          p_width: r.width,
          p_height: r.height,
          p_bytes: (await objectSize(r.path)) || 1,
        }, serviceHeaders());
        return json(200, { id: r.id, path: r.path, shareable: true, width: r.width, height: r.height });
      }
      default:
        return fail("BODY_INVALID");
    }
  } catch (e) {
    if (e instanceof ApiError) return fail(e.code);
    return json(500, { error: "UNKNOWN" });
  }
});

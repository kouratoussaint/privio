// PRIVIO — envoi d'une photo (lot 3.2).
//
// POST /functions/v1/photo-send?conversation_id=…&client_msg_id=…[&caption=…][&reply_to_id=…][&ttl_seconds=…]
// Corps : la photo JPEG (préparée par l'application). En-têtes : jeton de l'utilisateur.
//
// 1. réservation au nom de l'utilisateur, avec DÉBIT du quota du jour dans la même
//    transaction (5 photos par défaut ; idempotent par client_msg_id) ;
// 2. vérification et NETTOYAGE du fichier (métadonnées retirées : GPS, appareil, date…) ;
//    fichier refusé → réservation libérée et photo remboursée ;
// 3. dépôt dans le bucket privé « photos » ; 4. validation (service) puis publication.

import { MediaError } from "../_shared/mp4.ts";
import { cleanJpeg } from "../_shared/jpeg.ts";
import {
  ApiError,
  json,
  registerEndpoint,
  rpc,
  serviceHeaders,
  uploadObject,
  userHeaders,
} from "../_shared/supabase.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HARD_MAX_BYTES = 2097152; // limite du bucket ; la politique est plus stricte

const STATUS: Record<string, number> = {
  AUTH_REQUIRED: 401,
  NOT_MEMBER: 403,
  BLOCKED: 403,
  PHOTO_QUOTA_REACHED: 429,
  RATE_LIMITED: 429,
  MEDIA_TOO_LARGE: 413,
  MEDIA_INVALID: 422,
  BODY_INVALID: 422,
  TTL_INVALID: 422,
  REPLY_NOT_FOUND: 422,
  IDEMPOTENCY_CONFLICT: 409,
  MEDIA_NOT_FOUND: 409,
};

const fail = (code: string) => json(STATUS[code] ?? 500, { error: code });

interface Prepared {
  path: string | null;
  state: string;
  message_id: string | null;
  remaining: number | null;
}

interface Limits {
  photo_max_bytes: number;
  photo_max_dimension: number;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "METHOD_NOT_ALLOWED" });
  await registerEndpoint();
  if (!(req.headers.get("Authorization") ?? "").startsWith("Bearer ")) return fail("AUTH_REQUIRED");

  const q = new URL(req.url).searchParams;
  const conversationId = q.get("conversation_id") ?? "";
  const clientMsgId = q.get("client_msg_id") ?? "";
  const replyToId = q.get("reply_to_id");
  const caption = q.get("caption");
  const ttlRaw = q.get("ttl_seconds");
  const ttl = ttlRaw === null ? null : Number(ttlRaw);
  if (
    !UUID.test(conversationId) || !UUID.test(clientMsgId) ||
    (replyToId !== null && !UUID.test(replyToId)) ||
    (ttl !== null && !Number.isInteger(ttl)) ||
    (caption !== null && caption.length > 4000)
  ) {
    return fail("BODY_INVALID");
  }
  if (Number(req.headers.get("Content-Length") ?? "0") > HARD_MAX_BYTES) return fail("MEDIA_TOO_LARGE");

  const user = userHeaders(req);
  const publish = async () => {
    const rows = await rpc<Record<string, unknown>[]>("send_photo_message", {
      p_conversation_id: conversationId,
      p_client_msg_id: clientMsgId,
      p_caption: caption,
      p_reply_to_id: replyToId,
      p_ttl_seconds: ttl,
    }, user);
    return json(200, rows[0]);
  };

  let reserved: string | null = null;
  try {
    // 1. Réservation + débit du quota (vérifie aussi le jeton et la session).
    const [prep] = await rpc<Prepared[]>(
      "prepare_photo_message",
      { p_conversation_id: conversationId, p_client_msg_id: clientMsgId },
      user,
    );
    if (prep.state === "sent") return await publish();
    if (!prep.path) return fail("MEDIA_NOT_FOUND");
    reserved = prep.path;

    // 2. Vérification et nettoyage.
    const raw = new Uint8Array(await req.arrayBuffer());
    const limits = await rpc<Limits>("image_limits", {}, serviceHeaders());
    const photo = cleanJpeg(raw);
    if (photo.bytes.byteLength > limits.photo_max_bytes) throw new MediaError("MEDIA_TOO_LARGE");
    if (Math.max(photo.width, photo.height) > limits.photo_max_dimension) throw new MediaError("MEDIA_INVALID");

    // 3. Dépôt privé du fichier NETTOYÉ.
    if (!await uploadObject("photos", prep.path, photo.bytes, "image/jpeg")) {
      return json(503, { error: "STORAGE_UNAVAILABLE" });
    }

    // 4. Validation (service) puis publication (utilisateur).
    await rpc("commit_photo_upload", {
      p_path: prep.path,
      p_width: photo.width,
      p_height: photo.height,
      p_bytes: photo.bytes.byteLength,
    }, serviceHeaders());
    return await publish();
  } catch (e) {
    const code = e instanceof MediaError || e instanceof ApiError
      ? e.code
      : e instanceof RangeError
      ? "MEDIA_INVALID"
      : "UNKNOWN";
    // Fichier refusé avant acceptation : la photo n'est pas décomptée.
    if (reserved && (code === "MEDIA_INVALID" || code === "MEDIA_TOO_LARGE")) {
      await rpc("release_media_reservation", { p_path: reserved }, serviceHeaders()).catch(() => {});
    }
    return code === "UNKNOWN" ? json(500, { error: code }) : fail(code);
  }
});

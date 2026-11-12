// PRIVIO — photo de profil (lot 3.2).
//
// POST /functions/v1/avatar-set[?conversation_id=…] — corps : JPEG carré (≤ 1024 px).
// Sans paramètre : photo de profil. Avec conversation_id : photo du groupe (lot 3.3), selon
// le réglage « qui peut modifier les informations » du groupe.
// Vérification et nettoyage (métadonnées retirées), dépôt dans le bucket privé « avatars »,
// puis la photo devient celle du profil ; l'ancienne est effacée automatiquement.
// Retirer : RPC remove_avatar / remove_group_avatar (sans passer par cette fonction).

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

const HARD_MAX_BYTES = 1048576;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const STATUS: Record<string, number> = {
  AUTH_REQUIRED: 401,
  USER_NOT_FOUND: 404,
  NOT_MEMBER: 403,
  NOT_GROUP: 403,
  NOT_ADMIN: 403,
  BODY_INVALID: 422,
  RATE_LIMITED: 429,
  MEDIA_TOO_LARGE: 413,
  MEDIA_INVALID: 422,
  MEDIA_NOT_FOUND: 409,
};

const fail = (code: string) => json(STATUS[code] ?? 500, { error: code });

interface Limits {
  avatar_max_bytes: number;
  avatar_max_dimension: number;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "METHOD_NOT_ALLOWED" });
  await registerEndpoint();
  if (!(req.headers.get("Authorization") ?? "").startsWith("Bearer ")) return fail("AUTH_REQUIRED");
  if (Number(req.headers.get("Content-Length") ?? "0") > HARD_MAX_BYTES) return fail("MEDIA_TOO_LARGE");
  const group = new URL(req.url).searchParams.get("conversation_id");
  if (group !== null && !UUID.test(group)) return fail("BODY_INVALID");

  let reserved: string | null = null;
  try {
    reserved = group === null
      ? await rpc<string>("prepare_avatar_upload", {}, userHeaders(req))
      : await rpc<string>("prepare_group_avatar_upload", { p_conversation_id: group }, userHeaders(req));
    const raw = new Uint8Array(await req.arrayBuffer());
    const limits = await rpc<Limits>("image_limits", {}, serviceHeaders());
    const photo = cleanJpeg(raw);
    if (photo.bytes.byteLength > limits.avatar_max_bytes) throw new MediaError("MEDIA_TOO_LARGE");
    if (Math.max(photo.width, photo.height) > limits.avatar_max_dimension) {
      throw new MediaError("MEDIA_INVALID");
    }
    if (!await uploadObject("avatars", reserved, photo.bytes, "image/jpeg")) {
      return json(503, { error: "STORAGE_UNAVAILABLE" });
    }
    await rpc(group === null ? "commit_avatar" : "commit_group_avatar", {
      p_path: reserved,
      p_width: photo.width,
      p_height: photo.height,
      p_bytes: photo.bytes.byteLength,
    }, serviceHeaders());
    return json(200, { avatar_path: reserved });
  } catch (e) {
    const code = e instanceof MediaError || e instanceof ApiError
      ? e.code
      : e instanceof RangeError
      ? "MEDIA_INVALID"
      : "UNKNOWN";
    if (reserved && (code === "MEDIA_INVALID" || code === "MEDIA_TOO_LARGE")) {
      await rpc("release_media_reservation", { p_path: reserved }, serviceHeaders()).catch(() => {});
    }
    return code === "UNKNOWN" ? json(500, { error: code }) : fail(code);
  }
});

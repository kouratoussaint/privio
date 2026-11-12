// PRIVIO — photo de profil (lot 3.2).
//
// POST /functions/v1/avatar-set — corps : JPEG carré préparé par l'application (≤ 1024 px).
// Vérification et nettoyage (métadonnées retirées), dépôt dans le bucket privé « avatars »,
// puis la photo devient celle du profil ; l'ancienne est effacée automatiquement.
// Retirer sa photo : RPC remove_avatar (sans passer par cette fonction).

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

const STATUS: Record<string, number> = {
  AUTH_REQUIRED: 401,
  USER_NOT_FOUND: 404,
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

  let reserved: string | null = null;
  try {
    reserved = await rpc<string>("prepare_avatar_upload", {}, userHeaders(req));
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
    await rpc("commit_avatar", {
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

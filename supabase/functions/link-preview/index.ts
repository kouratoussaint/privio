// PRIVIO — aperçu d'un lien (lot 7.3b).
//
// POST /functions/v1/link-preview?message_id=…   (jeton de l'expéditeur)
// Le serveur de Privio lit la page (le site ne voit ni l'expéditeur ni les destinataires),
// en garde le titre, la description, le nom du site et une petite image (300 Ko au plus,
// stockage privé) ; tout s'efface avec le message.
//
// Protections : http(s) seulement, ports 80/443, aucune adresse locale ou privée (vérifiée
// à chaque redirection et après résolution DNS), 5 s et 512 Ko au plus pour la page.

import { fetchLimited, sniffImage } from "../_shared/klipy.ts";
import {
  ApiError,
  json,
  rpc,
  serviceHeaders,
  uploadObject,
  userHeaders,
} from "../_shared/supabase.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PAGE_MAX = 524288;
const IMAGE_MAX = 307200;

function privateIp(ip: string): boolean {
  const v4 = ip.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
  if (v4) {
    const [a, b] = [Number(v4[1]), Number(v4[2])];
    return a === 0 || a === 10 || a === 127 || (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) ||
      (a === 100 && b >= 64 && b <= 127) || a >= 224;
  }
  const v6 = ip.toLowerCase().replace(/^\[|\]$/g, "");
  return v6 === "::1" || v6 === "::" || v6.startsWith("fc") || v6.startsWith("fd") ||
    v6.startsWith("fe80") || v6.startsWith("::ffff:");
}

async function safeUrl(raw: string): Promise<URL | null> {
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    return null;
  }
  if (u.protocol !== "https:" && u.protocol !== "http:") return null;
  if (u.port && u.port !== "80" && u.port !== "443") return null;
  if (u.username || u.password) return null;
  const host = u.hostname.toLowerCase();
  if (host === "localhost" || host.endsWith(".localhost") || host.endsWith(".local") ||
    host.endsWith(".internal") || !host.includes(".")) return null;
  if (/^[\d.]+$/.test(host) || host.includes(":") || host.startsWith("[")) {
    return privateIp(host) ? null : u;
  }
  try {
    const addrs = [
      ...(await Deno.resolveDns(host, "A").catch(() => [] as string[])),
      ...(await Deno.resolveDns(host, "AAAA").catch(() => [] as string[])),
    ];
    if (addrs.some(privateIp)) return null;
  } catch {
    // Résolution indisponible : seules les vérifications ci-dessus s'appliquent.
  }
  return u;
}

/** Suit au plus 3 redirections, chacune vérifiée. */
async function fetchSafe(raw: string, accept: string): Promise<Response | null> {
  let url = await safeUrl(raw);
  for (let i = 0; url && i < 4; i++) {
    const res = await fetch(url, {
      redirect: "manual",
      signal: AbortSignal.timeout(5000),
      headers: { "User-Agent": "PrivioBot/1.0 (apercu de lien)", Accept: accept },
    });
    if (res.status >= 300 && res.status < 400) {
      const next = res.headers.get("Location");
      await res.body?.cancel();
      url = next ? await safeUrl(new URL(next, url).toString()) : null;
      continue;
    }
    return res.ok ? res : (await res.body?.cancel(), null);
  }
  return null;
}

async function readLimited(res: Response, max: number): Promise<Uint8Array | null> {
  if (!res.body) return null;
  const reader = res.body.getReader();
  const parts: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > max) {
      await reader.cancel();
      // Page trop longue : on garde le début (les balises utiles sont dans <head>).
      if (max === PAGE_MAX) break;
      return null;
    }
    parts.push(value);
  }
  const out = new Uint8Array(parts.reduce((n, p) => n + p.byteLength, 0));
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.byteLength;
  }
  return out;
}

function decode(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|amp|quot|apos|lt|gt|nbsp|#39);/gi, (m, e: string) => {
    const k = e.toLowerCase();
    if (k === "amp") return "&";
    if (k === "quot") return '"';
    if (k === "apos" || k === "#39") return "'";
    if (k === "lt") return "<";
    if (k === "gt") return ">";
    if (k === "nbsp") return " ";
    const n = k.startsWith("#x") ? parseInt(k.slice(2), 16) : parseInt(k.slice(1), 10);
    return Number.isFinite(n) && n > 0 && n < 0x110000 ? String.fromCodePoint(n) : m;
  }).replace(/\s+/g, " ").trim();
}

function metaTags(html: string): Map<string, string> {
  const out = new Map<string, string>();
  for (const tag of html.matchAll(/<meta\b[^>]*>/gi)) {
    const attrs = new Map<string, string>();
    for (const a of tag[0].matchAll(/([a-zA-Z:_-]+)\s*=\s*("([^"]*)"|'([^']*)')/g)) {
      attrs.set(a[1].toLowerCase(), a[3] ?? a[4] ?? "");
    }
    const key = (attrs.get("property") ?? attrs.get("name") ?? "").toLowerCase();
    const content = attrs.get("content");
    if (key && content && !out.has(key)) out.set(key, decode(content));
  }
  return out;
}

function jpegSize(b: Uint8Array): { width: number; height: number } | null {
  if (b[0] !== 0xff || b[1] !== 0xd8) return null;
  let i = 2;
  while (i + 9 < b.length) {
    if (b[i] !== 0xff) return null;
    const marker = b[i + 1];
    const len = (b[i + 2] << 8) | b[i + 3];
    if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
      return { height: (b[i + 5] << 8) | b[i + 6], width: (b[i + 7] << 8) | b[i + 8] };
    }
    i += 2 + len;
  }
  return null;
}

function imageInfo(b: Uint8Array): { type: string; width: number; height: number } | null {
  const jpg = jpegSize(b);
  if (jpg) return { type: "image/jpeg", ...jpg };
  if (b.length > 24 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) {
    const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
    return { type: "image/png", width: dv.getUint32(16), height: dv.getUint32(20) };
  }
  const w = sniffImage(b);
  return w && w.type === "image/webp" ? w : null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "METHOD_NOT_ALLOWED" });
  if (!(req.headers.get("Authorization") ?? "").startsWith("Bearer ")) {
    return json(401, { error: "AUTH_REQUIRED" });
  }
  const messageId = new URL(req.url).searchParams.get("message_id") ?? "";
  if (!UUID.test(messageId)) return json(422, { error: "BODY_INVALID" });
  try {
    const target = await rpc<string | null>(
      "link_preview_target",
      { p_message_id: messageId },
      userHeaders(req),
    );
    if (!target) return json(200, { preview: false });

    const page = await fetchSafe(target, "text/html,application/xhtml+xml");
    if (!page || !(page.headers.get("Content-Type") ?? "").includes("html")) {
      await page?.body?.cancel();
      return json(200, { preview: false });
    }
    const raw = await readLimited(page, PAGE_MAX);
    if (!raw) return json(200, { preview: false });
    const html = new TextDecoder().decode(raw);
    const meta = metaTags(html);
    const titleTag = html.match(/<title[^>]*>([^<]{1,500})<\/title>/i)?.[1];
    const title = meta.get("og:title") ?? meta.get("twitter:title") ??
      (titleTag ? decode(titleTag) : null);
    const description = meta.get("og:description") ?? meta.get("twitter:description") ??
      meta.get("description") ?? null;
    const site = meta.get("og:site_name") ?? new URL(target).hostname.replace(/^www\./, "");

    let image: { path: string; width: number; height: number; bytes: number } | null = null;
    const imageUrl = meta.get("og:image") ?? meta.get("twitter:image");
    if (imageUrl) {
      try {
        const res = await fetchSafe(new URL(imageUrl, target).toString(), "image/*");
        const bytes = res ? await readLimited(res, IMAGE_MAX) : null;
        const info = bytes ? imageInfo(bytes) : null;
        if (bytes && info && info.width > 0 && info.height > 0 && Math.max(info.width, info.height) <= 8192) {
          const path = `link/${messageId}`;
          if (await uploadObject("previews", path, bytes, info.type)) {
            image = { path, width: info.width, height: info.height, bytes: bytes.byteLength };
          }
        }
      } catch {
        // Pas d'image : l'aperçu garde le texte.
      }
    }
    if (!title && !description && !image) return json(200, { preview: false });
    await rpc("save_link_preview", {
      p_message_id: messageId,
      p_url: target,
      p_title: title?.slice(0, 300) ?? null,
      p_description: description?.slice(0, 500) ?? null,
      p_site: site.slice(0, 100),
      p_image_path: image?.path ?? null,
      p_image_width: image?.width ?? null,
      p_image_height: image?.height ?? null,
      p_image_bytes: image?.bytes ?? null,
    }, serviceHeaders());
    return json(200, { preview: true });
  } catch (e) {
    if (e instanceof ApiError) {
      return json(e.code === "AUTH_REQUIRED" ? 401 : e.code === "RATE_LIMITED" ? 429 : 403, {
        error: e.code,
      });
    }
    return json(200, { preview: false });
  }
});

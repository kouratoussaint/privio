// Lot 7.3b — accès à KLIPY (GIF). La clé n'existe que dans l'environnement des fonctions.
//
// Recherche : GET https://api.klipy.com/api/v1/{clé}/gifs/search?q=…&page=…&per_page=…
// Tendances : GET https://api.klipy.com/api/v1/{clé}/gifs/trending?page=…&per_page=…
// Un GIF    : GET https://api.klipy.com/api/v1/{clé}/gifs/{slug}
// Réponse   : { result, data: { data: [ … ], has_next } } ; chaque GIF a un « slug » et
//             « file » : { hd|md|sm|xs : { gif|webp|… : { url, width, height, size } } }.

export const KLIPY_KEY = Deno.env.get("KLIPY_API_KEY") ?? "";
const BASE = "https://api.klipy.com/api/v1";

/** Filtre de contenu : « g » (tout public, par défaut) ou « pg13 » (modéré). */
export function contentFilter(level: string | null): string {
  return level === "pg13" ? "medium" : "high";
}

export interface Rendition {
  url: string;
  width: number;
  height: number;
  size?: number;
}

type Formats = Record<string, Rendition | undefined>;
export interface KlipyGif {
  slug: string;
  title?: string;
  file?: Record<string, Formats | undefined>;
}

export class KlipyError extends Error {
  constructor(readonly code: string, readonly status: number) {
    super(code);
  }
}

async function call(path: string, params: Record<string, string>): Promise<unknown> {
  if (!KLIPY_KEY) throw new KlipyError("GIF_UNAVAILABLE", 503);
  const url = new URL(`${BASE}/${encodeURIComponent(KLIPY_KEY)}/${path}`);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
  const text = await res.text();
  if (!res.ok) throw new KlipyError("GIF_UNAVAILABLE", 503);
  try {
    return JSON.parse(text);
  } catch {
    throw new KlipyError("GIF_UNAVAILABLE", 503);
  }
}

function itemsOf(body: unknown): { items: KlipyGif[]; hasNext: boolean } {
  const outer = (body as { data?: unknown })?.data;
  const inner = (outer as { data?: unknown })?.data;
  const list = Array.isArray(inner) ? inner : Array.isArray(outer) ? outer : [];
  const hasNext = Boolean((outer as { has_next?: boolean })?.has_next);
  return {
    items: list.filter((g): g is KlipyGif =>
      typeof (g as KlipyGif)?.slug === "string" && typeof (g as KlipyGif)?.file === "object"
    ),
    hasNext,
  };
}

export async function search(
  query: string,
  page: number,
  customerId: string,
  filter: string,
): Promise<{ items: KlipyGif[]; hasNext: boolean }> {
  const params: Record<string, string> = {
    page: String(page),
    per_page: "24",
    customer_id: customerId,
    locale: "fr",
    content_filter: filter,
    format_filter: "gif,webp",
  };
  if (query) params.q = query;
  return itemsOf(await call(query ? "gifs/search" : "gifs/trending", params));
}

export async function item(slug: string, customerId: string, filter: string): Promise<KlipyGif> {
  const body = await call(`gifs/${encodeURIComponent(slug)}`, {
    customer_id: customerId,
    content_filter: filter,
  });
  const data = (body as { data?: unknown })?.data;
  const g = (data as { data?: unknown })?.data ?? data;
  const one = Array.isArray(g) ? g[0] : g;
  if (typeof (one as KlipyGif)?.slug !== "string") throw new KlipyError("GIF_NOT_FOUND", 404);
  return one as KlipyGif;
}

/** Fichiers venant uniquement des serveurs de KLIPY (pas d'adresse arbitraire). */
export function isKlipyUrl(raw: string): boolean {
  try {
    const u = new URL(raw);
    return u.protocol === "https:" &&
      (u.hostname === "klipy.com" || u.hostname.endsWith(".klipy.com") ||
        u.hostname === "klipy.co" || u.hostname.endsWith(".klipy.co"));
  } catch {
    return false;
  }
}

/** Aperçu pour la grille (petite taille) et fichier à envoyer (taille moyenne). */
export function pick(g: KlipyGif, sizes: string[]): Rendition | null {
  for (const s of sizes) {
    const f = g.file?.[s];
    for (const fmt of ["webp", "gif"]) {
      const r = f?.[fmt];
      if (r?.url && isKlipyUrl(r.url) && r.width > 0 && r.height > 0) return r;
    }
  }
  return null;
}

/** Type et dimensions lus dans le fichier lui-même (GIF ou WebP), null sinon. */
export function sniffImage(b: Uint8Array): { type: string; width: number; height: number } | null {
  const ascii = (o: number, n: number) => String.fromCharCode(...b.subarray(o, o + n));
  if (b.length > 10 && (ascii(0, 6) === "GIF87a" || ascii(0, 6) === "GIF89a")) {
    return { type: "image/gif", width: b[6] | (b[7] << 8), height: b[8] | (b[9] << 8) };
  }
  if (b.length > 30 && ascii(0, 4) === "RIFF" && ascii(8, 4) === "WEBP") {
    const chunk = ascii(12, 4);
    if (chunk === "VP8X") {
      return {
        type: "image/webp",
        width: 1 + (b[24] | (b[25] << 8) | (b[26] << 16)),
        height: 1 + (b[27] | (b[28] << 8) | (b[29] << 16)),
      };
    }
    if (chunk === "VP8 ") {
      return { type: "image/webp", width: (b[26] | (b[27] << 8)) & 0x3fff, height: (b[28] | (b[29] << 8)) & 0x3fff };
    }
    if (chunk === "VP8L") {
      const bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
      return { type: "image/webp", width: (bits & 0x3fff) + 1, height: ((bits >> 14) & 0x3fff) + 1 };
    }
  }
  return null;
}

/** Télécharge au plus [max] octets (sinon null). */
export async function fetchLimited(url: string, max: number): Promise<Uint8Array | null> {
  const res = await fetch(url, { signal: AbortSignal.timeout(10000), redirect: "error" });
  if (!res.ok || !res.body) {
    await res.body?.cancel();
    return null;
  }
  const declared = Number(res.headers.get("Content-Length") ?? "0");
  if (declared > max) {
    await res.body.cancel();
    return null;
  }
  const reader = res.body.getReader();
  const parts: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > max) {
      await reader.cancel();
      return null;
    }
    parts.push(value);
  }
  const out = new Uint8Array(total);
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.byteLength;
  }
  return out;
}

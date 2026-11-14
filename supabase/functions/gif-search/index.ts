// PRIVIO — recherche de GIF (lot 7.3b).
//
// GET /functions/v1/gif-search?q=…&page=1&filter=g|pg13   (q vide : tendances)
// En-têtes : jeton de l'utilisateur. La clé KLIPY reste ici ; KLIPY ne reçoit qu'un
// identifiant pseudonyme. Réponse : { items: [{ slug, title, url, width, height }], has_next }
// (url : petit aperçu servi par KLIPY, chargé seulement quand l'onglet GIF est ouvert).

import { contentFilter, KlipyError, pick, search } from "../_shared/klipy.ts";
import { ApiError, json, rpc, userHeaders } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "GET") return json(405, { error: "METHOD_NOT_ALLOWED" });
  if (!(req.headers.get("Authorization") ?? "").startsWith("Bearer ")) {
    return json(401, { error: "AUTH_REQUIRED" });
  }
  const q = new URL(req.url).searchParams;
  const query = (q.get("q") ?? "").trim().slice(0, 100);
  const page = Math.min(Math.max(Number(q.get("page") ?? "1") || 1, 1), 20);
  try {
    // Vérifie le jeton et la session, limite les recherches, donne l'identifiant pseudonyme.
    const customerId = await rpc<string>("gif_customer_id", {}, userHeaders(req));
    const result = await search(query, page, customerId, contentFilter(q.get("filter")));
    const items = result.items.flatMap((g) => {
      const r = pick(g, ["sm", "xs", "md"]);
      return r ? [{ slug: g.slug, title: g.title ?? "", url: r.url, width: r.width, height: r.height }] : [];
    });
    return json(200, { items, has_next: result.hasNext });
  } catch (e) {
    if (e instanceof KlipyError) return json(e.status, { error: e.code });
    if (e instanceof ApiError) {
      return json(e.code === "AUTH_REQUIRED" ? 401 : e.code === "RATE_LIMITED" ? 429 : 403, {
        error: e.code,
      });
    }
    return json(503, { error: "GIF_UNAVAILABLE" });
  }
});

// PRIVIO — serveurs réseau d'un appel (lot 9.1a, ADR-036).
//
// POST /functions/v1/call-ice   (jeton de l'utilisateur)
// Seulement pendant un appel (vérifié par la base). Renvoie { iceServers } : le STUN
// Cloudflare (gratuit) et, si la clé du relais est configurée, un accès TURN Cloudflare
// valable 2 heures. La clé du relais reste ici, jamais dans l'application.

import { ApiError, json, rpc, userHeaders } from "../_shared/supabase.ts";

const STUN = { urls: ["stun:stun.cloudflare.com:3478"] };

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "METHOD_NOT_ALLOWED" });
  if (!(req.headers.get("Authorization") ?? "").startsWith("Bearer ")) {
    return json(401, { error: "AUTH_REQUIRED" });
  }
  try {
    const allowed = await rpc<boolean>("can_use_call_relay", {}, userHeaders(req));
    if (!allowed) return json(403, { error: "CALL_NOT_FOUND" });
  } catch (e) {
    if (e instanceof ApiError) return json(e.code === "AUTH_REQUIRED" ? 401 : 403, { error: e.code });
    return json(503, { error: "UNAVAILABLE" });
  }

  const keyId = Deno.env.get("CLOUDFLARE_TURN_KEY_ID") ?? "";
  const token = Deno.env.get("CLOUDFLARE_TURN_API_TOKEN") ?? "";
  if (!keyId || !token) return json(200, { iceServers: [STUN], relay: false });
  try {
    const res = await fetch(
      `https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(keyId)}/credentials/generate-ice-servers`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({ ttl: 7200 }),
      },
    );
    if (!res.ok) {
      await res.body?.cancel();
      return json(200, { iceServers: [STUN], relay: false });
    }
    const body = await res.json() as { iceServers?: unknown };
    const servers = Array.isArray(body.iceServers) ? body.iceServers : [body.iceServers];
    // Les adresses sur le port 53 sont souvent bloquées sur mobile : on les retire.
    const clean = servers.filter(Boolean).map((s) => {
      const srv = s as { urls: string | string[]; username?: string; credential?: string };
      const urls = (Array.isArray(srv.urls) ? srv.urls : [srv.urls]).filter((u) => !u.includes(":53?"));
      return { ...srv, urls };
    });
    return json(200, { iceServers: clean, relay: true });
  } catch {
    return json(200, { iceServers: [STUN], relay: false });
  }
});

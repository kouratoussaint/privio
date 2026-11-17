// PRIVIO — serveurs réseau d'un appel (lot 9.1a, ADR-036).
//
// POST /functions/v1/call-ice   (jeton de l'utilisateur)
// Seulement pendant un appel (vérifié par la base). Renvoie { iceServers } : le STUN
// Cloudflare (gratuit) et, si la clé du relais est configurée, un accès TURN Cloudflare
// valable 2 heures. La clé du relais reste ici, jamais dans l'application.
//
// Lot 5.7 (ADR-047) : { "test": true } — diagnostic de la console, réservé à
// l'administration (vérifié et journalisé par la base) : demande un accès au relais et
// renvoie seulement le résultat ({ relay: "ok" | "not_configured" | "failed" }), jamais
// l'accès lui-même.

import { ApiError, json, rpc, userHeaders } from "../_shared/supabase.ts";

const STUN = { urls: ["stun:stun.cloudflare.com:3478"] };

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "METHOD_NOT_ALLOWED" });
  if (!(req.headers.get("Authorization") ?? "").startsWith("Bearer ")) {
    return json(401, { error: "AUTH_REQUIRED" });
  }
  const body = await req.json().catch(() => ({})) as { test?: unknown };
  if (body?.test === true) return await relayTest(req);
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

/** Diagnostic de la console : le relais répond-il ? (aucun accès renvoyé). */
async function relayTest(req: Request): Promise<Response> {
  try {
    await rpc<boolean>("console_relay_test", {}, userHeaders(req));
  } catch (e) {
    if (e instanceof ApiError) return json(e.code === "AUTH_REQUIRED" ? 401 : 403, { error: e.code });
    return json(503, { error: "UNAVAILABLE" });
  }
  const keyId = Deno.env.get("CLOUDFLARE_TURN_KEY_ID") ?? "";
  const token = Deno.env.get("CLOUDFLARE_TURN_API_TOKEN") ?? "";
  if (!keyId || !token) return json(200, { stun: true, relay: "not_configured" });
  const started = Date.now();
  try {
    const res = await fetch(
      `https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(keyId)}/credentials/generate-ice-servers`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({ ttl: 60 }),
      },
    );
    const ms = Date.now() - started;
    if (!res.ok) {
      await res.body?.cancel();
      return json(200, { stun: true, relay: "failed", http: res.status, ms });
    }
    const out = await res.json() as { iceServers?: unknown };
    const servers = Array.isArray(out.iceServers) ? out.iceServers : [out.iceServers];
    const turn = servers.filter(Boolean).flatMap((s) => {
      const u = (s as { urls?: string | string[] }).urls ?? [];
      return (Array.isArray(u) ? u : [u]).filter((x) => x.startsWith("turn"));
    }).length;
    return json(200, { stun: true, relay: turn > 0 ? "ok" : "failed", addresses: turn, ms });
  } catch {
    return json(200, { stun: true, relay: "failed", ms: Date.now() - started });
  }
}

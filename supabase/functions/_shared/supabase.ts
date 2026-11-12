// Accès minimal à l'API Supabase (PostgREST et Storage) par fetch, sans dépendance.
// La clé de service n'existe QUE dans l'environnement des fonctions, jamais dans l'app.

export const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");

function firstKey(json: string | undefined): string | undefined {
  if (!json) return undefined;
  try {
    const all = JSON.parse(json) as Record<string, string>;
    return all["default"] ?? Object.values(all)[0];
  } catch {
    return undefined;
  }
}

/** Clé de service : ancienne clé JWT ou nouvelle clé secrète (sb_secret_…). */
export const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  firstKey(Deno.env.get("SUPABASE_SECRET_KEYS")) ?? "";

/** Clé publique de repli quand la requête n'en fournit pas. */
export const PUBLIC_KEY = Deno.env.get("SUPABASE_ANON_KEY") ??
  firstKey(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")) ?? "";

/** En-têtes « service » : une clé sb_… ne va que dans apikey (la passerelle la convertit). */
export function serviceHeaders(): Record<string, string> {
  return SERVICE_KEY.startsWith("sb_")
    ? { apikey: SERVICE_KEY }
    : { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` };
}

/** En-têtes « utilisateur » : son jeton, vérifié par PostgREST et par la base. */
export function userHeaders(req: Request): Record<string, string> {
  return {
    apikey: req.headers.get("apikey") ?? PUBLIC_KEY,
    Authorization: req.headers.get("Authorization") ?? "",
  };
}

export class ApiError extends Error {
  constructor(readonly code: string, readonly status: number) {
    super(code);
  }
}

/** Appelle une fonction SQL. Les erreurs métier (raise exception 'CODE') gardent leur code. */
export async function rpc<T>(
  name: string,
  params: Record<string, unknown>,
  headers: Record<string, string>,
): Promise<T> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify(params),
  });
  const text = await res.text();
  if (!res.ok) {
    let code = res.status === 401 ? "AUTH_REQUIRED" : "UNKNOWN";
    try {
      const err = JSON.parse(text) as { code?: string; message?: string };
      if (err.code === "P0001" && err.message) code = err.message.trim();
      else if (err.code === "PGRST301" || err.code === "PGRST302" || res.status === 401) {
        code = "AUTH_REQUIRED";
      }
    } catch {
      // réponse non JSON : code générique
    }
    throw new ApiError(code, res.status);
  }
  return (text ? JSON.parse(text) : null) as T;
}

let registered = false;

/** Déclare l'adresse des fonctions à la base (une fois par instance), pour la purge planifiée. */
export async function registerEndpoint(): Promise<void> {
  if (registered || !SUPABASE_URL || !SERVICE_KEY) return;
  try {
    await rpc("media_register_endpoint", { p_functions_url: `${SUPABASE_URL}/functions/v1` }, serviceHeaders());
    registered = true;
  } catch {
    // Sans conséquence sur la requête en cours ; nouvel essai à la prochaine.
  }
}

export function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

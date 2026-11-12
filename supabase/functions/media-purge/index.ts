// PRIVIO — effacement physique des fichiers médias (lot 3.1).
//
// Appelée chaque minute par la base (pg_cron + pg_net) quand des fichiers attendent
// d'être effacés : vocaux expirés, supprimés pour tous, réservations abandonnées.
// Les fichiers sont déjà illisibles (politique Storage) ; ici on libère le stockage par
// l'API Storage, seule méthode qui efface réellement l'objet.
//
// En-tête x-privio-purge : jeton aléatoire créé par la migration et vérifié par la base.
// Sans jeton, la fonction se contente de déclarer son adresse (appel après déploiement).

import {
  ApiError,
  json,
  registerEndpoint,
  rpc,
  serviceHeaders,
  SUPABASE_URL,
} from "../_shared/supabase.ts";

interface Claimed {
  bucket: string;
  path: string;
}

Deno.serve(async (req) => {
  await registerEndpoint();
  const token = req.headers.get("x-privio-purge");
  if (!token) return json(200, { registered: true });

  let removed = 0;
  try {
    for (let round = 0; round < 5; round++) {
      const batch = await rpc<Claimed[]>(
        "media_purge_claim",
        { p_token: token, p_limit: 100 },
        serviceHeaders(),
      );
      if (batch.length === 0) break;
      const byBucket = new Map<string, string[]>();
      for (const c of batch) byBucket.set(c.bucket, [...(byBucket.get(c.bucket) ?? []), c.path]);
      for (const [bucket, paths] of byBucket) {
        // Un objet déjà absent n'est pas une erreur : l'effacement est idempotent.
        const res = await fetch(`${SUPABASE_URL}/storage/v1/object/${bucket}`, {
          method: "DELETE",
          headers: { ...serviceHeaders(), "Content-Type": "application/json" },
          body: JSON.stringify({ prefixes: paths }),
        });
        await res.body?.cancel();
        if (!res.ok) {
          // Les fichiers restent réservés 5 minutes, puis repartent dans un lot.
          return json(502, { error: "STORAGE_UNAVAILABLE", removed });
        }
        removed += await rpc<number>(
          "media_purge_complete",
          { p_token: token, p_paths: paths },
          serviceHeaders(),
        );
      }
    }
  } catch (e) {
    if (e instanceof ApiError) return json(e.code === "AUTH_REQUIRED" ? 401 : 500, { error: e.code });
    return json(500, { error: "UNKNOWN" });
  }
  return json(200, { removed });
});

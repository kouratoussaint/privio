// Envoi FCM HTTP v1 avec un compte de service Google (secret FCM_SERVICE_ACCOUNT, JSON).
// Le compte de service n'existe QUE dans l'environnement des fonctions, jamais dans l'app.

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

export function loadServiceAccount(): ServiceAccount | null {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) return null;
  try {
    const sa = JSON.parse(raw) as ServiceAccount;
    return sa.project_id && sa.client_email && sa.private_key ? sa : null;
  } catch {
    return null;
  }
}

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const enc = new TextEncoder();

let cached: { token: string; until: number } | null = null;

/** Jeton d'accès OAuth 2 (JWT signé RS256), mis en cache 50 minutes. */
async function accessToken(sa: ServiceAccount): Promise<string> {
  if (cached && Date.now() < cached.until) return cached.token;
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(enc.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = b64url(enc.encode(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, enc.encode(`${header}.${claims}`)),
  );
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claims}.${b64url(signature)}`,
    }),
  });
  if (!res.ok) throw new Error(`oauth ${res.status}`);
  const body = await res.json() as { access_token: string };
  cached = { token: body.access_token, until: Date.now() + 50 * 60 * 1000 };
  return body.access_token;
}

export type SendResult = "sent" | "invalid_token" | "failed";

/** Notification GÉNÉRIQUE : aucun nom, aucun contenu ; masquée sur l'écran verrouillé. */
export function sendGeneric(
  sa: ServiceAccount,
  token: string,
  conversationId: string,
  isGroup: boolean,
): Promise<SendResult> {
  return sendNotification(sa, token, {
    body: isGroup ? "Nouveau message dans un groupe" : "Nouveau message",
    data: { type: "message", conversation_id: conversationId },
    // Une seule notification par discussion (les suivantes la remplacent).
    tag: conversationId,
  });
}

/** Textes (sans nom ni contenu) des notifications de demande de connexion (lot 4.7). */
export const REQUEST_BODIES: Record<string, string> = {
  received: "Nouvelle demande de connexion",
  accepted: "Votre demande de connexion a été acceptée",
  refused: "Réponse à votre demande de connexion",
};

/** Demande de connexion : reçue (destinataire), acceptée ou refusée (expéditeur). */
export function sendRequestEvent(
  sa: ServiceAccount,
  token: string,
  event: string,
): Promise<SendResult> {
  return sendNotification(sa, token, {
    body: REQUEST_BODIES[event] ?? "Privio",
    data: { type: "request", event },
    tag: "privio-requests",
  });
}

async function sendNotification(
  sa: ServiceAccount,
  token: string,
  n: { body: string; data: Record<string, string>; tag: string },
): Promise<SendResult> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${await accessToken(sa)}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: "Privio", body: n.body },
          data: n.data,
          android: {
            priority: "HIGH",
            ttl: "86400s",
            notification: {
              channel_id: "privio_messages",
              icon: "ic_stat_privio",
              color: "#5B1FB8",
              tag: n.tag,
              visibility: "PRIVATE",
            },
          },
        },
      }),
    },
  );
  if (res.ok) {
    await res.body?.cancel();
    return "sent";
  }
  const text = await res.text();
  // Jeton expiré ou application désinstallée : FCM répond UNREGISTERED / INVALID_ARGUMENT.
  if (res.status === 404 || (res.status === 400 && /registration|UNREGISTERED|INVALID_ARGUMENT/.test(text))) {
    return "invalid_token";
  }
  return "failed";
}

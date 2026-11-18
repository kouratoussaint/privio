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

/** Mention dans un groupe (lot 7.1b) : envoyée même si le groupe est en sourdine. */
export const MENTION_BODY = "Vous avez été mentionné dans un groupe";

/** Notification GÉNÉRIQUE : aucun nom, aucun contenu ; masquée sur l'écran verrouillé. */
export function sendGeneric(
  sa: ServiceAccount,
  token: string,
  conversationId: string,
  isGroup: boolean,
  mentioned = false,
  secret = false,
): Promise<SendResult> {
  // Lot 10.2 : discussion cachée → texte neutre, aucune discussion à ouvrir (Privio s'ouvre
  // normalement), une seule notification pour toutes les discussions cachées.
  if (secret) {
    return sendNotification(sa, token, {
      body: "Nouveau message",
      data: { type: "message" },
      tag: "privio-secret",
    });
  }
  return sendNotification(sa, token, {
    body: mentioned ? MENTION_BODY : isGroup ? "Nouveau message dans un groupe" : "Nouveau message",
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

/** Invitation à rejoindre un groupe (lot 4.8) : ni nom du groupe, ni nom de l'invitant. */
export const INVITATION_BODY = "Nouvelle invitation à rejoindre un groupe";

export function sendInvitation(sa: ServiceAccount, token: string): Promise<SendResult> {
  return sendNotification(sa, token, {
    body: INVITATION_BODY,
    data: { type: "invitation" },
    tag: "privio-invitations",
  });
}

/** Demandes d'adhésion à un groupe (lot 7.1b) : ni nom du groupe, ni nom de la personne. */
export const JOIN_BODIES: Record<string, string> = {
  join_request: "Nouvelle demande pour rejoindre un groupe",
  join_approved: "Votre demande pour rejoindre un groupe a été acceptée",
};

/** Demande reçue (administrateurs : la fiche du groupe) ou acceptée (le groupe s'ouvre). */
export function sendJoinEvent(
  sa: ServiceAccount,
  token: string,
  event: string,
  conversationId: string,
): Promise<SendResult> {
  return sendNotification(sa, token, {
    body: JOIN_BODIES[event] ?? "Privio",
    data: { type: event, conversation_id: conversationId },
    tag: `privio-join-${conversationId}`,
  });
}

/** Administration (lot 5.3) : aucun nom, aucun contenu ; l'appui ouvre la console. */
export const ADMIN_BODIES: Record<string, string> = {
  report: "Nouveau signalement à traiter",
  support: "Nouvelle demande d’assistance",
  appeal: "Nouvelle contestation à examiner",
  // Lot 5.7 : alertes de la santé du service et notification de test (aucun contenu).
  alert_purge: "Alerte : l’effacement automatique est en retard",
  alert_sms: "Alerte : beaucoup de codes SMS demandés",
  alert_failures: "Alerte : des notifications ou des appels échouent",
  alert_relay: "Alerte : relais des appels à 80 % du volume gratuit",
  // Lot 5.9 : console ouverte sur un téléphone jamais vu pour la console.
  alert_console_device: "Console ouverte sur un nouveau téléphone",
  test: "Notification de test de la console Privio",
};

export function sendAdminEvent(sa: ServiceAccount, token: string, event: string): Promise<SendResult> {
  return sendNotification(sa, token, {
    body: ADMIN_BODIES[event] ?? "Privio",
    data: { type: "console", event },
    tag: "privio-console",
  });
}

/** Réponse de l'assistance (lot 5.4) : sans contenu ; l'appui ouvre Aide → Mes demandes. */
export const SUPPORT_REPLY_BODY = "L’équipe Privio a répondu à votre demande";

export function sendSupportReply(sa: ServiceAccount, token: string): Promise<SendResult> {
  return sendNotification(sa, token, {
    body: SUPPORT_REPLY_BODY,
    data: { type: "support" },
    tag: "privio-support",
  });
}

/** Rappel avant effacement (lot 8.4b) : sans nom ni contenu ; l'appui ouvre la discussion. */
export const EXPIRY_REMINDER_BODY = "Des messages non lus vont bientôt s’effacer";

export function sendExpiryReminder(
  sa: ServiceAccount,
  token: string,
  conversationId: string,
): Promise<SendResult> {
  return sendNotification(sa, token, {
    body: EXPIRY_REMINDER_BODY,
    data: { type: "message", conversation_id: conversationId },
    tag: `privio-expiry-${conversationId}`,
  });
}

/** Lot 9.1b : appel entrant. Message de données seul, prioritaire, valable le temps de la
 * sonnerie : l'application affiche elle-même l'écran d'appel (sans nom tant que le téléphone
 * ou Privio est verrouillé). Ni nom, ni numéro dans le message. */
export async function sendCallRing(
  sa: ServiceAccount,
  token: string,
  callId: string,
  conversationId: string,
  createdAt: string,
  kind: string,
): Promise<SendResult> {
  return await sendData(sa, token, {
    type: "call",
    call_id: callId,
    conversation_id: conversationId,
    created_at: createdAt,
    // Lot 9.2 : « audio » ou « video » (l'écran d'appel l'annonce, toujours sans nom).
    kind: kind === "video" ? "video" : "audio",
  }, "45s");
}

/** Lot 9.1b : appel non décroché. Arrête la sonnerie, puis « Appel manqué » (sans nom). */
export const MISSED_CALL_BODY = "Appel manqué";

export async function sendCallMissed(
  sa: ServiceAccount,
  token: string,
  callId: string,
  conversationId: string,
  muted: boolean,
  secret = false,
): Promise<SendResult> {
  const stop = await sendData(sa, token, { type: "call_end", call_id: callId }, "60s");
  if (stop === "invalid_token" || muted) return stop;
  // Lot 10.2 : discussion cachée → « Appel manqué » sans discussion à ouvrir.
  return await sendNotification(sa, token, {
    body: MISSED_CALL_BODY,
    data: secret ? { type: "message" } : { type: "message", conversation_id: conversationId },
    tag: secret ? "privio-secret-call" : `privio-call-${conversationId}`,
  });
}

/** Lot 9.4 : appel de groupe qui sonne (groupe de 16 membres ou moins), sans nom. */
export async function sendGroupCallRing(
  sa: ServiceAccount,
  token: string,
  callId: string,
  conversationId: string,
  createdAt: string,
  kind: string,
): Promise<SendResult> {
  return await sendData(sa, token, {
    type: "group_call",
    call_id: callId,
    conversation_id: conversationId,
    created_at: createdAt,
    kind: kind === "video" ? "video" : "audio",
  }, "45s");
}

/** Lot 9.4 : sonnerie de groupe sans réponse. Arrêt, puis « Appel de groupe manqué ». */
export const MISSED_GROUP_CALL_BODY = "Appel de groupe manqué";

export async function sendGroupCallMissed(
  sa: ServiceAccount,
  token: string,
  callId: string,
  conversationId: string,
  secret = false,
): Promise<SendResult> {
  const stop = await sendData(sa, token, { type: "call_end", call_id: callId }, "60s");
  if (stop === "invalid_token") return stop;
  return await sendNotification(sa, token, {
    body: MISSED_GROUP_CALL_BODY,
    data: secret ? { type: "message" } : { type: "message", conversation_id: conversationId },
    tag: secret ? "privio-secret-call" : `privio-call-${conversationId}`,
  });
}

/** Lot 9.4 : grand groupe (plus de 16 membres) : pas de sonnerie, une notification neutre. */
export const LIVE_GROUP_CALL_BODY = "Un appel de groupe a commencé";

export async function sendGroupCallLive(
  sa: ServiceAccount,
  token: string,
  conversationId: string,
  secret = false,
): Promise<SendResult> {
  return await sendNotification(sa, token, {
    body: LIVE_GROUP_CALL_BODY,
    data: secret ? { type: "message" } : { type: "message", conversation_id: conversationId },
    tag: secret ? "privio-secret-call" : `privio-call-${conversationId}`,
  });
}

async function sendData(
  sa: ServiceAccount,
  token: string,
  data: Record<string, string>,
  ttl: string,
): Promise<SendResult> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${await accessToken(sa)}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ message: { token, data, android: { priority: "HIGH", ttl } } }),
    },
  );
  return await sendResult(res);
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
  return await sendResult(res);
}

async function sendResult(res: Response): Promise<SendResult> {
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

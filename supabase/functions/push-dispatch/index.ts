// PRIVIO — notifications FCM sans contenu (lot 4.1 ; demandes de connexion : lot 4.7 ;
// invitations de groupe : lot 4.8).
//
// Appelée par la base (déclencheur sur messages + pg_net) avec l'en-tête x-privio-push
// (jeton aléatoire créé par la migration, vérifié par la base). Elle ne reçoit que
// l'identifiant du message ; la base lui renvoie les jetons des destinataires (jamais
// l'expéditeur, ni sourdine, ni blocage, ni appareil révoqué). Aucun texte, aucun nom.
// Sans compte de service FCM configuré : compte rendu « not_configured », rien n'est envoyé.

import { ApiError, json, registerEndpoint, rpc, serviceHeaders } from "../_shared/supabase.ts";
import { loadServiceAccount, sendGeneric, sendInvitation, sendRequestEvent } from "../_shared/fcm.ts";

interface Target {
  token: string;
  conversation_id: string;
  is_group: boolean;
}

Deno.serve(async (req) => {
  await registerEndpoint();
  const token = req.headers.get("x-privio-push");
  if (!token) return json(401, { error: "AUTH_REQUIRED" });

  let messageId = "";
  let requestId = "";
  let invitationId = "";
  try {
    const body = (await req.json()) as { message_id?: string; request_id?: string; invitation_id?: string };
    messageId = body.message_id ?? "";
    requestId = body.request_id ?? "";
    invitationId = body.invitation_id ?? "";
  } catch {
    return json(400, { error: "BODY_INVALID" });
  }
  const UUID = /^[0-9a-f-]{36}$/;
  // Lot 4.7 : événement d'une demande de connexion (reçue, acceptée, refusée).
  if (requestId) {
    if (!UUID.test(requestId)) return json(400, { error: "BODY_INVALID" });
    return await dispatchRequest(token, requestId);
  }
  // Lot 4.8 : invitation à rejoindre un groupe.
  if (invitationId) {
    if (!UUID.test(invitationId)) return json(400, { error: "BODY_INVALID" });
    return await dispatchInvitation(token, invitationId);
  }
  if (!UUID.test(messageId)) return json(400, { error: "BODY_INVALID" });

  const report = (recipients: number, sent: number, failed: number, status: string, invalid: string[] = []) =>
    rpc("push_report", {
      p_token: token,
      p_message_id: messageId,
      p_recipients: recipients,
      p_sent: sent,
      p_failed: failed,
      p_status: status,
      p_invalid_tokens: invalid,
    }, serviceHeaders());

  try {
    const targets = await rpc<Target[]>(
      "push_targets",
      { p_token: token, p_message_id: messageId },
      serviceHeaders(),
    );
    if (targets.length === 0) {
      await report(0, 0, 0, "no_targets");
      return json(200, { recipients: 0 });
    }
    const sa = loadServiceAccount();
    if (!sa) {
      await report(targets.length, 0, 0, "not_configured");
      return json(200, { recipients: targets.length, status: "not_configured" });
    }
    let sent = 0;
    let failed = 0;
    const invalid: string[] = [];
    for (const t of targets) {
      try {
        const r = await sendGeneric(sa, t.token, t.conversation_id, t.is_group);
        if (r === "sent") sent++;
        else {
          failed++;
          if (r === "invalid_token") invalid.push(t.token);
        }
      } catch {
        failed++;
      }
    }
    await report(targets.length, sent, failed, failed === 0 ? "sent" : "partial", invalid);
    return json(200, { recipients: targets.length, sent, failed });
  } catch (e) {
    if (e instanceof ApiError) return json(e.status === 401 ? 401 : 400, { error: e.code });
    return json(500, { error: "UNKNOWN" });
  }
});

interface RequestTarget {
  token: string;
  event: string;
}

/** Notifications d'une demande de connexion : la base choisit le destinataire. */
async function dispatchRequest(token: string, requestId: string): Promise<Response> {
  const report = (recipients: number, sent: number, failed: number, status: string, invalid: string[] = []) =>
    rpc("push_report", {
      p_token: token,
      p_message_id: requestId,
      p_recipients: recipients,
      p_sent: sent,
      p_failed: failed,
      p_status: status,
      p_invalid_tokens: invalid,
    }, serviceHeaders());
  try {
    const targets = await rpc<RequestTarget[]>(
      "push_request_targets",
      { p_token: token, p_request_id: requestId },
      serviceHeaders(),
    );
    if (targets.length === 0) {
      await report(0, 0, 0, "no_targets");
      return json(200, { recipients: 0 });
    }
    const sa = loadServiceAccount();
    if (!sa) {
      await report(targets.length, 0, 0, "not_configured");
      return json(200, { recipients: targets.length, status: "not_configured" });
    }
    let sent = 0;
    let failed = 0;
    const invalid: string[] = [];
    for (const t of targets) {
      try {
        const r = await sendRequestEvent(sa, t.token, t.event);
        if (r === "sent") sent++;
        else {
          failed++;
          if (r === "invalid_token") invalid.push(t.token);
        }
      } catch {
        failed++;
      }
    }
    await report(targets.length, sent, failed, failed === 0 ? "sent" : "partial", invalid);
    return json(200, { recipients: targets.length, sent, failed });
  } catch (e) {
    if (e instanceof ApiError) return json(e.status === 401 ? 401 : 400, { error: e.code });
    return json(500, { error: "UNKNOWN" });
  }
}

/** Invitation à rejoindre un groupe : notification sans contenu à l'invité (lot 4.8). */
async function dispatchInvitation(token: string, invitationId: string): Promise<Response> {
  const report = (recipients: number, sent: number, failed: number, status: string, invalid: string[] = []) =>
    rpc("push_report", {
      p_token: token,
      p_message_id: invitationId,
      p_recipients: recipients,
      p_sent: sent,
      p_failed: failed,
      p_status: status,
      p_invalid_tokens: invalid,
    }, serviceHeaders());
  try {
    const targets = await rpc<{ token: string }[]>(
      "push_invitation_targets",
      { p_token: token, p_invitation_id: invitationId },
      serviceHeaders(),
    );
    if (targets.length === 0) {
      await report(0, 0, 0, "no_targets");
      return json(200, { recipients: 0 });
    }
    const sa = loadServiceAccount();
    if (!sa) {
      await report(targets.length, 0, 0, "not_configured");
      return json(200, { recipients: targets.length, status: "not_configured" });
    }
    let sent = 0;
    let failed = 0;
    const invalid: string[] = [];
    for (const t of targets) {
      try {
        const r = await sendInvitation(sa, t.token);
        if (r === "sent") sent++;
        else {
          failed++;
          if (r === "invalid_token") invalid.push(t.token);
        }
      } catch {
        failed++;
      }
    }
    await report(targets.length, sent, failed, failed === 0 ? "sent" : "partial", invalid);
    return json(200, { recipients: targets.length, sent, failed });
  } catch (e) {
    if (e instanceof ApiError) return json(e.status === 401 ? 401 : 400, { error: e.code });
    return json(500, { error: "UNKNOWN" });
  }
}

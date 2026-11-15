// PRIVIO — notifications FCM sans contenu (lot 4.1 ; demandes de connexion : lot 4.7 ;
// invitations de groupe : lot 4.8 ; administration : lot 5.3 ; réponses de l'assistance : lot 5.4 ;
// demandes d'adhésion et @mentions : lot 7.1b ; rappel avant effacement : lot 8.4b ;
// appels entrants et manqués : lot 9.1b).
//
// Appelée par la base (déclencheur sur messages + pg_net) avec l'en-tête x-privio-push
// (jeton aléatoire créé par la migration, vérifié par la base). Elle ne reçoit que
// l'identifiant du message ; la base lui renvoie les jetons des destinataires (jamais
// l'expéditeur, ni sourdine, ni blocage, ni appareil révoqué). Aucun texte, aucun nom.
// Sans compte de service FCM configuré : compte rendu « not_configured », rien n'est envoyé.

import { ApiError, json, registerEndpoint, rpc, serviceHeaders } from "../_shared/supabase.ts";
import {
  ADMIN_BODIES,
  loadServiceAccount,
  sendAdminEvent,
  sendGeneric,
  sendInvitation,
  sendJoinEvent,
  sendCallMissed,
  sendCallRing,
  sendExpiryReminder,
  sendRequestEvent,
  sendSupportReply,
} from "../_shared/fcm.ts";

interface Target {
  token: string;
  conversation_id: string;
  is_group: boolean;
  mentioned?: boolean;
}

Deno.serve(async (req) => {
  await registerEndpoint();
  const token = req.headers.get("x-privio-push");
  if (!token) return json(401, { error: "AUTH_REQUIRED" });

  let messageId = "";
  let requestId = "";
  let invitationId = "";
  let adminEvent = "";
  let refId = "";
  let supportReplyId = "";
  let joinRequestId = "";
  let expiryReminderId = "";
  let callEvent = "";
  let callId = "";
  try {
    const body = (await req.json()) as {
      message_id?: string;
      request_id?: string;
      invitation_id?: string;
      admin_event?: string;
      ref_id?: string;
      support_reply_id?: string;
      join_request_id?: string;
      expiry_reminder_id?: string;
      call_event?: string;
      call_id?: string;
    };
    messageId = body.message_id ?? "";
    requestId = body.request_id ?? "";
    invitationId = body.invitation_id ?? "";
    adminEvent = body.admin_event ?? "";
    refId = body.ref_id ?? "";
    supportReplyId = body.support_reply_id ?? "";
    joinRequestId = body.join_request_id ?? "";
    expiryReminderId = body.expiry_reminder_id ?? "";
    callEvent = body.call_event ?? "";
    callId = body.call_id ?? "";
  } catch {
    return json(400, { error: "BODY_INVALID" });
  }
  const UUID = /^[0-9a-f-]{36}$/;
  // Lot 4.7 : événement d'une demande de connexion (reçue, acceptée, refusée).
  if (requestId) {
    if (!UUID.test(requestId)) return json(400, { error: "BODY_INVALID" });
    return await dispatchRequest(token, requestId);
  }
  // Lot 5.4 : l'équipe Privio a répondu à une demande d'assistance.
  if (supportReplyId) {
    if (!UUID.test(supportReplyId)) return json(400, { error: "BODY_INVALID" });
    return await dispatchTargets(
      token,
      supportReplyId,
      () => rpc<{ token: string }[]>(
        "push_support_targets",
        { p_token: token, p_report_id: supportReplyId },
        serviceHeaders(),
      ),
      (sa, t) => sendSupportReply(sa, t.token),
    );
  }
  // Lot 7.1b : demande d'adhésion reçue (administrateurs) ou acceptée (la personne).
  if (joinRequestId) {
    if (!UUID.test(joinRequestId)) return json(400, { error: "BODY_INVALID" });
    return await dispatchTargets(
      token,
      joinRequestId,
      () => rpc<{ token: string; event: string; conversation_id: string }[]>(
        "push_join_request_targets",
        { p_token: token, p_request_id: joinRequestId },
        serviceHeaders(),
      ),
      (sa, t) => sendJoinEvent(sa, t.token, t.event, t.conversation_id),
    );
  }
  // Lot 9.1b : appel entrant (sonnerie) ou non décroché (arrêt + « Appel manqué »).
  if (callEvent) {
    if (!["ring", "missed"].includes(callEvent) || !UUID.test(callId)) {
      return json(400, { error: "BODY_INVALID" });
    }
    const muted = callEvent === "missed"
      ? await rpc<boolean>("push_call_muted", { p_token: token, p_call_id: callId }, serviceHeaders())
        .catch(() => false)
      : false;
    return await dispatchTargets(
      token,
      callId,
      () => rpc<{ token: string; conversation_id: string; created_at: string; kind: string }[]>(
        "push_call_targets",
        { p_token: token, p_call_id: callId, p_event: callEvent },
        serviceHeaders(),
      ),
      (sa, t) => callEvent === "ring"
        ? sendCallRing(sa, t.token, callId, t.conversation_id, t.created_at, t.kind)
        : sendCallMissed(sa, t.token, callId, t.conversation_id, muted),
    );
  }
  // Lot 8.4b : des messages non lus vont bientôt s'effacer.
  if (expiryReminderId) {
    if (!UUID.test(expiryReminderId)) return json(400, { error: "BODY_INVALID" });
    return await dispatchTargets(
      token,
      expiryReminderId,
      () => rpc<{ token: string; conversation_id: string }[]>(
        "push_expiry_reminder_targets",
        { p_token: token, p_reminder_id: expiryReminderId },
        serviceHeaders(),
      ),
      (sa, t) => sendExpiryReminder(sa, t.token, t.conversation_id),
    );
  }
  // Lot 5.3 : signalement, demande d'assistance ou contestation, pour l'administration.
  if (adminEvent) {
    if (!(adminEvent in ADMIN_BODIES) || !UUID.test(refId)) return json(400, { error: "BODY_INVALID" });
    return await dispatchAdmin(token, adminEvent, refId);
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
        const r = await sendGeneric(sa, t.token, t.conversation_id, t.is_group, t.mentioned === true);
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

/** Événement pour l'administration (lot 5.3) : notification sans contenu, vers la console. */
async function dispatchAdmin(token: string, event: string, refId: string): Promise<Response> {
  const report = (recipients: number, sent: number, failed: number, status: string, invalid: string[] = []) =>
    rpc("push_report", {
      p_token: token,
      p_message_id: refId,
      p_recipients: recipients,
      p_sent: sent,
      p_failed: failed,
      p_status: status,
      p_invalid_tokens: invalid,
    }, serviceHeaders());
  try {
    const targets = await rpc<{ token: string }[]>("push_admin_targets", { p_token: token }, serviceHeaders());
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
        const r = await sendAdminEvent(sa, t.token, event);
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

/** Envoi générique : cibles calculées par la base, compte rendu dans push_log (lot 5.4). */
async function dispatchTargets<T extends { token: string }>(
  token: string,
  refId: string,
  targetsOf: () => Promise<T[]>,
  send: (sa: NonNullable<ReturnType<typeof loadServiceAccount>>, t: T) => Promise<string>,
): Promise<Response> {
  const report = (recipients: number, sent: number, failed: number, status: string, invalid: string[] = []) =>
    rpc("push_report", {
      p_token: token,
      p_message_id: refId,
      p_recipients: recipients,
      p_sent: sent,
      p_failed: failed,
      p_status: status,
      p_invalid_tokens: invalid,
    }, serviceHeaders());
  try {
    const targets = await targetsOf();
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
        const r = await send(sa, t);
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

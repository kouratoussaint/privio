// PRIVIO — notifications FCM sans contenu (lot 4.1).
//
// Appelée par la base (déclencheur sur messages + pg_net) avec l'en-tête x-privio-push
// (jeton aléatoire créé par la migration, vérifié par la base). Elle ne reçoit que
// l'identifiant du message ; la base lui renvoie les jetons des destinataires (jamais
// l'expéditeur, ni sourdine, ni blocage, ni appareil révoqué). Aucun texte, aucun nom.
// Sans compte de service FCM configuré : compte rendu « not_configured », rien n'est envoyé.

import { ApiError, json, registerEndpoint, rpc, serviceHeaders } from "../_shared/supabase.ts";
import { loadServiceAccount, sendGeneric } from "../_shared/fcm.ts";

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
  try {
    messageId = ((await req.json()) as { message_id?: string }).message_id ?? "";
  } catch {
    return json(400, { error: "BODY_INVALID" });
  }
  if (!/^[0-9a-f-]{36}$/.test(messageId)) return json(400, { error: "BODY_INVALID" });

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

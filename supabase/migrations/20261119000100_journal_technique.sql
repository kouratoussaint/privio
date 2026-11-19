-- Lot 6.1 : journal technique joint, avec l'accord de la personne, à une demande
-- d'assistance (ADR-055). Le journal ne contient ni message ni nom : seulement la version
-- de l'application, d'Android et les types d'erreurs avec leur emplacement dans le code.
-- Il est effacé avec la demande (purge habituelle des signalements).

alter table private.reports
  add column if not exists tech_log text check (tech_log is null or char_length(tech_log) <= 16000);

drop function if exists public.report(text, uuid, uuid, uuid, text, boolean);
CREATE OR REPLACE FUNCTION public.report(p_reason text, p_reported_user_id uuid DEFAULT NULL::uuid, p_conversation_id uuid DEFAULT NULL::uuid, p_message_id uuid DEFAULT NULL::uuid, p_details text DEFAULT NULL::text, p_include_message boolean DEFAULT false, p_tech_log text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid      uuid := private.require_active_user();
  v_msg      public.messages%rowtype;
  v_evidence jsonb;
  v_id       uuid;
  v_details  text := nullif(btrim(coalesce(p_details, '')), '');
  v_purge    timestamptz := now() + make_interval(days => private.policy_int('report_retention_days'));
begin
  perform private.consume_rate_limit(v_uid, 'report',
    private.policy_int('report_daily_limit'), interval '1 day');

  if p_reason is null or p_reason not in
     ('spam', 'harassment', 'inappropriate', 'threat', 'impersonation', 'other', 'support') then
    raise exception 'REPORT_INVALID' using errcode = 'P0001';
  end if;
  if v_details is not null and char_length(v_details) > 1000 then
    raise exception 'REPORT_INVALID' using errcode = 'P0001';
  end if;

  -- Lot 6.1 : journal technique joint (assistance seulement, 16 000 caractères au plus).
  if p_tech_log is not null and (p_reason <> 'support' or char_length(p_tech_log) > 16000) then
    raise exception 'REPORT_INVALID' using errcode = 'P0001';
  end if;
  if p_reason = 'support' then
    if p_reported_user_id is not null or p_message_id is not null or v_details is null then
      raise exception 'REPORT_INVALID' using errcode = 'P0001';
    end if;
  elsif p_reported_user_id is null then
    -- Signaler un groupe : en être membre ; ni message ni personne visée.
    if p_conversation_id is null or p_message_id is not null
       or not exists (select 1 from public.conversations c where c.id = p_conversation_id and c.kind = 'group')
       or not private.is_member(p_conversation_id, v_uid) then
      raise exception 'REPORT_INVALID' using errcode = 'P0001';
    end if;
  else
    if p_reported_user_id = v_uid then
      raise exception 'REPORT_INVALID' using errcode = 'P0001';
    end if;
    if p_conversation_id is not null and not private.is_member(p_conversation_id, v_uid) then
      raise exception 'NOT_MEMBER' using errcode = 'P0001';
    end if;
    if p_message_id is not null then
      v_msg := private.visible_message(p_message_id, v_uid);
      if v_msg.kind not in ('text', 'voice', 'photo') or v_msg.sender_id is distinct from p_reported_user_id
         or v_msg.conversation_id is distinct from p_conversation_id then
        raise exception 'REPORT_INVALID' using errcode = 'P0001';
      end if;
      select r.id into v_id from private.reports r
       where r.reporter_id = v_uid and r.message_id = p_message_id;
      if v_id is not null then
        return v_id;
      end if;
      if coalesce(p_include_message, false) and v_msg.deleted_at is null then
        v_evidence := jsonb_build_object(
          'kind', v_msg.kind, 'body', v_msg.body, 'sent_at', v_msg.sent_at,
          'sender_id', v_msg.sender_id, 'conversation_id', v_msg.conversation_id,
          'copied_at', now());
        if v_msg.media_path is not null then
          v_evidence := v_evidence || jsonb_build_object(
            'media_path', v_msg.media_path, 'duration_ms', v_msg.media_duration_ms);
          update private.media_objects
             set report_hold_until = greatest(coalesce(report_hold_until, v_purge), v_purge)
           where path = v_msg.media_path;
        end if;
      end if;
    end if;
  end if;

  insert into private.reports
    (reporter_id, reported_user_id, conversation_id, message_id, reason, details, evidence, purge_after,
     tech_log)
  values
    (v_uid, p_reported_user_id, p_conversation_id, p_message_id, p_reason, v_details, v_evidence, v_purge,
     nullif(btrim(coalesce(p_tech_log, '')), ''))
  returning id into v_id;
  return v_id;
end;
$function$;

drop function if exists public.console_reports(text);
CREATE OR REPLACE FUNCTION public.console_reports(p_status text DEFAULT 'open'::text)
 RETURNS TABLE(id uuid, kind text, reason text, details text, status text, created_at timestamp with time zone, taken_at timestamp with time zone, decision text, decision_note text, decided_at timestamp with time zone, reporter_handle text, reported_user_id uuid, reported_handle text, reported_name text, reported_since timestamp with time zone, conversation_id uuid, group_title text, group_closed boolean, message_id uuid, evidence_kind text, reports_90d integer, reporters_90d integer, suspended boolean, suspended_until timestamp with time zone, sanctions_count integer, protected boolean, reply text, replied_at timestamp with time zone, tech_log text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_uid uuid := private.require_console('{owner,moderator,support}');
begin
  if p_status not in ('open', 'reviewing', 'closed') then
    raise exception 'MODERATION_INVALID' using errcode = 'P0001';
  end if;
  perform private.admin_log(v_uid, 'reports', jsonb_build_object('status', p_status));
  return query
  select r.id,
         case when r.reason = 'support' then 'support'
              when r.message_id is not null then 'message'
              when r.reported_user_id is null then 'group'
              else 'account' end,
         r.reason, r.details, r.status, r.created_at, r.taken_at, r.decision, r.decision_note, r.decided_at,
         rp.handle,
         r.reported_user_id, tp.handle, tp.display_name, tp.created_at,
         r.conversation_id,
         case when c.kind = 'group' then c.title end,
         coalesce(c.kind = 'group' and c.posting = 'closed', false),
         r.message_id,
         case when r.evidence is null then null else coalesce(r.evidence ->> 'kind', 'text') end,
         (select count(*)::int from private.reports x
           where x.reported_user_id = r.reported_user_id and x.created_at > now() - interval '90 days'),
         (select count(distinct x.reporter_id)::int from private.reports x
           where x.reported_user_id = r.reported_user_id and x.created_at > now() - interval '90 days'),
         r.reported_user_id is not null and private.is_suspended(r.reported_user_id),
         (private.active_suspension(r.reported_user_id)).until,
         (select count(*)::int from private.sanctions s where s.user_id = r.reported_user_id),
         r.reported_user_id is not null and private.is_console_admin(r.reported_user_id),
         r.reply, r.replied_at, r.tech_log
    from private.reports r
    left join public.profiles rp on rp.id = r.reporter_id
    left join public.profiles tp on tp.id = r.reported_user_id
    left join public.conversations c on c.id = r.conversation_id
   where r.status = p_status
     and private.report_for_role(r.reason, private.console_role(v_uid))
   order by case when p_status = 'closed' then extract(epoch from r.decided_at) * -1
                 else extract(epoch from r.created_at) end
   limit 300;
end;
$function$;

select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.report(text, uuid, uuid, uuid, text, boolean, text) to authenticated;
grant execute on function public.console_reports(text) to authenticated;

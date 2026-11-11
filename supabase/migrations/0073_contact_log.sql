-- Waad ERP — 0073 the team's notes on a company become a contact log: each entry says how the contact happened
-- (e-mail, WhatsApp, call, in-person meeting, other) and the date it happened (today by default, can be earlier).

alter table public.platform_notes add column if not exists channel text not null default 'other'
  check (channel in ('email','whatsapp','call','meeting','other'));
alter table public.platform_notes add column if not exists contact_on date not null default ((now() at time zone 'Asia/Riyadh')::date);
update public.platform_notes set contact_on = (created_at at time zone 'Asia/Riyadh')::date where contact_on <> (created_at at time zone 'Asia/Riyadh')::date;

create or replace function public.platform_add_note(p_company uuid, p_body text, p_channel text, p_on date) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.platform_guard();
  if nullif(trim(p_body), '') is null then raise exception 'اكتب الملاحظة'; end if;
  if coalesce(p_channel, 'other') not in ('email','whatsapp','call','meeting','other') then raise exception 'نوع تواصل غير معروف'; end if;
  if p_on > (now() at time zone 'Asia/Riyadh')::date then raise exception 'تاريخ التواصل في المستقبل'; end if;
  insert into public.platform_notes(company_id, body, channel, contact_on)
  values (p_company, trim(p_body), coalesce(p_channel, 'other'), coalesce(p_on, (now() at time zone 'Asia/Riyadh')::date));
end $$;

create or replace function public.platform_company(p_company uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.platform_guard();
  return (select jsonb_build_object(
    'company', (select to_jsonb(x) from public.platform_companies() x where x.company_id = p_company),
    'plan_id', (select plan_id from public.company_subscriptions where company_id = p_company),
    'payments', coalesce((select jsonb_agg(to_jsonb(p) order by p.paid_on desc, p.created_at desc) from public.platform_payments p where p.company_id = p_company), '[]'),
    'notes', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'body', n.body, 'at', n.created_at, 'channel', n.channel, 'on', n.contact_on,
                 'by', (select coalesce(a.username, u.email) from auth.users u left join public.platform_admins a on a.user_id = u.id where u.id = n.created_by))
                 order by n.contact_on desc, n.created_at desc)
               from public.platform_notes n where n.company_id = p_company), '[]'),
    'history', coalesce((select jsonb_agg(jsonb_build_object('at', l.at, 'action', l.action, 'status', l.r->>'status', 'plan', l.r->>'plan',
                 'trial_ends', l.r->>'trial_ends', 'sub_ends', l.r->>'sub_ends') order by l.at desc)
               from (select at, action, coalesce(data->'new', data) as r from public.audit_log    -- an update is stored as {old, new}
                      where company_id = p_company and entity = 'company_subscriptions' order by at desc limit 50) l), '[]')));
end $$;

revoke all on function public.platform_add_note(uuid, text, text, date) from public, anon;
grant execute on function public.platform_add_note(uuid, text, text, date) to authenticated;

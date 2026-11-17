-- 0104 — admin-site permissions that abdulaziz grants to each team member (owner's decision, 2026-11-17).
-- platform_admins.perms: subs (accept companies, subscriptions, extend the deletion period), billing (payments, plans),
--   site (website texts, announcements), support (reply to tickets), settings (panel settings), export (company data at the
--   owner's request), purge (permanent company deletion), team (add/remove members, reset passwords).
-- The super account (is_super: abdulaziz) has every permission and alone grants them (platform_set_perms); a member with
-- «team» cannot touch the super account. Everyone on the team can still view the companies and keep the contact log.
-- Existing members keep what they could do before (subs, billing, site, support, settings; saud also export);
-- a new member starts with none until abdulaziz grants them. Every gated function below is its latest definition
-- with one added line: perform public.platform_need('<perm>').

alter table public.platform_admins add column if not exists perms text[] not null default '{}';
update public.platform_admins set perms = array['subs', 'billing', 'site', 'support', 'settings'] || case when can_export then array['export'] else '{}'::text[] end
 where not is_super and perms = '{}';
update public.platform_admins set perms = array['subs', 'billing', 'site', 'support', 'settings', 'export', 'purge', 'team'] where is_super;

create or replace function public.platform_has(p_perm text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_platform_admin() and coalesce((select is_super or p_perm = any(perms) from public.platform_admins where user_id = auth.uid()), false)
$$;
create or replace function public.platform_need(p_perm text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.platform_has(p_perm) then raise exception 'ليست لديك هذه الصلاحية في لوحة الإدارة — اطلبها من مالك المنصة' using errcode = '42501'; end if;
end $$;

create or replace function public.platform_can_export() returns boolean
language sql stable security definer set search_path = public as $$ select public.platform_has('export') $$;

create or replace function public.platform_admin_me() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return (select jsonb_build_object('username', username, 'must_change', must_change_password, 'super', is_super,
            'perms', case when is_super then to_jsonb(array['subs', 'billing', 'site', 'support', 'settings', 'export', 'purge', 'team']) else to_jsonb(perms) end)
            from public.platform_admins where user_id = auth.uid());
end $$;

drop function if exists public.platform_team();
create function public.platform_team()
returns table(username text, email text, added_at timestamptz, last_sign_in timestamptz, must_change boolean, is_me boolean, mfa boolean, is_super boolean, perms text[])
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query select a.username, case when a.username is null then u.email::text end, a.added_at, u.last_sign_in_at, a.must_change_password,
      a.user_id = auth.uid(), exists(select 1 from auth.mfa_factors f where f.user_id = a.user_id and f.status = 'verified'), a.is_super, a.perms
    from public.platform_admins a join auth.users u on u.id = a.user_id order by a.added_at;
end $$;

-- abdulaziz sets a member's permissions (only known keys; never on the super account)
create or replace function public.platform_set_perms(p_username text, p_perms text[]) returns void
language plpgsql security definer set search_path = public as $$
declare v text[] := array(select distinct x from unnest(coalesce(p_perms, '{}')) x where x = any(array['subs', 'billing', 'site', 'support', 'settings', 'export', 'purge', 'team']) order by 1);
begin
  perform public.platform_super_guard();
  update public.platform_admins set perms = v, can_export = 'export' = any(v) where username = lower(trim(p_username)) and not is_super;
  if not found then raise exception 'المستخدم غير موجود'; end if;
end $$;
drop function if exists public.platform_set_export(text, boolean);

CREATE OR REPLACE FUNCTION public.platform_approve(p_company uuid, p_status text, p_days integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_end date := case when p_days is not null then current_date + p_days end;
begin perform public.platform_need('subs');
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p_status not in ('trial','active') then raise exception 'اختر تجربة أو اشتراك'; end if;
  if p_days is not null and (p_days < 1 or p_days > 3660) then raise exception 'المدة من يوم إلى ١٠ سنوات'; end if;
  update public.company_subscriptions
     set status = p_status, plan = case when p_status = 'trial' then 'trial' when plan = 'trial' then 'اشتراك' else plan end,
         trial_ends = case when p_status = 'trial' then v_end end, sub_ends = case when p_status = 'active' then v_end end, updated_at = now()
   where company_id = p_company;
  if not found then raise exception 'المنشأة غير موجودة'; end if;
end $function$;

CREATE OR REPLACE FUNCTION public.platform_quick(p_company uuid, p_action text, p_days integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.company_subscriptions;
begin perform public.platform_need('subs');
  perform public.platform_guard();
  select * into s from public.company_subscriptions where company_id = p_company for update;
  if not found then raise exception 'المنشأة غير موجودة'; end if;
  if p_action = 'extend' then
    if coalesce(p_days, 0) < 1 or p_days > 3660 then raise exception 'المدة من يوم إلى ١٠ سنوات'; end if;
    if s.status = 'trial' then
      update public.company_subscriptions set trial_ends = greatest(coalesce(trial_ends, current_date), current_date) + p_days, updated_at = now() where company_id = p_company;
    elsif s.status = 'active' then
      update public.company_subscriptions set sub_ends = greatest(coalesce(sub_ends, current_date), current_date) + p_days, updated_at = now() where company_id = p_company;
    else raise exception 'التمديد للتجربة أو الاشتراك فقط'; end if;
  elsif p_action = 'suspend' then
    update public.company_subscriptions set status = 'suspended', updated_at = now() where company_id = p_company;
  elsif p_action = 'resume' then
    update public.company_subscriptions set status = case when sub_ends is not null or plan_id is not null then 'active' else 'trial' end, updated_at = now() where company_id = p_company;
  else raise exception 'إجراء غير معروف'; end if;
end $function$;

CREATE OR REPLACE FUNCTION public.platform_set_subscription(p_company uuid, p_plan text, p_modules text[], p_status text, p_trial_ends date, p_max_users integer, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin perform public.platform_need('subs');
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if not exists(select 1 from public.companies where id = p_company) then raise exception 'المنشأة غير موجودة'; end if;
  if coalesce(cardinality(p_modules), 0) = 0 then raise exception 'اختر قسماً واحداً على الأقل'; end if;
  insert into public.company_subscriptions(company_id, plan, modules, status, trial_ends, max_users, note, updated_at)
  values (p_company, coalesce(nullif(trim(p_plan), ''), 'custom'), p_modules, p_status, p_trial_ends, p_max_users, nullif(trim(p_note), ''), now())
  on conflict (company_id) do update set plan = excluded.plan, modules = excluded.modules, status = excluded.status,
    trial_ends = excluded.trial_ends, max_users = excluded.max_users, note = excluded.note, updated_at = now();
end $function$;

CREATE OR REPLACE FUNCTION public.platform_set_subscription(p_company uuid, p_plan text, p_modules text[], p_status text, p_trial_ends date, p_max_users integer, p_note text, p_sub_ends date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin perform public.platform_need('subs');
  perform public.platform_set_subscription(p_company, p_plan, p_modules, p_status, p_trial_ends, p_max_users, p_note);
  update public.company_subscriptions set sub_ends = p_sub_ends where company_id = p_company;
end $function$;

CREATE OR REPLACE FUNCTION public.platform_set_subscription(p_company uuid, p_plan text, p_modules text[], p_status text, p_trial_ends date, p_max_users integer, p_note text, p_sub_ends date, p_max_employees integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin perform public.platform_need('subs');
  perform public.platform_set_subscription(p_company, p_plan, p_modules, p_status, p_trial_ends, p_max_users, p_note, p_sub_ends);
  update public.company_subscriptions set max_employees = p_max_employees where company_id = p_company;
end $function$;

CREATE OR REPLACE FUNCTION public.platform_purge_extend(p_company uuid, p_days integer)
 RETURNS date
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.company_subscriptions; d date;
begin perform public.platform_need('subs');
  perform public.platform_guard();
  if p_days is null or p_days < 1 or p_days > 365 then raise exception 'مدة غير صحيحة'; end if;
  select * into s from public.company_subscriptions where company_id = p_company;
  if public.sub_ended_on(s) is null then raise exception 'المنشأة ليست منتهية'; end if;
  d := greatest(public.purge_on(s), (now() at time zone 'Asia/Riyadh')::date) + p_days;
  update public.company_subscriptions set purge_hold_until = d where company_id = p_company;
  return d;
end $function$;

CREATE OR REPLACE FUNCTION public.platform_add_payment(p_company uuid, p_amount numeric, p_paid_on date, p_method text, p_plan uuid, p_days integer, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pl public.platform_plans; s public.company_subscriptions; v_days int := p_days; v_from date;
begin perform public.platform_need('billing');
  perform public.platform_guard();
  if coalesce(p_amount, 0) <= 0 then raise exception 'اكتب المبلغ'; end if;
  if p_plan is not null then select * into pl from public.platform_plans where id = p_plan; v_days := coalesce(v_days, pl.period_days); end if;
  insert into public.platform_payments(company_id, amount, paid_on, method, plan_id, days, note)
  values (p_company, p_amount, coalesce(p_paid_on, (now() at time zone 'Asia/Riyadh')::date), coalesce(p_method, 'transfer'), p_plan, v_days, nullif(trim(p_note), ''));
  if v_days is not null then
    select * into s from public.company_subscriptions where company_id = p_company;
    v_from := greatest(current_date - 1, case when s.status = 'active' then coalesce(s.sub_ends, current_date - 1) else current_date - 1 end);
    update public.company_subscriptions set status = 'active', sub_ends = v_from + v_days, trial_ends = null,
      plan_id = coalesce(p_plan, plan_id), plan = coalesce(pl.name, case when plan = 'trial' then 'اشتراك' else plan end),
      modules = coalesce(pl.modules, modules), max_users = coalesce(pl.max_users, max_users),
      max_employees = case when p_plan is not null then pl.max_employees else max_employees end, updated_at = now()
     where company_id = p_company;
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public.platform_delete_payment(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin perform public.platform_need('billing'); perform public.platform_guard(); delete from public.platform_payments where id = p_id; end $function$;

CREATE OR REPLACE FUNCTION public.platform_save_plan(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v uuid := nullif(p->>'id', '')::uuid; m text[] := case when jsonb_typeof(p->'modules') = 'array' then array(select jsonb_array_elements_text(p->'modules')) else array['hr','finance','sales','purch','stock','proj'] end;
begin perform public.platform_need('billing');
  perform public.platform_guard();
  if nullif(trim(p->>'name'), '') is null then raise exception 'اكتب اسم الباقة'; end if;
  if coalesce(cardinality(m), 0) = 0 then raise exception 'اختر قسماً واحداً على الأقل'; end if;
  if v is null then
    insert into public.platform_plans(name, price, period_days, modules, max_users, max_employees, active)
    values (trim(p->>'name'), coalesce((p->>'price')::numeric, 0), coalesce((p->>'period_days')::int, 30), m, nullif(p->>'max_users', '')::int,
            nullif(p->>'max_employees', '')::int, coalesce((p->>'active')::boolean, true))
    returning id into v;
  else
    update public.platform_plans set name = trim(p->>'name'), price = coalesce((p->>'price')::numeric, 0), period_days = coalesce((p->>'period_days')::int, 30),
      modules = m, max_users = nullif(p->>'max_users', '')::int, max_employees = nullif(p->>'max_employees', '')::int, active = coalesce((p->>'active')::boolean, true) where id = v;
  end if;
  return v;
exception when unique_violation then raise exception 'اسم الباقة مستخدم مسبقاً';
end $function$;

CREATE OR REPLACE FUNCTION public.platform_set_site_content(p_key text, p_value jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin perform public.platform_need('site');
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p_key not in ('contact','banner','faq') then raise exception 'محتوى غير معروف'; end if;
  if p_value is null or p_value = 'null'::jsonb then delete from public.site_content where key = p_key; return; end if;   -- back to the built-in text
  if length(coalesce(p_value::text, '')) > 20000 then raise exception 'المحتوى طويل جداً'; end if;
  if p_key = 'contact' and (coalesce(p_value->>'phone', '') !~ '^9665[0-9]{8}$' or coalesce(p_value->>'email', '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception 'رقم الجوال أو البريد غير صحيح';
  end if;
  if p_key = 'faq' and jsonb_typeof(p_value) <> 'array' then raise exception 'محتوى غير معروف'; end if;
  insert into public.site_content(key, value, updated_at) values (p_key, p_value, now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
end $function$;

CREATE OR REPLACE FUNCTION public.platform_save_announcement(p_id uuid, p_body_ar text, p_body_en text, p_level text, p_starts date, p_ends date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v uuid;
begin perform public.platform_need('site');
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if nullif(trim(p_body_ar), '') is null then raise exception 'اكتب نص الإعلان'; end if;
  if p_ends is not null and p_ends < coalesce(p_starts, (now() at time zone 'Asia/Riyadh')::date) then raise exception 'تاريخ النهاية قبل البداية'; end if;
  if p_id is null then
    insert into public.platform_announcements(body_ar, body_en, level, starts_at, ends_at)
    values (trim(p_body_ar), nullif(trim(p_body_en), ''), coalesce(p_level, 'info'), coalesce(p_starts, (now() at time zone 'Asia/Riyadh')::date), p_ends)
    returning id into v;
  else
    update public.platform_announcements set body_ar = trim(p_body_ar), body_en = nullif(trim(p_body_en), ''), level = coalesce(p_level, 'info'),
      starts_at = coalesce(p_starts, starts_at), ends_at = p_ends where id = p_id returning id into v;
    if v is null then raise exception 'الإعلان غير موجود'; end if;
  end if;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.platform_delete_announcement(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin perform public.platform_need('site');
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  delete from public.platform_announcements where id = p_id;
end $function$;

CREATE OR REPLACE FUNCTION public.platform_reply_ticket(p_id uuid, p_reply text, p_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin perform public.platform_need('support');
  perform public.platform_guard();
  if p_status not in ('open','answered','closed') then raise exception 'حالة غير معروفة'; end if;
  update public.support_tickets set
      reply = coalesce(nullif(trim(p_reply), ''), reply),
      replied_at = case when nullif(trim(p_reply), '') is not null and nullif(trim(p_reply), '') is distinct from reply then now() else replied_at end,
      replied_by = case when nullif(trim(p_reply), '') is not null then auth.uid() else replied_by end,
      reply_notified_at = case when nullif(trim(p_reply), '') is not null and nullif(trim(p_reply), '') is distinct from reply then null else reply_notified_at end,
      status = p_status
   where id = p_id;
  if not found then raise exception 'الطلب غير موجود'; end if;
end $function$;

CREATE OR REPLACE FUNCTION public.platform_set_settings(p_modules text[], p_trial_days integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin perform public.platform_need('settings');
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if coalesce(cardinality(p_modules), 0) = 0 or not p_modules <@ array['hr','finance','sales','purch','stock','proj'] then raise exception 'اختر قسماً واحداً على الأقل'; end if;
  update public.platform_settings set default_modules = p_modules, default_trial_days = p_trial_days, updated_at = now() where id;
end $function$;

CREATE OR REPLACE FUNCTION public.platform_set_settings(p_modules text[], p_trial_days integer, p_require_approval boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin perform public.platform_need('settings');
  perform public.platform_set_settings(p_modules, p_trial_days);
  update public.platform_settings set require_approval = coalesce(p_require_approval, true) where id;
end $function$;

CREATE OR REPLACE FUNCTION public.platform_company_export(p_company uuid, p_reason text, p_files boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare c public.companies; d jsonb;
begin perform public.platform_need('export');
  perform public.platform_guard();
  select * into c from public.companies where id = p_company;
  if c.id is null then raise exception 'المنشأة غير موجودة'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 5 then raise exception 'اكتب كيف طلب المالك التصدير ومتى'; end if;
  if (select count(*) from public.company_exports_log where by_user = auth.uid() and at > now() - interval '1 hour') >= 5 then
    raise exception 'حاولت التصدير كثيراً — انتظر ساعة ثم أعد المحاولة'; end if;
  insert into public.company_exports_log(company_ref, company_name, by_user, by_email, reason, with_files)
  values (c.id, c.name, auth.uid(), (select email from auth.users where id = auth.uid()), btrim(p_reason), coalesce(p_files, false));
  d := public.company_export_data(p_company, coalesce(p_files, false));
  insert into public.audit_log(company_id, actor, action, entity, entity_id, data)
  values (p_company, auth.uid(), 'export', 'company', p_company::text, jsonb_build_object('files', p_files, 'by', 'waad', 'reason', btrim(p_reason), 'tables', d->'n_tables', 'rows', d->'n_rows'));
  return (d - 'n_tables' - 'n_rows') || jsonb_build_object('company_name', c.name, 'company_code', c.code);
end $function$;

CREATE OR REPLACE FUNCTION public.platform_company_purge(p_company uuid, p_confirm text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare c public.companies; s public.company_subscriptions; v_users uuid[]; v_pass int; v_left int; v_t text;
begin perform public.platform_need('purge');
  perform public.platform_guard();
  select * into c from public.companies where id = p_company for update;
  if c.id is null then raise exception 'المنشأة غير موجودة'; end if;
  if btrim(coalesce(p_confirm, '')) <> btrim(c.name) then raise exception 'اكتب اسم المنشأة كما هو للتأكيد'; end if;
  select * into s from public.company_subscriptions where company_id = p_company;
  if s.company_id is not null and s.status <> 'suspended' and s.status <> 'pending' and public.sub_ended_on(s) is null then
    raise exception 'المنشأة شغّالة. أوقفها أولا ثم احذفها'; end if;
  -- sign-in accounts that belong to this company only (never a Waad team account)
  select coalesce(array_agg(distinct m.user_id), '{}') into v_users from public.members m
   where m.company_id = p_company
     and not exists (select 1 from public.members o where o.user_id = m.user_id and o.company_id <> p_company)
     and not exists (select 1 from public.platform_admins a where a.user_id = m.user_id);
  update public.platform_payments set company_name = coalesce(company_name, c.name) where company_id = p_company;
  insert into public.company_deletions(company_name, registered_on, ended_on, deleted_by, deleted_by_email, users_removed, reason)
  values (c.name, (c.created_at at time zone 'Asia/Riyadh')::date, case when s.company_id is not null then public.sub_ended_on(s) end,
          auth.uid(), (select email from auth.users where id = auth.uid()), coalesce(array_length(v_users, 1), 0), nullif(btrim(coalesce(p_reason, '')), ''));
  perform set_config('waad.purge', 'on', true);
  -- table by table: rows that other rows still point to wait for the next pass (lines go with their documents)
  for v_pass in 1..12 loop
    v_left := 0;
    for v_t in select c2.table_name from information_schema.columns c2 join information_schema.tables t2 using (table_schema, table_name)
                where c2.table_schema = 'public' and c2.column_name = 'company_id' and t2.table_type = 'BASE TABLE'
                  and c2.table_name not in ('companies', 'platform_payments', 'company_deletions') loop
      begin
        execute format('delete from public.%I where company_id = $1', v_t) using p_company;
      exception when foreign_key_violation then v_left := v_left + 1;
      end;
    end loop;
    exit when v_left = 0;
  end loop;
  delete from public.companies where id = p_company;
  delete from auth.users where id = any(v_users);
  perform set_config('waad.purge', '', true);
end $function$;

CREATE OR REPLACE FUNCTION public.platform_add_admin(p_username text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_user uuid; v_created timestamptz; v_name text := lower(trim(p_username));
begin perform public.platform_need('team');
  if v_name !~ '^[a-z0-9._-]{3,30}$' then raise exception 'اسم المستخدم من ٣ إلى ٣٠ حرفاً إنجليزياً أو رقماً'; end if;
  if exists(select 1 from public.platform_admins where username = v_name) then raise exception 'اسم المستخدم مستخدم مسبقاً'; end if;
  select id, created_at into v_user, v_created from auth.users where lower(email) = public.admin_email(v_name);
  if v_user is null then raise exception 'لم يُنشأ حساب الدخول بعد'; end if;
  if v_created < now() - interval '10 minutes' then raise exception 'اسم المستخدم محجوز، اختر اسماً آخر'; end if;
  if exists(select 1 from public.members where user_id = v_user) then raise exception 'اسم المستخدم محجوز، اختر اسماً آخر'; end if;
  insert into public.platform_admins(user_id, username, must_change_password, added_by) values (v_user, v_name, true, auth.uid());
end $function$;

CREATE OR REPLACE FUNCTION public.platform_remove_admin(p_username text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.platform_admins;
begin perform public.platform_need('team');
  select * into a from public.platform_admins where username = lower(trim(p_username));
  if not found then raise exception 'المستخدم غير موجود'; end if;
  if a.is_super and not public.platform_is_super() then raise exception 'حساب مالك المنصة لا يُعدّل إلا منه' using errcode = '42501'; end if;
  if a.user_id = auth.uid() then raise exception 'لا تقدر تحذف حسابك'; end if;
  delete from public.platform_admins where user_id = a.user_id;
end $function$;

CREATE OR REPLACE FUNCTION public.platform_reset_admin_password(p_username text, p_password text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare a public.platform_admins;
begin perform public.platform_need('team');
  select * into a from public.platform_admins where username = lower(trim(p_username));
  if not found then raise exception 'المستخدم غير موجود'; end if;
  if a.is_super and not public.platform_is_super() then raise exception 'حساب مالك المنصة لا يُعدّل إلا منه' using errcode = '42501'; end if;
  if a.user_id = auth.uid() then raise exception 'غيّر كلمة مرورك من حسابك'; end if;
  if length(coalesce(p_password, '')) < 8 then raise exception 'كلمة المرور 8 أحرف على الأقل'; end if;
  update auth.users set encrypted_password = crypt(p_password, gen_salt('bf')) where id = a.user_id;
  update public.platform_admins set must_change_password = true where user_id = a.user_id;
end $function$;

revoke all on function public.platform_has(text), public.platform_need(text), public.platform_set_perms(text, text[]), public.platform_team(), public.platform_admin_me() from public, anon;
grant execute on function public.platform_has(text), public.platform_need(text), public.platform_set_perms(text, text[]), public.platform_team(), public.platform_admin_me() to authenticated;

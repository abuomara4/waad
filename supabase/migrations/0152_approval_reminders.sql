-- Waad ERP — 0152 automatic reminders to approvers (owner's request, 2026-11-25): a request that has waited at one step
-- longer than the company's step deadline («مهلة كل مرحلة», request_sla_days) — 3 days when none is set — reminds whoever
-- can approve it now: a phone notification (push_due, key rem:<request>:<step>:<period>) and one e-mail a day listing all of
-- his late requests (approval_reminders_due / approval_reminders_mark, read by the notify job; again every period while
-- it waits). Staff sign-in addresses (@staff.waad.app) are not mailboxes: the employee's own e-mail is used instead.

create or replace function public.reminder_days(p_company uuid) returns int
language sql stable security definer set search_path = public as $$
  select coalesce((select request_sla_days from public.companies where id = p_company), 3)
$$;
create or replace function public.waited_days(r public.requests) returns int
language sql stable set search_path = public as $$
  select floor(extract(epoch from now() - coalesce(r.step_at, r.created_at)) / 86400)::int
$$;
create or replace function public.request_kind_ar(k text) returns text language sql immutable as $$
  select case k when 'leave' then 'إجازة' when 'permit' then 'استئذان' when 'cert' then 'تعريف بالراتب' when 'advance' then 'سلفة' when 'resign' then 'استقالة'
    when 'settle' then 'مخالصة' when 'expense' then 'مطالبة مصروفات' when 'update' then 'تحديث بيانات' when 'punch' then 'نسيان بصمة' when 'ticket' then 'تذكرة سفر'
    when 'visa' then 'تأشيرة خروج وعودة' when 'purchase' then 'طلب شراء' when 'trip' then 'رحلة عمل' when 'overtime' then 'عمل إضافي' when 'remote' then 'عمل عن بعد'
    when 'move' then 'نقل أو ترقية' else k end
$$;

create table if not exists public.approval_reminders_sent (
  user_id uuid not null,
  key text not null,
  sent_at timestamptz not null default now(),
  primary key (user_id, key)
);
alter table public.approval_reminders_sent enable row level security;
revoke all on public.approval_reminders_sent from public, anon, authenticated;

-- for the notify job: per approver and company, his late requests not yet mailed for this period
create or replace function public.approval_reminders_due() returns table(user_id uuid, email text, company text, keys text[], lines text[])
language plpgsql security definer set search_path = public, auth as $$
declare u record;
begin
  for u in select distinct m.user_id from public.members m
             where exists(select 1 from public.requests r where r.company_id = m.company_id and r.status = 'pending'
                            and coalesce(r.step_at, r.created_at) <= now() - make_interval(days => public.reminder_days(r.company_id))) loop
    perform set_config('request.jwt.claim.sub', u.user_id::text, true);
    return query
    with mine as (select m.company_id, m.employee_id from public.members m where m.user_id = u.user_id and public.member_live(m.employee_id, m.role)),
    late as (
      select r.company_id, 'rem:' || r.id || ':' || r.step || ':' || floor(extract(epoch from now() - coalesce(r.step_at, r.created_at)) / 86400 / public.reminder_days(r.company_id))::int as k,
             coalesce((select e.full_name from public.employees e where e.id = r.employee_id), '') || ' — ' || public.request_kind_ar(r.kind) || ' — ' || public.waited_days(r) || ' أيام' as line,
             coalesce(r.step_at, r.created_at) as since
        from public.requests r join mine on mine.company_id = r.company_id
       where r.status = 'pending' and coalesce(r.step_at, r.created_at) <= now() - make_interval(days => public.reminder_days(r.company_id))
         and public.can_act(r, r.route[r.step + 1]))
    select u.user_id,
           coalesce(nullif(case when au.email ~* '@(staff|admin)\.waad\.app$' then null else au.email end, ''),
                    (select nullif(e.email, '') from public.members m join public.employees e on e.id = m.employee_id where m.user_id = u.user_id and m.company_id = l.company_id limit 1)),
           c.name, array_agg(l.k order by l.since), array_agg(l.line order by l.since)
      from late l join public.companies c on c.id = l.company_id left join auth.users au on au.id = u.user_id
     where not exists(select 1 from public.approval_reminders_sent x where x.user_id = u.user_id and x.key = l.k)
     group by c.name, au.email, l.company_id;
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
create or replace function public.approval_reminders_mark(p_user uuid, p_keys text[]) returns void
language sql security definer set search_path = public as $$
  insert into public.approval_reminders_sent(user_id, key) select p_user, k from unnest(p_keys) k on conflict do nothing;
  delete from public.approval_reminders_sent where sent_at < now() - interval '120 days';
$$;

CREATE OR REPLACE FUNCTION public.push_due()
 RETURNS TABLE(user_id uuid, key text, title text, body text, url text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare u record; since timestamptz;
begin
  for u in select s.user_id, min(s.created_at) as first_at from public.push_subscriptions s group by s.user_id loop
    since := greatest(u.first_at, now() - interval '2 days');
    perform set_config('request.jwt.claim.sub', u.user_id::text, true);
    return query
    with mine as (select m.company_id, m.employee_id from public.members m where m.user_id = u.user_id and public.member_live(m.employee_id, m.role)),
    ev as (
      select 'req:' || r.id || ':' || r.step as k, 'طلب بانتظار اعتمادك' as t,
             coalesce((select e.full_name from public.employees e where e.id = r.employee_id), '') || ' — ' || public.request_kind_ar(r.kind) as b, '#/approvals' as l
        from public.requests r join mine on mine.company_id = r.company_id
       where r.status = 'pending' and coalesce(r.step_at, r.created_at) > since and public.can_act(r, r.route[r.step + 1])
      union all
      select 'dec:' || r.id, case when r.status = 'approved' then 'اعتُمد طلبك' else 'رُفض طلبك' end, public.request_kind_ar(r.kind), '#/requests'
        from public.requests r join mine on mine.employee_id = r.employee_id
       where r.status in ('approved', 'rejected') and r.decided_at > since
      union all
      select 'sig:' || s.id, 'مستند بانتظار توقيعك', s.title, '#/sign'
        from public.signature_requests s join mine on mine.employee_id = s.employee_id
       where s.status = 'pending' and s.created_at > since
      union all
      select 'note:' || n.id, 'أشار إليك زميل في ملاحظة', left(n.body, 120), '#/home'
        from public.record_notes n join mine on mine.company_id = n.company_id
       where u.user_id = any(n.mentions) and n.created_by is distinct from u.user_id and n.created_at > since
      union all
      select 'pay:' || p.id, 'صدرت قسيمة راتبك', p.month || '/' || p.year, '#/payslips'
        from public.payroll_runs p join mine on mine.company_id = p.company_id
       where p.status <> 'draft' and p.approved_at > since and mine.employee_id is not null
         and exists(select 1 from public.payroll_lines l where l.run_id = p.id and l.employee_id = mine.employee_id)
      union all
      select 'ann:' || a.id, a.title, left(a.body, 120), '#/home'
        from public.company_announcements a join mine on mine.company_id = a.company_id
       where a.created_at > since and a.created_by is distinct from u.user_id
         and (a.department_id is null or exists(select 1 from public.employees e where e.id = mine.employee_id and e.department_id = a.department_id))
      union all
      select 'srv:' || s.id, 'استبيان جديد', s.title, '#/surveys'
        from public.surveys s join mine on mine.company_id = s.company_id
       where s.status = 'open' and s.created_at > since and s.created_by is distinct from u.user_id
      union all
      select 'fb:' || f.id, 'مطلوب رأيك في تقييم 360', coalesce((select e.full_name from public.employees e where e.id = f.employee_id), ''), '#/reviews'
        from public.review_feedback f join mine on mine.employee_id = f.rater_id
       where f.submitted_at is null and f.created_at > since
      union all
      select 'ts:' || p.id || ':' || max(t.created_at)::date, 'ساعات عمل بانتظار اعتمادك', p.name || ' — ' || count(*) || ' تسجيل', '#/mytime'
        from public.timesheets t join public.projects p on p.id = t.project_id join mine on mine.employee_id = p.manager_id
       where t.status = 'submitted' and t.employee_id <> mine.employee_id and t.created_at > since group by p.id, p.name
      union all
      select 'tsr:' || t.id, 'رُفضت ساعات عمل لك', coalesce(t.reject_note, ''), '#/mytime'
        from public.timesheets t join mine on mine.employee_id = t.employee_id
       where t.status = 'rejected' and t.reviewed_at > since
      union all
      select 'inst:' || i.id, 'قسط قرض مستحق قريبا', f.bank || ' — ' || (i.principal + i.profit) || ' — ' || i.due, '#/facilities'
        from public.facility_instalments i join public.bank_facilities f on f.id = i.facility_id join mine on mine.company_id = i.company_id
       where i.paid_on is null and f.status = 'active' and i.due <= current_date + 7 and public.has_role(i.company_id, array['owner','admin','finance'])
         and i.n = (select min(x.n) from public.facility_instalments x where x.facility_id = f.id and x.paid_on is null)
      union all
      select 'lg:' || f.id || ':' || f.expiry, 'خطاب ضمان ينتهي قريبا', f.bank || coalesce(' — ' || f.beneficiary, '') || ' — ' || f.expiry, '#/facilities'
        from public.bank_facilities f join mine on mine.company_id = f.company_id
       where f.kind = 'lg' and f.status = 'active' and f.expiry <= current_date + 30 and public.has_role(f.company_id, array['owner','admin','finance'])
      union all
      -- a request that has waited at my step longer than the company's step deadline (3 days by default); again every period
      select 'rem:' || r.id || ':' || r.step || ':' || floor(extract(epoch from now() - coalesce(r.step_at, r.created_at)) / 86400 / public.reminder_days(r.company_id))::int,
             'تذكير: طلب متأخر بانتظار اعتمادك',
             coalesce((select e.full_name from public.employees e where e.id = r.employee_id), '') || ' — ' || public.request_kind_ar(r.kind) || ' — ' || public.waited_days(r) || ' أيام', '#/approvals'
        from public.requests r join mine on mine.company_id = r.company_id
       where r.status = 'pending' and coalesce(r.step_at, r.created_at) <= now() - make_interval(days => public.reminder_days(r.company_id))
         and public.can_act(r, r.route[r.step + 1])
      union all
      select 'pw:' || r.id, 'موظف يطلب إعادة كلمة المرور', coalesce((select e.full_name from public.employees e where e.id = r.employee_id), ''), '#/employees'
        from public.staff_password_requests r join mine on mine.company_id = r.company_id
       where r.status = 'open' and r.created_at > since and public.has_role(r.company_id, array['owner','admin','hr']))
    select u.user_id, ev.k, ev.t, ev.b, ev.l from ev
     where not exists(select 1 from public.push_sent x where x.user_id = u.user_id and x.key = ev.k);
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);
end $function$;

revoke all on function public.reminder_days(uuid), public.waited_days(public.requests), public.request_kind_ar(text), public.push_due(),
  public.approval_reminders_due(), public.approval_reminders_mark(uuid, text[]) from public, anon, authenticated;
notify pgrst, 'reload schema';

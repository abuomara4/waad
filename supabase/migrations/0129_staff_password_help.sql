-- 0129 — employee sign-in (owner's request, 2026-11-18): «forgot password» from the employee sign-in screen.
-- The request goes only to the HR of the company whose code was entered. The answer never says whether the number exists, and
-- attempts are limited, so nobody can use it to discover employee numbers. HR issues a temporary password as before.
create table if not exists public.staff_password_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  status text not null default 'open' check (status in ('open','done','dismissed')),
  created_at timestamptz not null default now(),
  handled_by uuid, handled_at timestamptz
);
create unique index if not exists staff_password_requests_open on public.staff_password_requests(employee_id) where status = 'open';
create index if not exists staff_password_requests_co on public.staff_password_requests(company_id, status);
alter table public.staff_password_requests enable row level security;
drop policy if exists staff_password_requests_read on public.staff_password_requests;
create policy staff_password_requests_read on public.staff_password_requests for select using (public.has_role(company_id, array['owner','admin','hr']));
revoke all on public.staff_password_requests from anon, authenticated;
grant select on public.staff_password_requests to authenticated;
create table if not exists public.staff_help_hits (ip text not null, at timestamptz not null default now());
create index if not exists staff_help_hits_ip on public.staff_help_hits(ip, at);
alter table public.staff_help_hits enable row level security;
revoke all on public.staff_help_hits from anon, authenticated;

create or replace function public.staff_password_help(p_code text, p_emp_no text) returns void
language plpgsql volatile security definer set search_path = public as $$
declare hdr text := nullif(current_setting('request.headers', true), ''); v_ip text; c uuid; e uuid;
begin
  begin v_ip := nullif(trim(coalesce(hdr::json ->> 'cf-connecting-ip', hdr::json ->> 'x-real-ip', split_part(hdr::json ->> 'x-forwarded-for', ',', 1))), ''); exception when others then v_ip := null; end;
  v_ip := coalesce(v_ip, 'unknown');
  if (select count(*) from public.staff_help_hits where ip = v_ip and at > now() - interval '15 minutes') >= 5
     or (select count(*) from public.staff_help_hits where at > now() - interval '1 minute') >= 100 then
    raise exception 'محاولات كثيرة — حاول بعد ربع ساعة' using errcode = 'P0001'; end if;
  delete from public.staff_help_hits where at < now() - interval '1 day';
  insert into public.staff_help_hits(ip) values (v_ip);
  select id into c from public.companies where code = upper(btrim(coalesce(p_code, '')));
  if c is null then return; end if;
  select em.id into e from public.employees em join public.members m on m.company_id = em.company_id and m.employee_id = em.id
    join auth.users u on u.id = m.user_id
   where em.company_id = c and lower(em.emp_no::text) = lower(btrim(coalesce(p_emp_no, ''))) and lower(u.email) = lower(em.emp_no::text) || '.' || lower(btrim(p_code)) || '@staff.waad.app' and em.end_date is null limit 1;
  if e is null then return; end if;
  if exists(select 1 from public.staff_password_requests where employee_id = e and created_at > now() - interval '10 minutes') then return; end if;
  insert into public.staff_password_requests(company_id, employee_id) values (c, e) on conflict do nothing;
end $$;
create or replace function public.staff_password_dismiss(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare r public.staff_password_requests;
begin
  select * into r from public.staff_password_requests where id = p_id;
  if not found or not public.has_role(r.company_id, array['owner','admin','hr']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  update public.staff_password_requests set status = 'dismissed', handled_by = auth.uid(), handled_at = now() where id = p_id and status = 'open';
end $$;

CREATE OR REPLACE FUNCTION public.reset_staff_password(p_company uuid, p_employee uuid, p_password text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare m public.members;
begin
  select * into m from public.members where company_id = p_company and employee_id = p_employee;
  if not found then raise exception 'لا يوجد حساب دخول لهذا الموظف'; end if;
  if not public.can_invite(p_company, m.role) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if m.user_id = auth.uid() then raise exception 'غيّر كلمة مرورك من حسابك'; end if;
  if length(coalesce(p_password, '')) < 8 then raise exception 'كلمة المرور 8 أحرف على الأقل'; end if;
  if not exists(select 1 from auth.users where id = m.user_id and lower(email) = public.staff_email(p_company, p_employee)) then
    raise exception 'هذا الموظف يدخل ببريده — يستعيد كلمة المرور من «نسيت كلمة المرور»'; end if;
  update auth.users set encrypted_password = crypt(p_password, gen_salt('bf')) where id = m.user_id;
  update public.members set must_change_password = true where company_id = p_company and user_id = m.user_id;
  update public.staff_password_requests set status = 'done', handled_by = auth.uid(), handled_at = now() where company_id = p_company and employee_id = p_employee and status = 'open';
end $function$;

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
      select 'pw:' || r.id, 'موظف يطلب إعادة كلمة المرور', coalesce((select e.full_name from public.employees e where e.id = r.employee_id), ''), '#/employees'
        from public.staff_password_requests r join mine on mine.company_id = r.company_id
       where r.status = 'open' and r.created_at > since and public.has_role(r.company_id, array['owner','admin','hr']))
    select u.user_id, ev.k, ev.t, ev.b, ev.l from ev
     where not exists(select 1 from public.push_sent x where x.user_id = u.user_id and x.key = ev.k);
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);
end $function$;

revoke all on function public.staff_password_help(text, text), public.staff_password_dismiss(uuid) from public, anon, authenticated;
grant execute on function public.staff_password_help(text, text) to anon, authenticated;
grant execute on function public.staff_password_dismiss(uuid) to authenticated;

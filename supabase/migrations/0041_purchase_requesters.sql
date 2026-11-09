-- Who may raise a purchase request (company setting):
--   managers (default) — department managers (anyone with direct reports or the manager role), the owner, admins and finance
--   selected           — the above plus employees flagged «يرفع طلبات الشراء» in their record
--   all                — every employee (the direct manager's approval is then the gate)
alter table public.companies add column purchase_requesters text not null default 'managers'
  check (purchase_requesters in ('managers','selected','all'));
alter table public.employees add column can_request_purchase boolean not null default false;

create or replace function public.purchase_allowed(p_company uuid, p_emp uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select case (select purchase_requesters from public.companies where id = p_company)
    when 'all' then true
    else exists(select 1 from public.employees x where x.manager_id = p_emp and (x.end_date is null or x.end_date >= current_date))
      or exists(select 1 from public.members m where m.company_id = p_company and m.employee_id = p_emp
                and (m.role in ('owner','admin','finance','manager') or coalesce(m.extra_roles, '{}') && array['admin','finance','manager']))
      or ((select purchase_requesters from public.companies where id = p_company) = 'selected'
          and coalesce((select can_request_purchase from public.employees where id = p_emp), false))
  end
$$;

-- the caller's own permission (drives whether «طلب شراء» shows in the new-request list)
create or replace function public.my_purchase_allowed(p_company uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.my_employee(p_company) is not null and public.purchase_allowed(p_company, public.my_employee(p_company))
$$;

create or replace function public.purchase_requesters_set(p_company uuid, p_mode text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if p_mode not in ('managers','selected','all') then raise exception 'خيار غير معروف'; end if;
  update public.companies set purchase_requesters = p_mode where id = p_company;
end $$;

create or replace function public.purchase_request_check() returns trigger
language plpgsql security definer set search_path = public as $$
declare l jsonb; ls jsonb := '[]'; tot numeric := 0; q numeric; p numeric; d text;
begin
  if new.kind <> 'purchase' then return new; end if;
  if not public.purchase_allowed(new.company_id, new.employee_id) then
    raise exception 'طلب الشراء متاح لمدراء الأقسام ومن تحددهم المنشأة' using errcode = '42501'; end if;
  if jsonb_typeof(new.payload->'lines') <> 'array' or jsonb_array_length(new.payload->'lines') = 0 then raise exception 'أضف بنداً واحداً على الأقل'; end if;
  if jsonb_array_length(new.payload->'lines') > 30 then raise exception 'حتى 30 بنداً في الطلب'; end if;
  for l in select * from jsonb_array_elements(new.payload->'lines') loop
    d := trim(coalesce(l->>'desc', '')); q := nullif(l->>'qty', '')::numeric; p := coalesce(nullif(l->>'price', '')::numeric, 0);
    if length(d) < 2 then raise exception 'اكتب وصف البند'; end if;
    if q is null or q <= 0 then raise exception 'الكمية أكبر من صفر'; end if;
    if p < 0 then raise exception 'السعر التقديري لا يكون سالباً'; end if;
    ls := ls || jsonb_build_object('desc', left(d, 200), 'qty', q, 'price', round(p, 2));
    tot := tot + round(q * round(p, 2), 2);
  end loop;
  if new.from_date is not null and new.from_date < current_date then raise exception 'تاريخ الحاجة لا يكون قبل اليوم'; end if;
  new.payload := jsonb_build_object('lines', ls); new.amount := tot; new.to_date := new.from_date;
  return new;
end $$;

revoke all on function public.purchase_allowed(uuid, uuid), public.my_purchase_allowed(uuid), public.purchase_requesters_set(uuid, text), public.purchase_request_check() from public, anon, authenticated;
grant execute on function public.my_purchase_allowed(uuid), public.purchase_requesters_set(uuid, text) to authenticated;

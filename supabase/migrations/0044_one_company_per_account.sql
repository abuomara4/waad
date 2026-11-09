-- One account = one company (each company is its own subscription).
-- A user who already owns a company cannot create another one with the same account;
-- a second company needs its own account (another email).
create or replace function public.create_company(p_name text, p_vat text default null, p_cr text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  if auth.uid() is null then raise exception 'سجّل الدخول أولاً' using errcode = '42501'; end if;
  if exists(select 1 from public.members where user_id = auth.uid() and role = 'owner') then
    raise exception 'لكل حساب منشأة واحدة — لإضافة منشأة أخرى أنشئ حساباً جديداً ببريد آخر';
  end if;
  insert into public.companies(name, vat_no, cr_no) values (trim(p_name), nullif(p_vat,''), nullif(p_cr,'')) returning id into cid;
  insert into public.members(company_id, user_id, role) values (cid, auth.uid(), 'owner');
  perform public.seed_company(cid);   -- defined in 0003 (chart of accounts)
  return cid;
end $$;

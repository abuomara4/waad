-- Waad ERP — 0094 every company starts with the usual departments (owner's decision), Arabic and English; it can rename,
-- delete or add its own from «الموظفون ← الأقسام». Every existing company gets the ones it lacks now.
-- Nationalities were already a built-in list in the employee form.

create or replace function public.default_departments(p_company uuid) returns void
language sql security definer set search_path = public as $$
  insert into public.departments(company_id, name, name_en)
  select p_company, d.ar, d.en from (values
    ('الإدارة العامة', 'General Administration'), ('الموارد البشرية', 'Human Resources'), ('المالية', 'Finance'),
    ('المبيعات', 'Sales'), ('التسويق', 'Marketing'), ('المشتريات', 'Purchases'), ('المخزون', 'Inventory'),
    ('تقنية المعلومات', 'Information Technology'), ('خدمة العملاء', 'Customer Service')) d(ar, en)
  on conflict (company_id, name) do nothing
$$;
revoke all on function public.default_departments(uuid) from public, anon, authenticated;

create or replace function public.companies_default_departments() returns trigger
language plpgsql security definer set search_path = public as $$
begin perform public.default_departments(new.id); return new; end $$;
revoke all on function public.companies_default_departments() from public, anon, authenticated;
drop trigger if exists companies_default_departments on public.companies;
create trigger companies_default_departments after insert on public.companies for each row execute function public.companies_default_departments();

-- every existing company gets the ones it lacks (a department it already has, by name, is left as it is)
select public.default_departments(c.id) from public.companies c;

-- The company code employees sign in with is unique; a newly generated code that already exists is replaced
-- automatically, so creating a company never fails on a clash.
create or replace function public.company_code_guard() returns trigger language plpgsql as $$
begin
  new.code := upper(coalesce(nullif(trim(new.code), ''), substr(replace(gen_random_uuid()::text, '-', ''), 1, 6)));
  while exists(select 1 from public.companies c where c.code = new.code and c.id <> new.id) loop
    new.code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  end loop;
  return new;
end $$;
create trigger companies_code_guard before insert on public.companies for each row execute function public.company_code_guard();
revoke all on function public.company_code_guard() from public, anon, authenticated;

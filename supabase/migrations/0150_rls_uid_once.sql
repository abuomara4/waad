-- RLS performance (Supabase Postgres best practices, «security-rls-performance»): a policy that calls auth.uid() directly is
-- evaluated for every row; wrapped as (select auth.uid()) it is computed once per statement. Every public policy that still
-- calls it bare is recreated with the same name, command, roles, mode and conditions — only auth.uid() is wrapped.
do $$
declare p record; q text; w text;
begin
  for p in select * from pg_policies where schemaname = 'public'
            and (coalesce(qual, '') || coalesce(with_check, '')) ~ '(?<!SELECT )auth\.uid\(\)' loop
    q := regexp_replace(p.qual, '(?<!SELECT )auth\.uid\(\)', '(SELECT auth.uid())', 'g');
    w := regexp_replace(p.with_check, '(?<!SELECT )auth\.uid\(\)', '(SELECT auth.uid())', 'g');
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
    execute format('create policy %I on public.%I as %s for %s to %s%s%s', p.policyname, p.tablename, p.permissive, p.cmd,
      (select string_agg(case when r = 'public' then 'public' else quote_ident(r) end, ', ') from unnest(p.roles) r),
      case when q is not null then ' using (' || q || ')' else '' end,
      case when w is not null then ' with check (' || w || ')' else '' end);
  end loop;
end $$;
notify pgrst, 'reload schema';

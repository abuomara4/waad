-- 0055: the owner downloads a full copy of the company's data (personal-data access/portability under PDPL).
-- Tables are found from the schema itself, so new tables are included without touching this function:
--   * tables with a company_id column → rows of this company;
--   * tables without one → rows whose single-column foreign key points to an already-included row (up to 4 levels).
-- Attachments (base64 "data" text columns) and the logo are left out unless p_files is true.
-- Every export is written to the audit log; at most 5 exports per user per hour.

create or replace function public.company_export(p_company uuid, p_files boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  f jsonb := jsonb_build_object('companies', format('id = %L', p_company));   -- table → where clause
  skip text[] := array['client_errors', 'doc_sequences', 'platform_admins', 'platform_settings'];
  t record; fk record; pass int; added boolean; res jsonb := '{}'; rows jsonb; strip text[]; n int := 0; tot int := 0;
begin
  if not public.has_role(p_company, array['owner']) then raise exception 'تصدير البيانات لمالك المنشأة فقط' using errcode = '42501'; end if;
  if (select count(*) from public.audit_log where actor = auth.uid() and action = 'export' and at > now() - interval '1 hour') >= 5 then
    raise exception 'حاولت التصدير كثيراً — انتظر ساعة ثم أعد المحاولة'; end if;

  for t in select c.relname from pg_class c join pg_attribute a on a.attrelid = c.oid
            where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and a.attname = 'company_id' and not a.attisdropped
              and c.relname <> all(skip) loop
    f := f || jsonb_build_object(t.relname, format('company_id = %L', p_company));
  end loop;

  for pass in 1..4 loop
    added := false;
    for fk in select distinct on (c.relname) c.relname child, a.attname col, p.relname parent, pa.attname pcol
                from pg_constraint k join pg_class c on c.oid = k.conrelid join pg_class p on p.oid = k.confrelid
                join pg_attribute a on a.attrelid = c.oid and a.attnum = k.conkey[1]
                join pg_attribute pa on pa.attrelid = p.oid and pa.attnum = k.confkey[1]
               where k.contype = 'f' and cardinality(k.conkey) = 1 and c.relnamespace = 'public'::regnamespace and p.relnamespace = 'public'::regnamespace
                 and f ? p.relname and not f ? c.relname and c.relname <> all(skip)
               order by c.relname, k.conname loop
      f := f || jsonb_build_object(fk.child, format('%I in (select %I from public.%I where %s)', fk.col, fk.pcol, fk.parent, f->>fk.parent));
      added := true;
    end loop;
    exit when not added;
  end loop;

  for t in select key tbl, value #>> '{}' cond from jsonb_each(f) order by key loop
    strip := case when p_files then '{}'::text[] else array(
      select a.attname::text from pg_attribute a where a.attrelid = ('public.' || quote_ident(t.tbl))::regclass and a.attnum > 0 and not a.attisdropped
         and ((a.attname = 'data' and a.atttypid = 'text'::regtype) or (t.tbl = 'companies' and a.attname = 'logo'))) end;
    execute format('select coalesce(jsonb_agg(to_jsonb(x) - %L::text[]), ''[]'') from public.%I x where %s', strip, t.tbl, t.cond) into rows;
    n := n + 1; tot := tot + jsonb_array_length(rows);
    res := res || jsonb_build_object(t.tbl, rows);
  end loop;

  insert into public.audit_log(company_id, actor, action, entity, entity_id, data)
  values (p_company, auth.uid(), 'export', 'company', p_company::text, jsonb_build_object('files', p_files, 'tables', n, 'rows', tot));
  return jsonb_build_object('company_id', p_company, 'exported_at', now(), 'with_files', p_files, 'tables', res);
end $$;

revoke all on function public.company_export(uuid, boolean) from public, anon;
grant execute on function public.company_export(uuid, boolean) to authenticated;
notify pgrst, 'reload schema';

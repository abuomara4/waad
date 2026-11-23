-- Every foreign key gets an index on its referencing columns (0127 covered company_id and the cascade / set-null links;
-- this covers the rest), so joins and deletes of the referenced rows stay fast as companies grow.
do $$
declare r record; n int := 0;
begin
  for r in
    select c.conrelid::regclass as tbl, cl.relname, array_agg(a.attname order by k.ord) as cols
    from pg_constraint c
    join pg_class cl on cl.oid = c.conrelid
    join pg_namespace ns on ns.oid = cl.relnamespace
    cross join lateral unnest(c.conkey) with ordinality as k(attnum, ord)
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
    where c.contype = 'f' and ns.nspname = 'public'
      and not exists (select 1 from pg_index i where i.indrelid = c.conrelid
                      and (i.indkey::int2[])[0:array_length(c.conkey, 1) - 1] = c.conkey)
    group by c.oid, c.conrelid, cl.relname
  loop
    execute format('create index if not exists %I on %s (%s)', left(r.relname, 40) || '_fk_' || substr(md5(array_to_string(r.cols, ',')), 1, 8),
                   r.tbl, (select string_agg(quote_ident(x), ', ') from unnest(r.cols) x));
    n := n + 1;
  end loop;
  raise notice 'foreign-key indexes added: %', n;
end $$;

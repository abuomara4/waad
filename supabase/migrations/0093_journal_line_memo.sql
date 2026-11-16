-- Waad ERP — 0093 a description on each journal line (manual entries), and the purpose of a petty-cash fund (QA report).

alter table public.journal_lines add column if not exists memo text;

create or replace function public.post_journal(p_company uuid, p_date date, p_memo text, p_source text, p_source_id uuid, p_lines jsonb, p_reverses uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare jid uuid; l jsonb; d numeric := 0; c numeric := 0; n int := 0; pre text; dcc uuid := nullif(current_setting('waad.cc', true), '')::uuid;
begin
  for l in select * from jsonb_array_elements(p_lines) loop
    if round(coalesce((l->>'d')::numeric,0),2) = 0 and round(coalesce((l->>'c')::numeric,0),2) = 0 then continue; end if;
    if not exists(select 1 from public.accounts where company_id = p_company and code = l->>'a' and not is_header) then
      raise exception 'الحساب % غير موجود أو رئيسي', l->>'a'; end if;
    if nullif(l->>'cc', '') is not null and not exists(select 1 from public.cost_centers where id = (l->>'cc')::uuid and company_id = p_company) then
      raise exception 'مركز التكلفة غير موجود'; end if;
    d := d + round(coalesce((l->>'d')::numeric,0),2); c := c + round(coalesce((l->>'c')::numeric,0),2); n := n + 1;
  end loop;
  if n < 2 or d <> c then raise exception 'قيد غير متوازن (مدين % / دائن %)', d, c; end if;
  if dcc is not null and not exists(select 1 from public.cost_centers where id = dcc and company_id = p_company) then dcc := null; end if;
  pre := case p_source when 'manual' then 'JV' when 'reversal' then 'RJ' when 'opening' then 'OB' else 'AJ' end;
  insert into public.journal_entries(company_id, no, date, memo, source, source_id, reverses)
  values (p_company, public.next_doc_no(p_company, pre), p_date, p_memo, p_source, p_source_id, p_reverses) returning id into jid;
  insert into public.journal_lines(entry_id, company_id, account_code, debit, credit, cost_center_id, memo)
  select jid, p_company, x->>'a', round(coalesce((x->>'d')::numeric,0),2), round(coalesce((x->>'c')::numeric,0),2),
         coalesce(nullif(x->>'cc', '')::uuid, case when a.type in ('rev','exp') then dcc end), left(nullif(trim(x->>'m'), ''), 200)
  from jsonb_array_elements(p_lines) x join public.accounts a on a.company_id = p_company and a.code = x->>'a'
  where round(coalesce((x->>'d')::numeric,0),2) <> 0 or round(coalesce((x->>'c')::numeric,0),2) <> 0;
  return jid;
end $$;

-- petty cash: what the fund is for (shown in the list); set after opening it
create or replace function public.petty_set_note(p_id uuid, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare f public.petty_funds;
begin
  select * into f from public.petty_funds where id = p_id;
  if not found then raise exception 'العهدة غير موجودة'; end if;
  perform public.require_fin(f.company_id, 'je');
  update public.petty_funds set note = left(nullif(trim(p_note), ''), 300) where id = p_id;
end $$;
revoke all on function public.petty_set_note(uuid, text) from public, anon;
grant execute on function public.petty_set_note(uuid, text) to authenticated;

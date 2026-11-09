-- Bulk import of employee documents and contracts from Excel/CSV. All-or-nothing: any bad row aborts the file.
--  * Documents: one row per document. A row for a type the employee already has (or an "other" document with the same
--    title) updates it — that is how renewed iqamas and permits are uploaded; empty cells keep the stored value.
--  * Contracts: one row per employee. The new contract replaces the active one. When it starts the day after a
--    fixed-term contract ends, it is recorded as that contract's renewal (keeps the first start and counts renewals,
--    Art. 55). Re-uploading the same active contract changes nothing.

create or replace function public.import_documents(p_company uuid, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; ln text; e public.employees; t text; ttl text; iss date; exp date; d public.employee_documents; seen text[] := '{}'; k text;
        added int := 0; updated int := 0;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'الملف لا يحتوي مستندات'; end if;
  if jsonb_array_length(p_rows) > 3000 then raise exception 'الحد الأقصى 3000 سطر في الملف الواحد'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    ln := 'السطر ' || coalesce(r->>'_row', '?') || ': ';
    select * into e from public.employees where company_id = p_company and emp_no = trim(coalesce(r->>'emp_no', ''));
    if not found then raise exception '%الرقم الوظيفي % غير موجود', ln, coalesce(r->>'emp_no', ''); end if;
    t := r->>'doc_type';
    if t is null or t not in ('iqama','national_id','passport','work_permit','health','driving','other') then raise exception '%نوع المستند غير معروف', ln; end if;
    ttl := nullif(trim(coalesce(r->>'title', '')), '');
    if t = 'other' and length(coalesce(ttl, '')) < 2 then raise exception '%اكتب اسم المستند الآخر', ln; end if;
    begin iss := nullif(r->>'issue_date', '')::date; exp := nullif(r->>'expiry_date', '')::date;
    exception when others then raise exception '%التاريخ بصيغة YYYY-MM-DD', ln; end;
    if iss is not null and exp is not null and exp < iss then raise exception '%تاريخ الانتهاء قبل الإصدار', ln; end if;
    if nullif(trim(coalesce(r->>'doc_no', '')), '') is null and exp is null then raise exception '%أدخل رقم المستند أو تاريخ انتهائه', ln; end if;
    k := e.id || '|' || t || '|' || case when t = 'other' then lower(ttl) else '' end;
    if k = any(seen) then raise exception '%المستند مكرر في الملف لنفس الموظف', ln; end if;
    seen := seen || k;
    select * into d from public.employee_documents where employee_id = e.id and doc_type = t and (t <> 'other' or lower(title) = lower(ttl))
     order by expiry_date desc nulls last limit 1;
    if found then
      update public.employee_documents set
        doc_no = coalesce(nullif(trim(coalesce(r->>'doc_no', '')), ''), doc_no), issue_date = coalesce(iss, issue_date), expiry_date = coalesce(exp, expiry_date),
        title_en = coalesce(nullif(trim(coalesce(r->>'title_en', '')), ''), title_en), notes = coalesce(nullif(trim(coalesce(r->>'notes', '')), ''), notes)
       where id = d.id;
      updated := updated + 1;
    else
      insert into public.employee_documents(company_id, employee_id, doc_type, title, title_en, doc_no, issue_date, expiry_date, notes)
      values (p_company, e.id, t, case when t = 'other' then ttl end, case when t = 'other' then nullif(trim(coalesce(r->>'title_en', '')), '') end,
              nullif(trim(coalesce(r->>'doc_no', '')), ''), iss, exp, nullif(trim(coalesce(r->>'notes', '')), ''));
      added := added + 1;
    end if;
  end loop;
  return jsonb_build_object('added', added, 'updated', updated);
end $$;

create or replace function public.import_contracts(p_company uuid, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; ln text; e public.employees; t text; st date; en date; fs date; rn int; cur public.contracts; seen uuid[] := '{}';
        mp boolean; cl boolean; added int := 0; renewed int := 0; same int := 0;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'الملف لا يحتوي عقوداً'; end if;
  if jsonb_array_length(p_rows) > 1000 then raise exception 'الحد الأقصى 1000 عقد في الملف الواحد'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    ln := 'السطر ' || coalesce(r->>'_row', '?') || ': ';
    select * into e from public.employees where company_id = p_company and emp_no = trim(coalesce(r->>'emp_no', ''));
    if not found then raise exception '%الرقم الوظيفي % غير موجود', ln, coalesce(r->>'emp_no', ''); end if;
    if e.id = any(seen) then raise exception '%للموظف أكثر من عقد في الملف — ارفع العقد الساري فقط', ln; end if;
    seen := seen || e.id;
    t := r->>'contract_type';
    if t is null or t not in ('fixed','indefinite') then raise exception '%نوع العقد: محدد المدة أو غير محدد المدة', ln; end if;
    if t = 'indefinite' and not e.is_saudi then raise exception '%عقد غير السعودي يكون محدد المدة — م37', ln; end if;
    begin st := nullif(r->>'start_date', '')::date; en := nullif(r->>'end_date', '')::date; fs := nullif(r->>'first_start', '')::date;
    exception when others then raise exception '%التاريخ بصيغة YYYY-MM-DD', ln; end;
    if st is null then raise exception '%تاريخ بداية العقد مطلوب', ln; end if;
    if t = 'indefinite' and en is not null then raise exception '%العقد غير محدد المدة ليس له تاريخ نهاية', ln; end if;
    if t = 'fixed' and en is null then
      if e.is_saudi then raise exception '%أدخل تاريخ نهاية العقد المحدد المدة', ln; end if;
      en := (st + interval '1 year' - interval '1 day')::date;   -- Art. 37: one year when no term is stated
    end if;
    if en is not null and en < st then raise exception '%تاريخ نهاية العقد قبل بدايته', ln; end if;
    if fs is not null and fs > st then raise exception '%بداية أول عقد بعد بداية هذا العقد', ln; end if;
    if coalesce(r->>'renewal_no', '') !~ '^([0-9]{1,2})?$' then raise exception '%عدد مرات التجديد رقم من 0 إلى 99', ln; end if;
    rn := nullif(r->>'renewal_no', '')::int;
    mp := coalesce(nullif(r->>'monthly_paid', '')::boolean, true); cl := coalesce(nullif(r->>'renewal_clause', '')::boolean, false);
    select * into cur from public.contracts where employee_id = e.id and status = 'active';
    if found and cur.contract_type = t and cur.start_date = st and cur.end_date is not distinct from en then
      same := same + 1; continue;                     -- the same contract uploaded again
    end if;
    if found and cur.contract_type = 'fixed' and st = cur.end_date + 1 then   -- the next term of the current contract
      update public.contracts set status = 'renewed' where id = cur.id;
      insert into public.contracts(company_id, employee_id, contract_type, start_date, end_date, monthly_paid, renewal_clause, renewal_no, first_start, prev_id, notes)
      values (p_company, e.id, t, st, en, mp, cl, coalesce(rn, cur.renewal_no + 1), least(coalesce(fs, cur.first_start), cur.first_start), cur.id, nullif(trim(coalesce(r->>'notes', '')), ''));
      renewed := renewed + 1;
    else
      if found then update public.contracts set status = 'ended' where id = cur.id; end if;
      insert into public.contracts(company_id, employee_id, contract_type, start_date, end_date, monthly_paid, renewal_clause, renewal_no, first_start, notes)
      values (p_company, e.id, t, st, en, mp, cl, coalesce(rn, 0), coalesce(fs, st), nullif(trim(coalesce(r->>'notes', '')), ''));
      added := added + 1;
    end if;
  end loop;
  return jsonb_build_object('added', added, 'renewed', renewed, 'same', same);
end $$;

revoke all on function public.import_documents(uuid, jsonb), public.import_contracts(uuid, jsonb) from public, anon;
grant execute on function public.import_documents(uuid, jsonb), public.import_contracts(uuid, jsonb) to authenticated;
notify pgrst, 'reload schema';

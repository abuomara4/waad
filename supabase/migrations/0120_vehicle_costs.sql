-- 0120 — vehicle costs in the books (owner's request, 2026-11-18): every fuel / maintenance / service / repair cost logged on a
-- vehicle is posted at once (when the finance module is on): Dr 5240 «مصروفات السيارات (وقود وصيانة)» on the driver's cost
-- center, Cr the cash box (1110) or the bank (1120) it was paid from. Deleting a posted log reverses its entry, and only the
-- owner, the system admin or the finance manager may do that.

alter table public.vehicle_logs add column if not exists paid_from text not null default '1120' check (paid_from in ('1110','1120'));
alter table public.vehicle_logs add column if not exists entry_id uuid references public.journal_entries(id) on delete set null;
alter table public.journal_entries drop constraint if exists journal_entries_source_check;
alter table public.journal_entries add constraint journal_entries_source_check check (source in ('manual','reversal','sales','purchase','receipt','payment',
  'stock','payroll','payroll_pay','advance','expense','opening','sales_return','purchase_return','asset','depreciation','cheque','closing','petty','trip','vehicle'));
insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header)
  select a.company_id, '5240', 'مصروفات السيارات (وقود وصيانة)', 'Vehicle expenses (fuel and maintenance)', 'exp', '5000', false from public.accounts a where a.code = '5000'
  on conflict do nothing;

create or replace function public.vehicle_logs_post() returns trigger language plpgsql security definer set search_path = public as $$
declare v public.vehicles; cc uuid; jid uuid;
  K constant jsonb := '{"fuel":"وقود","service":"صيانة دورية","maintenance":"صيانة","repair":"إصلاح","other":"مصروف"}';
begin
  if new.amount <= 0 or not public.module_on(new.company_id, 'finance') then return new; end if;
  select * into v from public.vehicles where id = new.vehicle_id;
  select cost_center_id into cc from public.employees where id = coalesce(new.driver_id, v.driver_id);
  insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header)
  values (new.company_id, '5240', 'مصروفات السيارات (وقود وصيانة)', 'Vehicle expenses (fuel and maintenance)', 'exp', '5000', false) on conflict do nothing;
  jid := public.post_journal(new.company_id, new.day, (K->>new.kind) || ' — ' || v.plate || coalesce(' — ' || new.note, ''), 'vehicle', new.id,
    jsonb_build_array(jsonb_build_object('a', '5240', 'd', new.amount, 'cc', cc), jsonb_build_object('a', new.paid_from, 'c', new.amount)));
  new.entry_id := jid;
  return new;
end $$;
drop trigger if exists vehicle_logs_post on public.vehicle_logs;
create trigger vehicle_logs_post before insert on public.vehicle_logs for each row execute function public.vehicle_logs_post();

-- a posted cost is not edited: it is deleted (finance) and its entry reversed, then logged again
create or replace function public.vehicle_logs_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if old.entry_id is not null and (new.amount, new.paid_from, new.day) is distinct from (old.amount, old.paid_from, old.day) then
      raise exception 'المصروف مُرحّل في الحسابات: احذفه وسجّله من جديد'; end if;
    return new;
  end if;
  if old.entry_id is not null then
    if auth.uid() is not null and not public.has_role(old.company_id, array['owner','admin','finance']) then
      raise exception 'حذف مصروف مُرحّل للمالك ومدير النظام والمدير المالي فقط' using errcode = '42501'; end if;
    perform public.post_journal(old.company_id, current_date, 'عكس مصروف سيارة محذوف', 'reversal', null,
      (select jsonb_agg(jsonb_build_object('a', account_code, 'd', credit, 'c', debit, 'cc', cost_center_id)) from public.journal_lines where entry_id = old.entry_id), old.entry_id);
  end if;
  return old;
end $$;
drop trigger if exists vehicle_logs_guard on public.vehicle_logs;
create trigger vehicle_logs_guard before update or delete on public.vehicle_logs for each row execute function public.vehicle_logs_guard();

CREATE OR REPLACE FUNCTION public.seed_company(p_company uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.accounts(company_id, code, name, type, parent_code, is_header) values
  (p_company,'1000','الأصول','asset',null,true),(p_company,'1100','النقدية والبنوك','asset','1000',true),
  (p_company,'1110','الصندوق','asset','1100',false),(p_company,'1120','البنك','asset','1100',false),
  (p_company,'1200','العملاء (ذمم مدينة)','asset','1000',false),(p_company,'1300','المخزون','asset','1000',false),
  (p_company,'1400','ضريبة القيمة المضافة — مدخلات','asset','1000',false),(p_company,'1500','سلف الموظفين','asset','1000',false),
  (p_company,'1600','مصروفات مدفوعة مقدماً','asset','1000',false),(p_company,'1700','الأصول الثابتة','asset','1000',false),
  (p_company,'2000','الخصوم','liab',null,true),(p_company,'2100','الموردون (ذمم دائنة)','liab','2000',false),
  (p_company,'2200','ضريبة القيمة المضافة — مخرجات','liab','2000',false),(p_company,'2300','رواتب مستحقة','liab','2000',false),
  (p_company,'2400','التأمينات الاجتماعية المستحقة','liab','2000',false),(p_company,'2500','مخصص مكافأة نهاية الخدمة','liab','2000',false),
  (p_company,'3000','حقوق الملكية','equity',null,true),(p_company,'3100','رأس المال','equity','3000',false),
  (p_company,'3200','الأرباح المبقاة','equity','3000',false),
  (p_company,'4000','الإيرادات','rev',null,true),(p_company,'4100','إيرادات المبيعات','rev','4000',false),
  (p_company,'4200','إيرادات الخدمات','rev','4000',false),(p_company,'4900','إيرادات أخرى','rev','4000',false),
  (p_company,'5000','المصروفات','exp',null,true),(p_company,'5100','تكلفة البضاعة المباعة','exp','5000',false),
  (p_company,'5200','الرواتب والأجور','exp','5000',false),(p_company,'5210','حصة المنشأة في التأمينات الاجتماعية','exp','5000',false),(p_company,'5300','الإيجار','exp','5000',false),
  (p_company,'5400','المرافق والاتصالات','exp','5000',false),(p_company,'5500','مصروفات إدارية وعمومية','exp','5000',false),(p_company,'5230','بدل انتداب ورحلات العمل','exp','5000',false),(p_company,'5240','مصروفات السيارات (وقود وصيانة)','exp','5000',false),
  (p_company,'5600','فروقات المخزون','exp','5000',false),(p_company,'5900','مصروفات أخرى','exp','5000',false)
  on conflict do nothing;
  insert into public.finance_permissions(company_id, role, perm)
  select p_company, r, p from (values ('accountant','sales'),('accountant','purch'),('accountant','stock'),('accountant','items'),('accountant','je'),
                                      ('storekeeper','stock'),('storekeeper','stockadj'),('storekeeper','items')) v(r,p)
  on conflict do nothing;
end $function$;

revoke all on function public.vehicle_logs_post() from public, anon;
revoke all on function public.vehicle_logs_guard() from public, anon;

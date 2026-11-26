-- 0159 «رسالة الترحيب» as large companies do it: words from the manager (name, title, optional photo), the company's identity
-- (about, vision, values), the day-one plan (time, place, who to meet) and the first-week tasks — written once by the owner / HR;
-- per new employee: a companion colleague (buddy) and his own day-one details. Read by every member with the company row
-- (texts) and the employee's own row (buddy, first_day); written only through the two functions below.
alter table public.companies
  add column if not exists wel_note text check (wel_note is null or length(wel_note) <= 600),
  add column if not exists wel_note_en text check (wel_note_en is null or length(wel_note_en) <= 600),
  add column if not exists wel_from text check (wel_from is null or length(wel_from) <= 80),
  add column if not exists wel_from_en text check (wel_from_en is null or length(wel_from_en) <= 80),
  add column if not exists wel_title text check (wel_title is null or length(wel_title) <= 80),
  add column if not exists wel_title_en text check (wel_title_en is null or length(wel_title_en) <= 80),
  add column if not exists wel_photo text check (wel_photo is null or (wel_photo ~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$' and length(wel_photo) <= 200000)),
  add column if not exists about text check (about is null or length(about) <= 400),
  add column if not exists about_en text check (about_en is null or length(about_en) <= 400),
  add column if not exists vision text check (vision is null or length(vision) <= 300),
  add column if not exists vision_en text check (vision_en is null or length(vision_en) <= 300),
  add column if not exists core_values jsonb not null default '[]' check (jsonb_typeof(core_values) = 'array' and jsonb_array_length(core_values) <= 8),
  add column if not exists wel_time time,
  add column if not exists wel_place text check (wel_place is null or length(wel_place) <= 160),
  add column if not exists wel_place_en text check (wel_place_en is null or length(wel_place_en) <= 160),
  add column if not exists wel_week jsonb not null default '[]' check (jsonb_typeof(wel_week) = 'array' and jsonb_array_length(wel_week) <= 8);

alter table public.employees
  add column if not exists buddy_id uuid references public.employees(id) on delete set null,
  add column if not exists first_day jsonb not null default '{}' check (jsonb_typeof(first_day) = 'object');
alter table public.employees drop constraint if exists employees_buddy_not_self;
alter table public.employees add constraint employees_buddy_not_self check (buddy_id is null or buddy_id <> id);
create index if not exists employees_buddy_id_idx on public.employees(buddy_id);

-- a list of {ar, en} lines: trimmed, empty Arabic lines dropped, at most 8
create or replace function public.wel_lines(p jsonb, p_len int) returns jsonb
language sql immutable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('ar', left(btrim(x->>'ar'), p_len), 'en', nullif(left(btrim(coalesce(x->>'en', '')), p_len), '')) order by n), '[]'::jsonb)
    from (select x, n from jsonb_array_elements(case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end) with ordinality t(x, n)
           where jsonb_typeof(x) = 'object' and btrim(coalesce(x->>'ar', '')) <> '' order by n limit 8) s
$$;

create or replace function public.welcome_set(p_company uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare t text := nullif(btrim(coalesce(p->>'time', '')), '');
begin
  if not (public.has_role(p_company, array['owner','admin','hr']) or coalesce(public.fin_can(p_company, 'hr_ann'), false)) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  if t is not null and t !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'وقت المباشرة غير صحيح' using errcode = '22023'; end if;
  update public.companies set
    wel_note = nullif(btrim(p->>'note'), ''), wel_note_en = nullif(btrim(p->>'note_en'), ''),
    wel_from = nullif(btrim(p->>'from'), ''), wel_from_en = nullif(btrim(p->>'from_en'), ''),
    wel_title = nullif(btrim(p->>'title'), ''), wel_title_en = nullif(btrim(p->>'title_en'), ''),
    wel_photo = case when p ? 'photo' then nullif(p->>'photo', '') else wel_photo end,
    about = nullif(btrim(p->>'about'), ''), about_en = nullif(btrim(p->>'about_en'), ''),
    vision = nullif(btrim(p->>'vision'), ''), vision_en = nullif(btrim(p->>'vision_en'), ''),
    core_values = public.wel_lines(p->'values', 60), wel_week = public.wel_lines(p->'week', 120),
    wel_time = t::time, wel_place = nullif(btrim(p->>'place'), ''), wel_place_en = nullif(btrim(p->>'place_en'), '')
   where id = p_company;
end $$;

-- a new employee's companion and his own day-one details (time, place, who meets him)
create or replace function public.welcome_emp_set(p_company uuid, p_emp uuid, p_buddy uuid, p_day jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare t text := nullif(btrim(coalesce(p_day->>'time', '')), '');
begin
  if not public.has_role(p_company, array['owner','admin','hr']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if not exists (select 1 from public.employees where id = p_emp and company_id = p_company) then raise exception 'الموظف غير موجود' using errcode = 'P0002'; end if;
  if p_buddy is not null and (p_buddy = p_emp or not exists (select 1 from public.employees where id = p_buddy and company_id = p_company
      and (end_date is null or end_date >= current_date))) then raise exception 'الزميل المرافق يجب أن يكون موظفا آخر على رأس العمل في المنشأة' using errcode = '22023'; end if;
  if t is not null and t !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'وقت المباشرة غير صحيح' using errcode = '22023'; end if;
  update public.employees set buddy_id = p_buddy,
    first_day = jsonb_strip_nulls(jsonb_build_object('time', t, 'place', nullif(left(btrim(coalesce(p_day->>'place', '')), 160), ''),
      'meet', nullif(left(btrim(coalesce(p_day->>'meet', '')), 160), '')))
   where id = p_emp;
end $$;

revoke all on function public.wel_lines(jsonb, int), public.welcome_set(uuid, jsonb), public.welcome_emp_set(uuid, uuid, uuid, jsonb) from public, anon;
revoke all on function public.wel_lines(jsonb, int) from authenticated;
grant execute on function public.welcome_set(uuid, jsonb), public.welcome_emp_set(uuid, uuid, uuid, jsonb) to authenticated;

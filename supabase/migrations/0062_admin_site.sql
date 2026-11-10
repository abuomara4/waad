-- Waad ERP — 0062 the separate admin site (site/admin/): website visitor counts, editable website content, and
-- announcements shown to every company inside the system. Platform admin only; still no company records.

-- ---------- website visitor counts: daily totals only (no IP, no cookie, no visitor id) ----------
create table if not exists public.site_stats (
  day date not null,
  page text not null check (page in ('home','modules','trust','contact')),
  source text not null check (source in ('direct','whatsapp','google','bing','x','linkedin','instagram','snapchat','tiktok','facebook','other')),
  device text not null check (device in ('mobile','tablet','desktop')),
  lang text not null check (lang in ('ar','en')),
  views int not null default 0,
  visits int not null default 0,
  cta int not null default 0,
  primary key (day, page, source, device, lang)
);
alter table public.site_stats enable row level security;
revoke all on public.site_stats from anon, authenticated;

-- called by the public website (signed out): 'view' = a page opened, 'visit' = the first page of a visit (also a view),
-- 'cta' = the free-trial button pressed. Anything unexpected is folded into a safe value rather than rejected.
create or replace function public.site_hit(p_page text, p_source text, p_device text, p_lang text, p_kind text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_page text := case when p_page in ('home','modules','trust','contact') then p_page end;
  v_src text := case when p_source in ('direct','whatsapp','google','bing','x','linkedin','instagram','snapchat','tiktok','facebook') then p_source else 'other' end;
  v_dev text := case when p_device in ('mobile','tablet','desktop') then p_device else 'desktop' end;
  v_lang text := case when p_lang = 'en' then 'en' else 'ar' end;
begin
  if v_page is null or p_kind not in ('view','visit','cta') then return; end if;
  insert into public.site_stats as s(day, page, source, device, lang, views, visits, cta)
  values ((now() at time zone 'Asia/Riyadh')::date, v_page, v_src, v_dev, v_lang,
          (p_kind <> 'cta')::int, (p_kind = 'visit')::int, (p_kind = 'cta')::int)
  on conflict (day, page, source, device, lang) do update
    set views = s.views + excluded.views, visits = s.visits + excluded.visits, cta = s.cta + excluded.cta;
end $$;

create or replace function public.platform_site_stats(p_days int default 30)
returns table(day date, page text, source text, device text, lang text, views int, visits int, cta int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query select s.day, s.page, s.source, s.device, s.lang, s.views, s.visits, s.cta from public.site_stats s
    where s.day > (now() at time zone 'Asia/Riyadh')::date - least(greatest(coalesce(p_days, 30), 1), 366)
    order by s.day;
end $$;

-- ---------- website content the admin can change without a new release ----------
-- contact: {"phone":"9665…","email":"…"}; banner: {"on":true,"ar":"…","en":"…"}; faq: [{"qa":"…","aa":"…","qe":"…","ae":"…"}]
create table if not exists public.site_content (
  key text primary key check (key in ('contact','banner','faq')),
  value jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.site_content enable row level security;
revoke all on public.site_content from anon, authenticated;

create or replace function public.site_content() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from public.site_content
$$;

create or replace function public.platform_set_site_content(p_key text, p_value jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p_key not in ('contact','banner','faq') then raise exception 'محتوى غير معروف'; end if;
  if p_value is null or p_value = 'null'::jsonb then delete from public.site_content where key = p_key; return; end if;   -- back to the built-in text
  if length(coalesce(p_value::text, '')) > 20000 then raise exception 'المحتوى طويل جداً'; end if;
  if p_key = 'contact' and (coalesce(p_value->>'phone', '') !~ '^9665[0-9]{8}$' or coalesce(p_value->>'email', '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception 'رقم الجوال أو البريد غير صحيح';
  end if;
  if p_key = 'faq' and jsonb_typeof(p_value) <> 'array' then raise exception 'محتوى غير معروف'; end if;
  insert into public.site_content(key, value, updated_at) values (p_key, p_value, now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
end $$;

-- ---------- announcements to every company (maintenance, a new feature) ----------
create table if not exists public.platform_announcements (
  id uuid primary key default gen_random_uuid(),
  body_ar text not null check (length(trim(body_ar)) between 1 and 400),
  body_en text check (body_en is null or length(body_en) <= 400),
  level text not null default 'info' check (level in ('info','warn')),
  starts_at date not null default ((now() at time zone 'Asia/Riyadh')::date),
  ends_at date,
  created_at timestamptz not null default now(),
  check (ends_at is null or ends_at >= starts_at)
);
alter table public.platform_announcements enable row level security;
revoke all on public.platform_announcements from anon, authenticated;

-- what a signed-in user sees now (any role, any company)
create or replace function public.my_announcements() returns table(id uuid, body_ar text, body_en text, level text)
language sql stable security definer set search_path = public as $$
  select a.id, a.body_ar, a.body_en, a.level from public.platform_announcements a
   where auth.uid() is not null and a.starts_at <= (now() at time zone 'Asia/Riyadh')::date
     and (a.ends_at is null or a.ends_at >= (now() at time zone 'Asia/Riyadh')::date)
   order by a.created_at desc limit 3
$$;

create or replace function public.platform_announcements() returns setof public.platform_announcements
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query select * from public.platform_announcements order by created_at desc;
end $$;

create or replace function public.platform_save_announcement(p_id uuid, p_body_ar text, p_body_en text, p_level text, p_starts date, p_ends date)
returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if nullif(trim(p_body_ar), '') is null then raise exception 'اكتب نص الإعلان'; end if;
  if p_ends is not null and p_ends < coalesce(p_starts, (now() at time zone 'Asia/Riyadh')::date) then raise exception 'تاريخ النهاية قبل البداية'; end if;
  if p_id is null then
    insert into public.platform_announcements(body_ar, body_en, level, starts_at, ends_at)
    values (trim(p_body_ar), nullif(trim(p_body_en), ''), coalesce(p_level, 'info'), coalesce(p_starts, (now() at time zone 'Asia/Riyadh')::date), p_ends)
    returning id into v;
  else
    update public.platform_announcements set body_ar = trim(p_body_ar), body_en = nullif(trim(p_body_en), ''), level = coalesce(p_level, 'info'),
      starts_at = coalesce(p_starts, starts_at), ends_at = p_ends where id = p_id returning id into v;
    if v is null then raise exception 'الإعلان غير موجود'; end if;
  end if;
  return v;
end $$;

create or replace function public.platform_delete_announcement(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  delete from public.platform_announcements where id = p_id;
end $$;

revoke all on function public.site_hit(text, text, text, text, text), public.site_content(), public.platform_site_stats(int),
  public.platform_set_site_content(text, jsonb), public.my_announcements(), public.platform_announcements(),
  public.platform_save_announcement(uuid, text, text, text, date, date), public.platform_delete_announcement(uuid) from public, anon;
-- the public website is signed out: it may only count a visit and read its own texts
grant execute on function public.site_hit(text, text, text, text, text), public.site_content() to anon, authenticated;
grant execute on function public.platform_site_stats(int), public.platform_set_site_content(text, jsonb), public.my_announcements(),
  public.platform_announcements(), public.platform_save_announcement(uuid, text, text, text, date, date),
  public.platform_delete_announcement(uuid) to authenticated;

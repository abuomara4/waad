-- Waad ERP — 0158 «اختبر فهمك» covers the new features (owner's request, 2026-11-26): e8 confidential report, e9 directory
-- privacy, e10 expense receipt; m5 bulk approval, m6 probation evaluation. Same ids and order as GUIDE_QUIZ in
-- app/src/guide_lib.js; the key stays server-side only.
create or replace function public.guide_quiz_key(p_section text) returns jsonb
language sql immutable set search_path = public as $$
  select case p_section
    when 'emp' then '{"e1":1,"e2":0,"e3":2,"e4":0,"e5":1,"e6":2,"e7":0,"e8":0,"e9":1,"e10":2}'::jsonb
    when 'mgr' then '{"m1":1,"m2":0,"m3":2,"m4":0,"m5":1,"m6":0}'::jsonb end
$$;
revoke all on function public.guide_quiz_key(text) from public, anon, authenticated;

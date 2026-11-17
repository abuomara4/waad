-- 0117 — a default per diem every company starts with and can change (owner's decision, 2026-11-18): the common pattern in
-- published Saudi organisations' travel policies — outside the Kingdom about double inside, managers higher (set per grade):
-- 300 SAR a day inside the Kingdom and 600 SAR outside. The Labor Law sets no amount; it stays company policy.
alter table public.companies alter column per_diem_in set default 300;
alter table public.companies alter column per_diem_out set default 600;
update public.companies set per_diem_in = 300 where per_diem_in is null;
update public.companies set per_diem_out = 600 where per_diem_out is null;

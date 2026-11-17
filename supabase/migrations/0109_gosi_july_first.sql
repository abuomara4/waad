-- 0109 — GOSI: the yearly pension increase for contributors under the new Social Insurance Law (no contribution
-- before 3 July 2024) applies from 1 July of each year (GOSI clarification: 9% 2024, 9.5% from 1 July 2025, 10% from
-- 1 July 2026, 10.5% from 1 July 2027, 11% from 1 July 2028 — on the employee and the employer alike; pension branch only).
-- Eligibility stays «first registered from 3 July 2024» (gosi_is_new); only the step dates move from 3 July to 1 July.
create or replace function public.gosi_annuity(p_new boolean, p_as_of date) returns numeric language sql immutable as $$
  select case when not p_new then 9 else 9 + 0.5 * (
    (p_as_of >= date '2025-07-01')::int + (p_as_of >= date '2026-07-01')::int + (p_as_of >= date '2027-07-01')::int + (p_as_of >= date '2028-07-01')::int) end
$$;

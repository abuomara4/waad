-- Waad ERP — 0060 HR edits (batch 2): small additive HR-module changes requested from the live system.
-- Safe to run on an existing database (additive only). Groups several UI-backing columns in one file.

-- ---------- #19 interview type on candidates ----------
alter table public.candidates
  add column if not exists interview_type text
  check (interview_type is null or interview_type in ('onsite', 'remote', 'phone'));

comment on column public.candidates.interview_type is 'نوع المقابلة: حضورية/عن بُعد/هاتفية';

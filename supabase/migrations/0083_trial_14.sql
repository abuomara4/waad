-- Waad ERP — 0083 the free trial is 14 days by default (owner's decision with the yearly subscription; the Waad team can
-- still change it in the admin site, or per company when accepting it).
alter table public.platform_settings alter column default_trial_days set default 14;
update public.platform_settings set default_trial_days = 14;

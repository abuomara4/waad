-- Waad ERP — 0077 the free trial is 7 days by default (the Waad team can still change it in the admin site, or per company
-- when accepting it). An empty value used to mean "no end"; it now falls back to 7.
alter table public.platform_settings alter column default_trial_days set default 7;
update public.platform_settings set default_trial_days = 7 where default_trial_days is null;

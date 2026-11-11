-- Waad ERP — 0075 customers may start with their real data in the trial. At company creation the owner explicitly agrees
-- that the data is stored with a cloud provider outside the Kingdom (Japan); the moment of that consent is kept here.
alter table public.companies add column if not exists xfer_consent_at timestamptz;

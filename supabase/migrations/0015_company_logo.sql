-- Company logo for letters and printed documents. Stored inline as a small raster data URL (resized in the browser,
-- at most ~200 KB) so it needs no storage bucket; SVG is rasterized first, so no script can ride along in the image.
alter table public.companies add column logo text
  check (logo is null or (logo ~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$' and length(logo) <= 200000));
notify pgrst, 'reload schema';

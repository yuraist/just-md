-- Optional least-privilege hardening for the JustMD newsletter endpoint.
-- Project: Nuta Apps (txeisrdkgcloqjiqexnw).
-- Review current grants before applying through the Supabase SQL editor.
-- This preserves the existing anon INSERT policy and does not change rows.
-- The app uses POST with Prefer: return=minimal and needs only INSERT.
begin;

revoke all privileges on table public.newsletter_subscribers
  from anon, authenticated;
grant insert on table public.newsletter_subscribers to anon;

commit;

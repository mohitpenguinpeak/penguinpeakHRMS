-- Extend profiles without changing existing row-level security policies.
alter table public.profiles
  add column if not exists profile_details jsonb not null default '{}'::jsonb;

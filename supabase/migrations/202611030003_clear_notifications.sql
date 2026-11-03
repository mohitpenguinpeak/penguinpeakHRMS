-- Clearing hides notifications from the recipient's inbox without deleting history.
alter table public.notifications
  add column if not exists dismissed_at timestamptz;
grant update (dismissed_at) on public.notifications to authenticated;
-- The existing notifications_update_own RLS policy limits updates to the recipient.

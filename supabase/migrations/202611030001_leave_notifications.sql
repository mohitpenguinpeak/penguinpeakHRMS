-- Notifications are created atomically with the leave request, including RPC inserts.
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  leave_request_id text not null,
  title text not null,
  body text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  unique (recipient_id, leave_request_id)
);
create index notifications_recipient_created_idx
  on public.notifications (recipient_id, created_at desc);
alter table public.notifications enable row level security;
revoke all on public.notifications from anon, authenticated;
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;
create policy notifications_read_own on public.notifications for select
  to authenticated using (recipient_id = auth.uid());
create policy notifications_update_own on public.notifications for update
  to authenticated using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

create or replace function public.notify_leave_application()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  applicant public.profiles%rowtype;
begin
  select * into applicant from public.profiles where id = new.employee_id;
  insert into public.notifications (recipient_id, leave_request_id, title, body)
  select p.id, new.id::text, 'New leave application',
    coalesce(nullif(trim(applicant.full_name), ''), 'An employee') ||
    ' applied for ' || new.leave_type || ' leave from ' ||
    new.start_date::text || ' to ' || new.end_date::text || '.'
  from public.profiles p
  where p.approval_status = 'approved'
    and (lower(p.role) = 'hr' or p.id = applicant.manager_id)
  on conflict (recipient_id, leave_request_id) do nothing;
  return new;
end;
$$;
revoke all on function public.notify_leave_application() from public;
create trigger leave_application_notification
  after insert on public.leave_requests
  for each row execute function public.notify_leave_application();

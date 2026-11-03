-- Stability phase: approved-account boundary and a maximum of 50 approved seats.
-- Requires 004–007. Pending/rejected profiles remain preserved for HR review/history.
begin;
do $$
begin
  if (select count(*) from public.profiles where approval_status = 'approved') > 50 then
    raise exception 'More than 50 approved accounts exist; review capacity before installing this release';
  end if;
end;
$$;

create or replace function public.guard_approved_employee_capacity()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.approval_status <> 'approved' then return new; end if;
  if tg_op = 'UPDATE' then
    if old.approval_status = 'approved' then return new; end if;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(727300852574);
  if (select count(*) from public.profiles where approval_status = 'approved' and id <> new.id) >= 50 then
    raise exception 'All 50 approved employee seats are in use. Offboard an account before approving another.' using errcode = '23514';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_approved_employee_capacity() from public, anon, authenticated;
create trigger enforce_approved_employee_capacity before insert or update of approval_status
  on public.profiles for each row execute function public.guard_approved_employee_capacity();

-- Restrictive policies combine with, and do not replace, existing row ownership,
-- participant and HR policies. Pending users retain own-profile SELECT for login.
do $$
declare target text;
begin
  foreach target in array array[
    'attendance_adjustment_requests', 'attendance_breaks', 'attendance_correction_requests',
    'attendance_records', 'company_attendance_settings', 'company_wall_comments',
    'company_wall_posts', 'company_wall_reactions', 'conversation_participants',
    'conversations', 'holidays', 'leave_balances', 'leave_requests', 'leave_request_history',
    'messages', 'notifications', 'push_tokens', 'task_comments', 'tasks'
  ] loop
    if to_regclass('public.' || target) is not null then
      execute format('create policy require_approved_session on public.%I as restrictive for all to authenticated using (public.has_approved_account()) with check (public.has_approved_account())', target);
    end if;
  end loop;
end;
$$;
commit;

begin;
alter table public.profiles
  add column removed_at timestamptz,
  add column removed_by uuid references public.profiles(id),
  add constraint removed_account_cannot_be_approved
    check (removed_at is null or approval_status = 'rejected');

create or replace function public.guard_account_removal_fields()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.removed_at is distinct from old.removed_at or new.removed_by is distinct from old.removed_by then
    if not exists (select 1 from public.profiles where id = auth.uid()
      and role = 'hr' and approval_status = 'approved') then
      raise exception 'Only approved HR can remove accounts' using errcode = '42501';
    end if;
    if new.id = auth.uid() then raise exception 'You cannot remove your own account'; end if;
  end if;
  return new;
end;
$$;
create trigger protect_account_removal_fields before update on public.profiles
  for each row execute function public.guard_account_removal_fields();

create or replace function public.remove_employee_account(p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(727300852573);
  if not exists (select 1 from public.profiles where id = auth.uid()
    and role = 'hr' and approval_status = 'approved') then
    raise exception 'Only approved HR can remove users' using errcode = '42501';
  end if;
  if p_user_id is null or p_user_id = auth.uid() then
    raise exception 'You cannot remove your own account';
  end if;
  perform 1 from public.profiles where id = p_user_id for update;
  if not found then raise exception 'User not found'; end if;
  if exists (select 1 from public.profiles where manager_id = p_user_id and approval_status = 'approved') then
    raise exception 'Reassign this user''s direct reports to another manager before removing them';
  end if;
  update public.profiles set approval_status = 'rejected', removed_at = coalesce(removed_at, now()),
    removed_by = coalesce(removed_by, auth.uid()) where id = p_user_id;
end;
$$;
revoke all on function public.guard_account_removal_fields() from public, anon, authenticated;
revoke all on function public.remove_employee_account(uuid) from public, anon;
grant execute on function public.remove_employee_account(uuid) to authenticated;
commit;

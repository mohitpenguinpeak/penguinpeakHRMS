-- Let HR and administrators edit employee profile fields through the app.
-- The SECURITY DEFINER helper avoids recursive profiles RLS checks.
create or replace function public.can_manage_employee_profiles()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.role, '')) in ('admin', 'super_admin', 'hr')
  );
$$;

grant execute on function public.can_manage_employee_profiles() to authenticated;
grant update (
  full_name,
  department,
  designation,
  phone,
  joining_date,
  manager_id,
  profile_details
) on public.profiles to authenticated;

drop policy if exists "profiles_update_by_owner_or_hr" on public.profiles;
create policy "profiles_update_by_owner_or_hr"
on public.profiles
for update
to authenticated
using (auth.uid() = id or public.can_manage_employee_profiles())
with check (auth.uid() = id or public.can_manage_employee_profiles());

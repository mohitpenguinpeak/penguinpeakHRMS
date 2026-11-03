-- Based on exported production metadata dated 2026-11-03. Validate in staging.
-- No data is deleted. Coordinate deployment with the new chat client.
begin;

-- TRUNCATE bypasses RLS and has no place in browser/mobile database roles.
revoke truncate on all tables in schema public from public, anon, authenticated;

create or replace function public.has_approved_account()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles
    where id = auth.uid() and approval_status = 'approved'
      and role in ('employee', 'management', 'hr', 'admin', 'super_admin'));
$$;
revoke all on function public.has_approved_account() from public, anon;
grant execute on function public.has_approved_account() to authenticated;

create or replace function public.can_manage_employee_profiles()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles
    where id = auth.uid() and approval_status = 'approved'
      and role in ('hr', 'admin', 'super_admin'));
$$;
revoke all on function public.can_manage_employee_profiles() from public, anon;
grant execute on function public.can_manage_employee_profiles() to authenticated;

-- Retain owner editing of personal data, but prevent self-approval, elevation and
-- redirection of the reporting chain even through the existing permissive policy.
create or replace function public.guard_profile_employment_update()
returns trigger language plpgsql security definer set search_path = '' as $$
declare k text;
begin
  if auth.uid() is null then
    if current_setting('role', true) in ('anon', 'authenticated') then
      raise exception 'Authenticated account required' using errcode = '42501';
    end if;
    return new; -- trusted database maintenance/service role, not a client request
  end if;
  if new.manager_id is distinct from old.manager_id and new.manager_id is not null then
    -- Serialize reporting-chain changes, including direct HR updates that bypass
    -- the existing update_employee_details RPC's cycle check.
    perform pg_catalog.pg_advisory_xact_lock(727300852573);
    if new.manager_id = old.id or not exists (select 1 from public.profiles
      where id = new.manager_id and approval_status = 'approved') then
      raise exception 'Choose a different approved reporting manager' using errcode = '22023';
    end if;
    if exists (
      with recursive chain(id, manager_id) as (
        select id, manager_id from public.profiles where id = new.manager_id
        union
        select p.id, p.manager_id from public.profiles p join chain c on p.id = c.manager_id
      ) select 1 from chain where id = old.id
    ) then
      raise exception 'Reporting manager assignment would create a cycle' using errcode = '22023';
    end if;
  end if;
  if public.can_manage_employee_profiles() then return new; end if;
  if auth.uid() <> old.id or old.approval_status <> 'approved' then
    raise exception 'Approved profile owner required' using errcode = '42501';
  end if;
  if new.id is distinct from old.id or new.role is distinct from old.role
     or new.approval_status is distinct from old.approval_status
     or new.manager_id is distinct from old.manager_id
     or new.department is distinct from old.department
     or new.designation is distinct from old.designation
     or new.joining_date is distinct from old.joining_date
     or new.created_at is distinct from old.created_at then
    raise exception 'Employment and approval fields require HR administration'
      using errcode = '42501';
  end if;
  foreach k in array array['work_shift', 'employment_type', 'probation_period'] loop
    if nullif(btrim(new.profile_details ->> k), '') is distinct from
       nullif(btrim(old.profile_details ->> k), '') then
      raise exception 'Employment details require HR administration' using errcode = '42501';
    end if;
  end loop;
  return new;
end;
$$;
revoke all on function public.guard_profile_employment_update() from public, anon, authenticated;
create trigger protect_profile_employment_fields before update on public.profiles
for each row execute function public.guard_profile_employment_update();

-- A policy name is not enforcement: replace the exported ALL/true holiday policy.
drop policy "Admins and HR can manage holidays" on public.holidays;
drop policy "Authenticated users can view holidays" on public.holidays;
create policy holidays_read_approved on public.holidays for select to authenticated
  using (public.has_approved_account());
create policy holidays_insert_hr on public.holidays for insert to authenticated
  with check (public.can_manage_employee_profiles());
create policy holidays_update_hr on public.holidays for update to authenticated
  using (public.can_manage_employee_profiles())
  with check (public.can_manage_employee_profiles());
create policy holidays_delete_hr on public.holidays for delete to authenticated
  using (public.can_manage_employee_profiles());

-- Membership helper bypasses participant-table RLS to avoid recursive policies.
create or replace function public.is_conversation_member(p_conversation_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.has_approved_account() and exists (
    select 1 from public.conversation_participants
    where conversation_id = p_conversation_id and user_id = auth.uid());
$$;
revoke all on function public.is_conversation_member(uuid) from public, anon;
grant execute on function public.is_conversation_member(uuid) to authenticated;

drop policy "Users can insert participants" on public.conversation_participants;
drop policy "Users can select participants" on public.conversation_participants;
drop policy "Users can insert conversations" on public.conversations;
drop policy "Users can select conversations" on public.conversations;
drop policy "Participants can insert messages" on public.messages;
drop policy "Participants can view messages" on public.messages;

revoke all on public.conversations, public.conversation_participants from anon;
revoke insert, update, delete, references, trigger
  on public.conversations, public.conversation_participants from authenticated;
grant select on public.conversations, public.conversation_participants to authenticated;
create policy conversations_read_members on public.conversations for select to authenticated
  using (public.is_conversation_member(id));
create policy participants_read_members on public.conversation_participants for select to authenticated
  using (public.is_conversation_member(conversation_id));
create policy messages_read_members on public.messages for select to authenticated
  using (public.is_conversation_member(conversation_id));
create policy messages_insert_members on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and public.is_conversation_member(conversation_id));

create or replace function public.create_direct_conversation(p_peer_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare caller uuid := auth.uid(); existing_id uuid;
begin
  if not public.has_approved_account() or p_peer_id is null or p_peer_id = caller
     or not exists (select 1 from public.profiles
       where id = p_peer_id and approval_status = 'approved') then
    raise exception 'Two distinct approved accounts required' using errcode = '42501';
  end if;
  -- Serialize the same pair so double clicks/concurrent clients reuse one chat.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    least(caller::text, p_peer_id::text) || ':' || greatest(caller::text, p_peer_id::text), 0));
  select c.id into existing_id from public.conversations c
    where not c.is_group
      and (select count(*) from public.conversation_participants p where p.conversation_id = c.id) = 2
      and exists (select 1 from public.conversation_participants p where p.conversation_id = c.id and p.user_id = caller)
      and exists (select 1 from public.conversation_participants p where p.conversation_id = c.id and p.user_id = p_peer_id)
    order by c.created_at, c.id limit 1;
  if existing_id is not null then return existing_id; end if;
  insert into public.conversations(is_group) values (false) returning id into existing_id;
  insert into public.conversation_participants(conversation_id, user_id)
    values (existing_id, caller), (existing_id, p_peer_id);
  return existing_id;
end;
$$;
revoke all on function public.create_direct_conversation(uuid) from public, anon;
grant execute on function public.create_direct_conversation(uuid) to authenticated;

-- Export shows zero published tables. Publish only messages, behind membership RLS.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages') then
      alter publication supabase_realtime add table public.messages;
    end if;
  else
    raise exception 'Expected supabase_realtime publication is missing';
  end if;
end;
$$;
commit;

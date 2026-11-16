begin;
-- Configure ownership cascades and preserve shared records by clearing attribution.
-- Inspect exact catalog constraints so this also handles legacy constraint names.
do $$
declare fk record; col text; nullable_ref boolean; definition text; deletion_clause text;
begin
  for fk in
    select c.*, n.nspname, t.relname, a.attname
    from pg_constraint c join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    join pg_attribute a on a.attrelid=t.oid and a.attnum=c.conkey[1]
    where c.contype='f' and n.nspname='public' and cardinality(c.conkey)=1
      and (c.confrelid='public.profiles'::regclass
        or (t.relname='profiles' and c.confrelid='auth.users'::regclass)
        or (t.relname in ('attendance_breaks','attendance_correction_requests','task_comments','task_work_logs',
            'company_wall_comments','company_wall_reactions','hr_record_history','hr_acknowledgements','hr_attachments','leave_request_history')
          and a.attname in ('attendance_id','task_id','post_id','record_id','request_id')))
  loop
    col := fk.attname;
    nullable_ref := fk.confrelid='public.profiles'::regclass and col in
      ('manager_id','reviewer_id','actor_id','created_by','created_by_id','creator_id','cancelled_by','removed_by','updated_by');
    definition := pg_get_constraintdef(fk.oid);
    deletion_clause := case when nullable_ref then ' ON DELETE SET NULL' else ' ON DELETE CASCADE' end;
    if definition ~ ' ON DELETE ' then
      definition := regexp_replace(definition, ' ON DELETE (NO ACTION|RESTRICT|CASCADE|SET NULL|SET DEFAULT)', deletion_clause);
    elsif definition ~ ' (NOT DEFERRABLE|DEFERRABLE|NOT VALID)' then
      definition := regexp_replace(definition, ' (NOT DEFERRABLE|DEFERRABLE|NOT VALID)', deletion_clause || ' \1');
    else
      definition := definition || deletion_clause;
    end if;
    if nullable_ref then
      execute format('alter table %I.%I alter column %I drop not null', fk.nspname,fk.relname,col);
    end if;
    execute format('alter table %I.%I drop constraint %I',fk.nspname,fk.relname,fk.conname);
    execute format('alter table %I.%I add constraint %I %s', fk.nspname,fk.relname,fk.conname,definition);
  end loop;
end;
$$;

-- Internal only: storage service deletes the actual files returned here.
create or replace function public.user_owned_storage_objects(p_user_id uuid)
returns table(bucket_id text, name text) language sql security definer set search_path='' as $$
  select o.bucket_id, o.name from storage.objects o
  where o.owner_id = p_user_id::text or o.owner = p_user_id
  order by o.bucket_id,o.name limit 100;
$$;
revoke all on function public.user_owned_storage_objects(uuid) from public, anon, authenticated;
grant execute on function public.user_owned_storage_objects(uuid) to service_role;

-- Stop the old RPC from silently performing soft removal.
create or replace function public.remove_employee_account(p_user_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  raise exception 'Update the app and use permanent user deletion';
end;
$$;

-- FK cleanup of shared attribution runs through the trusted Auth backend.
create or replace function public.guard_account_removal_fields()
returns trigger language plpgsql set search_path='' as $$
begin
  if auth.uid() is null and current_setting('role',true) not in ('anon','authenticated') then return new; end if;
  if new.removed_at is distinct from old.removed_at or new.removed_by is distinct from old.removed_by then
    if not exists (select 1 from public.profiles where id=auth.uid() and role='hr' and approval_status='approved') then
      raise exception 'Only approved HR can remove accounts' using errcode='42501';
    end if;
    if new.id=auth.uid() then raise exception 'You cannot remove your own account'; end if;
  end if;
  return new;
end;
$$;
create or replace function public.guard_task_edit_permissions()
returns trigger language plpgsql set search_path = '' as $$
begin
  -- Preserve trusted backend maintenance; enforce permissions for app users.
  if auth.role() = 'service_role' or (auth.uid() is null and current_setting('role',true) not in ('anon','authenticated')) then return new; end if;
  if auth.uid() = old.creator_id then
    if new.creator_id is distinct from old.creator_id then
      raise exception 'Task creator cannot be changed.' using errcode = '42501';
    end if;
    return new;
  end if;
  if auth.uid() = old.assignee_id then
    -- Completion/update timestamps are maintained alongside status changes.
    if (to_jsonb(new) - array['status', 'priority', 'completed_at', 'updated_at'])
       is distinct from
       (to_jsonb(old) - array['status', 'priority', 'completed_at', 'updated_at']) then
      raise exception 'Assignees can change only task status and priority.' using errcode = '42501';
    end if;
    return new;
  end if;
  raise exception 'Only the task creator or assignee can edit this task.' using errcode = '42501';
end;
$$;

notify pgrst, 'reload schema';
commit;

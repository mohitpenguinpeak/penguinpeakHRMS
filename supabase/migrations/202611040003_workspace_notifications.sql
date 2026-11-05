-- Requires the leave notification migrations and both HR module migrations.
-- No historical backfill: only new workflow events produce alerts.
begin;
alter table public.notifications alter column leave_request_id drop not null;
alter table public.notifications add column target_id text;

-- Private helper: clients cannot manufacture notifications for other users.
create function public.emit_workspace_notification(
  p_recipient uuid, p_key text, p_type text, p_destination text, p_target text,
  p_title text, p_body text, p_priority text default 'normal'
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_recipient is null or p_recipient=auth.uid() then return; end if;
  insert into public.notifications(recipient_id,leave_request_id,title,body,event_type,event_key,category,priority,destination,target_id)
  select p.id,null,p_title,p_body,p_type,p_key,split_part(p_type,'.',1),p_priority,p_destination,p_target
  from public.profiles p where p.id=p_recipient and p.approval_status='approved'
    and p.role in ('employee','management','hr','admin','super_admin')
  on conflict(recipient_id,event_key) do nothing;
end;
$$;

create function public.notify_hr_workflow_event() returns trigger
language plpgsql security definer set search_path = '' as $$
declare r public.hr_records; recipient uuid; key text;
begin
  select * into r from public.hr_records where id=new.record_id;
  if not found or r.module not in ('onboarding','payslip','ticket','document') then return new; end if;
  key := 'hr:' || r.id || ':history:' || new.id;
  if r.module='onboarding' and new.action='created' then
    perform public.emit_workspace_notification(r.employee_id,key,'onboarding.assigned','onboarding',r.id::text,'Your onboarding is ready','Open your joining checklist and required documents.');
  elsif r.module='onboarding' and new.action='completed' then
    for recipient in select id from public.profiles where role in ('hr','admin','super_admin') and id<>r.employee_id loop
      perform public.emit_workspace_notification(recipient,key,'onboarding.completed','onboarding',r.id::text,'Onboarding completed','An employee completed their joining checklist.');
    end loop;
  elsif r.module='payslip' and new.action='published' then
    perform public.emit_workspace_notification(r.employee_id,key,'payslip.published','payslip',r.id::text,'Your payslip is available','Sign in to securely view your salary details and payslip.');
  elsif r.module='document' and new.action='published' then
    for recipient in select id from public.profiles where r.company_wide or id=r.employee_id loop
      perform public.emit_workspace_notification(recipient,key,'document.published','document',r.id::text,'New document to acknowledge','Open Document Centre to read and acknowledge a new document.');
    end loop;
  elsif r.module='ticket' and (new.action='created' or new.action='open') then
    for recipient in select id from public.profiles where role in ('hr','admin','super_admin') and id<>r.employee_id loop
      perform public.emit_workspace_notification(recipient,key,case when new.action='open' then 'ticket.reopened' else 'ticket.created' end,'ticket',r.id::text,
        case when new.action='open' then 'HR ticket reopened' else 'New HR helpdesk ticket' end,'A helpdesk ticket needs your attention.',case when lower(r.data->>'priority')='high' then 'high' else 'normal' end);
    end loop;
    if new.action='created' then
      perform public.emit_workspace_notification(r.employee_id,key,'ticket.created_for_you','ticket',r.id::text,'HR helpdesk ticket created','A helpdesk ticket has been created for you.');
    end if;
  elsif r.module='ticket' and new.action in ('in_progress','resolved') then
    perform public.emit_workspace_notification(r.employee_id,key,'ticket.' || new.action,'ticket',r.id::text,
      case when new.action='resolved' then 'Your HR ticket is resolved' else 'Your HR ticket is in progress' end,'Open HR Helpdesk to view the update and any resolution notes.');
  end if;
  return new;
end;
$$;
create trigger hr_workflow_notifications after insert on public.hr_record_history for each row execute function public.notify_hr_workflow_event();

create function public.notify_private_document_ack() returns trigger
language plpgsql security definer set search_path = '' as $$
declare r public.hr_records;
begin
  select * into r from public.hr_records where id=new.record_id;
  -- Company policy acknowledgements remain in the roster, avoiding an HR alert storm.
  if r.module='document' and not r.company_wide and r.status='published' and exists(select 1 from public.profiles where id=r.created_by and role in ('hr','admin','super_admin')) then
    perform public.emit_workspace_notification(r.created_by,'document:' || r.id || ':ack:' || new.employee_id,'document.acknowledged','document',r.id::text,'Document acknowledged','An employee acknowledged the document you published.');
  end if;
  return new;
end;
$$;
create trigger hr_document_ack_notification after insert on public.hr_acknowledgements for each row execute function public.notify_private_document_ack();

create function public.notify_task_workflow() returns trigger
language plpgsql security definer set search_path = '' as $$
declare key text := 'task:' || new.id || ':tx:' || pg_catalog.txid_current(); recipient uuid; assigned boolean;
begin
  assigned := tg_op='INSERT';
  if tg_op='UPDATE' then assigned := new.assignee_id is distinct from old.assignee_id; end if;
  if assigned then
    perform public.emit_workspace_notification(new.assignee_id,key || ':assigned','task.assigned','tasks',new.id::text,'Task assigned to you','Open Tasks to review your assignment or booking request.',case when new.status='pending_acceptance' then 'high' else 'normal' end);
  end if;
  if tg_op='UPDATE' then
    if new.status is distinct from old.status and new.status in ('in_progress','declined','blocked','completed') then
      for recipient in select distinct id from (values(new.creator_id),(new.assignee_id)) people(id) loop
        if assigned and recipient=new.assignee_id then continue; end if;
        perform public.emit_workspace_notification(recipient,key || ':status:' || new.status,'task.' || new.status,'tasks',new.id::text,
          case new.status when 'completed' then 'Task completed' when 'declined' then 'Task booking declined' when 'blocked' then 'Task is blocked' else 'Task is in progress' end,'Open Tasks to view the latest update.');
      end loop;
    end if;
  end if;
  return new;
end;
$$;
create trigger task_workflow_notifications after insert or update of assignee_id,status on public.tasks for each row execute function public.notify_task_workflow();

create function public.notify_chat_message() returns trigger
language plpgsql security definer set search_path = '' as $$
declare recipient uuid;
begin
  for recipient in select user_id from public.conversation_participants where conversation_id=new.conversation_id and user_id<>new.sender_id loop
    perform public.emit_workspace_notification(recipient,'chat:message:' || new.id,'chat.message','chat',new.conversation_id::text,'New chat message','Open HRMS to read your message.',case when left(new.message,10) like '%[URGENT]%' then 'high' else 'normal' end);
  end loop;
  return new;
end;
$$;
create trigger chat_message_notifications after insert on public.messages for each row execute function public.notify_chat_message();

create function public.notify_attendance_request() returns trigger
language plpgsql security definer set search_path = '' as $$
declare recipient uuid; key text := tg_table_name || ':' || new.id;
begin
  if tg_op='INSERT' then
    for recipient in select id from public.profiles where (role in ('hr','admin','super_admin') or id=(select manager_id from public.profiles where id=new.employee_id)) and id<>new.employee_id loop
      perform public.emit_workspace_notification(recipient,key || ':submitted','attendance.submitted','attendance_adjustments',new.id::text,'Attendance request needs review','An employee submitted an attendance adjustment or correction.');
    end loop;
  elsif new.status is distinct from old.status and new.status in ('approved','rejected') then
    perform public.emit_workspace_notification(new.employee_id,key || ':tx:' || pg_catalog.txid_current() || ':' || new.status,'attendance.' || new.status,'attendance_adjustments',new.id::text,
      'Attendance request ' || new.status,'Open Attendance Adjustments to view the decision.');
  end if;
  return new;
end;
$$;
create trigger attendance_adjustment_notifications after insert or update of status on public.attendance_adjustment_requests for each row execute function public.notify_attendance_request();
create trigger attendance_correction_notifications after insert or update of status on public.attendance_correction_requests for each row execute function public.notify_attendance_request();

create function public.notify_company_announcement() returns trigger
language plpgsql security definer set search_path = '' as $$
declare recipient uuid;
begin
  if new.post_type<>'announcement' or not exists(select 1 from public.profiles where id=new.author_id and approval_status='approved' and role in ('hr','admin','super_admin','management')) then return new; end if;
  for recipient in select id from public.profiles where id<>new.author_id loop
    perform public.emit_workspace_notification(recipient,'wall:' || new.id || ':announcement','company.announcement','company_wall',new.id::text,'New company announcement','Open Company Wall to read the announcement.');
  end loop;
  return new;
end;
$$;
create trigger company_announcement_notifications after insert on public.company_wall_posts for each row execute function public.notify_company_announcement();

revoke all on function public.emit_workspace_notification(uuid,text,text,text,text,text,text,text),public.notify_hr_workflow_event(),public.notify_private_document_ack(),public.notify_task_workflow(),public.notify_chat_message(),public.notify_attendance_request(),public.notify_company_announcement() from public,anon,authenticated;
commit;

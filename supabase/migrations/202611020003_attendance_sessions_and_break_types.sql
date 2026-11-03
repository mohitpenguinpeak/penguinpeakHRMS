-- Preserve multiple work periods in one daily attendance row and classify breaks.
alter table public.attendance_records
  add column if not exists work_sessions jsonb not null default '[]'::jsonb;

alter table public.attendance_breaks
  add column if not exists break_type text not null default 'Rest',
  add column if not exists session_index integer not null default 0;

grant update (
  check_in,
  check_out,
  status,
  late_minutes,
  work_duration_minutes,
  break_duration_minutes,
  updated_at,
  work_sessions
) on public.attendance_records to authenticated;

grant insert (
  attendance_id,
  break_start,
  break_end,
  duration_minutes,
  break_type,
  session_index
) on public.attendance_breaks to authenticated;

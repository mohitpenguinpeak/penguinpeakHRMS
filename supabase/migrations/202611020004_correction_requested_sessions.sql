-- Store every requested punch pair while keeping legacy first/last time columns.
alter table public.attendance_correction_requests
  add column if not exists requested_sessions jsonb not null default '[]'::jsonb;

grant update (work_sessions, check_in, check_out, work_duration_minutes, status, updated_at)
  on public.attendance_records to authenticated;
grant insert (requested_sessions) on public.attendance_correction_requests to authenticated;

-- READ ONLY: export this single JSON result to inspect existing business RPCs.
-- Explicit allowlist; does not export pg_net/webhook functions or trigger arguments.
select coalesce(jsonb_agg(jsonb_build_object(
  'name', p.proname,
  'arguments', pg_get_function_identity_arguments(p.oid),
  'definition', pg_get_functiondef(p.oid)
) order by p.proname), '[]'::jsonb) as business_functions
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in (
  'apply_for_leave', 'review_leave_by_manager', 'review_leave_by_hr',
  'set_employee_leave_balance', 'assign_employee_role', 'review_employee',
  'update_employee_details', 'is_approved_user', 'is_hr_admin',
  'can_manage_employee_profiles', 'handle_new_user', 'register_push_token',
  'notify_leave_application'
);

# Backend metadata inventory — supplied export, 3 November 2026

Source: user-supplied SQL audit captured at 2026-11-03T10:42:22.150815+00:00. No employee rows or token values were included. This is a point-in-time snapshot, not a fresh production verification after migrations.

| Table | Columns | RLS |
| --- | --- | --- |
| attendance_adjustment_requests | `id`, `employee_id`, `request_date`, `adjustment_type`, `duration_minutes`, `reason`, `status`, `reviewer_id`, `review_comment`, `created_at`, `updated_at` | enabled |
| attendance_breaks | `id`, `attendance_id`, `break_start`, `break_end`, `duration_minutes`, `created_at`, `break_type`, `session_index` | enabled |
| attendance_correction_requests | `id`, `employee_id`, `attendance_id`, `request_date`, `requested_check_in`, `requested_check_out`, `reason`, `status`, `reviewer_id`, `review_comment`, `created_at`, `updated_at`, `requested_sessions` | enabled |
| attendance_records | `id`, `employee_id`, `attendance_date`, `check_in`, `check_out`, `status`, `late_minutes`, `work_duration_minutes`, `break_duration_minutes`, `created_at`, `updated_at`, `work_sessions` | enabled |
| company_attendance_settings | `id`, `work_start_time`, `work_end_time`, `grace_period_minutes`, `half_day_hours`, `breaks_enabled`, `timezone`, `updated_at` | enabled |
| company_wall_comments | `id`, `post_id`, `author_id`, `comment`, `created_at` | enabled |
| company_wall_posts | `id`, `author_id`, `post_type`, `title`, `content`, `is_pinned`, `created_at`, `updated_at` | enabled |
| company_wall_reactions | `id`, `post_id`, `user_id`, `reaction_type`, `created_at` | enabled |
| conversation_participants | `conversation_id`, `user_id`, `joined_at` | enabled |
| conversations | `id`, `title`, `is_group`, `created_at` | enabled |
| holidays | `id`, `name`, `holiday_date`, `type`, `created_at` | enabled |
| leave_balances | `id`, `employee_id`, `leave_type`, `allocated_days`, `used_days`, `updated_at` | enabled |
| leave_requests | `id`, `employee_id`, `manager_id`, `leave_type`, `start_date`, `end_date`, `days`, `reason`, `manager_status`, `manager_comment`, `hr_status`, `hr_comment`, `created_at`, `reviewed_by_manager_at`, `reviewed_by_hr_at` | enabled |
| messages | `id`, `conversation_id`, `sender_id`, `message`, `created_at` | enabled |
| notifications | `id`, `recipient_id`, `leave_request_id`, `title`, `body`, `created_at`, `read_at`, `dismissed_at` | enabled |
| profiles | `id`, `full_name`, `approval_status`, `created_at`, `role`, `department`, `designation`, `phone`, `joining_date`, `manager_id`, `profile_details`, `avatar_url` | enabled |
| push_tokens | `token`, `user_id`, `updated_at` | enabled |
| task_comments | `id`, `task_id`, `author_id`, `comment`, `created_at` | enabled |
| tasks | `id`, `title`, `description`, `creator_id`, `assignee_id`, `priority`, `status`, `due_date`, `project`, `completed_at`, `created_at`, `updated_at` | enabled |

## Function signatures (bodies not exported)

| Function | Arguments | SECURITY DEFINER | Anonymous EXECUTE |
| --- | --- | --- | --- |
| apply_for_leave | p_leave_type text, p_start_date date, p_end_date date, p_days numeric, p_reason text | True | False |
| assign_employee_role | p_user_id uuid, p_role text | True | False |
| can_manage_employee_profiles | none | True | True |
| handle_new_user | none | True | True |
| is_approved_user | none | True | False |
| is_hr_admin | none | True | True |
| notify_leave_application | none | True | True |
| register_push_token | p_token text | True | True |
| review_employee | p_user_id uuid, p_approval_status text | True | False |
| review_leave_by_hr | p_request_id uuid, p_decision text, p_comment text | True | False |
| review_leave_by_manager | p_request_id uuid, p_decision text, p_comment text | True | False |
| set_employee_leave_balance | p_employee_id uuid, p_leave_type text, p_allocated_days numeric | True | False |
| update_employee_details | p_user_id uuid, p_department text, p_designation text, p_phone text, p_joining_date date, p_manager_id uuid | True | False |

## Other metadata

- 63 constraints, 28 indexes, 43 public/storage policies.
- Realtime publication membership: no tables in the supplied export.
- Public triggers: leave application notification; notification INSERT webhook.
- Storage: one public profile-photos bucket, 5 MB image limit; owner-folder INSERT/UPDATE policies. No private employee document/chat attachment bucket found.
- All public tables have RLS enabled; this alone does not validate policy scopes.
- `notifications.dismissed_at` exists: clear-inbox migration is reflected in this snapshot.
- Full function bodies and auth-schema triggers were not collected; inspect the separate allowlisted function export.

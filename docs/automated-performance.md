# Automated performance scorecards

Open **Performance** in the workspace menu or the **Performance** tab of an
employee profile. Daily, weekly, monthly, quarterly and annual scorecards share
one server-side v1 KPI matrix. The employee selector contains only employees
within the signed-in account's permitted scope.

## Activation

Apply `supabase/migrations/202611160001_automated_performance.sql` through the
existing Supabase migration workflow or SQL editor after all earlier migrations,
including approved/cancelled leave ranges and half-day leave support (migration
`202611130009_half_day_leave.sql`). Deploy the updated Flutter app afterward.
The migration is prepared locally; it has not been applied to a live project.
It adds one read-only RPC and two query indexes; it adds no score storage,
notifications, scheduled jobs or external services. The previously retired
manual HR performance-record workflow remains retired.

Run an approved employee, their reporting manager, and HR account through the
five period selectors after deployment. Confirm the company's attendance
`timezone` and the Monday–Friday workweek assumption before relying on scores.
An unset or invalid timezone falls back to UTC. Future anchor dates are rejected.

## Shared KPI matrix

| KPI | Weight | Calculation |
| --- | --- | --- |
| Task completion | 50% | Completed eligible tasks / all eligible tasks |
| On-time delivery | 20% | Eligible dated tasks completed by their due date / eligible dated tasks with known completion evidence or still unfinished |
| Attendance | 20% | Attended day equivalents / expected day equivalents |
| Punctuality | 10% | Attended full working days without a late flag or late minutes / attended full working days |

A metric with a zero denominator is **No data**, not 0% or 100%. Its weight is
removed and the remaining weights are normalized. Coverage reports the sum of
available original weights. A closed scheduled day with no attendance is an
absence (0% attendance), not missing evidence. A period with no eligible tasks
and no expected attendance has no score or rating.

Scores round to one decimal. Ratings are Excellent (90+), On track (75+),
Developing (60+) and Needs attention (below 60). Ratings describe these operational
metrics only; work quality, complexity, collaboration and manager feedback are
not measured. Task size and priority do not change the weights.

## Period and evidence rules

- Company timezone determines today's date and completion dates. Due dates use
  the existing calendar date selected on the task. Weeks run Monday–Sunday;
  quarters and years follow the calendar rather than a fiscal year.
- The selected period's end is capped at today for evidence collection. Current
  periods are provisional. Each KPI aggregates source counts across the entire
  period; weekly/monthly/yearly scores are not averages of daily percentages.
- Tasks with deadlines belong to their deadline's period. Undated tasks belong
  to the period of their completion. Future deadlines, declined tasks and tasks
  awaiting acceptance are excluded. An incomplete task due today is included in
  the provisional score. Undated unfinished tasks cannot be assigned to a period.
- A completed task with no completion timestamp can count toward completion in
  its due-date period, but is excluded from on-time delivery, with a visible data
  quality note. A completion recorded after the period's end is not treated as a
  completion within that period.
- Working days are Monday–Friday, excluding company holidays and dates before
  joining. If joining date is missing, account creation date is used. Approved,
  noncancelled leave uses the HR-approved range. Each approved half is excluded
  at most once, even with overlapping legacy requests. Pending/rejected/cancelled
  leave does not reduce expected attendance.
- A half-day attendance status contributes 0.5 day; approved half-day leave reduces
  the expected day to 0.5. Full-day leave contributes no expected day. Duplicate
  attendance rows do not add extra days. Any late flag across duplicate rows
  counts as late. Punctuality excludes days with approved half-day leave because
  the normal shift-start rule may not apply.
- Today contributes attendance only after a check-in exists; no employee is marked
  absent merely because the current day is unfinished. A check-in initially
  contributes a full day unless the record is subsequently classified half-day.

## Automation, history and access

Scorecards recalculate on opening, selecting a period/date, manual refresh and
every minute while mounted. There is no background scheduler to install or run.
Historical selections are recalculated from current source records: approved
attendance corrections, task edits/reassignments and leave changes can change
previous results. They are not immutable review snapshots; deleted tasks cannot
be reconstructed. No scheduled emails, push summaries or annual review records
are created. The previous calendar period's score is shown when both have data;
for an in-progress period this compares a partial period with a complete one.

The RPC uses an empty search path, revoked public/anonymous execution and explicit
approved-account checks. Employees see themselves; management sees themselves
and direct reports; HR/admin/super-admin see approved employees. Requesting an
out-of-scope profile is rejected on the server. Only aggregate KPI facts are
returned, not task descriptions, attendance punches or leave reasons.

## Validation

```bash
flutter test
flutter analyze --no-fatal-infos lib/features/performance lib/role_dashboard_screen.dart
node scripts/test_performance.mjs /absolute/path/to/pglite/dist/index.js
flutter build apk --release --dart-define-from-file=supabase.env.json
```

The SQL runner uses an isolated PostgreSQL engine and fixture data; it never
connects to Supabase. Tests cover access scopes, each calendar period, leap years,
weights and missing evidence, leave/attendance adjustments, duplicates, live
recalculation and timezone fallback. Widget tests cover mobile layout, all period
choices, profile scope, errors/retry, ratings and timer lifecycle. Live deployment
and physical-device acceptance require the migration and an updated app.

Local verification on 16 November 2026: all 112 Flutter tests and 43 isolated
database checks passed. Targeted analysis reported no errors or warnings (22
existing informational findings in the dashboard). Android release compilation
with `supabase.env.json` succeeded and produced
`build/app/outputs/flutter-apk/app-release.apk`. The existing release configuration
still uses the debug signing key. No production migration or physical-device test
was performed.

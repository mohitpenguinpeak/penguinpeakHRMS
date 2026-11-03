# Core HR release: partial leave approval, cancellation and history

Notification troubleshooting remains deferred at the user's request. This unit
changes business workflows, saved events and UI; it does not claim remote push
works or require new Firebase credentials. Other enterprise modules remain on the
saved roadmap. The audit has not been repeated.

## Implemented behavior

- HR retains Full approve/Reject and can now Approve selected dates using a date
  range picker constrained to the original request. A contiguous subset of full
  calendar days is supported, not disjoint ranges or half-days.
- The database locks the request and balance, validates the selected range, and
  deducts only approved days once. Existing 3-argument HR review remains a full
  approval wrapper around the same authoritative implementation.
- Future leave can be cancelled by the applicant or approved HR administration.
  A reason is required. Cancellation and exact approved-quantity refund are one
  transaction; duplicate cancellation and post-cancellation reviews are rejected.
- Cancellation is allowed only before the effective start date. The authoritative
  boundary uses database CURRENT_DATE (Supabase's configured database timezone,
  typically UTC); company timezone policy is not yet implemented. The UI provides
  an optimistic local-date gate; the server always decides. Started/past leave
  needs a later audited historical-correction workflow, not an automatic refund.
- All new application, manager decision, HR decision and cancellation transitions
  append audit history. Clients have SELECT-only access within existing applicant,
  manager and HR scopes; history cannot be edited/deleted through client roles.
- Existing approved requests backfill approved dates and their previously recorded
  quantity. Historic balance totals are not recalculated, and missing past audit
  events are not invented. Legacy inconsistent day quantities require manual HR
  review; the new review RPC does not over-approve beyond recorded request days.
- Cancelled leave is excluded from approval queues, calendar, on-leave-today and
  task availability. Partial leave uses effective approved dates in those views.
  New applications can use dates outside a previously approved subset.
- The dashboard now shows actual Supabase leave_balances values. The former
  hardcoded 18/12/6 allowances and request-count subtraction were removed.
- Existing saved notification events reflect approved dates and cancellation.
  Transport diagnostics, retries and platform background delivery are unchanged.

## Database changes

Migration `202611030007_leave_ranges_cancellation_history.sql` adds:

- leave_requests: approved_start_date, approved_end_date, approved_days,
  cancelled_at, cancelled_by, cancellation_reason; range constraint and active
  employee/date index.
- leave_request_history: request/actor/action/time/details, indexed by request/time;
  RLS plus SELECT only for approved authorized accounts. No destructive cascading
  deletion is added; retention and offboarding deletion need deliberate policy.
- RPCs: review_leave_by_hr_range, cancel_leave_request; existing HR review delegates.
- Updated application/manager RPCs respect cancellation/effective overlap dates.
- Append-only audit trigger and effective-date review notification text.

No existing roles, employee rows, original request dates or balance rows are dropped.
No new Edge Function or environment variable is introduced by this unit.

## Choose exactly one SQL deployment path

Test with a genuinely separate staging backend first. The repository's QA and main
configuration currently point to the SAME backend. Use your normal schema/data
backup and review before applying migrations to production.

**A. Earlier release 004–006 already installed:** apply ONLY migration 007 once.
Do not run either combined bundle. It depends on the previous hardened helpers,
event-key notification schema and secure conversation RPC.

**B. None of 004–007 installed (matches the last supplied database export):** apply
`supabase/deploy/core_hr_release.sql` once. This generated single transaction
combines 004–007 and supersedes the previous phase1 bundle for a fresh rollout.
Do not also apply the individual files. Preflight rejects partial/already installed
releases. Reconcile your normal migration history after manual SQL-editor releases
so a later migration runner does not replay constituent files.

**C. Some earlier files installed but not all:** use your migration history and
apply only the remaining incremental files in timestamp order. Do not guess or run
a bundle; its preflight should refuse this case.

The generated bundle comes from `python3 scripts/build_core_hr_bundle.py`; never
hand-edit it or place it inside the automatic migrations directory. Test fixtures
under supabase/tests are for isolated databases only, never production SQL.

## Client rollout and manual acceptance

Deploy SQL before these updated clients. Older calendar/task clients do not know
about cancellation/partial dates and must update together; old chat creation was
also intentionally denied by the prior security release. Use a coordinated release.
No migration was applied or deployment performed by the assistant.

```bash
flutter pub get
flutter test --no-pub
flutter run -d linux --dart-define-from-file=supabase.env.json
flutter build apk --release --dart-define-from-file=supabase.env.json --dart-define=PUSH_ENABLED=true
```

Use separate employee, reporting manager, HR and unrelated test users:

1. Allocate an actual balance in Leave Management; verify dashboard matches it.
2. Employee requests five future calendar days. Manager approves; no balance debit.
3. HR clicks Approve selected dates and selects three days inside that range.
4. Verify Partially approved, approved range, and balance reduced by exactly three.
5. Check calendar/task availability/on-leave summaries count only those three days.
6. Employee clicks Cancel leave, supplies a reason. Verify balance restores exactly
   three, queues and calendar exclude the request, and History records the action.
7. Repeat cancellation/review via a test session: rejected with no extra refund.
8. Try out-of-range approval, insufficient balance, unrelated user review/history,
   history writes and cancelling started leave: denied without partial DB changes.
9. Verify old full approvals retain their recorded balance/dates; old history shows
   an honest empty state until subsequent events, not fabricated approvals.

## Test evidence

- 59 PostgreSQL security/leave checks pass in the upgrade fixture, which runs the
  prior release, creates/reviews requests, then applies 007 and verifies backfill.
- The same 59 scenarios also run against a fresh combined 004–007 bundle.
- Flutter: 14 tests pass, including partial/cancelled/legacy date models, actual
  fractional dashboard balances, empty states and prior regressions.
- These are isolated fixture and widget checks; real Supabase auth/Realtime, manual
  target acceptance and cross-connection contention testing remain required.

Commands (reuse the already installed temporary PostgreSQL test runtime):

```bash
python3 scripts/build_core_hr_bundle.py
node scripts/test_access_hardening.mjs /tmp/penguinpeak-sql-validation/node_modules/@electric-sql/pglite/dist/index.js
node scripts/test_access_hardening.mjs /tmp/penguinpeak-sql-validation/node_modules/@electric-sql/pglite/dist/index.js --combined
flutter test --no-pub
```

## Source files and remaining work

New feature code: features/leave/domain/leave_request.dart,
features/leave/data/leave_repository.dart,
features/leave/presentation/leave_balance_summary.dart. Updated screens:
leave_management_screen, role_dashboard_screen, task_management_screen and
team_leave_calendar_screen. Tests and migration are checked into this workspace;
no new production dependency was added.

Remaining Core HR work: transactional attendance/corrections and audit, full
employee lifecycle/private data separation, company leave policy/timezone,
working-day/half-day calculations, accrual/carry-forward, disjoint/partial-day
approval, attachments and historical corrections. Phase 2 is not complete and
production readiness is not claimed. Projects/Scrum/timesheets follow the saved
phases after core workflow stabilization. Notification delivery stays deferred.

Final local verification: Linux debug build passed; full analyzer reported no
errors, one existing warning and 113 informational findings (114 total). This is
not a clean-lint or actual Supabase/device acceptance result. git diff --check
passed. Both upgrade and combined SQL fixture paths passed all 59 checks.

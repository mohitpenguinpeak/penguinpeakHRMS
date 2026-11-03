# PenguinPeak implementation record — 3 November 2026

## Organization chart layout correction

Replaced the stacked, connector-less organization display with a full-width forest,
actual reporting connectors, fit/pan/zoom, mobile outline, contextual search and
department filtering. Missing-manager and cyclic components remain visible without
altering profile data. Details and verification: `organization-chart-fix.md`.

## Expansion storage crash correction

Reproduced and fixed the Tasks double-to-bool crash introduced by per-module
scroll restoration: filter, grouped-board and attendance expansion state now has
separate PageStorage identity. The regression includes a real saved scroll offset,
not only isolated layout rendering. See `task-workspace-reference-status.md`.

## Reference task workspace continuation

The supplied OrangeScrum screenshots now map to shared advanced task filters,
sorting, removable chips/reset, grouped Kanban swimlanes and a responsive expanded
task inspector. Existing task editing now preserves creator/absent deadlines,
adds project editing, validates estimates, and records completion timestamps.
See `task-workspace-reference-status.md` for verified scope and the unimplemented
server-backed timer/daily/weekly timesheet requirements. No migration was added.

## Mobile-first layout and task views continuation

Fixed the content-sized leave sections from the supplied screenshot with full-width
responsive grids; added shared adaptive layouts/reduced-motion-aware transitions,
phone-oriented screen fixes, and Calendar/Graphs task views. Six analytics panels
use existing authorized records; there is no fabricated sprint/time history.
See `workspace-design-direction.md` for changed behavior, test evidence and limits.

## Workspace design continuation

User direction: Keka-inspired HR design/functionality plus OrangeScrum-inspired
project/task design/functionality, retaining the existing PenguinPeak palette.
See `workspace-design-direction.md` for the implemented grouped navigation,
page context, shared control styling, responsive task toolbar and connected Kanban
view, along with explicit functional limits. The full enterprise scope remains.

## Latest continuation: session request isolation

The earlier sections retain the original audit and historical findings; subsequent
release guides supersede their descriptions of already prepared fixes. The current
local baseline includes migrations 004–008, staged leave approval/range/cancellation
and history, actual dashboard balances/holidays, and the centralized session gate.
Production installation and live acceptance of those changes remain unverified.
See `stability-phase-release.md` and `core-hr-leave-release.md` before deployment.

This continuation fixes an additional session race: a pending profile request from
before logout or verified login could be reused by a new check for the same user
ID. Invalidation now releases the coalesced request as well as invalidating its
result. New session checks start immediately; the old completion cannot clear a
new request or overwrite its approval decision. Requests within the same current
session still coalesce. Database RLS remains the authorization boundary.

Changed Flutter source: `lib/features/auth/application/session_controller.dart`.
Added two race regressions to `test/session_controller_test.dart`. No database,
RLS, Storage, Edge Function, dependency, environment or deployment change is needed.
Existing uncommitted work is preserved. Full Flutter suite: **31 tests passed**.
Linux debug build with the existing public Supabase defines: **passed**, output
`build/linux/x64/debug/bundle/penguinpeak_hrms`. `git diff --check`: **passed**.
Full analyzer: **113 informational findings**, no errors/warnings; exits 1 due to
the existing infos. Physical platform notification status is unchanged from the
matrix below; no remote push capability was newly verified.

Remaining order: reconcile staged migration installation and test real account/RLS
acceptance, then server-owned attendance/break/correction transactions and immutable
audit before expanding core HR. Attendance still reads the device clock and writes
multi-step changes client-side; it is not yet concurrency-safe or production-ready.
Windows needs a real Windows toolchain; all-platform delivery needs actual devices
and provider configuration. The complete requested enterprise platform remains
unfinished; this is a tested stabilization unit, not completion of a phase.

## Scope and evidence

The product requirements are preserved in `enterprise-product-brief.md`. Continue
this record in later sessions instead of repeating the source audit. Do not treat
a screen, a successful build, or a unit test as verified production functionality.

This audit inspected the Dart sources, seven existing incremental SQL migrations,
notification Edge Function, platform manifests/configuration, dependencies, and
tests. It did NOT connect to the production database or download Storage policies.
The repository lacks the base database migrations and four leave RPC definitions.
All statements about their security or transaction semantics remain unverified.

Phase 1 is **in progress**, not complete. No production migration was applied and
no server deployment was performed during this unit. Existing uncommitted work
and application configuration were preserved.

## Module inventory

| Module | Existing state, based on source | Missing/uncertain | Required action |
| --- | --- | --- | --- |
| Authentication | Supabase email/password, signup metadata name, profile approval gate | Recovery/session resumption, approval revocation, original auth trigger/RLS | Verify server privileges; implement centralized session lifecycle |
| Roles/permissions | employee, management, admin, hr, super_admin; scattered widget checks | No central permission model; role writes/server authorization unverified | Export policy metadata, preserve role names, define permissions |
| Employees | Directory/search, approval controls, basic/profile JSON editing | Private bank/docs separation, photos, employment history, audit, lifecycle | Restrict organization fields server-side before expanding profile data |
| Organization | Profile manager hierarchy and department/designation strings | Dedicated organization configuration, teams, cycle prevention | Reuse existing schema after live inventory |
| Dashboard | Role labels, HR approvals, attendance/leave/wall/holiday summaries | Many shared sections, broad queries, local attendance calculations | Role-specific sections, repository queries, pagination and policy-backed data |
| Attendance | Punches, multiple sessions/breaks, history, summaries/settings, correction forms | Writes/calculations client-side; concurrent sessions and audit atomicity unverified | Server clock/transaction RPCs, configurable policy and concurrency tests |
| Adjustments | Requests and correction review, requested punch pairs | Request status and attendance changes span client operations | Atomic review RPC with authorization and immutable audit |
| Leave | Apply, manager review, HR final review, balances via existing RPC names | RPC source absent; no partial/cancel/accrual/overlap workflow verified | Inspect RPC definitions, then transaction-safe staged approvals |
| Calendar | Team leave calendar | Unified milestones/events/privacy/timezone filters | Extend existing calendar with authorized event data |
| Tasks | CRUD, assignments/status/comments, due-date and leave availability helpers | No project membership model; multi-operation edits, incomplete advanced task workflow | Add projects around existing tasks after schema inspection |
| Projects | No project screen or repository migration found | Owners/members/milestones/budgets/views/activity | Phase 3 membership-secured module; avoid duplicate tasks |
| Scrum/Kanban | Task status UI is not a sprint system | Epics, sprints, capacity, story points, burndown/velocity | Phase 3, after projects and task workflow |
| Timesheets | Attendance duration exists; it is not project time tracking | Timers, entries, approval, overlap rules | Separate domain integrated with tasks/attendance |
| Chat | Direct conversation creation, participants, messages, Realtime, urgent text marker | Group workflow/read receipts/edits/audit; attachments are pasted URLs; OS push absent | Secure membership/RPC/private Storage; event notifications |
| Company Wall | Posts, categories, comments, reactions, pin/order support | Private attachment handling, mentions, polls/visibility workflows, notifications | Review moderation RLS then extend existing module |
| Notifications | Leave INSERT trigger, inbox/read/dismiss, push tokens, FCM webhook, Android foreground presentation, desktop alerts | 401 unresolved, retry/outbox/preferences/deep-link routing for other domains, generic events absent | Resolve auth; add secure event/outbox architecture incrementally |
| Birthday/anniversary automation | No reliable scheduled backend detected | Privacy/timezones/dedup/scheduler/calendar | Scheduled backend event producer, never app-only timers |
| Payroll/finance | No implemented module found | All payroll/compensation/tax jurisdiction rules | Phase 6 with separate restricted data and validated policy |
| Expenses | No implemented module found | Receipt storage, approval/payment/audit | Phase 6 |
| Performance | Profile empty state | Goals/cycles/reviews/confidentiality | Phase 6 |
| Recruitment/onboarding | Signup approval is not recruitment/onboarding | Candidates/interviews/offers/checklists/equipment | Phase 6 |
| Assets/documents | Profile empty states, not an asset/document system | Private uploads, signed URLs, assignment/history/expiry | Phase 6, storage policies first |
| Reports/export | Dashboard summaries only | Authorized reports, CSV/XLSX/PDF | Phase 7; backend permissions apply to exports |
| Global search | Employee/action search | Authorized cross-module search | Phase 7 with indexed scoped queries |
| Preferences/settings | Theme and some attendance configuration | Notification preferences/quiet hours/privacy; organization-wide config | Incremental feature repositories and permission-backed forms |

## Architecture now and target

Current: `main.dart` initializes Supabase, OS notifications and Firebase; splash
opens login; login reads approval/role; dashboard routes screens. Most screens
query Supabase directly and perform business calculations and writes in widget
state. `app_theme.dart` supplies shared light/dark Material themes. No global
repository layer, consistent pagination, or centralized error mapper exists.

Target: `features/<feature>/{domain,data,presentation}` with domain validators,
repositories and typed models introduced per stabilized workflow. Keep existing
screens and routes while extracting a coherent feature at a time. PostgreSQL
RPCs own authorization, timestamps, locking and multi-step business transactions;
RLS protects direct queries. Committed domain events enqueue delivery jobs;
workers send through platform adapters and record attempts/retries. Notification
transport failures must never roll back an already accepted business operation.
Do not add a queue, payroll table, or project table before checking the live schema.

First extracted domain model: `features/auth/domain/account_access.dart`.
Approved status AND a supported existing role are required by login/token client
checks. These checks are UX/defense in depth, not substitutes for RLS.

## Database dependencies and security findings

`data-dependencies.json` maps current Dart table/RPC references. It is an inventory
of usage, not an authoritative database schema. Base tables, policies, grants,
indexes, relationships and Storage must be inspected using
`supabase/audit/metadata_inventory.sql` (read only, no business rows or webhook
secret arguments). Save the resulting internal metadata privately. Inspect leave
RPC source in the SQL editor separately, without exposing credentials embedded
in unrelated functions/triggers.

Priority findings:

1. **Blocking security verification:** no checked-in base schema/RLS or leave RPC
   bodies. Backend role checks and final-balance locking cannot be certified.
2. The profile update migration allows owner updates including manager,
   department, designation and joining date. Confirm approved-account rules,
   column/table grants, and all permissive policies; owners must not be able to
   redirect approvals or modify controlled employment fields. Do not broadly
   revoke production privileges before inventorying dependent workflows.
3. Attendance/adjustments/tasks/chat use multiple client writes without a shared
   transaction. Concurrent approval, timer and partial-write behavior need RPCs.
4. Chat Realtime subscribes to message inserts and shows banners; confidentiality
   depends on live participant RLS/publication settings, which are unverified.
   Conversation creation and adding participants are separate writes.
5. No actual private Storage upload flow found. URL text is not secure file upload.
6. Notifications currently reach all approved HR users at application time as well
   as the manager. The new brief requires HR only at its approval stage. Change
   this in Phase 2 after inspecting actual review RPCs and policy, not by guessing
   column/status transitions. Existing behavior is retained for this unit.
7. `notifications.leave_request_id` is required text with no FK, so it is not a
   generic event/entity schema. Unique recipient/request deduplicates INSERTs,
   not transition events or delivery attempts. No retry/dead-letter worker exists.
8. Device registration previously required only an authenticated UID and valid
   token length. New migration `202611030004_approved_push_registration.sql`
   additionally requires an approved existing-role profile, rejects null tokens,
   and preserves auth.uid()-derived ownership. Apply in staging and test before
   production. Previously registered tokens are preserved; revocation/delivery
   eligibility for subsequently suspended accounts still needs implementation.
9. Shared JSON profile details must not become storage for banking/payroll data
   visible through employee-directory policies. Use separate restricted records.
10. Keep service-account/privileged Supabase credentials server-side. This audit
    did not inspect secret values. A Firebase client config is not a server key.

## Notification implementation and verified capability matrix

Transport chain: leave INSERT → SECURITY DEFINER trigger → recipient-specific
`notifications` row → pg_net database webhook → `send-leave-push` → FCM HTTP v1.
The inbox polls every 20 seconds; it is NOT a Realtime notification subscription.
The sender checks `x-webhook-secret`, reads trusted recipient/content, looks up
registered devices and sends an FCM notification/data payload. Android foreground
messages are turned into local OS alerts; background display relies on FCM.

| Platform | Foreground | Background | App closed | Required configuration / evidence |
| --- | --- | --- | --- | --- |
| Android | Local test alert user-verified; real leave OS delivery NOT verified | NOT verified | NOT verified | Firebase project, Google Play services, permission, token, webhook; last supplied remote logs 401 |
| iOS | Implemented adapter, NOT target-tested | NOT verified | NOT verified | Apple signing, APNs, entitlements and target configuration |
| Linux | User reported receiving notifications; exact popup/bell distinction not independently confirmed; local integration/build present | Minimized-process design, NOT separately verified | Native remote delivery NOT implemented | Desktop notification server/session D-Bus; stopped process cannot poll |
| Windows | Toast adapter present, NOT target-tested | Running/minimized design, NOT verified | Native remote delivery NOT implemented | Windows build/identity, MSIX release validation; background agent needed |
| macOS | Native local and Firebase code present, NOT target-tested | NOT verified | NOT verified | Signing, APNs/entitlements or browser companion; validate on Mac |
| Web | Service-worker/FCM code and web build present, NOT browser delivery-tested | NOT verified | Tab-closed delivery NOT verified; browser policy dependent | HTTPS root hosting, public web config, VAPID, registration, webhook |

Unit tests validate channel calls, not physical-device delivery. No target is
certified for all foreground/background/terminated cases. Browser companion is an
optional alternative, NOT completion of native Windows/Linux closed-app delivery.
Native agents need user-session installation/autostart, secure credential storage,
refresh/revocation, OS notification adapters, IPC/deep links, and signed/packaged
release testing. Do not install services or claim they exist in the current app.

Setup and troubleshooting live in `notification-setup.md`. Server authentication
failures now distinguish missing server secret, missing header, and mismatch,
without logging values. Last user-provided evidence is a 401; resolution has not
been demonstrated. No APK rebuild repairs a webhook secret mismatch.

## Changes in this Phase 1 unit

- Added a reusable account approval/role model and login eligibility validation.
- Push token registration checks the authenticated profile client-side; the new
  incremental RPC migration enforces approved-account eligibility server-side.
- Corrected chat wording/comments that falsely described in-app banners as OS push.
- Added account eligibility tests and read-only backend metadata audit queries.
- Preserved product brief, source dependency inventory and this continuation record.
- No new third-party dependencies; no new production tables, role names or UI demos.

Flutter files: `lib/features/auth/domain/account_access.dart`,
`lib/login_screen.dart`, `lib/push_notification_service.dart`, `lib/chat_screen.dart`.
SQL: `supabase/migrations/202611030004_approved_push_registration.sql`.
No new Edge Function in this unit; existing `send-leave-push` remains the sender.
No broad RLS rewrite; live policies still require review. To roll back the RPC
eligibility change if needed, restore the function definition from migration 002;
this removes approval enforcement and should only be done through a reviewed
rollback. No rows/columns are dropped by migration 004.

## Environments, build and deployment

Existing client variables: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` via existing
Supabase defines files. Mobile/macOS push uses generated `firebase_options.dart`;
Android defaults push on, explicit `PUSH_ENABLED=false` disables it. Apple/web
push requires `PUSH_ENABLED=true`. Web also uses `FIREBASE_API_KEY`,
`FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID`,
`FIREBASE_VAPID_KEY` plus generated worker public configuration. See setup script.

Server only: `FCM_SERVICE_ACCOUNT_JSON`, `PUSH_WEBHOOK_SECRET`, optional
`HRMS_WEB_URL`, and Supabase's runtime database service credentials. Never add
these private values to Dart, assets, browser scripts or source control.

Run from repository root:

```bash
flutter pub get
flutter test --no-pub
python3 -m unittest discover -s scripts -p 'test_*.py'
flutter analyze --no-pub
flutter run -d linux --dart-define-from-file=supabase.env.json
flutter build apk --release --dart-define-from-file=supabase.env.json --dart-define=PUSH_ENABLED=true
```

Deploy only after staging review (do not blindly replay CREATE TABLE migrations
against an existing production database). Run metadata audit, inspect migration
history, then apply the missing incremental migrations in timestamp order. Test
approved and pending accounts and verify cross-user RLS before promotion.
Rebuild clients to include account changes. Existing function deployment command:

```bash
npx supabase functions deploy send-leave-push --remote=fohwesyhwdbpocgqliwg --no-verify-jwt --use-api
```

The webhook secret check must remain active. No deployment was run in this unit.

## Remaining phased roadmap and next safe unit

1. **Finish Phase 1:** capture live schema/policies/RPCs/Storage/migration history;
   check self-approval/role/manager escalation, deny pending access server-side,
   isolate private data, stabilize sign-in/resumption/sign-out and revoked sessions.
   Resolve webhook 401 using diagnostic evidence, then test real Android delivery.
2. **Phase 2:** atomic attendance/correction and staged leave RPCs with locking,
   audit records, partial/cancel logic, final-only balance deduction and transition
   notifications. Restrict employment fields; update UI around verified RPCs.
3. **Phase 3:** project membership/RLS integrated with existing tasks, then workflow,
   dependencies/subtasks, milestones, sprints, timers/timesheets and reports.
4. **Phase 4:** secure atomic conversations/membership, private attachments and chat
   lifecycle; wall mentions/moderation. Do not expose chats to HR by default.
5. **Phase 5:** generic event catalogue, durable outbox/attempts/retries/idempotency,
   preferences/private previews/quiet hours, category centre and deep links;
   scheduled birthday/anniversary producer; native desktop background agents and
   target-by-target delivery evidence. No email delivery without a later decision.
6. **Phase 6:** payroll/expenses/recruitment/onboarding/performance/assets/documents,
   each with restricted permissions, transaction/audit and meaningful workflow tests.
7. **Phase 7:** authorized reports/exports/global search, distinct role dashboards,
   responsive/accessibility checks, pagination and measured query optimization.

Next session should read this record, inspect only new changes, and complete the
live metadata/security review before new schema-dependent workflow migrations.
Do not mark any phase production-ready until UI, backend, policies and target
workflow tests pass.

## Validation for this unit

- `flutter test --no-pub`: 7 tests passed (4 account-access tests plus 3 existing
  tests). The existing basic widget test is a placeholder, not workflow coverage.
- Python web configuration generator tests: 3 passed.
- Full `flutter analyze --no-pub`: 0 errors, 1 warning and 116 informational
  findings, unchanged from the audit baseline. Existing deprecations, async
  context lints and null-check warning remain; this is not a clean analyzer run.
- `git diff --check`: passed.
- No production SQL, RLS, Storage, concurrency, remote push, or physical-platform
  end-to-end test was executed. The approved-registration migration is prepared,
  not deployed or database-tested. Existing Linux/web builds from earlier work
  are not evidence of target push delivery or this unit's release-build validation.

## Continuation: live metadata supplied and access hardening prepared

The user has now supplied the metadata export. The earlier statement that all
live policies were unavailable is superseded for this point-in-time snapshot;
function bodies and production execution tests are still pending. See
`backend-schema-inventory.md` for the 19 tables, 148 columns, 43 policies, 13
functions, 28 indexes and 63 constraints. The snapshot contains no Realtime
publication tables and only a public profile-photo bucket.

Confirmed priority issues: self-approval through profile owner updates plus
approval_status grants, unrestricted chat membership insertion and conversation
metadata visibility, unrestricted holiday writes, and client TRUNCATE privileges.
Prepared migration 005 and updated chat/profile UI with a coordinated rollout
plan in `security-hardening-rollout.md`. No production change was applied.

Migrations 004 and 005 execute successfully in an isolated PostgreSQL/PGlite
fixture. 22 security assertions pass; seven Flutter tests pass after the client
changes. The fixture uses stub legacy helper bodies and cannot certify those
production RPCs or real Supabase Realtime. Actual device delivery remains as
previously recorded. Next audit input is the single-result allowlisted
`supabase/audit/business_function_definitions.sql`, not a repeat metadata scan.

## Continuation: supplied business functions reviewed; consolidated release

Business function bodies are now supplied and preserved as test-only baseline
source. Existing HR approval uses FOR UPDATE on both request and balance and
only deducts on final approval; that behavior is retained. Existing review_employee
and role assignment RPCs check approved caller roles and reject self-review/role
changes. Existing details RPC checks manager cycles, but direct profile updates
bypassed it; the new trigger also checks reporting-chain changes.

New migration 006 validates full calendar-day quantities, rejects overlapping
active applications, retains locked final-only deduction, rejects duplicate
reviews and emits manager/HR/employee notifications at appropriate stages.
It adds event_type/category/priority/destination/event_key to existing notifications
and replaces request-only uniqueness with recipient/event uniqueness. Historical
rows remain. Partial approval/cancellation/accrual and scheduled events are not
implemented. The sender still has no durable retry worker or delivery-attempt DB.

The generated single transactional release is `supabase/deploy/phase1_release.sql`
(004–006); do not apply both bundle and individual migrations. It has a replay/
partial-install guard. `docs/phase1-release-guide.md` is the consolidated runbook.
It requires staging and coordinated client release; no production SQL/deployment
was performed by the assistant. Broader enterprise phases remain incomplete.

Final checks for this release: 42 isolated PostgreSQL security/leave assertions,
10 mocked push-handler assertions, 7 Flutter tests and 3 Python configuration
tests passed. None substitutes for production RLS/session tests, concurrent
multi-connection tests, or actual target notification delivery. Test fixtures
include synthetic auth functions and the supplied legacy business RPC source.
The last evidenced real remote push failure remains 401 until a new successful
request/device delivery is observed. No native Linux/Windows background service
has been installed or claimed.

## Continuation: notification troubleshooting deferred; Core HR leave unit

The user explicitly deferred notification troubleshooting, then re-supplied the
same enterprise brief. Continue the saved phases; do not restart the audit or
resume FCM/desktop push investigation without a new request.

Prepared migration 007 plus complete UI/repository/domain integration for one
contiguous full-calendar-day partial approval, future cancellation with exact
refund, and immutable scoped leave history. Original requested dates remain;
effective approved dates feed calendars, task availability and on-leave summaries.
Dashboard balances now come from leave_balances instead of hardcoded entitlements
and request counts. Detailed deployment and acceptance steps are in
`core-hr-leave-release.md`.

Use ONLY 007 if 004–006 already installed; otherwise the generated
`supabase/deploy/core_hr_release.sql` is the single bundle for the last exported
pre-004 schema. Do not replay the previous phase1 bundle or individual migrations
on top of the combined release. No production deployment was executed.

This is a safe Core HR unit, not Phase 2 completion. Started/past leave cancellation,
company-timezone policy, half-day/disjoint approval, accrual and attachments remain
unimplemented. New history starts when the migration is installed; old missing
audit events are not fabricated. Reviewers must test the actual Supabase sessions
and release clients together. Next coherent core unit: attendance/correction
transactions with server timestamps, sequence validation and audit history.

Verification for the Core HR leave unit: 59 SQL assertions passed in each of the
upgrade and fresh combined fixture paths, all 14 Flutter tests passed, Linux
debug build passed, and full analyzer has zero errors with existing lints (114
total findings). No remote notification troubleshooting/deployment was resumed.

## Continuation: zero-cost Phase 0 constraints supersede earlier recommendations

User now requires at most 50 employees permanently and ₹0/year infrastructure.
Do not add paid services, trial-dependent infrastructure, automatic billable storage
or paid build workers. Preserve Supabase; do not migrate providers without explicit
approval. Updated phase order starts with audit/stability and a real Windows build
before further core-HR expansion. Full evidence/capacity/cost review is recorded
in zero-cost-audit.md; actual Windows build instructions are in windows-build-guide.md.
The original master scope remains, with notification troubleshooting still deferred.

Small safe post-audit change: remove fabricated holiday fallback, query at most
20 actual upcoming records, show empty/error/retry states. No migration/dependency
or external credential is needed. Three holiday widget checks added. No provider
billing setting or production schema was changed. Native iOS distribution has an
Apple membership cost conflict unless already covered/waived; supported Home Screen
web deployment is a possible free alternative, not a tested native substitute.

Zero-cost audit verification: 17 Flutter tests passed, Linux debug build passed,
full analyzer has no errors/warnings and 113 informational findings, and diff
whitespace checks passed. Windows compilation is still not performed. Next task
must respect new phase numbering and external Windows toolchain dependency.

## Continuation: stability phase; Apple deferred, Windows host unavailable

User authorized the next phase and deprioritized iOS/macOS due to no Apple device
or Xcode. User explicitly confirmed no Windows computer is available. Focus is
Linux/Android; do not buy/introduce a paid remote runner. Windows source/helper
preparation is allowed, but real Phase 2 compilation remains externally unverified.

Completed local session lifecycle unit: restore approved sessions after splash,
coalesce profile validation, recheck on resume/auth change and every five minutes
in foreground, fail closed with retry, reject stale/account-switch responses,
preserve signup flow on duplicate sign-out and clear local auth despite optional
registration-cleanup failure. New migration 008 adds restrictive approval policies
and 50 approved seats (pending/rejected records preserved). No production SQL or
account/billing mutation was executed. Detailed deployment/acceptance instructions
and Windows helper status are in stability-phase-release.md. Notification transport
troubleshooting remains deferred; no new Apple/desktop push claim is made.

Stability evidence: full Flutter suite 29 passed, focused session suite 12 passed
(including disposal guard), PostgreSQL fixture 67 checks passed for upgrade and
fresh combined release. Local Linux debug build verified; no real Supabase session
or Windows runtime acceptance was performed. iOS/macOS explicitly deferred. The
prepared 50-seat cap means approved accounts, including admin/HR; pending/rejected
history is preserved and total Auth registration count is not capped by this unit.

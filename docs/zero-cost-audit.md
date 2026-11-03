# PenguinPeak zero-cost Phase 0 audit — 3 November 2026

## Decision and scope

Target: one internal company, permanently at most 50 employees, ₹0/year incremental
infrastructure spending. Preserve Flutter/Supabase and the original functional
scope. No paid plan, billing linkage, storage extension, worker or migration was
introduced. New constraints override older roadmap recommendations. Notification
troubleshooting remains deferred. This execution audits/reuses prior evidence and
makes one small correctness fix, not a new module rollout.

Current free allowances can support modest 50-person use, but are not a guarantee
of capacity, uptime or permanent provider pricing. A hard spending ceiling means
rejecting/capping work or accepting service restrictions when quotas are reached,
not silently upgrading. Unlimited retained media and unlimited audit history do
not fit a fixed storage allowance indefinitely. Real 50-concurrent-user load tests
have not been performed. Existing hardware, internet and OS licenses are assumed;
no purchases are authorized by this audit.

## 1. Actual structure

```text
lib/
  main.dart, splash_screen.dart, login_screen.dart, signup_screen.dart
  role_dashboard_screen.dart, app_theme.dart
  attendance_management_screen.dart, attendance_adjustment_screen.dart
  leave_management_screen.dart, team_leave_calendar_screen.dart
  task_management_screen.dart, chat_screen.dart, company_wall_screen.dart
  notification_bell.dart, desktop_notification_service.dart
  push_notification_service.dart, firebase_options.dart
  features/auth/domain/account_access.dart
  features/leave/{domain,data,presentation}/
  features/dashboard/presentation/holiday_list.dart
supabase/
  migrations/       # incremental schema/security/workflow SQL
  deploy/           # generated one-time bundles, not automatic migrations
  audit/            # read-only metadata/business function exports
  tests/            # isolated fixtures only, NEVER production input
scripts/            # configuration, bundle generators and SQL/sender checks
test/               # account/profile/leave/Android-local-alert/holiday tests
android/, ios/, linux/, windows/, macos/, web/
docs/               # inventories, rollout guides, preserved product briefs
```

Most UI still queries Supabase in widget state. New auth/leave/dashboard feature
pieces are extracted incrementally. No Kubernetes, microservices, additional
production database, or paid worker is present. Keep PostgreSQL RPCs/transactions,
scoped Realtime, small Edge Functions and explicit storage budgets.

## 2. Concise module audit

“Working” below means local code/test or explicitly supplied user evidence, not
all-platform production certification. All newly prepared SQL must be deployed
and accepted before its workflows can be considered live.

| Module | Status | Evidence/gap and dependencies |
| --- | --- | --- |
| Authentication | Partial | Supabase login/signup + approved role gate; session restoration/revocation and SMTP configuration unverified |
| Employee profiles/directory | Partial; security concern | Profile editing exists; supplied policy permits self-approval; prepared migration guards it but deployment unconfirmed |
| Organization | Partial | Profile manager hierarchy; prepared server cycle guards; dedicated organization/lifecycle still absent |
| Attendance/breaks | Partial; integrity concern | Multiple sessions/break UI; writes/calculations remain client-driven; needs atomic server sequencing/audit |
| Adjustments | Partial | Review UI exists; multi-write approval lacks an authoritative transaction |
| Leave | Partial | Full approval RPC locking inspected; prepared range/cancellation/history unit passes fixtures, needs deployment and real sessions |
| Tasks | Partial | Existing CRUD/assignment/comments; projects/workflows/permissions need extension |
| Projects/Scrum/timesheets | Missing | No complete membership/project/sprint/timer system; do not confuse tasks or attendance duration with it |
| Chat | Partial; security concern | Realtime code, direct chat; exported policies allow self-invite, publication empty; prepared secure RPC/RLS/publication not live-verified |
| Company Wall | Partial | Posts/comments/reactions; private attachments, moderation/mentions/polls incomplete |
| Team calendar | Partial | Leave lists; prepared effective-range integration; unified event calendar absent |
| Dashboard | Partial | Live HR/attendance/leave cards; fake holiday fallback removed in this unit; other role-specific summaries need work |
| Profile/settings | Partial | Saved JSON/profile/theme; private HR data separation and broader preferences missing |
| Notifications | Partial/broken remote delivery | User confirmed local Android test and inbox; last remote sender evidence 401; desktop closed-process delivery missing; troubleshooting deferred |
| Storage | Partial; privacy concern | One public image-only profile-photo bucket; no audited private document/chat file workflow |
| Payroll/expenses/recruitment/onboarding/performance/assets | Missing | Empty profile tabs are honest placeholders, not complete business modules |
| Reports/search | Partial/missing | Employee/action search and dashboard summaries only; scoped exports/analytics absent |
| 50-user capacity rule | Not enforced | Business target documented; no database cap/invite quota implementation yet |

The prior detailed inventories remain in enterprise-implementation-status.md and
backend-schema-inventory.md. No redundant full schema export was requested.

## 3. Database and Storage evidence

User-supplied metadata: 19 public tables, 148 columns, 43 policies, 13 functions,
28 indexes and 63 constraints. All public tables have RLS enabled, which does not
prove safe policy expressions. Supplied business RPC source confirms final-only
leave balance deduction with request/balance row locks.

Storage snapshot: profile-photos only, PUBLIC, 5 MB file limit, JPEG/PNG/WebP;
owner-folder INSERT/UPDATE rules. Public photos must be non-sensitive. Sensitive
employee documents, bank details, receipts, chat media and payslips must not be
put here. Future uploads need private buckets, server/RLS ownership checks,
allowed MIME/size validation, signed downloads, metadata and progress/retry UI.
Existing pasted chat URLs do not constitute secure attachment storage.

No R2 integration is needed now; none was added. Do not enable automatically
billable object storage as a “free” workaround. First measure existing usage and
budget compressed photos/small documents within Supabase Storage.

## 4. Security review and release state

Confirmed in supplied pre-hardening snapshot:

- Owner profile UPDATE plus approval_status grant enables self-approval.
- Conversation participant INSERT WITH CHECK true enables self-invites; metadata
  SELECT is unrestricted. HR must not read chats unless a participant.
- Holiday ALL policy uses true despite its HR/admin name.
- Client TRUNCATE grants bypass RLS if a SQL execution path is available.
- Realtime publication has no tables, so existing chat subscription is ineffective.

Prepared migrations 004–007 address a coherent subset: account registration,
profile/holiday/chat hardening, publication, leave quantity/overlap/staging,
partial approval/cancellation and audit. They have isolated PostgreSQL tests;
production application is unconfirmed. See core-hr-leave-release.md and use ONE
bundle/incremental path, never replay both. This audit did not apply them.

Remaining: attendance transactions, private profile separation, membership cleanup
of historically unauthorized invites, session revocation, 50-person admission cap,
retention/backups and role-scoped exports. Android release currently uses debug
signing: replace with a privately held free signing key before real distribution;
no private signing key should enter Git. Client uses public Supabase configuration;
private server keys must stay in Edge Function secrets. Billing settings and live
secrets were NOT read/changed during this audit.

## 5. Current free allowances and failure behavior

Verified against official documentation on 3 November 2026:

| Supabase Free resource | Current allowance |
| --- | --- |
| Auth monthly active users | 50,000 |
| Database | 500 MB/project, shared compute |
| File storage | 1 GB |
| Egress | 5 GB uncached + separately listed 5 GB cached |
| Realtime | 2 million messages/month, 200 peak connections |
| Edge Functions | 500,000 invocations/month |
| Active projects | 2 |

Sources: [Supabase pricing](https://supabase.com/pricing) and
[billing allowances](https://supabase.com/docs/guides/platform/billing-on-supabase).

Free-plan quota excess causes restrictions rather than free automatic paid
capacity. Supabase says Free has no charges; do not move the organization to a
paid plan or enable add-ons. Spend-cap controls are not a substitute for staying
on Free. No billing change was made here.
[Cost controls](https://supabase.com/docs/guides/platform/cost-control),
[quota FAQ](https://supabase.com/docs/guides/platform/billing-faq).

Low-activity Free projects may pause after roughly seven days; activity is not an
uptime guarantee. Document owner restoration/monitoring and accept free-service
availability limits; do not add fake keepalive traffic to simulate employee use.
[Pausing policy](https://supabase.com/docs/guides/platform/free-project-pausing).

Auth email delivery is a separate dependency: built-in SMTP limits recipients to
project team addresses and about 2 emails/hour. Actual project SMTP settings are
unverified. Existing company SMTP may be usable at no extra spend only after its
permissions, allowance and billing are checked; no email provider was added and
email confirmation/security was not disabled to bypass this limitation.
[Supabase SMTP](https://supabase.com/docs/guides/auth/auth-smtp).

FCM is no-cost. Stay on Firebase Spark and do not link billing/upgrade to Blaze.
Only messaging is required; do not add Firestore, Firebase Storage, Cloud Functions
or App Hosting for this app. No new Firebase service was integrated.
[Firebase pricing](https://firebase.google.com/pricing).

Optional static Firebase Hosting currently provides 10 GB storage and 10 GB/month
transfer at no cost. On Spark, storage saturation blocks deployments and transfer
quota exhaustion can disable sites until reset. Budget alerts on a paid account
are NOT a spending cap. Keep old static releases bounded and avoid serving media
through the Flutter site. [Hosting limits](https://firebase.google.com/docs/hosting/usage-quotas-pricing).

## 6. Capacity risks at 50 employees

These are illustrative calculations, not measured usage:

- 50 employees × one 20 MB video consumes roughly 1 GB before any photos/docs.
  Unlimited video sharing cannot fit. Initially disable video uploads until a
  real retention/size budget and secure private upload flow exist.
- 50 × 10 documents × 200 KB ≈ 100 MB. Compressed 200 KB photos for 50 people ≈
  10 MB. These illustrate a possible small-media budget, not implemented caps.
- The inbox's 20-second polling means 50 users × 8 hours/day × 22 workdays ≈
  1.584 million reads/month. At an assumed 50 KB response, ≈79.2 GB transfer,
  exceeding the free uncached allowance. API request count alone is not the issue.
  Notification pagination/delta retrieval/scoped Realtime needs a later bounded
  change; no notification transport work was resumed here.
- Several screens fetch entire task/comment/message/request histories. Add cursor
  pagination and indexes before data grows; 50 users does not bound row count.
- Realtime message quota is delivered fanout, not just one user's send count.
  Multiple app/device sessions consume connections. 50 users is below the nominal
  connection limit only if sessions/channels are controlled.
- Attendance rows, JSON sessions and immutable history accumulate permanently.
  Decide retention with HR/legal requirements; don't silently delete audit records
  or claim infinite 500 MB retention. Maintain reviewed local encrypted backups
  on existing company storage; free hosting is not an availability/backup SLA.

Proposed internal operating thresholds (not provider limits, not implemented):
review at 70% of DB/storage/egress, stop optional uploads by 85%, reserve the rest
for attendance/leave/auth. Show quota-full states instead of retry storms or
upgrades. Measure real concurrent latency before claiming 50-user reliability.

## 7. Linux and Windows readiness

Local Flutter: stable 3.47.8, Dart 3.13.7, existing Linux runner. Linux debug build
passed before this audit and is rechecked after the holiday fix. It is not a
release acceptance or remote-push test. Main config and QA config currently share
one backend; separate project/config is needed for genuine isolation.

Windows source runner/CMake/manifest and generated plugin registrations exist.
Plugins detected: app_links, firebase_core, flutter_local_notifications_windows,
jni, path_provider_windows, shared_preferences_windows, url_launcher_windows.
This is declared compatibility, NOT proof of Windows compilation/runtime success.
No Windows SDK/MSVC environment is available on this Ubuntu host. No .exe or
Windows release bundle was generated and no binary was renamed.

FCM initialization is skipped on Windows; Supabase remains the backend. Firebase's
Windows SDK is documented for local development, not production use. The native
firebase_core plugin remains a build dependency and must be evaluated on Windows
rather than used for production Firebase features.
[Firebase platform support](https://firebase.google.com/docs/flutter/setup).

Exact Windows tooling/build/distribution steps are in windows-build-guide.md.
No paid CI/runner or cloud VM is required by the plan; use an existing legitimately
licensed Windows machine with appropriate C++ tooling. If none is available,
Phase 2 is blocked on that external resource, not “verified” through Linux tests.

## 8. Notification feasibility and cost matrix

| Platform | Foreground evidence | Background | Closed app | Free setup / limitation |
| --- | --- | --- | --- | --- |
| Android | Inbox and local OS test user-confirmed | Actual remote delivery unverified | Actual remote delivery unverified | FCM no-cost, device token/permission/channel; last remote failure 401 |
| iOS | Code only, target untested | Unverified | Unverified | Native distribution/APNs signing requires suitable Apple program access; paid membership conflicts with ₹0 unless already provided/eligible waiver |
| Linux | Local adapter/build; inbox user-confirmed | Running/minimized process design, not independently tested | Native delivery absent | Session D-Bus/notification daemon; a user-session agent would be needed, not a paid server |
| Windows | Toast adapter/identity configured, untested | Running/minimized design unverified | Native delivery absent | Real Windows tooling/packaging/activation and a background adapter/agent needed |
| macOS | Native adapter code only | Unverified | Unverified | Local alerts need permission; native remote APNs/signing/distribution must be validated; browser alternative possible |
| Web | Service worker/config code, web build only | Unverified | Tab-closed delivery unverified; browser-policy dependent | HTTPS, permission, VAPID/subscription; no new paid push service |

Apple Developer Program ordinarily costs US$99/year. Native iOS rollout cannot be
promised at ₹0 without existing program entitlement or a valid fee waiver. A Home
Screen web app with standards-based Web Push is the genuinely free alternative
on supported iOS versions, but this app's iOS browser path is NOT tested/certified.
[Apple membership](https://developer.apple.com/programs/whats-included/),
[Apple web push](https://developer.apple.com/documentation/usernotifications/sending-web-push-notifications-in-web-apps-and-browsers).

OS Focus/user settings always apply. Local test alerts never prove server remote
delivery. No change to push credentials, billing, webhook or background service
was made in this audit; notification investigation remains deferred.

## 9. Small safe fix completed after the audit

Removed hardcoded holiday examples and silent fallback on database errors.
Dashboard now queries only real upcoming holidays (maximum 20), displays an honest
empty state, and exposes a retry on failure. No migration, paid dependency,
credential or external configuration is required for this fix. Added three widget
checks for empty/error/retry/actual records; existing workflows are preserved.

## 10. Revised phase order and next task

Use the new numbering: 0 audit → 1 stability → 2 real Windows test build →
3 core HR → 4 project management → 5 communication → 6 notifications →
7 advanced HR → 8 reports/polish. Previous prepared core-HR work is retained,
not erased or claimed newly complete. Review deployment status before continuing.

Recommended next safe task: Phase 1 staging acceptance of existing prepared RLS
and auth fixes, followed by Phase 2 Windows build on a real Windows workstation.
Do not create another database schema until existing releases are reconciled.
Use one of the two allowed free Supabase projects for staging if available; first
check current organization quotas. No paid branching/preview environment is needed.

After stability/Windows evidence, continue server-owned attendance/correction
transactions and controlled employee admission (50-person cap); then complete core
HR before projects. Notification transport stays deferred. Do not expand storage,
add services or introduce paid execution to avoid fixing unbounded queries.

## Sources and billing checks

All references above are primary vendor documentation checked on 3 November 2026.
Actual organization billing, usage totals, SMTP configuration, deployment status
and Windows runtime are not visible through the supplied source exports. Owner
must confirm Supabase organization is Free and Firebase project is Spark, inspect
usage dashboards and keep paid upgrades/add-ons disabled. No claim is made that
an account setting was changed remotely or providers guarantee these terms forever.

## Final local checks for this execution

- Flutter regression suite: 17 passed (including three new holiday checks).
- Linux debug build: passed, output build/linux/x64/debug/bundle/penguinpeak_hrms.
- Full analyzer: no errors or warnings; 113 existing informational findings remain.
- git diff --check: passed.
- Windows release build and physical-platform remote delivery: not performed.
- No production migration, provider billing update, private bucket/service setup,
  paid dependency, new database, or notification transport investigation occurred.

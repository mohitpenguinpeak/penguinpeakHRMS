# penguinpeak_hrms

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Profile details

Apply `supabase/migrations/202611020001_profile_details.sql` to your Supabase
project before running this version (using your migration workflow or the SQL
editor). It adds a `profile_details` JSONB column to `public.profiles` and keeps
existing row-level security policies unchanged.

Use **My Profile → Edit Details** to update contact information, bio, skills,
emergency contact, personal information, and employment details. Values are saved
to Supabase and loaded on refresh. Missing values show “Not provided”. Documents,
assets, and performance tabs show empty states until those features are connected.

To enable field edits in the app, also apply
`supabase/migrations/202611020002_profile_update_permissions.sql`. It grants
column-level update access to the profile fields used by the editor and adds an
RLS update policy for the signed-in profile owner and HR/admin roles.

For multiple work sessions per day and categorized breaks, apply
`supabase/migrations/202611020003_attendance_sessions_and_break_types.sql` before
using the updated attendance workflow. Existing attendance rows are preserved;
legacy shifts are treated as the first session, and existing breaks default to
`Rest`.

For correction requests covering multiple punch pairs, apply
`supabase/migrations/202611020004_correction_requested_sessions.sql`. The
correction popup then preloads every punch pair for the selected date and lets
the employee adjust or add entries for HR review.

## Leave notifications

See the [first-time notification setup guide](docs/notification-setup.md) for
step-by-step database, Firebase, webhook, Android, Apple, Windows, Linux, and web
configuration. No email is sent.

The bell inbox works across platforms after applying the notification migrations.
Desktop OS alerts work while the app is running/minimized. Windows/Linux users
need to enable the HTTPS browser companion for push after the native app closes;
this depends on browser/OS background delivery being permitted. Android and Apple
remote push require Firebase/platform configuration. No Windows/Linux background
daemon is installed.

For the inbox **Clear notifications** button, apply
`supabase/migrations/202611030003_clear_notifications.sql`. Clearing hides the
currently displayed notifications for the signed-in recipient and resets their
inbox unread count. New notifications remain visible. Saved history and other
recipients' inboxes are preserved; already delivered OS alerts are unaffected.

## Enterprise upgrade progress

The product brief is preserved in [enterprise-product-brief.md](docs/enterprise-product-brief.md).
Read [the implementation inventory and continuation record](docs/enterprise-implementation-status.md)
for audited module status, security findings, platform notification evidence,
architecture, deployment requirements and the phased roadmap. Phase 1 remains
in progress; the production database/RLS and leave RPCs are not yet verified.

The read-only [backend metadata audit](supabase/audit/metadata_inventory.sql)
collects the schema/security information needed before further workflow changes.
The new `202611030004_approved_push_registration.sql` migration restricts device
registration to approved accounts with existing supported roles; review and test
it against staging before applying to production.

The supplied backend metadata is summarized in
[backend-schema-inventory.md](docs/backend-schema-inventory.md). Review the
[security hardening rollout](docs/security-hardening-rollout.md) before applying
migration `202611030005_phase1_access_hardening.sql`: new chat clients require its
atomic conversation RPC, and old clients cannot create conversations after it.
The migration has isolated PostgreSQL test coverage, not production validation.

For the consolidated audited security and full-day leave workflow release, follow
[phase1-release-guide.md](docs/phase1-release-guide.md). Its single generated SQL
bundle combines migrations 004–006 in one transaction; never apply both the
bundle and its constituent migrations to the same database. QA and main defines
currently use the same backend; use a genuinely separate staging project first.

The next Core HR leave unit is documented in
[core-hr-leave-release.md](docs/core-hr-leave-release.md): partial date-range
approval, future cancellation/refunds, scoped audit history and actual dashboard
balances. Apply only migration 007 after 004–006, or use the new single
`core_hr_release.sql` bundle if none were installed; never apply both paths.
Notification transport troubleshooting is deferred at the user's request.

## Zero-cost operating constraints

The current business ceiling is 50 internal employees and ₹0/year incremental
infrastructure spending. See [the zero-cost audit](docs/zero-cost-audit.md) for
verified free quotas, cost conflicts, module/security status and revised phases,
and [Windows release instructions](docs/windows-build-guide.md) for actual Windows
toolchain requirements. No paid service or plan change was introduced.

## Stability phase

[Stability release guide](docs/stability-phase-release.md): verified session
restoration/access rechecks, resilient local logout, restrictive approved-account
policies and a 50-approved-seat cap. Apply only migration 008 after 004–007, or
use the new stability bundle for the last exported pre-004 schema; never replay
multiple bundles. Windows helper is prepared but cannot be target-tested without
a Windows machine. iOS/macOS work is deferred per the user's priority.

## HR services

Onboarding, payslips/salary, HR helpdesk and Document Centre are available in the
workspace. The other newly added HR modules and reports have been removed.
See [HR modules release and setup](docs/hr-modules-release.md) for the migration
sequence, retained workflows and Android build command.

## Workspace notifications

The bell now covers important retained HR events, task updates, chat, attendance
reviews and official announcements. See [notification activation and event routing](docs/workspace-notifications.md)
for the new migration and the existing push-function update. No live migration or
remote notification send is performed by building the app.

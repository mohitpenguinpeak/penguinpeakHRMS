# PenguinPeak workspace design and functionality

The product direction is Keka-inspired HR workflows and OrangeScrum-inspired work
management, using PenguinPeak's own identity and the existing palette. This applies
to functionality as well as appearance. Keep the master enterprise scope; implement
connected backend/UI/permission/test units progressively rather than empty screens.

## Palette and components

Preserved: orange #F59E0B, dark backgrounds #101010/#1A1A1A, grey light background
#BDBDBD, white light cards, and existing light-theme primary #B85C00. Shared theme
now standardizes input surfaces/focus borders, button spacing/radii, table headings,
tabs and dividers. Existing semantic status colours remain available.

## Implemented in this continuation

- Sidebar groups Home, People & Organization, Time & Attendance, Work Management,
  Collaboration and Personal. Existing destinations remain connected; attendance
  adjustments sit beside attendance. Branding uses the existing PenguinPeak asset.
- Workspace breadcrumb and role badge identify the active page and account context.
- Dashboard switches to two content columns only on wider windows, allowing for
  the desktop sidebar instead of squeezing cards into tablet-width content.
- Tasks use a wrapping header/filter toolbar and horizontally scrollable scope tabs.
- List/Board switching retains the current user scope and search/status/priority
  filters. Kanban cards use the same fetched, RLS-authorized tasks; clicking opens
  the existing task detail/comment workflow. Counts are for the filtered records.
- Board retains current workflow states including booking acceptance and declined;
  unexpected legacy statuses receive their own column rather than losing tasks.

No new package, migration, privileged configuration or external service is needed.
No production data was modified during development. Board drag/drop and new workflow
states are not implemented; status changes continue through existing task actions.

## Remaining functional scope

The existing task project text field is not a project entity/membership model.
Projects, milestones, backlog/sprints, dependencies, task timers/timesheets and
advanced reporting still require authoritative backend workflows and permissions.
HR lifecycle, transactional attendance/corrections, private employee documents,
payroll and the other advanced modules remain on the enterprise roadmap. This
visual/workspace unit does not complete the full enterprise platform or certify
existing client-side business writes as production-safe.

Reference the module inventory in enterprise-implementation-status.md. Continue
with secure core HR and project membership workflows before claiming full Keka or
OrangeScrum feature coverage. Notification platform evidence remains unchanged.

## Mobile-first continuation

The desktop leave screenshot exposed content-sized sections and narrow cards.
Leave sections now stretch to the available width, and approval/history queues use
an adaptive grid (single column on phones, up to three on wide desktops). Balance
cards distribute across available columns. No fixed card height truncates reasons
or actions. Dashboard balance cards use the same sizing primitive.

Shared widgets in `lib/shared/widgets/adaptive_layout.dart` provide content-width
card grids, wrapping page headings and a 220 ms page-entry fade/slide. Page changes
and task-view changes animate; chart bars ease to their values in 350 ms. These
animations respect `MediaQuery.disableAnimations`; timer rebuilds do not remount
page animations. Existing Material tap/hover feedback remains.

Mobile improvements also include compact app-bar actions, wrapping task filters,
wrapping task list cards/actions, attendance tabs and summary grids, company-wall
header/reactions, adjustment headings/status labels, team-calendar heading and
profile layouts based on their actual content width. Chat switches between
conversation list/detail at 720 content pixels rather than whole-window width.
Wide resource/attendance tables and Kanban columns retain horizontal scrolling.

### Task views

List, Board, Calendar and Graphs share the existing scope/search/status/priority
filters and the same authorized task records. Calendar supports month navigation,
Today, date selection, counts, a daily agenda, tasks without due dates and opening
the existing detail/comment workflow. Dates are presented in the device timezone.

Graphs provide status doughnut and bars, priority bars, tasks by existing project
text, active workload by assignee, active deadline buckets and seven-day completion
trend. Counts and text alternatives accompany graphical data. Workload groups by
assignee ID, so duplicate employee names do not merge their records. Completed,
declined and cancelled tasks are excluded from active workload/deadline buckets.
Completion trends exclude missing timestamps and disclose that count. Day buckets
use calendar dates rather than assuming local days always contain 24 hours.

These are snapshots of fetched, permission-scoped records, not historical sprint
analytics or a replacement project model. Burndown, velocity, budget/cost and
estimated-versus-actual-time graphs require real sprint/timesheet/history data;
no values or history were fabricated. Existing query pagination limits still apply.
No new backend table, migration, service, dependency or credentials were introduced.

### Verification

- 44 Flutter tests pass, including 320/390/768/1600-pixel calendar/analytics layouts,
  calendar navigation/task opening, desktop card fill, mobile stacking, reduced
  motion and phone profile/leave summaries.
- Temporary 390-pixel mobile renders were inspected with real Roboto/Material icon
  fonts; preview-only fixture tests were removed afterward.
- Runtime acceptance with real backend accounts, physical Android/iOS devices,
  keyboard/IME, large accessibility text and every legacy dialog/table remains
  necessary. Width-based widget tests do not certify every screen on a device.

Employee directory cards now also use adaptive columns and natural heights,
removing clipping of approval/profile actions caused by the previous fixed-height
grid. Workspace scroll state is kept per module so switching pages does not reuse
another module's scroll offset. Linux debug compilation passes. Full analyzer:
113 informational findings, no errors/warnings (nonzero exit for infos).

Android debug APK compilation also passes with existing public Supabase defines:
`build/app/outputs/flutter-apk/app-debug.apk`. This includes the final employee-card
layout change. Gradle reports Java native-access and firebase_core Kotlin-plugin
future-compatibility warnings; they did not prevent compilation. No Android device
runtime, push delivery, release signing or app-store deployment is claimed.

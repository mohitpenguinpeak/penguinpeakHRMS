# Task workspace reference implementation

The six user screenshots define the intended functional direction, alongside the
existing PenguinPeak palette and mobile-first requirement. They are references,
not evidence of data or integrations present in this application.

## Implemented against existing task records

| Reference area | Current implementation |
| --- | --- |
| Detailed task inspector | Responsive details/timeline panels, project, assignee, creator, due date, status, priority, actual saved estimate, created/updated/completed timestamps; description and existing comments/actions remain connected |
| Task editing | Existing form now edits project text; preserves original creator and absent due dates; explicit deadline clearing; non-negative finite estimate validation; controller cleanup after modal exit |
| Task completion | Saves completion/update timestamp and surfaces write failures; this remains the existing client-write workflow, not a new audited server RPC |
| Filters | Search title/description/project/task ID/people, status, priority, project, assignee, creator, due today/within seven days/overdue/undated, inclusive custom due-date range |
| Filter usability | Removable active-filter chips, reset, matching count, same scoped results across List/Board/Calendar/Graphs |
| Sorting | Newest, oldest, deadline, priority, title; missing dates last, deterministic ties |
| Board groups | Project, assignee or priority swimlanes with counts, completed count, expand/collapse all and individual group expansion |
| Board layout | Columns fill wide workspaces where possible and scroll on phones; existing workflow states and legacy custom states are retained |
| Calendar and charts | Previously implemented task-deadline calendar and six snapshot analytics panels use the same filtered records |

No new package, backend migration, RLS policy, Edge Function, credentials or storage
was added. Project remains the existing task text field, not a new project entity
or membership system. Filters cannot grant access; the query starts with records
returned under the existing backend policies and then applies the current scope.
The resource-availability matrix remains a separate view and is not presented as a
filtered timesheet report. Its existing scheduling heuristics are not logged time.

The old assumed eight-hour display is removed when no estimate marker exists.
Existing estimate markers remain compatible; estimates are not called spent hours.
No historic completion dates or task activities are backfilled or invented.

## Remaining screenshot features — not implemented

- Durable start/stop timers and manual time entries with server-owned timestamps.
- Daily/weekly timesheets and logged-hours calendar; task deadlines are different.
- Billable/non-billable time, submitted/approved/rejected time entries and corrections.
- Resource/date/project/time-entry-status filters on actual time-entry records.
- Time-entry CSV/PDF exports, utilization and estimated-versus-actual time reports.
- First-class projects/task groups, sprints, stories, epics, story points, versions,
  releases, labels, dependencies, private files and immutable activity history.
- Board drag/drop, bulk mutations and persisted manual ordering.

There are no nonfunctional buttons advertising these missing workflows. The
in-memory Set Active task selector is not a durable timer and is not relabelled as
Start Timer. No attendance durations are converted to task time. Completion state
is not turned into invented percent-complete values for unfinished tasks.

## Backend prerequisite for time tracking

The last supplied metadata has no time-entry/timesheet tables and omits task column
types and constraint definitions. Check the current database before adding tables;
use `supabase/audit/task_time_readiness.sql` (read-only metadata, no employee rows,
auth tokens, webhook secrets or private documents). Preserve/reuse any matching
existing tables. No database connection or production migration is claimed here.

Then implement one authoritative time-entry domain shared by timers/manual entries,
with scoped approval records, overlap checks, a unique active timer per employee,
server timestamps, idempotent start/stop, locking, append-only corrections/audit,
and existing-role authorization. Daily/weekly/calendar/report views must aggregate
these same records. Keep task time separate from attendance. Validate RLS and
concurrent timer/approval actions in staging before exposing production controls.

## Verification

- Full Flutter regression suite: 57 passed.
- Final focused query/board/inspector suite: 15 passed after inspector refinement.
- Layout tests include 320/768/1600-pixel grouped boards and detail panels with
  1.3x text, plus the earlier calendar/analytics/mobile coverage.
- Analyzer: no errors or warnings; informational findings remain.
- Production writes, live authorization policies, manual create/edit acceptance,
  actual target-device interaction and new time tracking remain unverified.

Final build evidence: Linux debug build passed; updated Android debug APK build
passed at `build/app/outputs/flutter-apk/app-debug.apk`. Java/Firebase Kotlin future
compatibility warnings persist. No target-device/runtime certification is implied.
The final full regression rerun passed all 57 tests; `git diff --check` passed.
Task-only filter controls are hidden in the independent resource-availability tab,
where they would otherwise be misleading. Final recorded analyzer output has 108
informational findings and no errors/warnings.

## Saved-scroll / expansion crash correction

The supplied Tasks screenshot (`double` is not a subtype of `bool?`) was reproduced
by saving a workspace ListView scroll offset and then mounting the task panels in
the same PageStorage bucket. Unkeyed expansion panels inherited the scrollable's
PageStorage identity and read its double as their boolean expanded state.

The task filter panel is now a small independently testable widget with its own
PageStorageKey. Grouped-board panels also use PageStorageKeys; a revision counter
makes explicit Collapse all / Expand all override previously saved manual states.
Attendance month/day panels have distinct nested keys as well. Workspace scroll
restoration remains enabled. No backend/configuration/data changes are required.

`test/task_page_storage_test.dart` failed with the exact double-to-bool error before
the key fix and passes afterward. It also checks expansion, group collapse/expand
and continued double-valued scroll state. Earlier standalone widget tests did not
include this shared-storage nesting. Fully restart the running client after
rebuilding to discard any already corrupted legacy in-memory page state.

Crash-fix verification: all 58 Flutter tests pass; Linux debug and Android debug
APK rebuilds pass. Analyzer reports 108 informational findings, no errors/warnings;
`git diff --check` passes. No database migration or production deployment occurred.

# PROJECT: PenguinPeak — Enterprise HRMS + Project Management Platform

## PRIMARY OBJECTIVE

Transform the existing partially developed Flutter application into a comprehensive, production-ready Enterprise HRMS and Project Management platform.

The product should combine the breadth of HR functionality found in Keka with the project management, task tracking and Agile functionality found in OrangeScrum.

Product name: PenguinPeak HRMS

Reference products:
- Keka: HRMS, employee lifecycle, attendance, leave, payroll, performance, employee engagement and HR operations.
- OrangeScrum: project management, task management, Scrum, Kanban, time tracking, collaboration, milestones and project reporting.

Build comparable feature categories and workflows, not copied source code, proprietary assets, branding or UI.

This is an existing partially implemented application. Continue and upgrade the current project. Do not unnecessarily rebuild it from scratch.

The ultimate goal is one unified application where employee management, HR workflows, project management, communication, approvals and notifications work together.

---

# 1. FIRST: AUDIT THE EXISTING PROJECT

Before writing code:

Inspect:
- Flutter project structure.
- Existing Dart screens and widgets.
- Supabase database schema.
- Existing SQL migrations.
- Database functions and RPCs.
- RLS policies.
- Supabase Storage buckets and policies.
- Authentication and role management.
- Existing dependencies.
- Existing notification implementation, if any.
- Existing theme and navigation architecture.

Existing modules include:
- Dashboard
- Employees
- Organization
- Leave
- Attendance
- Attendance Adjustments
- Tasks
- Chat
- Company Wall
- Team Calendar
- My Profile
- Settings

Existing files include:
- lib/main.dart
- lib/role_dashboard_screen.dart
- lib/login_screen.dart
- lib/signup_screen.dart
- lib/attendance_management_screen.dart
- lib/leave_management_screen.dart
- lib/task_management_screen.dart
- lib/chat_screen.dart
- lib/company_wall_screen.dart
- lib/team_leave_calendar_screen.dart

Actual files and implementation may differ. Discover the real project structure before editing.

Create an implementation inventory:

| Module | Existing state | Missing features | Required action |
|---|---|---|---|
| Authentication | Audit | Audit | Upgrade |
| Employees | Audit | Audit | Upgrade |
| Attendance | Audit | Audit | Upgrade |
| Leave | Audit | Audit | Upgrade |
| Tasks | Audit | Audit | Upgrade |
| Chat | Audit | Audit | Upgrade |
| Notifications | Audit | Audit | Implement |
| Projects | Audit | Audit | Implement |
| Dashboard | Audit | Audit | Upgrade |

Do not assume that an existing screen means the feature is fully implemented.

Identify broken workflows, missing backend operations, security issues and incomplete UI interactions.

Prioritize fixing existing modules before introducing duplicate implementations.

---

# 2. TECHNICAL ARCHITECTURE

Continue using the existing Flutter and Supabase architecture unless a documented technical limitation requires a change.

Backend:
- Supabase Authentication.
- PostgreSQL.
- Supabase Realtime.
- Supabase Storage.
- Supabase Edge Functions.
- Database migrations.
- Row Level Security.

Frontend:
- Flutter.
- Dart.
- Material 3.
- Responsive desktop, tablet and mobile layouts.
- Shared reusable widgets and components.
- Dark and light themes.

Architecture requirements:
- Modular feature-based architecture.
- Clear separation of UI, business logic and data access.
- Reusable repositories and services.
- Centralized error handling.
- Consistent validation.
- Pagination for large datasets.
- Efficient database queries.
- Avoid duplicate network requests.
- Proper loading, empty, error and success states.
- Maintainable code and automated tests.

Use existing dependencies wherever possible. Introduce new dependencies only when justified.

Never expose Supabase service-role keys, database passwords, FCM server credentials or other privileged secrets inside the Flutter application.

---

# 3. EMPLOYEE MANAGEMENT AND HR

Implement a comprehensive employee management system.

Employee profiles:
- Employee ID.
- Full name.
- Profile photograph.
- Email.
- Phone.
- Address and contact details.
- Department.
- Designation.
- Employment type.
- Employment status.
- Joining date.
- Probation details.
- Reporting manager.
- Work location.
- Skills.
- Employee documents.
- Emergency contact.
- Bank details with restricted access.
- Employment history.

Employee lifecycle:
- Employee registration.
- Account approval.
- Offer and onboarding workflow.
- Document collection.
- Probation management.
- Confirmation.
- Department transfers.
- Designation changes.
- Manager changes.
- Promotions.
- Resignation.
- Notice period.
- Exit clearance.
- Offboarding.

Organization management:
- Departments.
- Teams.
- Designations.
- Reporting hierarchy.
- Multi-level organizational chart.
- Manager/direct-report relationships.
- Organization-wide directory.

Support existing roles and permissions. Do not introduce duplicate or conflicting roles.

---

# 4. ATTENDANCE MANAGEMENT

Build a complete attendance system.

Features:
- Clock in.
- Clock out.
- Multiple breaks.
- Break start/end timestamps.
- Net working hours.
- Break duration.
- Late arrival.
- Early departure.
- Half-day calculation.
- Full-day calculation.
- Overtime.
- Weekly and monthly summaries.
- Attendance calendar.
- Attendance history.
- Shift management.
- Flexible working hours.
- Work-from-home status.
- Holiday calendar.
- Weekend rules.
- Attendance regularization.
- Manager approval.
- HR approval.
- Attendance correction audit history.

Rules:
- Never fabricate attendance timestamps.
- Prevent invalid clock-in/clock-out sequences.
- Prevent duplicate active sessions.
- Calculate net working hours correctly.
- Preserve all attendance audit records.
- Use configurable company attendance policies.

Integrate attendance with employee profiles, leave, timesheets and payroll where applicable.

---

# 5. LEAVE MANAGEMENT

Implement complete leave management.

Features:
- Configurable leave categories.
- Earned leave.
- Sick leave.
- Casual leave.
- Unpaid leave.
- Compensatory leave.
- Leave accrual.
- Carry-forward.
- Encashment rules where applicable.
- Employee leave balances.
- Leave applications.
- Attachments.
- Leave cancellation.
- Leave history.
- Team leave calendar.
- Holiday integration.
- Overlapping leave detection.

Approval workflow:

1. Employee submits leave request.
2. Direct manager receives an approval notification.
3. Manager approves or rejects.
4. Manager approval forwards the request to HR when HR approval is required.
5. HR grants, partially grants or rejects the request.
6. Leave balance is deducted only for the finally approved leave quantity.
7. Employee receives the final result notification.

Support:
- Full approval.
- Partial approval.
- Partial date-range approval.
- Rejection.
- Cancellation.
- Multi-level approvals.
- Configurable approval policies.

All balance calculations must be transaction-safe.

Never deduct leave balance before the final approval stage.

---

# 6. PROJECT MANAGEMENT — ORANGESCRUM-INSPIRED

Implement a complete project management module.

Projects:
- Create projects.
- Edit projects.
- Project descriptions.
- Project owners.
- Project managers.
- Team members.
- Start dates.
- Due dates.
- Status.
- Priority.
- Progress percentage.
- Project budgets where applicable.
- Milestones.
- Project documents.
- Activity history.

Project views:
- List view.
- Kanban board.
- Calendar view.
- Gantt/timeline view.
- Project overview.
- Project reports.

Tasks:
- Create tasks.
- Assign multiple responsible users where supported.
- Task owners.
- Task followers/watchers.
- Task descriptions.
- Priority.
- Due date.
- Start date.
- Status.
- Estimated hours.
- Actual hours.
- Attachments.
- Comments.
- Checklists/subtasks.
- Dependencies.
- Labels.
- Task activity history.

Task statuses:
- Backlog.
- To Do.
- In Progress.
- In Review.
- Blocked.
- Completed.
- Cancelled.

Allow configurable workflows.

Subtasks and dependencies must update project progress appropriately.

Notifications must be triggered when:
- A task is assigned.
- A task is reassigned.
- A task deadline changes.
- A task is due soon.
- A task becomes overdue.
- A task is commented on.
- A user is mentioned.
- Task status changes.
- A task is completed.
- A dependency blocks or unblocks a task.

---

# 7. AGILE / SCRUM MANAGEMENT

Implement proper Agile workflows.

Features:
- Scrum projects.
- Product backlog.
- Sprint creation.
- Sprint planning.
- Sprint start/end dates.
- Sprint capacity.
- Story points.
- User stories.
- Epics.
- Task assignment.
- Sprint backlog.
- Sprint progress.
- Burndown chart.
- Velocity reporting.
- Sprint retrospective.
- Sprint completion.
- Kanban boards.
- Workflow customization.

Support configurable Scrum and Kanban project types.

Keep project/task permissions consistent with project membership.

---

# 8. TIMESHEETS AND TIME TRACKING

Implement:
- Start/stop task timers.
- Manual time entries.
- Timesheet submission.
- Weekly timesheets.
- Project-based time tracking.
- Task-based time tracking.
- Billable/non-billable time.
- Manager approval.
- Timesheet corrections.
- Time reports.

Prevent overlapping active timers where the business policy disallows them.

Integrate time tracking with tasks, projects and attendance without confusing attendance duration with project working time.

---

# 9. LEAVE, ATTENDANCE AND PROJECT CALENDAR

Create unified calendar functionality.

Display:
- Approved employee leave.
- Public holidays.
- Employee birthdays.
- Work anniversaries.
- New joiners.
- Project milestones.
- Sprint deadlines.
- Task deadlines.
- Company events.
- Attendance-related events where appropriate.

Respect permissions and employee privacy.

Allow filtering by team, department, project and event type.

---

# 10. SECURE INTERNAL CHAT

Upgrade the existing chat module.

Features:
- One-to-one chat.
- Group chat.
- Group management.
- Text messages.
- Images.
- Videos.
- Documents.
- Multiple attachments.
- Message editing with audit history.
- Message deletion according to policy.
- Replies.
- Mentions.
- Reactions.
- Read receipts.
- Typing indicators.
- Unread message counts.
- Conversation search.
- Message search.
- Pinned messages.
- File downloads.
- Secure private storage.

Message priority:
- Normal.
- Important.
- Urgent.

Urgent messages must trigger appropriate notifications to conversation participants.

Do not expose private conversations to HR/Admin unless they are authorized participants or a legitimate, audited administrative policy permits access.

Use Supabase Realtime for live messaging.

---

# 11. COMPANY WALL AND EMPLOYEE ENGAGEMENT

Upgrade the existing Company Wall.

Features:
- Company announcements.
- Employee posts.
- Comments.
- Reactions.
- Mentions.
- Birthday wishes.
- Work anniversary wishes.
- Praise and recognition.
- Polls.
- Pinned announcements.
- Attachments.
- Post visibility controls.
- Moderation permissions.

Provide a Keka-inspired dashboard feed.

Ensure the wall and chat remain separate features with appropriate permissions.

---

# 12. NOTIFICATION SYSTEM — CRITICAL REQUIREMENT

This is one of the highest-priority modules.

I do not want notifications limited to a notification bell inside the Flutter application.

I require actual operating-system notifications visible in the device notification center/panel.

Supported targets:
- Android.
- iOS.
- Linux.
- Windows.
- macOS.
- Web, if the existing Flutter application supports web.

The implementation must distinguish:
1. In-app notifications.
2. Foreground OS notifications.
3. Background remote push notifications.
4. Notifications when the application is closed.
5. Notification delivery and read status.

Do not falsely claim all five are supported just because an in-app notification appears.

## 12.1 Platform notification architecture

Android:
- Firebase Cloud Messaging.
- Android notification channels.
- Appropriate notification permissions.
- Foreground notification presentation.
- Background notifications.
- Tap handling and deep links.
- Notification icons.
- Priority and sound configuration.

iOS:
- APNs integration, using Firebase Cloud Messaging where appropriate.
- Required notification permissions.
- Foreground presentation.
- Background/terminated app handling where supported.
- Notification categories.
- Tap handling and deep links.
- Correct APNs credentials and entitlements.

Windows:
- Native Windows toast notifications or a verified supported notification integration.
- Application identity and notification activation configuration.
- Foreground and background behavior.
- Deep-link handling.
- Document packaging and deployment requirements.

macOS:
- Native macOS notification center integration or a verified supported implementation.
- Notification permissions.
- App signing and entitlement requirements where necessary.
- Foreground and background behavior.
- Notification activation/deep links.

Linux:
- Native desktop notifications using the supported desktop notification service, such as DBus/libnotify.
- Notification action handling where supported.
- Desktop environment compatibility.
- Packaging and deployment requirements.
- Do not assume that a local notification plugin provides remote push while the application is closed.

Web:
- Web Push where supported.
- Service worker.
- Browser notification permissions.
- Secure notification subscription management.

IMPORTANT TECHNICAL REQUIREMENT:

Flutter Firebase Messaging does not provide a universal, officially supported remote push solution for every desktop platform.

Do not pretend FCM alone solves Linux, Windows and macOS background notifications.

Build a platform capability matrix and implement the correct native or remote delivery adapter for each platform.

For desktop, if reliable background delivery requires a companion background process, native service, application packaging or another infrastructure component, document and implement the architecture where feasible.

If a platform cannot support the requested background behavior in the current distribution model, state the exact limitation and provide the best supported alternative.

## 12.2 Notification event catalogue

Create notifications for appropriate business events.

### Employee and HR notifications

- New employee registration.
- Account approval.
- Account rejection.
- Profile changes where relevant.
- Department changes.
- Designation changes.
- Reporting manager changes.
- Document requests.
- Onboarding tasks.
- Probation reminders.
- Employment anniversaries.
- Birthdays.
- Work anniversaries.
- New employee joining.

### Leave notifications

- Leave applied.
- Manager approval pending.
- Manager approved.
- Manager rejected.
- Forwarded to HR.
- HR approval pending.
- HR approved.
- HR partially approved.
- HR rejected.
- Leave cancelled.
- Leave balance updated.
- Leave request modified.

The employee must be notified at every meaningful transition.

Managers must receive notifications for requests requiring their action.

HR must receive notifications only at the appropriate HR approval stage.

### Attendance notifications

- Clock-in reminders where configured.
- Late arrival.
- Missed clock-out.
- Early departure requests.
- Attendance regularization submitted.
- Manager approval required.
- HR approval required.
- Attendance adjustment approved.
- Attendance adjustment rejected.
- Shift changes.

Avoid sending unnecessary notifications for every clock-in/clock-out unless the user or company policy enables them.

### Task notifications

- Task created.
- Task assigned.
- Task reassigned.
- Task deadline approaching.
- Task overdue.
- Task commented on.
- User mentioned.
- Task status changed.
- Task completed.
- Task reopened.
- Task blocked.
- Task unblocked.

### Project notifications

- Project created.
- Project member added.
- Project assignment changed.
- Milestone created.
- Milestone due soon.
- Milestone overdue.
- Sprint started.
- Sprint ending.
- Sprint completed.
- Important project update.

### Chat notifications

- New direct message.
- New group message.
- User mentioned.
- Reply to message.
- Urgent message.
- File shared.
- Relevant group announcement.

Respect muted conversations and notification preferences.

### Company Wall notifications

- New company announcement.
- Mention in a post.
- Comment on own post.
- Reaction to own post where configured.
- Birthday reminder.
- Work anniversary reminder.
- Praise received.
- Poll participation/reminder where appropriate.

### Timesheet notifications

- Timesheet submitted.
- Timesheet approval required.
- Timesheet approved.
- Timesheet rejected.
- Timesheet returned for correction.

## 12.3 Notification behavior and priorities

Provide:
- Normal.
- Important.
- Urgent.

Map these to appropriate OS presentation and delivery settings.

Urgent notifications should be prominent, but must not falsely claim to bypass OS Focus modes, Do Not Disturb or user notification settings.

Do not abuse urgent priority for ordinary events.

Each notification should contain:
- Clear title.
- Useful message.
- Sender or event source.
- Timestamp.
- Related entity ID.
- Deep-link destination.
- Priority.
- Read/unread state.

Example:

Title: Leave Request Requires Approval

Body: Mohit has requested leave from 12 November to 14 November. Review the request.

Example:

Title: Task Assigned to You

Body: You have been assigned "Update HRMS dashboard". Due date: 10 November.

Example:

Title: Birthday Today

Body: Today is Viren's birthday. Send your wishes!

Example:

Title: Urgent Message from HR

Body: Please review the urgent message in the HR group.

Do not expose confidential content in lock-screen previews if a user chooses private notification previews.

## 12.4 Notification backend design

Implement a centralized, event-driven notification architecture.

Use:
- PostgreSQL notification/event records.
- Supabase Edge Functions.
- Secure event processing.
- Supabase Realtime for in-app updates.
- FCM/APNs or supported platform-specific providers.
- Device registration and token management.
- Delivery attempts and status tracking.
- Retry handling.
- Deduplication.
- Idempotency keys.
- Dead-letter/error handling where appropriate.

Create a reusable event-to-notification service.

Business operations must persist successfully before their notifications are dispatched.

Avoid duplicate notification dispatch caused by repeated database events or retries.

Never allow a Flutter client to forge notification recipients or privileged event data.

## 12.5 Notification preferences

Each employee should have settings for:
- Push notifications enabled/disabled.
- In-app notifications.
- Email notifications where configured.
- Normal notification preferences.
- Important notification preferences.
- Urgent notification preferences.
- Birthday and anniversary reminders.
- Task notifications.
- Chat notifications.
- Leave notifications.
- Attendance notifications.
- Quiet hours.
- Sound preferences.
- Private notification previews.

Respect OS-level notification permissions.

Provide a clear UI explaining if notification permissions are disabled.

## 12.6 Notification centre

Build a centralized notification centre with:
- All.
- Unread.
- Important.
- Urgent.
- Category filters.
- Mark as read.
- Mark all as read.
- Notification history.
- Click-to-open destination.
- Unread badge.
- Notification preferences.

Maintain notification history in the backend.

---

# 13. BIRTHDAY AND ANNIVERSARY AUTOMATION

Implement automatic scheduled event detection.

Use employee date-of-birth and joining-date information where permitted.

Requirements:
- Identify birthdays.
- Identify work anniversaries.
- Detect upcoming events.
- Send configured reminders.
- Avoid duplicate notifications.
- Handle time zones correctly.
- Respect privacy settings.
- Support scheduled backend execution.
- Show events on the dashboard and team calendar.

Do not rely only on the Flutter application being open to trigger scheduled notifications.

Use a reliable scheduled backend process.

---

# 14. PAYROLL AND FINANCE

Build a configurable payroll module.

Features:
- Salary structures.
- Earnings.
- Allowances.
- Deductions.
- Bonuses.
- Reimbursements.
- Payslip generation.
- Monthly payroll processing.
- Payroll history.
- Salary revisions.
- Employee compensation records.
- Payroll approval.
- Payroll reports.

Support configurable statutory/tax rules by country and jurisdiction.

Do not hardcode tax calculations or claim legal compliance without validated jurisdiction-specific rules.

Restrict compensation and banking data to authorized roles.

---

# 15. EXPENSES AND REIMBURSEMENTS

Features:
- Expense submissions.
- Categories.
- Receipts and attachments.
- Reimbursement requests.
- Manager approval.
- Finance approval.
- Rejection and correction.
- Payment status.
- Expense reports.
- Audit history.

---

# 16. PERFORMANCE MANAGEMENT

Features:
- Employee goals.
- OKRs.
- KPIs.
- Performance cycles.
- Self-assessment.
- Manager assessment.
- Peer feedback.
- One-to-one meetings.
- Feedback history.
- Review approvals.
- Development plans.
- Performance dashboards.

Respect confidentiality and role-based access.

---

# 17. RECRUITMENT AND ONBOARDING

Recruitment:
- Job openings.
- Applications.
- Candidate profiles.
- Interview scheduling.
- Interview feedback.
- Hiring stages.
- Offer management.
- Candidate status.
- Recruitment analytics.

Onboarding:
- New employee checklist.
- Document submission.
- Task assignment.
- Equipment allocation.
- Department orientation.
- Manager assignment.
- Onboarding completion.

---

# 18. ASSET AND DOCUMENT MANAGEMENT

Assets:
- Company assets.
- Asset categories.
- Assignment to employees.
- Asset issue/return.
- Asset history.
- Maintenance status.

Documents:
- Employee documents.
- Company policies.
- Contracts.
- Offer letters.
- Payslips.
- Secure file storage.
- Expiry reminders.
- Role-based access.
- Document version history where appropriate.

Use private storage and signed URLs for sensitive documents.

---

# 19. REPORTING AND ANALYTICS

Build role-based reporting dashboards.

HR:
- Total employees.
- New joiners.
- Attrition.
- Leave statistics.
- Attendance trends.
- Employee distribution.
- Pending approvals.

Management:
- Department performance.
- Project progress.
- Task completion.
- Workload.
- Project timelines.
- Timesheet summaries.

Project managers:
- Project progress.
- Sprint performance.
- Overdue tasks.
- Team workload.
- Time tracking.
- Milestone status.

Exports:
- CSV.
- XLSX.
- PDF where appropriate.

Ensure exported reports respect user permissions.

---

# 20. GLOBAL SEARCH AND NAVIGATION

Create unified search across authorized entities:

- Employees.
- Projects.
- Tasks.
- Conversations.
- Announcements.
- Documents.
- Leave requests.
- Attendance records.

Provide quick actions:
- Apply leave.
- Create task.
- Create project.
- Start attendance.
- Open employee profile.
- Open pending approvals.

Only show search results and actions permitted for the authenticated user.

---

# 21. ROLE-BASED ACCESS CONTROL

Preserve existing roles where possible.

Existing roles include:
- employee
- management
- admin
- hr
- super_admin

Use permission-based authorization rather than scattered hardcoded role checks.

Examples:
- Employees access their own records and permitted shared data.
- Managers access direct reports and assigned team workflows.
- HR accesses authorized HR operations.
- Admin manages organizational configuration.
- Super Admin manages system-wide configuration.

Implement:
- Secure database policies.
- Role/permission checks.
- Server-side validation.
- Audit logs.
- Restricted access to payroll, banking and private documents.

Never trust a role or user ID supplied by the client without validating it server-side.

---

# 22. DESIGN SYSTEM AND USER EXPERIENCE

The application should combine:
- Keka-inspired HR dashboard structure.
- OrangeScrum-inspired project and task management usability.
- PenguinPeak's own identity.

Design:
- Modern enterprise interface.
- Dark and light themes.
- Orange accent.
- Responsive layouts.
- Sidebar navigation on desktop.
- Mobile navigation.
- Global search.
- Notification centre.
- Reusable cards.
- Data tables.
- Kanban boards.
- Calendar views.
- Charts.
- Dialogs and forms.
- Consistent typography.
- Accessibility.
- Keyboard navigation on desktop.

The dashboard should adapt to user roles.

Employee dashboard:
- Attendance.
- Leave balance.
- Tasks.
- Announcements.
- Upcoming events.
- Messages.

Manager dashboard:
- Team attendance.
- Leave approvals.
- Team tasks.
- Project status.
- Workload.
- Upcoming deadlines.

HR dashboard:
- Employee overview.
- Leave and attendance approvals.
- Recruitment.
- Birthdays.
- Anniversaries.
- New joiners.
- HR analytics.

Admin dashboard:
- Organization health.
- User approvals.
- System configuration.
- Overall reports.

Do not make every role see the same dashboard.

---

# 23. DATABASE AND SECURITY

Inspect the existing database before migrations.

Requirements:
- Reuse existing tables.
- Avoid duplicate tables.
- Add missing relationships safely.
- Use foreign keys.
- Add appropriate indexes.
- Use constraints.
- Use transactions for multi-step approvals.
- Use secure RPCs where needed.
- Implement RLS for every sensitive table.
- Restrict Storage access.
- Audit important changes.
- Validate user permissions on the server.
- Handle concurrent approval actions safely.

Use incremental, reversible migrations wherever possible.

Never drop existing production data to make a migration easier.

Do not weaken RLS just to make a screen work.

---

# 24. AUTOMATED TESTING

Implement tests for critical workflows.

Authentication:
- Signup.
- Login.
- Approval.
- Role access.

Leave:
- Application.
- Manager approval.
- HR approval.
- Partial approval.
- Rejection.
- Balance calculation.

Attendance:
- Clock in/out.
- Breaks.
- Working-hour calculations.
- Regularization.

Tasks:
- Creation.
- Assignment.
- Reassignment.
- Completion.
- Deadline notifications.

Projects:
- Membership.
- Permissions.
- Milestones.
- Sprint workflow.

Chat:
- Message delivery.
- Attachments.
- Urgent messages.
- Read status.

Notifications:
- Event creation.
- Recipient selection.
- Deduplication.
- Retry.
- Device token registration.
- Foreground delivery.
- Background delivery.
- Notification tap/deep links.
- Platform-specific notification behavior.

Test platform behavior independently for Android, iOS, Linux, Windows and macOS.

---

# 25. IMPLEMENTATION STRATEGY — IMPORTANT

Do not attempt a massive uncontrolled rewrite.

Work in phases.

PHASE 1 — Audit and stabilize:
- Inspect project.
- Map modules.
- Identify broken workflows.
- Fix authentication and security issues.
- Document existing schema.

PHASE 2 — Core HR:
- Employees.
- Organization.
- Attendance.
- Leave.
- Approval workflows.

PHASE 3 — Project management:
- Projects.
- Tasks.
- Scrum.
- Kanban.
- Time tracking.
- Milestones.

PHASE 4 — Communication:
- Chat.
- Attachments.
- Company Wall.
- Announcements.

PHASE 5 — Notification infrastructure:
- Central event system.
- Persistent notification centre.
- Android push.
- iOS push.
- Linux desktop notifications.
- Windows notifications.
- macOS notifications.
- Web push where supported.
- Scheduled birthday and anniversary notifications.

PHASE 6 — Advanced HR:
- Payroll.
- Expenses.
- Recruitment.
- Onboarding.
- Performance.
- Assets.
- Documents.

PHASE 7 — Analytics and polish:
- Reports.
- Exports.
- Global search.
- Dashboard.
- Responsive UI.
- Performance optimization.

Implement one coherent phase at a time.

Do not mark a phase complete until its backend, UI, permissions, error handling and tests are working.

---

# 26. STRICT CODEX EXECUTION RULES

- Work in the existing repository.
- Inspect before editing.
- Do not recreate the application.
- Do not replace working modules unnecessarily.
- Do not rewrite entire files for small changes.
- Do not create duplicate database tables.
- Do not create duplicate migrations or RPC functions.
- Do not invent successful integrations.
- Do not use mock data as production functionality.
- Do not expose secrets.
- Do not disable security policies.
- Do not silently skip failed features.
- Do not claim a platform supports background push without testing it.
- Preserve current authentication, user data and application configuration.
- Preserve existing functionality during upgrades.
- Use targeted changes.
- Run relevant tests after each phase.
- Report errors and incomplete dependencies honestly.

When a task is too large for one execution, finish the current safe unit of work, document the remaining tasks and continue in subsequent sessions without repeating the repository audit.

Avoid unnecessary repeated scans, huge rewrites and redundant tool calls.

---

# 27. REQUIRED FINAL DELIVERABLES

Provide:

1. Complete feature inventory.
2. Implementation status by module.
3. Architecture overview.
4. Database schema changes.
5. SQL migrations.
6. RLS and security changes.
7. Edge Functions.
8. Notification architecture.
9. Platform-specific notification setup instructions.
10. Flutter files modified.
11. Required environment variables.
12. Build and deployment instructions.
13. Test results.
14. Known limitations.
15. Remaining implementation roadmap.

For every notification platform, report separately:

| Platform | Foreground | Background | App closed | Required configuration |
|---|---|---|---|---|
| Android | Tested status | Tested status | Tested status | FCM/permissions |
| iOS | Tested status | Tested status | Tested status | APNs/entitlements |
| Linux | Tested status | Tested status | Tested status | Native integration |
| Windows | Tested status | Tested status | Tested status | Toast/app identity |
| macOS | Tested status | Tested status | Tested status | Native integration |
| Web | Tested status | Tested status | Tested status | Web Push/service worker |

Never mark a capability as working unless it has been verified on the actual target platform.

FINAL PRODUCT REQUIREMENT:

PenguinPeak must function as one connected enterprise platform, not a collection of disconnected demo screens.

An action in one module must trigger the appropriate workflows and notifications in other modules.

Examples:
- Leave application → manager approval → HR approval → balance update → employee notification.
- Task assignment → assignee notification → task progress → project progress update.
- New employee joining → onboarding workflow → manager notification → team calendar update.
- Birthday → scheduled event → dashboard update → appropriate employee notifications.
- Urgent chat message → persistent message → recipient notification → conversation deep link.

Prioritize correctness, security, reliability, usability and real functionality over the number of screens completed.
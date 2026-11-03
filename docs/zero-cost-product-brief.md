# PENGUINPEAK HRMS — ZERO-COST ENTERPRISE PLATFORM

## 1. PROJECT OBJECTIVE

Continue developing the existing partially completed Flutter application, PenguinPeak HRMS.

The product should combine:
- Keka-inspired HRMS functionality.
- OrangeScrum-inspired project and task management.
- Secure internal messaging.
- Centralized notifications.
- Employee engagement and company communication.

The application must be suitable for a maximum of 50 employees permanently.

This is an internal company application, not a public multi-tenant SaaS product.

## 2. HARD BUSINESS CONSTRAINTS

These constraints override all other architectural recommendations.

- Maximum users: 50, permanently.
- Maximum infrastructure budget: ₹0/year.
- No paid VPS.
- No paid database plans.
- No paid storage subscriptions.
- No paid API subscriptions.
- No paid notification services.
- No paid background workers.
- No paid third-party integrations.
- No automatic upgrades to paid plans.
- No architecture that requires future paid infrastructure to function.

Use free services and free-tier infrastructure only.

Before integrating any service:
1. Verify its current free allowance.
2. Check storage, bandwidth, database and execution limits.
3. Check inactivity and suspension policies.
4. Check whether the required feature actually works on the free plan.
5. Check whether exceeding a quota can cause automatic charges.
6. Document limitations and disable automatic paid upgrades wherever possible.

Never assume a free trial is a permanent free plan.

If a requested feature cannot be implemented reliably within ₹0/year, document the limitation and provide a genuinely free alternative. Never silently introduce paid dependencies.

## 3. EXISTING TECHNICAL STACK

Continue with:

Frontend:
- Flutter and Dart.
- Material 3.
- Android, iOS, Linux, Windows and macOS targets.
- Existing dark and light themes.
- Responsive desktop and mobile layouts.

Backend:
- Existing Supabase project.
- PostgreSQL.
- Supabase Authentication.
- Supabase Realtime.
- Supabase Storage.
- Existing Row Level Security.
- Existing SQL functions and migrations.

Do not migrate away from Supabase without first presenting a documented technical reason and receiving explicit approval.

Evaluate free storage extensions such as Cloudflare R2 only when required.

Do not introduce Firebase Firestore or another database merely for notifications.

## 4. USER AND CAPACITY MODEL

Design for a maximum of 50 employees.

Expected usage:
- Up to 50 authenticated users.
- Internal employee communication.
- Attendance and leave workflows.
- Project and task collaboration.
- Small group messaging.
- Employee documents.
- Limited internal image and video sharing.

Do not introduce Kubernetes, microservices, complex distributed systems or unnecessary infrastructure.

Prefer:
- PostgreSQL transactions.
- Indexed queries.
- Realtime subscriptions.
- Efficient pagination.
- Small, maintainable backend functions.
- Event-driven workflows.
- Simple scheduled processing.

The architecture must remain reliable at 50 concurrent users without unnecessary complexity.

## 5. EXISTING APPLICATION AUDIT

Inspect the existing project before modifying it.

Inspect:
- Flutter structure.
- Existing screens.
- Existing navigation.
- Supabase schema.
- SQL migrations.
- RLS policies.
- RPC functions.
- Storage buckets.
- Authentication.
- Dependencies.
- Existing notification code.
- Existing build configurations.

Existing modules include:
- Dashboard.
- Employee management.
- Organization.
- Attendance.
- Leave.
- Tasks.
- Chat.
- Company Wall.
- Team Calendar.
- Attendance Adjustments.
- Profile.
- Settings.

Discover the actual implementation instead of assuming every listed feature exists.

Create a concise feature audit with:
- Working.
- Partially working.
- Broken.
- Missing.
- Security concerns.
- Required dependencies.

Do not rewrite existing working modules unnecessarily.

## 6. COMPLETE FUNCTIONAL SCOPE

Retain the original master specification's complete feature scope.

Implement these modules progressively:

### HRMS
- Employee lifecycle.
- Employee profiles.
- Organization hierarchy.
- Departments and designations.
- Attendance.
- Shifts.
- Break management.
- Leave management.
- Multi-level leave approvals.
- Holidays.
- Payroll and payslips.
- Expenses and reimbursements.
- Recruitment.
- Onboarding.
- Performance management.
- Employee documents.
- Asset management.

### Project Management
- Projects.
- Project members.
- Tasks.
- Subtasks.
- Task assignments.
- Priorities.
- Deadlines.
- Dependencies.
- Kanban.
- Scrum.
- Sprints.
- Backlog.
- Milestones.
- Gantt/timeline.
- Timesheets.
- Time tracking.
- Project analytics.

### Communication
- One-to-one chat.
- Group chat.
- Images.
- Videos.
- Documents.
- File attachments.
- Message replies.
- Mentions.
- Reactions.
- Read receipts.
- Important and urgent messages.
- Company announcements.
- Company Wall.
- Polls.
- Praise and recognition.

### Dashboard
- Role-specific dashboards.
- Quick access.
- Attendance.
- Leave balances.
- Upcoming holidays.
- Birthdays.
- Anniversaries.
- New joiners.
- Company announcements.
- Tasks and projects.
- Notifications.

Preserve the existing Keka-inspired and OrangeScrum-inspired design direction while maintaining PenguinPeak branding.

## 7. CENTRALIZED NOTIFICATION SYSTEM

This is a critical requirement.

Build a unified notification architecture for:

- Leave applications.
- Manager approvals.
- HR approvals.
- Partial leave approvals.
- Final leave approvals.
- Leave rejections.
- Attendance regularization.
- Task creation.
- Task assignments.
- Task deadlines.
- Project updates.
- Chat messages.
- Urgent messages.
- Employee birthdays.
- Work anniversaries.
- New joiners.
- Announcements.
- Timesheet approvals.

Notification types:
- Normal.
- Important.
- Urgent.

Each notification must support:
- Title.
- Message.
- Recipient.
- Timestamp.
- Related record.
- Deep link.
- Priority.
- Read/unread status.

Implement:
- Persistent notification records.
- Notification centre.
- Realtime in-app updates.
- OS notification delivery.
- Notification preferences.
- Duplicate prevention.
- Retry handling.
- Secure recipient validation.

### Platform requirements

Android:
- FCM.
- Notification channels.
- Permission handling.
- Foreground/background notifications.
- Tap handling.

iOS:
- APNs/FCM.
- Notification permissions.
- Foreground presentation.
- Background handling.
- Tap handling.

Linux:
- Native desktop notifications.
- DBus/libnotify integration where appropriate.

Windows:
- Windows toast notifications.
- Application identity.
- Notification activation.

macOS:
- Native notification centre integration.
- Permission and signing requirements.

Important:
- Do not claim desktop closed-app push works just because foreground desktop notifications work.
- Identify the exact background delivery requirements for every platform.
- Do not introduce paid notification infrastructure.
- Clearly report unavailable capabilities.

## 8. STORAGE REQUIREMENTS

Use the existing Supabase Storage initially.

Evaluate free alternatives only when necessary.

Potential option:
- Cloudflare R2 free allowance for additional object storage.

Requirements:
- Private buckets.
- Secure file paths.
- Signed URLs.
- Storage access validation.
- File size validation.
- MIME type validation.
- Upload progress.
- Retry.
- Download handling.
- File metadata.

Use storage efficiently for:
- Profile photos.
- Employee documents.
- Chat attachments.
- Videos.
- Project documents.
- Payslips.
- Reports.

Never store sensitive files in public buckets.

Never introduce an automatically billable storage configuration.

## 9. SECURITY

Preserve and strengthen existing security.

- RLS on sensitive tables.
- Server-side authorization.
- Role-based access.
- Secure RPC functions.
- Private Storage.
- Audit logs.
- Secure notification dispatch.
- No service-role keys in Flutter.
- No privileged credentials in source code.
- No client-side role escalation.
- No unauthorized access to employee records.

Preserve existing user accounts and data.

## 10. DEVELOPMENT PHASES

Do not implement the entire platform in one uncontrolled operation.

PHASE 0 — AUDIT:
- Inspect the repository.
- Inspect the database.
- Create a module inventory.
- Identify build problems.
- Identify security problems.
- Identify missing integrations.
- Create a realistic implementation roadmap.

PHASE 1 — STABILITY:
- Fix existing errors.
- Preserve existing modules.
- Verify authentication.
- Verify Supabase connectivity.
- Verify RLS.
- Ensure Linux desktop build works.

PHASE 2 — WINDOWS TEST BUILD:
- Inspect Windows desktop support.
- Ensure the project supports Windows compilation.
- Verify all required Windows plugins.
- Generate a Windows release build using an actual Windows toolchain.
- Test the complete release bundle.
- Document any platform-specific issues.

PHASE 3 — CORE HRMS:
- Employee management.
- Organization.
- Attendance.
- Leave.
- Approval workflows.

PHASE 4 — PROJECT MANAGEMENT:
- Projects.
- Tasks.
- Kanban.
- Scrum.
- Milestones.
- Time tracking.

PHASE 5 — COMMUNICATION:
- Chat.
- Attachments.
- Company Wall.
- Announcements.

PHASE 6 — NOTIFICATIONS:
- Central event system.
- Notification centre.
- Android and iOS push.
- Desktop notification integrations.
- Scheduled birthdays and anniversaries.

PHASE 7 — ADVANCED HR:
- Payroll.
- Expenses.
- Recruitment.
- Onboarding.
- Performance.
- Documents.
- Assets.

PHASE 8 — REPORTING AND POLISH:
- Analytics.
- Exports.
- Global search.
- Responsive design.
- Testing.
- Performance optimization.

## 11. WINDOWS BUILD REQUIREMENTS

The current development environment is Ubuntu 24.04 with Flutter stable.

Linux builds are supported locally.

Windows release builds must be generated using a real Windows environment with the required Visual Studio C++ toolchain.

Do not attempt to create a Windows executable by renaming a Linux binary.

Prepare the Windows project files and verify plugin compatibility.

Provide exact Windows build instructions:

flutter pub get

flutter build windows --release --dart-define-from-file=supabase.env.json

Expected output:

build/windows/x64/runner/Release/

The entire Release folder must be distributed, not only the EXE.

Do not include privileged secrets in the build.

## 12. STRICT EXECUTION RULES

- Work in the existing repository.
- Inspect before editing.
- Do not rebuild the application from scratch.
- Do not rewrite entire files for small changes.
- Do not duplicate database tables.
- Do not create redundant migrations.
- Do not weaken security.
- Do not introduce paid dependencies.
- Do not use fake production data.
- Do not claim incomplete features are complete.
- Do not silently skip errors.
- Use minimal targeted patches.
- Reuse existing dependencies.
- Avoid repeated repository scans.
- Run relevant tests after changes.
- Preserve existing data and configuration.

## 13. FIRST ACTION — START NOW

For the first execution, perform PHASE 0 only.

Do not begin building all missing modules immediately.

Deliver:

1. Actual project structure.
2. Existing module inventory.
3. Current database and storage architecture.
4. Existing security review.
5. Missing and broken features.
6. Current Linux build status.
7. Windows build readiness.
8. Free-tier capacity risks.
9. Notification feasibility by platform.
10. Recommended next implementation task.

After the audit, immediately begin the smallest safe, high-priority fix that can be completed without risking existing data.

Do not wait for another general instruction to perform the audit.

If a migration, credential, account permission or external configuration requires explicit user action, stop only at that dependency and provide exact instructions.

## 14. FINAL PRINCIPLE

PenguinPeak is designed for 50 employees and ₹0/year infrastructure spending.

Prioritize:
1. Correct functionality.
2. Security.
3. Data integrity.
4. Reliable notifications.
5. Zero-cost operation.
6. Maintainability.
7. Good UI/UX.

Do not over-engineer a 50-user application.

Build a connected, usable HRMS and project management system, not a collection of demo screens.
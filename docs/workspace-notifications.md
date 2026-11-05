# Workspace notifications — 4 November 2026

Notifications are created by database triggers in the same transaction as the
saved event. They are never manufactured by Flutter clients. The bell uses the
existing recipient-only inbox, read state, and clear/dismiss behavior. Existing
leave application/review/cancellation notifications remain in place.

## Events and recipients

| Event | Recipient |
| --- | --- |
| Onboarding assigned | Assigned employee |
| Onboarding completed | Approved HR/admin staff |
| Payslip published | That employee only |
| Private letter published | That employee only |
| Company policy published | Approved employees, excluding publisher |
| Private letter acknowledged | Its publisher, if still HR/admin |
| Helpdesk ticket opened/reopened | Approved HR/admin staff |
| Helpdesk ticket created on someone's behalf | Ticket owner |
| Helpdesk ticket in progress/resolved | Ticket owner |
| Task assigned or reassigned | New assignee |
| Task started, declined, blocked or completed | Creator/assignee, excluding actor; assignment and simultaneous status update produce one alert for the new assignee |
| New chat message | Approved conversation participants except sender |
| Attendance adjustment/correction submitted | HR/admin staff and the assigned reporting manager |
| Attendance adjustment/correction approved/rejected | Request owner |
| Company announcement from HR/admin/management | Approved employees except author |

Self-alerts, pending/rejected accounts, unsupported roles, ordinary wall posts,
company-policy acknowledgement storms, routine checklist saves, and attachment
uploads do not produce notifications. Reopening and resolving a ticket again
produces a new event; retrying an unchanged status does not. No reminders or
scheduled/background job has been introduced.

## Privacy and navigation

New device alerts contain generic summaries, not salary amounts, document names,
private ticket titles/notes, or chat content. Inbox rows contain an allowlisted
destination and source record identifier. A tap on mobile push, a local system
alert, the web link, or the inbox opens the appropriate workspace page. HR records,
tasks and conversations open their specific saved item. Attendance requests and
announcements are brought to the top of the relevant page.

Push click data is not trusted for authorization: Flutter fetches the signed-in
recipient's saved notification, then the target page loads records under RLS.
Unavailable targets show a message. The push dispatcher also rechecks approved
account/role and access to HR records or chat membership before delivery. Already
read/dismissed notices and unsupported destinations are skipped. New notifications
have unique recipient/event keys; source events cannot be sent by anonymous or
ordinary authenticated clients through the private emission helper.

The old `leave_requests` Android channel remains for existing leave alerts. Other
updates use `hrms_updates`. Normal chat messages use normal FCM transport priority;
urgent messages marked by the existing chat UI use high priority. Background Android chat
alerts share a conversation tag to replace earlier alerts for that conversation. Existing
in-app chat presentation remains unchanged.

## Activation

No live migration, Edge Function deployment, or actual message send was performed
while implementing/testing this change.

1. Make sure both selected-HR migrations and existing notification/leave migrations
   are installed; see [HR module setup](hr-modules-release.md).
2. Install the new app (or publish the new web build), so the new destinations and
   Android channel are available.
3. Deploy the updated existing dispatcher **before enabling the new triggers**:

   ```bash
   supabase functions deploy send-leave-push --no-verify-jwt
   ```

   The function retains its old name so the existing notification INSERT webhook
   does not need to be renamed. It still requires `x-webhook-secret` matching
   `PUSH_WEBHOOK_SECRET`, plus the existing Supabase/FCM service credentials.
   No credential is included in the Flutter build.
4. Apply `supabase/migrations/202611040003_workspace_notifications.sql` once. It
   adds the nullable target ID and allows a null legacy leave reference for
   non-leave notifications. It does not backfill or notify old records.
5. Keep the existing `public.notifications` **INSERT** webhook pointing to
   `send-leave-push`. Do not create a second webhook for each source table: that
   would duplicate delivery. If transport has never been configured, follow
   [notification transport setup](notification-setup.md).
6. Verify two real accounts: HR publishes a payslip for an employee; employee opens
   a ticket; HR resolves it; a chat participant sends a message. Confirm recipient,
   unread badge, destination, and system alert with the app foreground/background.

Without configured push transport, saved notifications still appear in the bell
when the app is running (20-second refresh and a refresh on resume). Existing
local device alerts can display newly discovered notices. Delivery while the app
is closed requires the existing Firebase/webhook transport and device permission;
SQL alone does not enable it.

## Local validation

```bash
flutter test
flutter analyze
node scripts/test_workspace_notifications.mjs /path/to/pglite/dist/index.js
node scripts/test_push_dispatch.mjs /path/to/typescript/lib/typescript.js
```

The SQL tests use isolated PostgreSQL fixtures; push tests execute the actual
handler with mocked credentials/network. No notification has been sent to a real
employee as part of these checks. Physical-device and live Supabase acceptance
remain deployment work.

Latest local results: 94 Flutter tests, 35 isolated SQL notification checks and
17 mocked push-handler checks passed. The configured Android release APK built
successfully. Existing analyzer informational findings remain; no errors or
warnings were reported.

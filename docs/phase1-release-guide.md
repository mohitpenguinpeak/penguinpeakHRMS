# PenguinPeak — consolidated Phase 1 / leave stabilization release

This is one release package for the audited current app. It is NOT completion of
the entire enterprise product brief. Production data is preserved. SQL, clients,
permissions and function deployment must be coordinated as described below.

## Included

- Approved-account push registration, explicit account role gates.
- Prevent profile self-approval and non-HR employment/manager changes.
- Validate manager approval and reporting-chain cycles even for direct HR updates.
- Remove client TRUNCATE grants; restrict holiday writes to approved HR/admin.
- Participant-only chat metadata/messages; no self-invites; atomic direct chats.
- Enable message publication for Realtime behind membership RLS.
- Use the existing reviewed account-approval RPC in dashboard approval actions.
- Leave days calculated/validated server-side; serialize application checks and
  reject overlapping active leave. Preserve full calendar-day semantics.
- Preserve request/balance locking and deduct only on final HR approval.
- Leave applied → assigned manager notification; manager approval → HR queue and
  employee update; manager rejection → employee; HR result → employee.
- Stable per-stage event keys prevent duplicate notification rows on replay.
- Sender skips suspended recipients; logs safe auth/provider failure categories,
  sent/failed counts and setup stage, never credentials or device tokens.
- Existing inbox/read/clear, Android OS foreground alerts and desktop local alerts.

Existing historical notifications are retained, including HR notifications sent
under the old application-time rule. Historical leave quantities are not rewritten.
Partial days/approval, cancellation/refunds, accrual, retry queue, scheduled events,
private documents and native Windows/Linux closed-process agents are NOT included.
No tax/payroll or jurisdiction rules are invented. See the broader roadmap.

## 1. Review and stage the single SQL bundle

Use `supabase/deploy/phase1_release.sql`. It is generated from migrations 004–006;
do NOT also apply those migrations individually to the same database. The bundle
is outside `migrations` so migration tools do not apply it a second time.

Prerequisites match your supplied export: migrations 001–003 already represented,
including profile_details, notifications.dismissed_at, push_tokens and existing
leave/chat tables. New create_direct_conversation/event_key must not exist. The
bundle rejects already/partly installed releases rather than guessing migration
history. If using a migration runner, apply only missing incremental files in
order and skip the bundle. Reconcile your normal migration history after a manual
SQL-editor release; do not replay 004–006 automatically later.

First use a staging project/copy and your normal backup procedure. Open the
bundle, paste its entire contents into SQL Editor and Run once. It runs in ONE
transaction; failure rolls back the bundle. No business rows are deleted.
Do not paste test fixtures into the SQL Editor. They create synthetic test data
and belong only to the isolated test runner.

## 2. Deploy the updated sender

From the Flutter project directory:

```bash
npx supabase functions deploy send-leave-push --remote=fohwesyhwdbpocgqliwg --no-verify-jwt --use-api
```

The project ref is the production ref from existing configuration. Use your actual
STAGING ref first if staging. The function's x-webhook-secret verification MUST
remain enabled. Required server secrets remain:

- `FCM_SERVICE_ACCOUNT_JSON`: complete private Firebase service-account JSON.
- `PUSH_WEBHOOK_SECRET`: the original secret VALUE, not its SHA256 digest.
- `HRMS_WEB_URL`: optional HTTPS web companion URL, not needed for native Android.

Supabase supplies server DB credentials. Never include privileged values in Flutter.
The existing INSERT webhook must target public.notifications, use POST and header
`x-webhook-secret` with exactly the server secret value. No APK change can repair
401. With this deployed sender, logs distinguish NOT_CONFIGURED, HEADER_MISSING
and MISMATCH. Do not remove authentication to silence the error.

## 3. Build/install coordinated clients

```bash
flutter pub get
flutter test --no-pub
flutter build apk --release --dart-define-from-file=supabase.env.json --dart-define=PUSH_ENABLED=true
```

Android APK: `build/app/outputs/flutter-apk/app-release.apk`. Install/update the app,
sign in as manager/HR and enable push in the bell. Confirm push_tokens registration.
Test local OS permission with Enable and test device alerts.

Linux development:

```bash
flutter run -d linux --dart-define-from-file=supabase.env.json
```

Build Windows on Windows; build/sign macOS and iOS on a Mac using the notification
setup guide. Clients use the new chat RPC; old clients can no longer create direct
conversations after the hardening migration. Existing history is preserved.
Use a coordinated maintenance release and update active clients. Do not restore
unsafe membership inserts to support old clients. App already uses the existing
review_employee RPC rather than direct approval field updates.

## 4. End-to-end acceptance checklist

Use separate employee, assigned manager, unrelated employee and HR accounts.

1. Pending account cannot self-approve/register push. Employee can change personal
   phone/profile fields but not approval, manager, department or employment data.
2. Employee A cannot read/join B's private chat. HR is denied unless a participant.
   Two participants can create/reopen a direct chat and exchange live messages.
3. Employee cannot edit holidays. Approved HR/admin can.
4. Employee applies NEW non-overlapping full-day leave: manager gets notification;
   HR gets no new application-stage notification. Balance is unchanged.
5. Manager approves: employee gets update, HR gets pending approval notification;
   balance still unchanged. Unrelated manager is denied.
6. HR approves: employee gets final notification; balance deducted exactly once.
   Repeat review is rejected. Manager rejection does not deduct balance or notify
   HR. Insufficient balance leaves request pending HR and balance unchanged.
7. Try mismatched leave days through an authorized test API call: rejected. Try
   an overlapping active request: rejected. Existing full-day UI remains valid.
8. Android recipient open: OS notification shade and inbox; background: actual FCM
   alert. A local test notification is NOT proof of remote delivery. Check sender
   logs for auth failure/provider code or sent count and compare a fresh event.
9. Check a suspended user's old token does not cause new push dispatch. Historical
   inbox access/revocation across other modules still needs broader policy work.
10. Test clear-inbox; saved rows are hidden per recipient, other inboxes unaffected.

## 5. Evidence and limits

The combined bundle is exercised in isolated PostgreSQL/PGlite with exported
business function baselines and synthetic users. These tests do not connect to
production, deliver push messages or prove cross-connection concurrency. Target
platform delivery still requires actual device/browser tests and setup.

Run SQL regression checks using a test runtime outside this repository:

```bash
npm install --prefix /tmp/penguinpeak-sql-validation @electric-sql/pglite typescript@5.9.3
python3 scripts/build_phase1_bundle.py
node scripts/test_access_hardening.mjs /tmp/penguinpeak-sql-validation/node_modules/@electric-sql/pglite/dist/index.js
node scripts/test_push_dispatch.mjs /tmp/penguinpeak-sql-validation/node_modules/typescript/lib/typescript.js
python3 -m unittest discover -s scripts -p 'test_*.py'
flutter test --no-pub
```

The sender tests mock external dependencies; they validate handler branches and
channel payloads, not Firebase credentials or physical OS delivery.

The full enterprise roadmap is in enterprise-implementation-status.md. Core
security/leave stabilization is one unit; payroll, projects/sprints/timesheets,
expanded chat/wall and reliable native desktop background services remain future
phases. Do not label this package production-verified until staging and actual
client acceptance checks pass.

## Actual validation result for this package

- 42 isolated PostgreSQL security/leave checks: passed.
- 10 sender handler checks with mocked dependencies: passed.
- 7 Flutter tests: passed.
- 3 Python configuration generator tests: passed.
- No production deployment or real target remote-delivery test performed.

**Environment note:** the existing `supabase.qa.env.json` and `supabase.env.json`
currently point to the same Supabase backend. Merely choosing the QA filename
is NOT staging isolation. Use a separate project/ref and configuration for staging.

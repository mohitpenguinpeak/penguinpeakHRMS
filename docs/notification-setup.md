# Notification transport setup

Current event routing is described in [Workspace notifications](workspace-notifications.md),
including onboarding, payslips, helpdesk, documents, tasks, chat, attendance and
announcements. Leave notifications follow the staged manager → HR workflow.
This guide covers the shared transport and permissions; follow the current
release migration guides as well as the initial transport setup. Nothing is emailed.

## 1. Understand the two parts

- **In-app inbox:** the bell inside HRMS. Supabase saves these notifications so
  they are still there after signing out, closing the app, or changing computers.
- **Device alert:** the popup shown by Android, iOS, macOS, Windows, Linux, or the
  browser. An alert is a reminder to open HRMS; the bell remains the saved record.

The current implementation supports the following:

| Device/app | While open or minimized | After HRMS closes |
| --- | --- | --- |
| Android | Inbox and Firebase push | Firebase push, subject to OS restrictions |
| iPhone/iPad | Inbox and Firebase push | Firebase/APNs push, subject to OS restrictions |
| Native macOS app | Inbox, local alerts; Firebase push after Apple setup | Firebase/APNs push after Apple setup, subject to OS restrictions |
| Native Windows app | Inbox and local desktop alerts | Use the browser push companion below |
| Native Linux app | Inbox and local desktop alerts | Use the browser push companion below |
| Web app on a supported desktop browser | Inbox and browser push | Service-worker push after closing the HRMS tab, if browser/OS permits background delivery |

**Windows/Linux users must enable the web companion once to get alerts while the
native app is closed.** This does not install a Windows/Linux background daemon.
If the browser is fully stopped, background execution is disabled, the device is
asleep/offline, or notifications are blocked, immediate delivery is not guaranteed.
A separately installed background agent would be needed to remove the browser
requirement; that is not implemented here. No notification system can deliver a
visible alert to a powered-off computer.

Start with the database and Linux test. Add Firebase after the bell works.

## 2. Prepare three test accounts

1. Open your existing HRMS app as an administrator or HR user.
2. Have one approved employee, one approved manager, and one approved HR account.
3. Edit the employee profile and assign their reporting manager.
4. In Supabase → **Table Editor → profiles**, verify:
   - Employee `manager_id` is the manager profile's `id`.
   - The HR profile has `role = hr`.
   - Both recipient profiles have `approval_status = approved`.
5. Use separate devices or browser profiles for each account. Logging into a
   different account in the same browser profile changes that browser's recipient.

## 3. Add the database tables and leave trigger

A **migration** is a SQL file that changes the database structure.

1. Open the Supabase dashboard for the project used by this app.
2. Open **SQL Editor → New query**.
3. Open this repository file in your editor:
   `supabase/migrations/202611030001_leave_notifications.sql`.
4. Copy the entire file into the SQL editor and click **Run** once.
5. Create another query and run:
   `supabase/migrations/202611030002_push_tokens.sql`.
6. Open **Table Editor**. You should now see `notifications` and `push_tokens`.
7. Do not disable row-level security. It prevents users reading another person's
   alerts and device tokens. The app only supplies public Supabase credentials.

If your migration tool already applied these files, do not run them again. A
"table already exists" message means you should inspect migration history first.
Old leave applications are not automatically converted into notifications.

## 4. Try the bell and local desktop alerts first

From the project directory on Linux:

```bash
flutter pub get
flutter run -d linux --dart-define-from-file=supabase.env.json
```

Use your existing QA defines file instead if testing against QA.

1. Sign in as the manager or HR.
2. Click the notification bell in the top bar.
3. Click **Enable and test device alerts**.
4. Allow notifications if asked. Look for a test popup in your desktop's
   notification area. The button reports that it sent a test; OS settings can
   still hide it.
5. Leave the dashboard running; minimizing is fine. Do not close the process.
6. On another device/account, submit a **new** leave request as the employee.
7. Wait up to 20 seconds. The recipient should see a popup and an unread badge.
8. Click the bell entry. It should open Leave Management and mark that entry read.
9. Check HR and the manager, and verify an unrelated employee cannot see it.

Existing notifications on initial login populate the inbox without a popup storm.
New unread notifications discovered during that running session produce alerts.
Desktop alerts are polled every 20 seconds, not guaranteed instant delivery.

Other native desktop run commands (execute on the corresponding OS):

```bash
flutter run -d windows --dart-define-from-file=supabase.env.json
flutter run -d macos --dart-define-from-file=supabase.env.json
```

- **Linux:** run inside a normal GNOME/KDE desktop session with its notification
  server and session D-Bus running. A headless SSH session is not sufficient.
- **Windows:** enable app notifications in Settings → System → Notifications.
  Focus/Do Not Disturb may suppress popups. Package and test release builds as
  MSIX for a stable app identity and reliable notification management.
- **macOS:** allow HRMS in System Settings → Notifications. The project includes
  outgoing-network sandbox entitlements required to reach Supabase.

## 5. Create your Firebase project

Firebase is Google's service that transports remote push messages. Supabase
continues to store leave requests, notification history, and recipient tokens.

1. Open https://console.firebase.google.com/ and sign in with your Google account.
2. Click **Create a project** / **Add project**.
3. Choose a name such as `PenguinPeak HRMS` and complete the wizard. Google
   Analytics is optional for this feature.
4. Open the project gear → **Project settings → General**.
5. Note your **Project ID**. Use this same project for all apps and server keys.

Menu wording can vary. The official setup references are linked at the end.

## 6. Register a web app for Windows/Linux closed-app alerts

This is also useful for macOS users who do not want to configure Apple signing.

1. In Firebase Project settings → General → Your apps, click the **Web (`</>`)**
   icon. Name it `HRMS web companion` and register it.
2. Copy the public web config values: `apiKey`, `appId`, `messagingSenderId`, and
   `projectId`. These identify your Firebase web app; they are not a server key.
3. Open Project settings → **Cloud Messaging → Web configuration / Web Push
   certificates** and generate a key pair. Copy the **public** key (VAPID key).
4. In this repository, copy `firebase-web-config.example.json` to
   `firebase-web-config.json`. Replace its five placeholder values with those
   from steps 2–3. Keep valid JSON: double quotes, commas, no trailing comma.
5. Generate the two files the app and background worker need:

   ```bash
   python3 scripts/configure_web_push.py firebase-web-config.json
   ```

   Expected output:
   `Generated web/firebase-public-config.js and firebase.web.env.json`.
   Do not use a Firebase service-account/private-key JSON file as input.
6. Test the web app locally:

   ```bash
   flutter run -d chrome --web-port=8080 --dart-define-from-file=supabase.env.json --dart-define-from-file=firebase.web.env.json
   ```

7. Sign in as HR/manager. Open the bell and click **Enable push notifications**.
   Click **Allow** in the browser prompt. This explicit click is required by
   browsers; the app does not request web permission at page load.
8. In Supabase Table Editor → `push_tokens`, verify that the recipient now has a
   registration. Treat tokens as private; do not share screenshots containing them.
9. If registration fails, open browser developer tools → Console and check the
   Firebase project values, VAPID key, permission, and service-worker errors.

For actual use, deploy an HTTPS web build at the **root of a domain**, for example
`https://hrms.yourcompany.example/`:

```bash
flutter build web --dart-define-from-file=supabase.env.json --dart-define-from-file=firebase.web.env.json
```

Upload the **contents** of `build/web` to your web host. Firebase Hosting is one
option: install Firebase CLI, run `firebase login`, `firebase init hosting`, set
public directory to `build/web`, configure as a single-page app, and do not
replace the generated index file. Then run `firebase deploy --only hosting`.
If choosing that host, review the displayed Firebase plan/quotas first.

Verify both `/firebase-messaging-sw.js` and `/firebase-public-config.js` return
JavaScript, not an HTML fallback or 404. Ordinary HTTP is not enough outside
localhost. This worker currently assumes root-domain hosting, not a subfolder.

On **each HR/manager computer**, open the deployed site in a supported browser,
sign in, and enable push. Allow browser background activity in browser/OS settings
where available. Keep that browser profile signed in; signing out unregisters it.
You can then close the HRMS web tab and native app. Test delivery explicitly on
each supported OS/browser. Installing the site as a PWA can make it convenient
to launch, but is not a guarantee that a fully stopped browser receives alerts.

## 7. Give Supabase permission to send Firebase push

A **service account** lets your server send messages. Its private key is secret.

1. In Firebase Project settings → Cloud Messaging, ensure the **Firebase Cloud
   Messaging API (V1)** is enabled. Follow its Google Cloud link if necessary.
2. Open Project settings → **Service accounts → Firebase Admin SDK → Generate
   new private key**. Download it to a secure location outside this repository.
3. In Supabase → **Edge Functions → Secrets**, add:

   | Secret | Value |
   | --- | --- |
   | `FCM_SERVICE_ACCOUNT_JSON` | Full contents of the downloaded service-account JSON |
   | `PUSH_WEBHOOK_SECRET` | A long random secret, shared only with your database webhook |
   | `HRMS_WEB_URL` | Your HTTPS HRMS web address, e.g. `https://your-site.web.app/` |

4. To generate the webhook secret locally, run:

   ```bash
   python3 -c 'import secrets; print(secrets.token_urlsafe(32))'
   ```

5. Keep this value in your password manager. Do not put any of these private
   credentials into Flutter Dart defines, browser scripts, source control, or chat.
   `HRMS_WEB_URL` itself is public. Never put a Supabase service-role key in the app.

## 8. Deploy the server function

An **Edge Function** is server-side code hosted by Supabase. It looks up the
recipient's devices and sends a Firebase message to each one.

1. Install Supabase CLI using the instructions for your OS:
   https://supabase.com/docs/guides/local-development/cli/getting-started
2. From this repository, run:

   ```bash
   supabase login
   supabase functions deploy send-leave-push --project-ref YOUR_PROJECT_REF --no-verify-jwt
   ```

3. Replace `YOUR_PROJECT_REF` with the reference shown in your Supabase project
   URL/settings. It is an identifier, not the project password.
4. Confirm `send-leave-push` appears under Edge Functions in the dashboard.

The command disables Supabase user-JWT checking for this webhook endpoint. The
function instead requires your private `x-webhook-secret` header. Do not remove
that check. Supabase automatically provides the function's database URL and
service-role credential; you do not add them to client configuration.

## 9. Connect the database webhook

A **webhook** tells the server function when a notification row is created.

1. Open Supabase → **Database → Webhooks**. Enable webhooks if prompted.
2. Create a webhook named `send_leave_push`.
3. Select schema `public`, table `notifications`, event **INSERT** only.
4. Choose the `send-leave-push` Edge Function, or use its HTTPS function URL
   shown in the Edge Functions dashboard. Use method **POST**.
5. Keep the default database webhook JSON payload.
6. Add header `Content-Type: application/json` if it is not supplied by default.
7. Add header `x-webhook-secret` with exactly your `PUSH_WEBHOOK_SECRET` value.
8. Save. Do not put this webhook on `leave_requests`: the function expects the
   recipient-specific `notifications` INSERT payload.

There are now two stages: leave INSERT → notification rows → webhook → push.
Push failures do not undo a leave application or delete its in-app notification.

## 10. Android setup

Android push is now enabled by default in new builds. An explicit
`--dart-define=PUSH_ENABLED=false` still disables it. Rebuild/reinstall older
APKs; hot reload cannot change compile-time configuration.

1. In Firebase Project settings, add an Android app with package name
   `com.example.penguinpeak_hrms` (the current project application ID).
2. Install the Firebase CLI, sign in with `firebase login`, then install FlutterFire:

   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```

3. Select the same Firebase project and Android (plus Apple targets if needed).
4. Confirm `android/app/google-services.json` exists and FlutterFire configured
   the Google Services Gradle plugin. FlutterFire's generated configuration must
   match the native package/application ID.
5. Run:

   ```bash
   flutter run -d YOUR_ANDROID_DEVICE_ID --dart-define-from-file=supabase.env.json --dart-define=PUSH_ENABLED=true
   ```

   Get device IDs using `flutter devices`.
6. Sign in as a recipient and allow notifications. You can retry using the bell's
   **Enable push notifications** button. Use a device/emulator with Google Play
   services. Background the app and submit leave from the employee account.

## 11. iOS and native macOS remote push setup

These steps require a Mac, Xcode, Apple signing, and an Apple developer account
with push capability. You can use the web companion on macOS instead.

1. Register each Apple app in Firebase using its real Runner bundle identifier
   shown in Xcode. Android, iOS, and macOS identifiers are not interchangeable.
2. Run `flutterfire configure` and choose iOS/macOS for the same project.
3. Ensure each target includes its own `GoogleService-Info.plist` in the Runner
   target. This code uses native default `Firebase.initializeApp()` configuration.
4. Open `ios/Runner.xcworkspace` or `macos/Runner.xcworkspace` in Xcode.
5. Runner → Signing & Capabilities: select your team and enable **Push
   Notifications**. For iOS, enable Background Modes → Remote notifications.
6. Ensure the provisioning profile and push entitlement match the target and
   signing environment. Let Xcode manage signing if you are new to this.
7. Create an APNs authentication key in your Apple Developer account and upload
   it in Firebase Project settings → Cloud Messaging for the relevant Apple app,
   along with its key ID and team ID. Keep the `.p8` key private.
8. Run the app with `--dart-define=PUSH_ENABLED=true` and your Supabase defines.
9. Allow notifications, then click **Enable push notifications** again if Apple
   registration was not ready on the first attempt.
10. Verify background/closed-app delivery on actual signed devices/builds.

The current Linux environment cannot validate Apple provisioning or build Xcode
projects. Windows builds also need validation on Windows.

## 12. End-to-end test and troubleshooting

1. Enable push on the manager's and HR's devices/browser profiles.
2. Close the HRMS browser tab/native app for the closed-app test. Keep desktop
   browser background delivery allowed. On phones, do not force-stop the app in
   OS settings; force-stop can prevent delivery until reopened.
3. Submit a **new** employee leave application.
4. Check Supabase `notifications`: one row for each expected recipient.
5. Check `push_tokens`: expected recipients have registered devices.
6. Check Edge Function logs and webhook delivery status.
7. Confirm OS alerts on both recipient devices.
8. Click an alert. Native push opens Leave Management. Browser push opens the
   configured HRMS site; sign in if required, then open the bell/Leave screen.
9. Reopen HRMS and confirm the saved notification is present. Opening a bell
   entry marks it read; dismissing an OS alert does not mark the inbox read.
10. Sign out on a shared device and verify subsequent alerts do not reach it.

| Symptom | What to check |
| --- | --- |
| No notification rows | Migration applied, correct Supabase project, approved HR and manager, employee manager assignment |
| Rows exist, no local popup | App still running, wait 20 seconds, system permissions/Do Not Disturb, click test button |
| Rows exist, no remote push | Token registered, webhook INSERT configured, shared secret matches, server credential belongs to same Firebase project |
| Web token cannot register | HTTPS/localhost, VAPID public key, browser permission, worker scripts return JS, root-domain hosting |
| Web works open but not closed | Browser/OS background policy, browser profile still signed in, not a fully stopped/unsupported browser |
| Apple push fails | APNs key, bundle ID, signing/provisioning, push capability, retry registration after APNs token exists |
| Duplicate device alerts | Same person registered multiple installations, local native app and browser companion both running, or webhook replay |

This initial delivery function logs failures but has no scheduled retry queue.
Webhook replay can duplicate pushes to devices already reached. Test notification
privacy on lock screens because alerts include employee name, leave type, dates.

## Official references

- [Firebase Flutter setup](https://firebase.google.com/docs/flutter/setup)
- [Firebase Flutter messaging](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)
- [Firebase web messaging and service workers](https://firebase.google.com/docs/cloud-messaging/web/get-started)
- [Supabase Database Webhooks](https://supabase.com/docs/guides/database/webhooks)
- [Desktop notification plugin setup and limitations](https://pub.dev/packages/flutter_local_notifications)

# Stability phase release — Linux and Android first

User priorities: Linux/Android first; Windows source/build preparation next;
iOS/macOS work deferred because no Apple hardware/Xcode is available. The user
also confirmed no Windows computer is available. ₹0/year infrastructure ceiling
and 50-employee limit remain in force. No paid runner, remote machine or new
service is introduced. Notification delivery troubleshooting stays deferred.

## Changes completed locally

- Splash now opens a session gate. Saved sessions are checked against their own
  database profile before opening the dashboard; absent sessions open Login.
- Existing password login checks approval/role once and hands the verified result
  to the gate rather than performing an immediate duplicate profile request.
- Role changes replace the dashboard state. Rejected/pending/missing/unknown-role
  profiles cannot enter the dashboard. Lookup errors show retry/sign-out rather
  than granting cached access or displaying an empty demo screen.
- Access rechecks on app resume, auth token/user changes, and every five minutes
  while the app is foreground/approved. Checks are coalesced for the same session.
  A later result cannot reopen a logged-out account or replace a different user's
  profile. Duplicate sign-out events do not dismiss signup's success route.
- Blocked/error/signed-out gates close nested workspace routes such as a profile
  dialog so stale employee data does not remain above the login/blocked view.
- Best-effort device registration cleanup no longer prevents local logout on an
  error. The installed SDK clears its local session before remote revocation;
  network errors are suppressed only after that local removal succeeded. Other
  devices are not claimed signed out, and durable token cleanup still needs the
  later notification lifecycle work. The sender already skips unapproved users.

These are client access/UX safeguards. PostgreSQL policies/RPCs remain the actual
security boundary; no UI timer provides instantaneous revocation by itself.
Offline verification fails closed and Retry can recover when connectivity returns.

## Database migration 008

`202611030008_session_access_and_employee_capacity.sql` depends on 004–007:

- Adds restrictive approved-account policies to existing business tables. They
  combine with existing ownership/membership/HR policies; no broad access grant
  replaces a scoped policy. Pending users can still select their own profile for
  login/approval messaging. Existing public profile-photo objects are unaffected;
  private employee document separation remains future work.
- Enforces at most **50 approved accounts**, including employee, manager, HR and
  admin seats. Pending/rejected records are retained for review/history and are
  not active seats. This is not a cap of 50 total Auth registrations; signup
  admission/rate-limiting and employment lifecycle remain separate work.
- Counts under a transaction advisory lock for approval/approved inserts. An
  attempted 51st approval is rejected; it does not revoke existing employees or
  silently delete records. A preflight rejects an already-over-cap database for
  explicit HR reconciliation. Existing data is not automatically changed.
- Policies cover the current known business tables; future modules must add their
  own scoped approval policies. Approval cannot replace row ownership checks.

New UI revocation detection can take up to five minutes while continuously open;
resume/auth changes can recheck sooner. Server table access is denied as soon as
an account becomes unapproved once migration 008 is installed. Existing reviewed
business RPCs independently check approved caller state. Test actual JWT sessions
in staging; running SQL as postgres is not a live RLS acceptance test.

## Deployment — choose one path, not both

First back up using the normal company procedure and use a genuinely separate
staging project. Current QA/main defines point at the same backend.

1. **004–007 already installed:** run only migration 008 once in the SQL editor or
   normal migration pipeline. Do not replay any earlier combined release.
2. **None installed (last supplied export):** use the single generated
   `supabase/deploy/stability_release.sql` transaction for 004–008 instead of older
   bundles. Its guard refuses a partially/already installed base release.
3. **Partly installed:** reconcile migration history and apply only missing files
   in timestamp order. Do not run bundles blindly or reset production data.

After SQL, rebuild/install clients. No new secrets or Edge Function deployment is
required for this unit. Existing notification failures are not a prerequisite for
session/seat testing and are not being debugged here.

```bash
flutter pub get
flutter test --no-pub
flutter run -d linux --dart-define-from-file=supabase.env.json
flutter build apk --release --dart-define-from-file=supabase.env.json --dart-define=PUSH_ENABLED=true
```

Manual acceptance with test users:

- Approved login, close/reopen: dashboard restores after approval verification.
- No saved session: login shown, no cross-user dashboard flashes.
- HR revokes a test account: that account loses business-table access; on resume
  or next gate check it sees the blocked screen, including closing nested routes.
- Change a test user's role via authorized RPC: next check reloads the proper role.
- Disconnect network and resume: error/retry, no unverified cached approval. Restore
  connectivity and Retry: access recovers only if database approval is valid.
- Logout while optional device cleanup fails: local session still clears. Reopen:
  no prior dashboard. Test signup and its success/back/login navigation as well.
- On a synthetic staging population, fill 50 approved seats; next approval fails.
  Follow HR's actual offboarding/account process to release a seat. Do not reject
  real employees just to exercise a capacity test.

## Windows preparation and exact blocker

`windows/` runner and plugin metadata remain. Added
`scripts/build_windows_release.ps1` for a future real Windows workstation. It
rejects non-Windows hosts, checks for public-only configuration, runs dependency
resolution/tests/build, verifies required release files and archives the complete
Release folder with SHA256. It does not buy software, use paid CI, upload source,
or assert MSIX/signing/remote-notification support.

When an existing Windows machine becomes available, install appropriately licensed
Visual Studio C++ tooling and matching Flutter, then use:

```powershell
.\scripts\build_windows_release.ps1
```

If company policy blocks PowerShell scripts, use the manual commands from
windows-build-guide.md within that policy:

```powershell
flutter pub get
flutter build windows --release --dart-define-from-file=supabase.env.json
```

Expected: build/windows/x64/runner/Release/ and the entire folder distributed.
The helper's archive path is build/artifacts/PenguinPeak-Windows-x64.zip.
PowerShell/helper execution and actual Windows compilation are UNTESTED here.
The lack of a Windows host is an external validation dependency, not a reason to
introduce a paid VM or rename a Linux binary. Phase 2 cannot be certified complete.
Apple targets are preserved but intentionally not configured/tested in this unit.

## Tests and scope limits

Session tests cover startup, approval/role refresh, revoked state, network retry,
query coalescing, account/logout/dispose races, duplicate auth events and cleanup
failure. SQL fixtures cover prior security/leave scenarios, rejected-user isolation
against a legacy permissive wall policy, approved-user continuity and the seat cap.
These are synthetic tests, not production account manipulation or load testing.

The modified Flutter files are login_screen.dart, splash_screen.dart,
role_dashboard_screen.dart and new features/auth/{data,application,presentation}
components. No package dependency or provider billing setting changed. Existing
Supabase credentials/configuration remain in place, without secret values in logs.
Broader private-data/RPC/attendance concerns from the audit remain on the roadmap.
No platform is newly claimed to support remote push or closed-app delivery.

## Recorded validation

- Full Flutter suite: 29 tests passed. The focused 12-session-test suite also passed
  after the final disposed-controller guard, including no lookup after disposal.
- PostgreSQL fixture: 67 checks passed on both upgrade and fresh stability-bundle
  paths. Includes a representative legacy wall SELECT-true policy to verify that
  restrictive approval rules deny revoked users without denying approved users.
- Linux debug bundle builds; real backend sessions and manual UX still require
  staging acceptance. No production migration was applied.
- PowerShell execution and Windows release build remain untested: user has no
  Windows workstation. No iOS/macOS work was undertaken.

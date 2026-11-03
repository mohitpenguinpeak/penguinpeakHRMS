# Windows release readiness and build instructions

Status: Windows runner and declared plugin support inspected; actual compilation
and release testing NOT performed. This workstation is Linux. A Linux executable
cannot be converted into a Windows executable by renaming it. No paid build VM,
runner or subscription was configured.

## Prerequisites on an actual Windows machine

Use existing company hardware/appropriately licensed Windows and developer tools.
Do not buy anything or start a trial/cloud VM for this workflow. Review developer
tool licensing for the organization instead of assuming a personal free license
covers every company.

1. Install Flutter stable matching the project's tested version (currently
   3.47.8 / Dart 3.13.7), Git and Visual Studio.
2. In Visual Studio Installer enable **Desktop development with C++**, including
   its MSVC build tools, Windows SDK and CMake components. Visual Studio Code
   alone is not the Windows C++ toolchain.
3. Open PowerShell in the project checkout and run:

   ```powershell
   flutter doctor -v
   flutter devices
   ```

   Resolve Windows/Visual Studio errors. The Windows desktop target must appear.
   [Official Flutter Windows setup](https://docs.flutter.dev/platform-integration/windows/setup).

## Dependency audit

Generated plugin metadata declares Windows implementations for app_links,
firebase_core, flutter_local_notifications_windows, jni, path_provider_windows,
shared_preferences_windows and url_launcher_windows. Do not hand-edit generated
registrants. Run pub get on Windows so native dependencies are generated there.
JNI/FFI/CMake/native build tools must be validated by a real build. Firebase
Messaging is not a Windows push transport; production app logic uses Supabase and
local toast integration. Firebase core remains a native dependency even though
Windows Firebase initialization is skipped; review compilation/runtime behavior.

## Build the entire release bundle

The local supabase.env.json must contain only public SUPABASE_URL and
SUPABASE_PUBLISHABLE_KEY. Never use a server-secret file as Dart defines. Point to
a staging backend for initial tests; QA/main files in the current Linux workspace
refer to the same backend, so the filename is not isolation.

```powershell
flutter pub get
flutter build windows --release --dart-define-from-file=supabase.env.json
```

Expected folder:

```text
build/windows/x64/runner/Release/
```

It must contain the .exe, required DLLs, data directory and plugin/native assets.
Distribute **the complete Release folder**, not the EXE alone. For a local archive:

```powershell
Compress-Archive -Path build/windows/x64/runner/Release/* -DestinationPath PenguinPeak-Windows-x64.zip -Force
```

Test on a separate Windows user/machine that does not have the development
checkout. Follow Flutter's [Windows distribution instructions](https://docs.flutter.dev/platform-integration/windows/building)
for runtime redistributables. Portable builds may show OS trust warnings; do not
claim trusted publisher signing or MSIX identity exists just because the EXE runs.
No paid signing service is assumed. OS security prompts belong to the user.

## Actual release acceptance

Record Windows version, Flutter version, build command/output and test result:

- App starts from the Release folder and archive on another machine.
- Supabase login, pending-account denial and logout; public credentials only.
- Employee/profile, actual holiday list/error retry, attendance/leave/task screens.
- New chat RPC and participant isolation after required SQL migration is applied.
- Leave dates/balances/cancellation match actual backend state after migration 007.
- Resizing, light/dark theme, keyboard navigation and file paths.
- Local test toast visible; activation opens the correct app view.
- Closed-process notification delivery is NOT implemented by the local plugin.

If packaging as MSIX later, validate application identity and activation against
the toast plugin. Non-MSIX local notifications have notification-management
limitations; do not infer remote background delivery from packaging.

Until the actual Windows build/test occurs, record Phase 2 as unverified/blocked
on access to the Windows workstation. Do not attach a fabricated Windows binary.

## Latest availability and helper

The user confirmed no Windows machine is available. Actual release compilation
and script execution therefore remain unverified. No paid runner/VM was added.
A local helper is prepared at scripts/build_windows_release.ps1 for later use;
it validates public client configuration, runs tests/build and archives the whole
Release directory with a SHA256 file. It is not a produced Windows artifact.
See stability-phase-release.md for current staging/migration prerequisites.

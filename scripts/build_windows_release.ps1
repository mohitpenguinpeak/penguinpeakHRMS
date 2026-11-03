# Run only on a real Windows machine with Flutter + Visual Studio C++ installed.
# No cloud runner, paid service, signing subscription or secret upload is used.
param([string]$DefinesFile = 'supabase.env.json', [switch]$SkipTests)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'A real Windows environment is required.' }
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    if (-not (Test-Path $DefinesFile)) { throw 'Public Supabase configuration file is missing.' }
    $config = Get-Content $DefinesFile -Raw | ConvertFrom-Json
    foreach ($property in $config.PSObject.Properties) {
        if ($property.Name -match '(SERVICE_ROLE|PRIVATE_KEY|PASSWORD|WEBHOOK_SECRET|FCM_SERVICE_ACCOUNT|SUPABASE_SECRET)') {
            throw 'Privileged configuration must never be compiled into the client.'
        }
    }
    if (-not $config.SUPABASE_URL -or -not $config.SUPABASE_PUBLISHABLE_KEY) {
        throw 'SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY are required.'
    }
    $publicKey = [string]$config.SUPABASE_PUBLISHABLE_KEY
    if ($publicKey.StartsWith('sb_secret_')) { throw 'Use a public Supabase key, never a server secret.' }
    if ($publicKey.StartsWith('eyJ')) {
        try {
            $payloadPart = $publicKey.Split('.')[1].Replace('-', '+').Replace('_', '/')
            $payloadPart = $payloadPart.PadRight($payloadPart.Length + ((4 - $payloadPart.Length % 4) % 4), '=')
            $payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payloadPart)) | ConvertFrom-Json
        } catch { throw 'The legacy public JWT key is malformed.' }
        if ($payload.role -ne 'anon') { throw 'Only an anon/public client key may be compiled.' }
    }
    flutter doctor -v
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
    if (-not $SkipTests) {
        flutter test --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'Tests failed; release was not built.' }
    } else { Write-Warning 'Tests explicitly skipped for this build.' }
    flutter build windows --release "--dart-define-from-file=$DefinesFile"
    if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed.' }
    $release = 'build/windows/x64/runner/Release'
    foreach ($entry in @('penguinpeak_hrms.exe', 'flutter_windows.dll', 'data')) {
        if (-not (Test-Path (Join-Path $release $entry))) { throw "Release is incomplete: missing $entry" }
    }
    New-Item -ItemType Directory -Force 'build/artifacts' | Out-Null
    $archive = 'build/artifacts/PenguinPeak-Windows-x64.zip'
    Compress-Archive -Path "$release/*" -DestinationPath $archive -Force
    $hash = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  PenguinPeak-Windows-x64.zip" | Set-Content 'build/artifacts/PenguinPeak-Windows-x64.sha256'
    Write-Host "Release folder: $release"
    Write-Host "Complete distribution archive: $archive"
    Write-Host 'Actual Windows user/device acceptance testing is still required.'
} finally { Pop-Location }

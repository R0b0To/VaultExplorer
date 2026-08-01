# Canonical release-APK build procedure for Windows PowerShell.
# Used for byte-for-byte build reproduction and local testing.
#
# Prerequisites (infra/toolchain installs):
#   - JDK 17 on PATH or JAVA_HOME set
#   - Flutter 3.44.0 with `flutter` on PATH
#   - Android NDK r28d (28.2.13676358) installed
#   - Node.js 26 on PATH (optional if assets/pdfjs is already built)

$ErrorActionPreference = "Stop"

# Navigate to repo root (one level up from script directory)
Set-Location (Join-Path $PSScriptRoot "..")

Write-Host "== Toolchain versions in use =========================="
java -version 2>&1 | Write-Host
flutter --version
if (Get-Command node -ErrorAction SilentlyContinue) {
    node --version
} else {
    Write-Host "node: not on PATH (fine if assets/pdfjs is already built)"
}
Write-Host "========================================================"

# Embedded timestamps: derive from commit timestamp if not set
if (-not $env:SOURCE_DATE_EPOCH) {
    $env:SOURCE_DATE_EPOCH = (git log -1 --format=%ct).Trim()
}
$epochDateTime = ([DateTimeOffset]::FromUnixTimeSeconds([long]$env:SOURCE_DATE_EPOCH)).UtcDateTime
Write-Host "SOURCE_DATE_EPOCH=$env:SOURCE_DATE_EPOCH ($epochDateTime UTC)"

# Set default PUB_CACHE under repository root if not already defined
if (-not $env:PUB_CACHE) {
    $env:PUB_CACHE = Join-Path (Get-Location).Path ".pub-cache"
}
Write-Host "PUB_CACHE=$env:PUB_CACHE"

flutter config --no-analytics
flutter pub get

# taskset is Linux-specific; display a warning on Windows
Write-Warning "taskset not found on Windows -- R8 output may not match a build that used CPU core pinning"

# Build release APK
flutter build apk --release --target-platform android-arm64

$APK = "build\app\outputs\flutter-apk\app-release.apk"
Write-Host "Built: $APK"

# Verification: Check that .note.gnu.build-id was removed
$VerifyDir = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $VerifyDir | Out-Null

try {
    Expand-Archive -Path $APK -DestinationPath $VerifyDir -Force
    $fail = 0

    $soFiles = Get-ChildItem -Path "$VerifyDir\lib\*\libdartjni.so" -ErrorAction SilentlyContinue
    $readElfCmd = Get-Command readelf, llvm-readelf -ErrorAction SilentlyContinue | Select-Object -First 1

    foreach ($so in $soFiles) {
        if (-not (Test-Path $so.FullName)) { continue }

        $hasBuildId = $false

        if ($readElfCmd) {
            $output = & $readElfCmd.Name -W -S $so.FullName 2>&1
            if ($output -match '\.note\.gnu\.build-id') {
                $hasBuildId = $true
            }
        } else {
            # Fallback if readelf isn't on PATH: string search inside binary
            $content = [System.IO.File]::ReadAllText($so.FullName, [System.Text.Encoding]::ASCII)
            if ($content.Contains(".note.gnu.build-id")) {
                $hasBuildId = $true
            }
        }

        if ($hasBuildId) {
            Write-Error "error: $($so.FullName) still has .note.gnu.build-id -- reproducibility patch didn't apply"
            $fail = 1
        }
    }

    if ($fail -ne 0) {
        exit 1
    }

    Write-Host "OK: $APK"
} finally {
    if (Test-Path $VerifyDir) {
        Remove-Item -Recurse -Force $VerifyDir
    }
}
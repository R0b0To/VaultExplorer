#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',

    [string]$Msys2Root = $env:MSYS2_ROOT,

    # Force `flutter pub get`, even when .dart_tool/package_config.json exists.
    [switch]$PubGet,

    # Launch the freshly built app after copying the engine DLL.
    [switch]$Run
)

$ErrorActionPreference = 'Stop'

function Assert-NativeSuccess {
    param([string]$Step)
    if ($LASTEXITCODE -ne 0) {
        throw "$Step failed with exit code $LASTEXITCODE."
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$cppSource = Join-Path $repoRoot 'android\app\src\main\cpp'
$engineBuild = Join-Path $repoRoot 'build\desktop-engine-win'
$appOutput = Join-Path $repoRoot "build\windows\x64\runner\$Configuration"
$engineDll = Join-Path $engineBuild 'vaultexplorer_engine.dll'
$appExe = Join-Path $appOutput 'vaultexplorer.exe'

$msysRoots = @()
if (-not [string]::IsNullOrWhiteSpace($Msys2Root)) {
    $msysRoots += $Msys2Root
}
$msysRoots += @('C:\msys64', 'C:\msys2')

$ucrtBin = $null
$msysUsrBin = $null
foreach ($root in $msysRoots) {
    $candidateUcrtBin = Join-Path $root 'ucrt64\bin'
    $candidateUsrBin = Join-Path $root 'usr\bin'
    if ((Test-Path (Join-Path $candidateUcrtBin 'cmake.exe')) -and
        (Test-Path (Join-Path $candidateUcrtBin 'ninja.exe')) -and
        (Test-Path (Join-Path $candidateUcrtBin 'gcc.exe')) -and
        (Test-Path (Join-Path $candidateUcrtBin 'g++.exe'))) {
        $ucrtBin = $candidateUcrtBin
        $msysUsrBin = $candidateUsrBin
        break
    }
}

if (-not $ucrtBin) {
    throw @"
MSYS2 UCRT64 tools were not found. Install MSYS2 UCRT64 with:
  pacman -S --needed mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja mingw-w64-ucrt-x86_64-gcc git
Then rerun this script, or pass -Msys2Root with your MSYS2 install folder.
"@
}

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    throw 'Flutter was not found on PATH. Add Flutter bin to PATH, reopen PowerShell, then retry.'
}

$runningApp = @(Get-Process -Name 'vaultexplorer' -ErrorAction SilentlyContinue)
if ($runningApp.Count -gt 0) {
    $ids = ($runningApp | ForEach-Object { $_.Id }) -join ', '
    throw "VaultExplorer is running (PID $ids). Close it before rebuilding so the executable and DLL can be replaced."
}

$cmake = Join-Path $ucrtBin 'cmake.exe'
$originalPath = $env:PATH
$previousLocation = Get-Location
try {
    # CMake and Ninja run as Windows programs; adding UCRT64 first lets CMake find the MinGW compilers.
    $env:PATH = "$ucrtBin;$msysUsrBin;$originalPath"
    Set-Location $repoRoot

    $packageConfig = Join-Path $repoRoot '.dart_tool\package_config.json'
    if ($PubGet -or -not (Test-Path $packageConfig)) {
        Write-Host 'Preparing Flutter packages...'
        & $flutter.Source pub get
        Assert-NativeSuccess 'flutter pub get'
    }

    Write-Host 'Configuring the Windows engine DLL...'
    & $cmake -S $cppSource -B $engineBuild -G Ninja `
        '-DVAULTEXPLORER_DESKTOP=ON' '-DCMAKE_BUILD_TYPE=Release'
    Assert-NativeSuccess 'CMake configure for vaultexplorer_engine.dll'

    Write-Host 'Building vaultexplorer_engine.dll...'
    & $cmake --build $engineBuild --target vaultexplorer
    Assert-NativeSuccess 'CMake build for vaultexplorer_engine.dll'
    if (-not (Test-Path $engineDll)) {
        throw "The engine build succeeded but the DLL was not found at $engineDll."
    }

    Write-Host "Building the Flutter Windows app ($Configuration)..."
    if ($Configuration -eq 'Debug') {
        & $flutter.Source build windows --debug
    } else {
        & $flutter.Source build windows --release
    }
    Assert-NativeSuccess 'Flutter Windows build'

    if (-not (Test-Path $appOutput)) {
        throw "Flutter build succeeded but the output folder was not found: $appOutput"
    }

    $bundledDll = Join-Path $appOutput 'vaultexplorer_engine.dll'
    try {
        Copy-Item -LiteralPath $engineDll -Destination $bundledDll -Force
    } catch {
        throw "Could not copy the new engine DLL to $bundledDll. Close any app using that DLL, then rerun. Details: $($_.Exception.Message)"
    }

    Write-Host "Engine DLL: $bundledDll"
    Write-Host "Windows app: $appExe"

    if ($Run) {
        if (-not (Test-Path $appExe)) {
            throw "The app executable was not found at $appExe."
        }
        $previousEngineLibrary = [Environment]::GetEnvironmentVariable('VE_ENGINE_LIBRARY', 'Process')
        try {
            $env:VE_ENGINE_LIBRARY = $engineDll
            $process = Start-Process -FilePath $appExe -WorkingDirectory $appOutput -PassThru
            Write-Host "Started VaultExplorer (PID $($process.Id))."
        } finally {
            if ($null -eq $previousEngineLibrary) {
                Remove-Item Env:VE_ENGINE_LIBRARY -ErrorAction SilentlyContinue
            } else {
                $env:VE_ENGINE_LIBRARY = $previousEngineLibrary
            }
        }
    }
} finally {
    Set-Location $previousLocation
    $env:PATH = $originalPath
}

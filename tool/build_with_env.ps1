<#
.SYNOPSIS
    Builds SPECTA, injecting secrets from a local .env file as --dart-define.

.DESCRIPTION
    The app reads its build-time secrets with String.fromEnvironment (see
    lib/core/tmdb/tmdb_providers.dart). This script reads a developer-owned
    .env from the project root and forwards each entry to the Dart compiler as
    a --dart-define.

    The .env file is NEVER bundled into the app:
      * it is git-ignored,
      * it is not listed in pubspec assets, so it never becomes an app asset,
      * only the values it defines are passed to the compiler.

    The resulting binary DOES contain the key, because that is what a
    compile-time constant means. Treat a shipped APK as containing the secret.

.PARAMETER Target
    Flutter target (apk, appbundle, ...). Defaults to apk.

.PARAMETER Release
    Build a RELEASE binary. This is the default: `flutter build` defaults to
    release, and this switch only makes that explicit. A release build requires
    android/key.properties (see build.gradle.kts and docs/RELEASE.md).

.PARAMETER DebugBuild
    Build a DEBUG binary instead. Needed whenever the app must be installed with
    assertions and diagnostics on, but still with the .env secrets injected
    (there was previously no way to do this: the script always produced a
    release artifact while printing "debug").

    Named `-DebugBuild` rather than `-Debug` because `-Debug` is a PowerShell
    COMMON parameter on any [CmdletBinding()] script: declaring it locally is a
    metadata error ("parameter with the name 'Debug' was defined multiple
    times") and the script refuses to load at all.

.PARAMETER OtherArgs
    Extra arguments passed straight through to `flutter build`.

.EXAMPLE
    .\tool\build_with_env.ps1

.EXAMPLE
    .\tool\build_with_env.ps1 -DebugBuild

.EXAMPLE
    .\tool\build_with_env.ps1 -Target appbundle -Release
#>
[CmdletBinding()]
param(
    [string]$Target = 'apk',
    [switch]$Release,
    [switch]$DebugBuild,
    [string[]]$OtherArgs = @()
)

$ErrorActionPreference = 'Stop'

if ($Release -and $DebugBuild) {
    throw '-Release and -DebugBuild are mutually exclusive; pick the artifact you want.'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $projectRoot '.env'

if (-not (Test-Path -LiteralPath $envFile)) {
    Write-Host "No .env found at $envFile" -ForegroundColor Yellow
    Write-Host 'Continuing without injected secrets; the build will simply report' -ForegroundColor Yellow
    Write-Host 'the catalogue as unconfigured.' -ForegroundColor Yellow
}

# Collect defines without ever echoing a value.
$defines = @()
$defineNames = @()
if (Test-Path -LiteralPath $envFile) {
    foreach ($line in Get-Content -LiteralPath $envFile) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }

        $separator = $trimmed.IndexOf('=')
        if ($separator -lt 1) { continue }

        $name = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1).Trim().Trim('"').Trim("'")

        if ($name -eq '' -or $value -eq '') { continue }
        $defines += "--dart-define=$name=$value"
        $defineNames += $name
    }
}

# SAFETY: only NAMES are ever printed, so a build log proves what was injected
# without disclosing any value. The names are collected as they are parsed rather
# than recovered from `$defines`, because splitting a define back apart risks
# echoing the value.
if ($defineNames.Count -gt 0) {
    Write-Host ("Injecting build-time defines: " + ($defineNames -join ', ')) -ForegroundColor Green
} else {
    Write-Host 'No build-time defines to inject.' -ForegroundColor Yellow
}

$flutter = Join-Path 'H:\flutter' 'bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutter)) {
    $flutter = 'flutter'
}

# The build mode is passed EXPLICITLY instead of being left to Flutter's
# default. `flutter build` defaults to RELEASE, so the previous version of this
# script always produced a release artifact while printing "(debug)" — a log
# line that claimed something the build did not do, which is precisely what this
# project forbids. Existing invocations still get a release binary; the default
# is now stated rather than assumed, and `-DebugBuild` makes a debug build possible.
$buildMode = if ($DebugBuild) { 'debug' } else { 'release' }
$args = @('build', $Target, "--$buildMode")
$args += $defines
$args += $OtherArgs

# SAFETY: the assembled command line is NEVER echoed. `--dart-define=NAME=VALUE`
# contains the secret, so printing `$args` would leak the key into the terminal,
# scrollback, CI logs and any transcript of this session. Only the define NAMES
# (printed above) are safe to show.
# NOTE: plain string concatenation rather than the `? :` ternary, which Windows
# PowerShell 5.1 does not support.
$mode = " ($buildMode)"
Write-Host "Running: flutter build $Target$mode" -ForegroundColor DarkGray

# `$ErrorActionPreference = 'Stop'` (set above, so a missing .env or a bad
# argument fails loudly) must NOT be left in force across the native call.
# `flutter` always writes its Kotlin-Gradle-Plugin deprecation notice to STDERR,
# and in Windows PowerShell 5.1 any STDERR line from a native command becomes a
# terminating NativeCommandError under 'Stop'. The script therefore reported
# FAILURE — and never reached `exit $LASTEXITCODE` — on builds that actually
# SUCCEEDED, truncating the build log at the first warning while Gradle quietly
# finished in the background. Error handling is restored to Stop immediately
# after, and the real exit code is propagated.
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $flutter @args
$buildExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousPreference

exit $buildExitCode

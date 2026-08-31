# build_web_app.ps1 - Builds the Flutter web UI (as the HTCommander-hosted build)
# and stages it for the desktop app's built-in web server to serve at the root.
#
# The desktop web server (lib/services/web/web_server_io.dart) serves the
# Flutter web build from disk. In order of preference it looks for:
#   1. the `webAppPath` setting (device 0),
#   2. a `web_app` folder next to the executable,
#   3. `build/web` under the working directory (dev convenience).
#
# The build is produced with --dart-define=HTC_HOSTED=true so it connects back
# to the host over the WebSocket bridge instead of using Web Bluetooth.
#
# During development you only need to run this script once - the server picks up
# `build/web` automatically. For a packaged desktop build, pass -Stage to also
# copy the output next to a target executable (or into ./web_app).
#
# Usage:
#   ./tools/build_web_app.ps1                 # flutter build web (served in dev)
#   ./tools/build_web_app.ps1 -Wasm           # build with the wasm renderer
#   ./tools/build_web_app.ps1 -Stage          # also copy build/web -> ./web_app
#   ./tools/build_web_app.ps1 -Stage -Dest "C:\path\to\app\web_app"

[CmdletBinding()]
param(
    [switch]$Wasm,
    [switch]$Stage,
    [string]$Dest
)

$ErrorActionPreference = 'Stop'

# Resolve the Flutter project root (parent of this tools/ folder).
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    $buildArgs = @(
        'build', 'web',
        '--base-href', '/',
        '--dart-define', 'HTC_HOSTED=true'
    )
    if ($Wasm) {
        $buildArgs += '--wasm'
    } else {
        # The vendored flutter_tts web plugin trips the WebAssembly dry-run
        # (unrelated to this app's code), which makes the default JS build exit
        # non-zero. Skip the dry-run for the JS build.
        $buildArgs += '--no-wasm-dry-run'
    }

    Write-Host "Running: flutter $($buildArgs -join ' ')" -ForegroundColor Cyan
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "flutter build web failed (exit $LASTEXITCODE)" }

    $buildWeb = Join-Path $projectRoot 'build/web'
    Write-Host "Flutter web build ready at: $buildWeb" -ForegroundColor Green

    if ($Stage) {
        if ([string]::IsNullOrWhiteSpace($Dest)) {
            $Dest = Join-Path $projectRoot 'web_app'
        }
        if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
        New-Item -ItemType Directory -Force -Path $Dest | Out-Null
        Copy-Item -Recurse -Force (Join-Path $buildWeb '*') $Dest

        # De-duplicate: the desktop app already carries its own pubspec assets
        # and serves them from rootBundle (see web_server_io.dart), so drop the
        # copy the web build bundled under assets/assets/ to avoid shipping them
        # twice. Engine files (manifests, fonts, packages) under assets/ stay.
        $dupAssets = Join-Path $Dest 'assets/assets'
        if (Test-Path $dupAssets) { Remove-Item -Recurse -Force $dupAssets }

        Write-Host "Staged web build to: $Dest (shared assets served from host)" -ForegroundColor Green
    }
}
finally {
    Pop-Location
}

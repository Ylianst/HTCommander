# Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
param([switch]$BuildOnly, [switch]$UpdateGoldens)

$ErrorActionPreference = 'Stop'
$src = Split-Path $PSScriptRoot -Parent
$root = Split-Path $src -Parent
$reference = Join-Path $root 'reference'
$archive = Join-Path $reference 'sbc-2.2.tar.xz'
$upstream = Join-Path $reference 'sbc-2.2'
$build = Join-Path $reference 'sbc-comparison'
$hash = 'A1ADA76EF35E5AF9C2FBD063754DC9E37A8D989417C6EB1ECEBB089B1383AE9E'

New-Item -ItemType Directory -Force $reference, $build | Out-Null
if (-not (Test-Path $archive)) {
    & curl.exe --fail --location --output $archive 'https://www.kernel.org/pub/linux/bluetooth/sbc-2.2.tar.xz'
    if ($LASTEXITCODE -ne 0) { throw 'BlueZ SBC download failed' }
}
if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $hash) {
    throw 'BlueZ SBC archive SHA256 mismatch'
}
# Always rebuild from the verified archive, rather than a potentially edited tree.
& tar.exe -xf $archive -C $reference
if ($LASTEXITCODE -ne 0) { throw 'BlueZ SBC extraction failed' }

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Visual Studio x64 C++ build tools are required' }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
$compat = Join-Path $PSScriptRoot 'sbc_reference_msvc.h'
$codec = Join-Path $upstream 'sbc\sbc.c'
$primitives = Join-Path $upstream 'sbc\sbc_primitives.c'
$dll = Join-Path $build 'bluez_sbc.dll'
$exports = 'sbc_init', 'sbc_init_msbc', 'sbc_finish', 'sbc_encode', 'sbc_decode', 'sbc_get_implementation_info'
$link = ($exports | ForEach-Object { "/EXPORT:$_" }) -join ' '
$command = "call `"$vcvars`" >nul && cd /d `"$build`" && cl /nologo /std:c11 /O2 /LD /FI`"$compat`" `"$codec`" `"$primitives`" /link /OUT:`"$dll`" $link"
& $env:ComSpec /d /c $command
if ($LASTEXITCODE -ne 0) { throw 'BlueZ SBC build failed' }
Write-Host "Built BlueZ SBC 2.2 (generic C); archive SHA256 $hash"
$googleRevision = '6e505650145c9973d08a0bdd5e5f5e1914305e40'
$google = Join-Path $reference "google-libsbc-$googleRevision"
if (-not (Test-Path $google)) {
    & git init $google
    if ($LASTEXITCODE -ne 0) { throw 'Google SBC checkout initialization failed' }
    & git -C $google fetch --depth 1 'https://github.com/google/libsbc.git' $googleRevision
    if ($LASTEXITCODE -ne 0) { throw 'Google SBC download failed' }
    & git -C $google checkout --detach FETCH_HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Google SBC checkout failed' }
}
$revision = & git -C $google rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $revision -ne $googleRevision) {
    throw 'Google SBC checkout revision mismatch'
}
$dirty = & git -C $google status --porcelain --untracked-files=all
if ($LASTEXITCODE -ne 0 -or $dirty) { throw 'Google SBC checkout must be unmodified' }
$googleDll = Join-Path $build 'google_sbc.dll'
$googleCodec = Join-Path $google 'src\sbc.c'
$googleBits = Join-Path $google 'src\bits.c'
$googleInclude = Join-Path $google 'include'
$adapter = Join-Path $PSScriptRoot 'sbc_google_reference.c'
$command = "call `"$vcvars`" >nul && cd /d `"$build`" && cl /nologo /std:c11 /O2 /LD /FI`"$compat`" /I`"$googleInclude`" `"$googleCodec`" `"$googleBits`" `"$adapter`" /link /OUT:`"$googleDll`""
& $env:ComSpec /d /c $command
if ($LASTEXITCODE -ne 0) { throw 'Google SBC build failed' }
Write-Host "Built Google SBC at $googleRevision"
if ($BuildOnly) { return }

Push-Location $src
try {
    $arguments = @('run', 'tool\sbc_reference_compare.dart', $dll, $googleDll, $build)
    if ($UpdateGoldens) { $arguments += '--write-goldens' }
    & dart @arguments
    if ($LASTEXITCODE -eq 2) { throw 'Google SBC differences found; inspect google-comparison.json' }
    if ($LASTEXITCODE -ne 0) { throw 'SBC reference comparison failed; inspect the JSON report' }
} finally {
    Pop-Location
}

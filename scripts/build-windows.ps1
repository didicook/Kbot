<#
.SYNOPSIS
Builds the Windows installers for Kbot: a setup .exe (NSIS) and an .msi.

.DESCRIPTION
Run it on a Windows PC from the repo folder:

  powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1              # this PC's architecture
  powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1 -Arch x64    # 64-bit Intel/AMD
  powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1 -Arch arm64  # Windows on ARM (setup .exe only)
  powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1 -Bundles nsis

The installers are copied to release\ as Kbot_<version>_<arch>-setup.exe and
Kbot_<version>_<arch>.msi.

What the PC needs (see https://tauri.app/start/prerequisites/):
  - Microsoft C++ Build Tools with "Desktop development with C++"
  - Rust from https://rustup.rs (the default MSVC toolchain)
  - Node.js 22.6 or later
  - WebView2, which comes with Windows 10 and 11
The Tauri CLI downloads NSIS and WiX by itself the first time. Building the
.msi needs the VBSCRIPT Windows feature; if the .msi step fails, turn it on
under Settings > System > Optional features, or build with -Bundles nsis.

The installers are not code-signed, so Windows SmartScreen warns the first
time they run: click "More info", then "Run anyway". To sign them, set
bundle > windows > certificateThumbprint in src-tauri\tauri.conf.json
(see https://tauri.app/distribute/sign/windows/).

.PARAMETER Arch
x64 or arm64. Defaults to this PC's architecture.

.PARAMETER Bundles
Which installer to build: nsis (setup .exe) or msi. Leave it out to build both
on x64, or only nsis on arm64, because WiX can't build an .msi for ARM.
#>
[CmdletBinding()]
param(
  [ValidateSet('x64', 'arm64')]
  [string]$Arch,

  [ValidateSet('nsis', 'msi')]
  [string[]]$Bundles
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

function Die([string]$Message) {
  Write-Host "error: $Message" -ForegroundColor Red
  exit 1
}

# Runs a program and stops the script if it fails.
function Invoke-Checked([string]$Exe, [string[]]$Arguments) {
  & $Exe @Arguments
  if ($LASTEXITCODE -ne 0) { Die "$Exe $($Arguments -join ' ') failed (exit code $LASTEXITCODE)" }
}

if ($env:OS -ne 'Windows_NT') { Die 'the Windows installer can only be built on Windows' }

if (-not $Arch) {
  # PROCESSOR_ARCHITEW6432 is set when a 32-bit PowerShell runs on 64-bit Windows.
  $machine = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
  switch ($machine) {
    'AMD64' { $Arch = 'x64' }
    'ARM64' { $Arch = 'arm64' }
    default { Die "unsupported processor '$machine' (use -Arch x64 or -Arch arm64)" }
  }
}

switch ($Arch) {
  'x64'   { $target = 'x86_64-pc-windows-msvc';  $vcComponent = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64' }
  'arm64' { $target = 'aarch64-pc-windows-msvc'; $vcComponent = 'Microsoft.VisualStudio.Component.VC.Tools.ARM64' }
}

if (-not $Bundles) {
  $Bundles = if ($Arch -eq 'arm64') { @('nsis') } else { @('nsis', 'msi') }
}
if ($Arch -eq 'arm64' -and $Bundles -contains 'msi') {
  Die 'an .msi can''t be built for arm64; use -Bundles nsis'
}

foreach ($tool in 'node', 'npm', 'cargo', 'rustup') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    Die "$tool not found (see Getting started in README.md)"
  }
}

$nodeVersion = [version](& node -p 'process.versions.node')
if ($nodeVersion -lt [version]'22.6.0') { Die "Node.js 22.6 or later is needed (found $nodeVersion)" }

# Rust needs the MSVC linker from the C++ Build Tools.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) {
  $vs = & $vswhere -latest -products '*' -requires $vcComponent -property installationPath
  if (-not $vs) {
    Die "the C++ build tools for $Arch are missing. In Visual Studio Installer, add `"Desktop development with C++`"."
  }
} else {
  Write-Host 'warning: Visual Studio Installer not found, so the C++ build tools could not be checked.' -ForegroundColor Yellow
}

$installed = & rustup target list --installed
if ($installed -notcontains $target) {
  Invoke-Checked 'rustup' @('target', 'add', $target)
}

if (-not (Test-Path 'node_modules')) {
  Invoke-Checked 'npm' @('ci')
}

Invoke-Checked 'npx' @('tauri', 'build', '--target', $target, '--bundles', ($Bundles -join ','), '--ci')

$version = (Get-Content 'src-tauri\tauri.conf.json' -Raw | ConvertFrom-Json).version
$bundleDir = "src-tauri\target\$target\release\bundle"
New-Item -ItemType Directory -Force -Path 'release' | Out-Null

$outputs = @()
if ($Bundles -contains 'nsis') {
  $exe = Get-ChildItem "$bundleDir\nsis\*-setup.exe" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $exe) { Die "no setup .exe found in $bundleDir\nsis" }
  $out = "release\Kbot_${version}_${Arch}-setup.exe"
  Copy-Item $exe.FullName $out -Force
  $outputs += $out
}
if ($Bundles -contains 'msi') {
  $msi = Get-ChildItem "$bundleDir\msi\*.msi" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $msi) { Die "no .msi found in $bundleDir\msi" }
  $out = "release\Kbot_${version}_${Arch}.msi"
  Copy-Item $msi.FullName $out -Force
  $outputs += $out
}

Write-Host ''
foreach ($o in $outputs) { Write-Host "Installer: $o" }
Write-Host "App:       src-tauri\target\$target\release\kbot.exe"

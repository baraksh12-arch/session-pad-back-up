# Install SessionPad10 Remote Script (Ableton Live 10) to Ableton User Library.
# Run from PowerShell: .\install_live10.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Source = Join-Path $ScriptDir "SessionPad10"
$Dest = Join-Path $env:USERPROFILE "Documents\Ableton\User Library\Remote Scripts\SessionPad10"

if (-not (Test-Path $Source -PathType Container)) {
    Write-Error "SessionPad10 source not found at $Source"
    exit 1
}

$RemoteScriptsRoot = Join-Path $env:USERPROFILE "Documents\Ableton\User Library\Remote Scripts"
New-Item -ItemType Directory -Force -Path $RemoteScriptsRoot | Out-Null

if (Test-Path $Dest) {
    Remove-Item -Recurse -Force $Dest
}

robocopy $Source $Dest /E /XD __pycache__ vendor /XF .DS_Store | Out-Null
if ($LASTEXITCODE -ge 8) {
    Write-Error "robocopy failed with exit code $LASTEXITCODE"
    exit 1
}

Get-ChildItem -Path $Dest -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Installed SessionPad10 Remote Script to:"
Write-Host "  $Dest"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Launch SessionPad Bridge on your PC (Python bridge or SessionPadBridge.exe)"
Write-Host "  2. Fully quit Ableton Live 10 and reopen — toggling the control surface does NOT reload Python code"
Write-Host "  3. Live -> Preferences -> Link, Tempo & MIDI -> Control Surface: SessionPad10"
Write-Host "     (Use only ONE SessionPad10 entry — do not also select SessionPad unless you intend to)"
Write-Host "  4. Open SessionPad on iOS (same Wi-Fi)"
Write-Host "  5. Allow SessionPad Bridge through Windows Firewall if prompted"

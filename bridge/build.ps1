# Build SessionPadBridge.exe on Windows
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".venv")) {
    python -m venv .venv
}

& .\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
pip install pyinstaller

pyinstaller SessionPadBridge.spec --noconfirm

Write-Host ""
Write-Host "Built:"
Write-Host "  $PSScriptRoot\dist\SessionPadBridge.exe"
Write-Host ""
& "$PSScriptRoot\dist\SessionPadBridge.exe" --version

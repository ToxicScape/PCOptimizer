[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "Programs\PCOptimizer")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Force -Recurse
}

$desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "PC Optimizer.lnk"
$startMenuShortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\PC Optimizer.lnk"

foreach ($shortcut in @($desktopShortcut, $startMenuShortcut)) {
    if (Test-Path -LiteralPath $shortcut) {
        Remove-Item -LiteralPath $shortcut -Force
    }
}

Write-Host "PC Optimizer has been removed."

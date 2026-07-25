[CmdletBinding()]
param(
    [string]$SourceDir = "",
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "Programs\PCOptimizer"),
    [switch]$NoDesktopShortcut,
    [switch]$NoStartMenuShortcut
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SourceDir)) {
    $SourceDir = Split-Path -Parent $PSScriptRoot
}

function New-Shortcut {
    param(
        [string]$ShortcutPath,
        [string]$TargetPath,
        [string]$WorkingDirectory,
        [string]$Description
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = $Description
    $shortcut.Save()
}

if (-not (Test-Path -LiteralPath $SourceDir)) {
    throw "Source directory not found: $SourceDir"
}

if (-not (Test-Path -LiteralPath $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$itemsToCopy = @(
    "PCOptimizer.ps1",
    "Run-PCOptimizer.bat",
    "README.md",
    "appsettings.json",
    "version.json",
    "scripts"
)

foreach ($item in $itemsToCopy) {
    $sourcePath = Join-Path $SourceDir $item
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        continue
    }

    $destinationPath = Join-Path $InstallDir $item
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force -Recurse
}

if (-not $NoDesktopShortcut) {
    $desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "PC Optimizer.lnk"
    New-Shortcut -ShortcutPath $desktopShortcut -TargetPath (Join-Path $InstallDir "Run-PCOptimizer.bat") -WorkingDirectory $InstallDir -Description "Launch PC Optimizer"
}

if (-not $NoStartMenuShortcut) {
    $startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    $startMenuShortcut = Join-Path $startMenuDir "PC Optimizer.lnk"
    New-Shortcut -ShortcutPath $startMenuShortcut -TargetPath (Join-Path $InstallDir "Run-PCOptimizer.bat") -WorkingDirectory $InstallDir -Description "Launch PC Optimizer"
}

Write-Host ("Installed PC Optimizer to {0}" -f $InstallDir)
Write-Host "Run the app from the created shortcut or Run-PCOptimizer.bat."

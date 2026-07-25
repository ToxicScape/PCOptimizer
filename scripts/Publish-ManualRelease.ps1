[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$Version = "",
    [switch]$NoPush,
    [switch]$NoOpenReleasePage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}

function Get-VersionFilePath {
    param([string]$RootPath)
    return (Join-Path $RootPath "version.json")
}

function Get-AppSettingsPath {
    param([string]$RootPath)
    return (Join-Path $RootPath "appsettings.json")
}

function Get-VersionInfo {
    param([string]$RootPath)
    return (Get-Content -LiteralPath (Get-VersionFilePath -RootPath $RootPath) -Raw | ConvertFrom-Json)
}

function Save-VersionInfo {
    param(
        [string]$RootPath,
        [object]$VersionInfo
    )

    ($VersionInfo | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath (Get-VersionFilePath -RootPath $RootPath) -Encoding UTF8
}

function Get-ReleaseDraftUrl {
    param([string]$RootPath)

    $settings = Get-Content -LiteralPath (Get-AppSettingsPath -RootPath $RootPath) -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace([string]$settings.githubOwner) -or [string]::IsNullOrWhiteSpace([string]$settings.githubRepo)) {
        return $null
    }

    return ("https://github.com/{0}/{1}/releases/new" -f $settings.githubOwner, $settings.githubRepo)
}

function Invoke-Git {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory
    )

    $output = & git -C $WorkingDirectory @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ($output -join [Environment]::NewLine)
    }

    return @($output)
}

if (-not (Test-Path -LiteralPath $ProjectRoot)) {
    throw "Project root not found: $ProjectRoot"
}

$versionInfo = Get-VersionInfo -RootPath $ProjectRoot
if (-not [string]::IsNullOrWhiteSpace($Version)) {
    $versionInfo.version = $Version
    Save-VersionInfo -RootPath $ProjectRoot -VersionInfo $versionInfo
}

$currentVersion = [string](Get-VersionInfo -RootPath $ProjectRoot).version
$tagName = "v$currentVersion"

Write-Host ("Preparing release {0}" -f $tagName)

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectRoot "scripts\Build-Release.ps1")
if ($LASTEXITCODE -ne 0) {
    throw "Build-Release.ps1 failed."
}

$statusBeforeCommit = @(Invoke-Git -Arguments @("status", "--short") -WorkingDirectory $ProjectRoot)
if ($statusBeforeCommit.Count -gt 0) {
    [void](Invoke-Git -Arguments @("add", "-A") -WorkingDirectory $ProjectRoot)

    $stagedStatus = @(Invoke-Git -Arguments @("diff", "--cached", "--name-only") -WorkingDirectory $ProjectRoot)
    if ($stagedStatus.Count -gt 0) {
        [void](Invoke-Git -Arguments @("commit", "-m", ("Release {0}" -f $tagName)) -WorkingDirectory $ProjectRoot)
        Write-Host ("Committed release changes for {0}" -f $tagName)
    }
}

$tagExists = $false
try {
    [void](Invoke-Git -Arguments @("rev-parse", "--verify", ("refs/tags/{0}" -f $tagName)) -WorkingDirectory $ProjectRoot)
    $tagExists = $true
} catch {
    $tagExists = $false
}

if (-not $tagExists) {
    [void](Invoke-Git -Arguments @("tag", "-a", $tagName, "-m", ("Release {0}" -f $tagName)) -WorkingDirectory $ProjectRoot)
    Write-Host ("Created tag {0}" -f $tagName)
} else {
    Write-Host ("Tag {0} already exists. Skipping tag creation." -f $tagName)
}

if (-not $NoPush) {
    [void](Invoke-Git -Arguments @("push", "origin", "main") -WorkingDirectory $ProjectRoot)
    if (-not $tagExists) {
        [void](Invoke-Git -Arguments @("push", "origin", $tagName) -WorkingDirectory $ProjectRoot)
    }
    Write-Host "Pushed main and release tag to origin."
}

$distDir = Join-Path $ProjectRoot "dist"
$packagePath = Join-Path $distDir ("PCOptimizer-{0}.zip" -f $tagName)
$latestManifestPath = Join-Path $distDir "latest.json"
$installScriptPath = Join-Path $distDir "Install-PCOptimizer.ps1"
$installBootstrapPath = Join-Path $distDir "Install-PCOptimizer.bat"
$releaseDraftUrl = Get-ReleaseDraftUrl -RootPath $ProjectRoot

Write-Host ""
Write-Host "Upload these files to the GitHub Release:"
Write-Host ("- {0}" -f $packagePath)
Write-Host ("- {0}" -f $latestManifestPath)
Write-Host ("- {0}" -f $installScriptPath)
Write-Host ("- {0}" -f $installBootstrapPath)

if ($releaseDraftUrl) {
    $releaseTagUrl = ("{0}?tag={1}" -f $releaseDraftUrl, $tagName)
    Write-Host ("Release page: {0}" -f $releaseTagUrl)
    if (-not $NoOpenReleasePage) {
        Start-Process $releaseTagUrl
    }
}

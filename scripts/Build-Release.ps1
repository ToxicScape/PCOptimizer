[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$OutputDir = "",
    [string]$GitHubOwner = "",
    [string]$GitHubRepo = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot "dist"
}

$versionInfo = Get-Content -LiteralPath (Join-Path $ProjectRoot "version.json") -Raw | ConvertFrom-Json
$config = Get-Content -LiteralPath (Join-Path $ProjectRoot "appsettings.json") -Raw | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($GitHubOwner)) {
    $GitHubOwner = [string]$config.githubOwner
}
if ([string]::IsNullOrWhiteSpace($GitHubRepo)) {
    $GitHubRepo = [string]$config.githubRepo
}

$version = [string]$versionInfo.version
$tag = "v$version"
$packageName = "PCOptimizer-$tag.zip"
$stagingDir = Join-Path $ProjectRoot "release-staging"
$packageDir = Join-Path $stagingDir "package"
$packagePath = Join-Path $OutputDir $packageName
$installScriptPath = Join-Path $ProjectRoot "scripts\Install-PCOptimizer.ps1"
$releaseBaseUrl = ""

if ($GitHubOwner -and $GitHubRepo -and $GitHubOwner -notlike "YOUR_*" -and $GitHubRepo -notlike "YOUR_*") {
    $releaseBaseUrl = "https://github.com/$GitHubOwner/$GitHubRepo/releases"
}

foreach ($path in @($OutputDir, $stagingDir)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force -Recurse
    }
    New-Item -ItemType Directory -Path $path -Force | Out-Null
}

New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

$itemsToPackage = @(
    "Install-PCOptimizer.bat",
    "PCOptimizer.ps1",
    "PCOptimizer.GUI.ps1",
    "Run-PCOptimizer.bat",
    "README.md",
    "appsettings.json",
    "version.json",
    "scripts"
)

foreach ($item in $itemsToPackage) {
    $sourcePath = Join-Path $ProjectRoot $item
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        continue
    }

    $destinationPath = Join-Path $packageDir $item
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Recurse -Force
}

Compress-Archive -Path (Join-Path $packageDir "*") -DestinationPath $packagePath -Force

$hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()

$latestManifest = [pscustomobject]@{
    app_name = if ($config.appName) { [string]$config.appName } else { "PC Optimizer" }
    version = $version
    channel = if ($versionInfo.channel) { [string]$versionInfo.channel } else { "stable" }
    package_file = $packageName
    sha256 = $hash
    published_at = (Get-Date).ToString("s")
    package_url = if ($releaseBaseUrl) { "$releaseBaseUrl/download/$tag/$packageName" } else { "" }
    install_script_url = if ($releaseBaseUrl) { "$releaseBaseUrl/latest/download/Install-PCOptimizer.ps1" } else { "" }
    release_notes_url = if ($releaseBaseUrl) { "$releaseBaseUrl/tag/$tag" } else { "" }
}

($latestManifest | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $OutputDir "latest.json") -Encoding UTF8
Copy-Item -LiteralPath $installScriptPath -Destination (Join-Path $OutputDir "Install-PCOptimizer.ps1") -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot "Install-PCOptimizer.bat") -Destination (Join-Path $OutputDir "Install-PCOptimizer.bat") -Force

Write-Host ("Created release assets in {0}" -f $OutputDir)
Write-Host ("Package: {0}" -f $packagePath)
Write-Host ("SHA256: {0}" -f $hash)

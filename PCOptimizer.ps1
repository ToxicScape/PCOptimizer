[CmdletBinding()]
param(
    [ValidateSet(
        "Menu",
        "Version",
        "JunkScan",
        "JunkClean",
        "StartupList",
        "StartupDisable",
        "StartupRestore",
        "PrivacyAudit",
        "PrivacyClean",
        "DuplicatesScan",
        "DuplicatesQuarantine",
        "QuarantineList",
        "QuarantineRestore",
        "UpdateCheck",
        "SelfUpdate"
    )]
    [string]$Action = "Menu",
    [string]$Path,
    [int]$Index = -1,
    [ValidateSet("First", "Oldest", "Newest")]
    [string]$Keep = "Oldest"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:ScriptRoot = $PSScriptRoot

function Get-AppState {
    $baseDir = Join-Path $env:LOCALAPPDATA "PCOptimizer"
    [pscustomobject]@{
        BaseDir                = $baseDir
        QuarantineDir          = Join-Path $baseDir "Quarantine"
        StartupBackupFile      = Join-Path $baseDir "startup-backups.json"
        DuplicateScanCacheFile = Join-Path $baseDir "last-duplicate-scan.json"
        DisabledStartupDir     = Join-Path $baseDir "DisabledStartup"
        DownloadDir            = Join-Path $baseDir "Downloads"
        UpdateWorkDir          = Join-Path $baseDir "UpdateWork"
    }
}

$script:AppState = Get-AppState

function Ensure-AppState {
    foreach ($dir in @(
        $script:AppState.BaseDir,
        $script:AppState.QuarantineDir,
        $script:AppState.DisabledStartupDir,
        $script:AppState.DownloadDir,
        $script:AppState.UpdateWorkDir
    )) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    if (-not (Test-Path -LiteralPath $script:AppState.StartupBackupFile)) {
        "[]" | Set-Content -LiteralPath $script:AppState.StartupBackupFile -Encoding UTF8
    }
}

function Format-Bytes {
    param([long]$Bytes)

    if ($Bytes -lt 1KB) { return "$Bytes B" }
    if ($Bytes -lt 1MB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    if ($Bytes -lt 1GB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    return ("{0:N2} GB" -f ($Bytes / 1GB))
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 72)
    Write-Host $Title
    Write-Host ("=" * 72)
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-JsonArray {
    param([string]$FilePath)

    if (-not (Test-Path -LiteralPath $FilePath)) {
        return @()
    }

    $raw = Get-Content -LiteralPath $FilePath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @()
    }

    $data = $raw | ConvertFrom-Json
    if ($null -eq $data) {
        return @()
    }

    if ($data -is [System.Array]) {
        return @($data)
    }

    return @($data)
}

function Save-JsonArray {
    param(
        [string]$FilePath,
        [object[]]$Data
    )

    $json = @($Data) | ConvertTo-Json -Depth 8
    $json | Set-Content -LiteralPath $FilePath -Encoding UTF8
}

function Get-JsonFileObject {
    param(
        [string]$FilePath,
        [object]$DefaultObject = $null
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        return $DefaultObject
    }

    $raw = Get-Content -LiteralPath $FilePath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $DefaultObject
    }

    return ($raw | ConvertFrom-Json)
}

function Save-JsonFileObject {
    param(
        [string]$FilePath,
        [object]$Data
    )

    ($Data | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $FilePath -Encoding UTF8
}

function Get-AppConfigPath {
    return (Join-Path $script:ScriptRoot "appsettings.json")
}

function Get-VersionFilePath {
    return (Join-Path $script:ScriptRoot "version.json")
}

function Get-AppConfig {
    return (Get-JsonFileObject -FilePath (Get-AppConfigPath))
}

function Get-AppVersionInfo {
    return (Get-JsonFileObject -FilePath (Get-VersionFilePath))
}

function Get-AppIdentity {
    $versionInfo = Get-AppVersionInfo
    $config = Get-AppConfig

    [pscustomobject]@{
        Name = if ($config -and $config.appName) { [string]$config.appName } else { "PC Optimizer" }
        Version = if ($versionInfo -and $versionInfo.version) { [string]$versionInfo.version } else { "0.0.0" }
        Channel = if ($versionInfo -and $versionInfo.channel) { [string]$versionInfo.channel } else { "dev" }
        Publisher = if ($config -and $config.publisher) { [string]$config.publisher } else { "" }
    }
}

function Get-AppReleaseBaseUrl {
    $config = Get-AppConfig
    if ($null -eq $config) {
        return $null
    }

    $owner = [string]$config.githubOwner
    $repo = [string]$config.githubRepo
    if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repo)) {
        return $null
    }

    if ($owner -like "YOUR_*" -or $repo -like "YOUR_*") {
        return $null
    }

    return ("https://github.com/{0}/{1}/releases" -f $owner, $repo)
}

function Get-UpdateManifestUrl {
    $config = Get-AppConfig
    if ($null -ne $config -and -not [string]::IsNullOrWhiteSpace([string]$config.latestManifestUrl)) {
        return [string]$config.latestManifestUrl
    }

    $releaseBaseUrl = Get-AppReleaseBaseUrl
    if ([string]::IsNullOrWhiteSpace($releaseBaseUrl)) {
        return $null
    }

    return ($releaseBaseUrl + "/latest/download/latest.json")
}

function ConvertTo-VersionObject {
    param([string]$VersionString)

    if ([string]::IsNullOrWhiteSpace($VersionString)) {
        return ([version]"0.0.0")
    }

    $normalized = ($VersionString -replace "[^0-9\.].*$", "")
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return ([version]"0.0.0")
    }

    return ([version]$normalized)
}

function Get-RemoteUpdateInfo {
    $manifestUrl = Get-UpdateManifestUrl
    if ([string]::IsNullOrWhiteSpace($manifestUrl)) {
        throw "Update settings are not configured yet. Set githubOwner and githubRepo in appsettings.json."
    }

    return (Invoke-RestMethod -Uri $manifestUrl -Method Get)
}

function Show-AppVersion {
    Write-Section "Application Version"
    $identity = Get-AppIdentity
    Write-Host ("Name: {0}" -f $identity.Name)
    Write-Host ("Version: {0}" -f $identity.Version)
    Write-Host ("Channel: {0}" -f $identity.Channel)
    if (-not [string]::IsNullOrWhiteSpace($identity.Publisher)) {
        Write-Host ("Publisher: {0}" -f $identity.Publisher)
    }
}

function Show-UpdateStatus {
    Write-Section "Update Check"
    $identity = Get-AppIdentity
    Write-Host ("Installed version: {0}" -f $identity.Version)

    $remote = Get-RemoteUpdateInfo
    $remoteVersion = [string]$remote.version
    Write-Host ("Latest version: {0}" -f $remoteVersion)

    if ((ConvertTo-VersionObject $remoteVersion) -gt (ConvertTo-VersionObject $identity.Version)) {
        Write-Host "Update available."
        if ($remote.release_notes_url) {
            Write-Host ("Release notes: {0}" -f [string]$remote.release_notes_url)
        }
    } else {
        Write-Host "You already have the latest version."
    }
}

function Invoke-SelfUpdate {
    Write-Section "Self Update"

    $identity = Get-AppIdentity
    $remote = Get-RemoteUpdateInfo
    $remoteVersion = [string]$remote.version
    if ((ConvertTo-VersionObject $remoteVersion) -le (ConvertTo-VersionObject $identity.Version)) {
        Write-Host "No update available."
        return
    }

    $packageUrl = [string]$remote.package_url
    if ([string]::IsNullOrWhiteSpace($packageUrl)) {
        throw "The update manifest does not contain package_url."
    }

    $packageFileName = if ($remote.package_file) { [string]$remote.package_file } else { [IO.Path]::GetFileName($packageUrl) }
    $downloadPath = Join-Path $script:AppState.DownloadDir $packageFileName
    $extractPath = Join-Path $script:AppState.UpdateWorkDir ([Guid]::NewGuid().Guid)
    $helperPath = Join-Path $script:AppState.UpdateWorkDir "apply-update.ps1"
    $targetRoot = $script:ScriptRoot

    Write-Host ("Downloading version {0}..." -f $remoteVersion)
    Invoke-WebRequest -Uri $packageUrl -OutFile $downloadPath

    if ($remote.sha256) {
        $actualHash = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $expectedHash = ([string]$remote.sha256).ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "Downloaded package hash mismatch. Update was cancelled."
        }
    }

    if (Test-Path -LiteralPath $extractPath) {
        Remove-Item -LiteralPath $extractPath -Force -Recurse
    }
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
    Expand-Archive -LiteralPath $downloadPath -DestinationPath $extractPath -Force

    $helperScript = @"
param(
    [int]`$ParentProcessId,
    [string]`$SourcePath,
    [string]`$TargetPath
)

for (`$i = 0; `$i -lt 180; `$i++) {
    if (-not (Get-Process -Id `$ParentProcessId -ErrorAction SilentlyContinue)) {
        break
    }
    Start-Sleep -Milliseconds 500
}

`$robocopy = Start-Process -FilePath robocopy.exe -ArgumentList @(
    `$SourcePath,
    `$TargetPath,
    '/E',
    '/R:1',
    '/W:1',
    '/NFL',
    '/NDL',
    '/NJH',
    '/NJS',
    '/NP'
) -PassThru -Wait -WindowStyle Hidden

if (`$robocopy.ExitCode -gt 7) {
    exit `$robocopy.ExitCode
}

Start-Sleep -Seconds 1
Start-Process -FilePath (Join-Path `$TargetPath 'Run-PCOptimizer.bat')
"@
    $helperScript | Set-Content -LiteralPath $helperPath -Encoding UTF8

    Write-Host "Closing this session so the updater can replace the app files."
    Start-Process -FilePath powershell.exe -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $helperPath,
        "-ParentProcessId", $PID,
        "-SourcePath", $extractPath,
        "-TargetPath", $targetRoot
    ) -WindowStyle Hidden
    exit 0
}

function Get-RelativePathSafe {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )

    try {
        $resolvedBase = (Resolve-Path -LiteralPath $BasePath).Path.TrimEnd("\")
        $resolvedTarget = (Resolve-Path -LiteralPath $TargetPath).Path
        $baseUri = [Uri]($resolvedBase + "\")
        $targetUri = [Uri]$resolvedTarget
        $relative = $baseUri.MakeRelativeUri($targetUri).ToString().Replace("/", "\")
        return [Uri]::UnescapeDataString($relative)
    } catch {
        return [IO.Path]::GetFileName($TargetPath)
    }
}

function Get-FileStats {
    param([object[]]$Files)

    $fileList = @($Files | Where-Object { $null -ne $_ })
    $sum = 0L
    foreach ($file in $fileList) {
        $sum += [long]$file.Length
    }

    [pscustomobject]@{
        FileCount = $fileList.Count
        TotalBytes = $sum
    }
}

function Get-JunkTargets {
    @(
        [pscustomobject]@{
            Name = "User Temp"
            Type = "DirectoryContents"
            Path = $env:TEMP
            RequiresAdmin = $false
        }
        [pscustomobject]@{
            Name = "Windows Temp"
            Type = "DirectoryContents"
            Path = (Join-Path $env:WINDIR "Temp")
            RequiresAdmin = $true
        }
        [pscustomobject]@{
            Name = "Crash Dumps"
            Type = "DirectoryContents"
            Path = (Join-Path $env:LOCALAPPDATA "CrashDumps")
            RequiresAdmin = $false
        }
        [pscustomobject]@{
            Name = "WER Archive"
            Type = "DirectoryContents"
            Path = (Join-Path $env:PROGRAMDATA "Microsoft\Windows\WER\ReportArchive")
            RequiresAdmin = $true
        }
        [pscustomobject]@{
            Name = "WER Queue"
            Type = "DirectoryContents"
            Path = (Join-Path $env:PROGRAMDATA "Microsoft\Windows\WER\ReportQueue")
            RequiresAdmin = $true
        }
        [pscustomobject]@{
            Name = "Thumbnail Cache"
            Type = "Pattern"
            Path = (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Explorer")
            Filter = "thumbcache*.db"
            RequiresAdmin = $false
        }
        [pscustomobject]@{
            Name = "Icon Cache"
            Type = "Pattern"
            Path = (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Explorer")
            Filter = "iconcache*.db"
            RequiresAdmin = $false
        }
    )
}

function Get-TargetFiles {
    param([pscustomobject]$Target)

    if ([string]::IsNullOrWhiteSpace($Target.Path) -or -not (Test-Path -LiteralPath $Target.Path)) {
        return @()
    }

    try {
        switch ($Target.Type) {
            "DirectoryContents" {
                return @(Get-ChildItem -LiteralPath $Target.Path -Force -Recurse -File -ErrorAction SilentlyContinue)
            }
            "Pattern" {
                return @(Get-ChildItem -LiteralPath $Target.Path -Force -File -Filter $Target.Filter -ErrorAction SilentlyContinue)
            }
            default {
                return @()
            }
        }
    } catch {
        return @()
    }
}

function Get-TargetCleanupItems {
    param([pscustomobject]$Target)

    if ([string]::IsNullOrWhiteSpace($Target.Path) -or -not (Test-Path -LiteralPath $Target.Path)) {
        return @()
    }

    try {
        switch ($Target.Type) {
            "DirectoryContents" {
                return @(Get-ChildItem -LiteralPath $Target.Path -Force -ErrorAction SilentlyContinue)
            }
            "Pattern" {
                return @(Get-ChildItem -LiteralPath $Target.Path -Force -File -Filter $Target.Filter -ErrorAction SilentlyContinue)
            }
            default {
                return @()
            }
        }
    } catch {
        return @()
    }
}

function Get-JunkReport {
    $report = foreach ($target in Get-JunkTargets) {
        $files = Get-TargetFiles -Target $target
        $stats = Get-FileStats -Files $files
        [pscustomobject]@{
            Name = $target.Name
            Path = $target.Path
            Files = $stats.FileCount
            Size = $stats.TotalBytes
            SizeLabel = Format-Bytes $stats.TotalBytes
            RequiresAdmin = $target.RequiresAdmin
        }
    }

    return @($report)
}

function Show-JunkReport {
    Write-Section "Junk File Report"
    $report = Get-JunkReport
    $report | Format-Table Name, Files, SizeLabel, RequiresAdmin -AutoSize
    $total = ($report | Measure-Object -Property Size -Sum).Sum
    Write-Host ""
    Write-Host ("Potential reclaimable space: {0}" -f (Format-Bytes ([long]$total)))
}

function Clear-JunkTarget {
    param([pscustomobject]$Target)

    $removedItems = 0
    foreach ($item in Get-TargetCleanupItems -Target $Target) {
        try {
            Remove-Item -LiteralPath $item.FullName -Force -Recurse -ErrorAction Stop
            $removedItems++
        } catch {
        }
    }

    return $removedItems
}

function Invoke-JunkCleanup {
    Write-Section "Cleaning Junk Files"
    $before = Get-JunkReport
    foreach ($target in Get-JunkTargets) {
        [void](Clear-JunkTarget -Target $target)
    }
    $after = Get-JunkReport

    $reclaimed = 0L
    for ($i = 0; $i -lt $before.Count; $i++) {
        $reclaimed += [long]$before[$i].Size - [long]$after[$i].Size
    }

    Write-Host ("Estimated reclaimed space: {0}" -f (Format-Bytes $reclaimed))
    if (-not (Test-IsAdministrator)) {
        Write-Host "Some system folders may still contain files because the script is not running as administrator."
    }
}

function Get-StartupItems {
    $items = New-Object System.Collections.Generic.List[object]
    $index = 1

    $registrySources = @(
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"; Scope = "Current User" }
        @{ Path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"; Scope = "All Users" }
        @{ Path = "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Scope = "All Users (32-bit)" }
    )

    foreach ($source in $registrySources) {
        if (-not (Test-Path -LiteralPath $source.Path)) {
            continue
        }

        try {
            $key = Get-Item -LiteralPath $source.Path
            foreach ($name in $key.GetValueNames()) {
                $items.Add([pscustomobject]@{
                    Index = $index
                    Name = $name
                    Kind = "Registry"
                    Scope = $source.Scope
                    Source = $source.Path
                    Command = [string]$key.GetValue($name)
                    ValueKind = [string]$key.GetValueKind($name)
                })
                $index++
            }
        } catch {
        }
    }

    $folderSources = @(
        @{ Path = (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"); Scope = "Current User" }
        @{ Path = (Join-Path $env:PROGRAMDATA "Microsoft\Windows\Start Menu\Programs\StartUp"); Scope = "All Users" }
    )

    foreach ($source in $folderSources) {
        if (-not (Test-Path -LiteralPath $source.Path)) {
            continue
        }

        try {
            foreach ($file in Get-ChildItem -LiteralPath $source.Path -Force -File -ErrorAction SilentlyContinue) {
                $items.Add([pscustomobject]@{
                    Index = $index
                    Name = $file.Name
                    Kind = "StartupFolder"
                    Scope = $source.Scope
                    Source = $source.Path
                    Command = $file.FullName
                    ValueKind = ""
                })
                $index++
            }
        } catch {
        }
    }

    return @($items.ToArray())
}

function Show-StartupItems {
    Write-Section "Startup Items"
    $items = Get-StartupItems
    if ($items.Count -eq 0) {
        Write-Host "No startup items found."
        return
    }

    $items | Format-Table Index, Name, Kind, Scope, Command -AutoSize
}

function Get-StartupBackups {
    return @(Get-JsonArray -FilePath $script:AppState.StartupBackupFile)
}

function Save-StartupBackups {
    param([object[]]$Backups)
    Save-JsonArray -FilePath $script:AppState.StartupBackupFile -Data $Backups
}

function Disable-StartupItem {
    param([int]$SelectedIndex)

    $items = Get-StartupItems
    $item = $items | Where-Object { $_.Index -eq $SelectedIndex } | Select-Object -First 1
    if ($null -eq $item) {
        throw "Startup item index $SelectedIndex was not found."
    }

    $backups = Get-StartupBackups
    $backupId = [Guid]::NewGuid().Guid
    $entry = [ordered]@{
        BackupId = $backupId
        Restored = $false
        DisabledAt = (Get-Date).ToString("s")
        Name = $item.Name
        Kind = $item.Kind
        Scope = $item.Scope
        Source = $item.Source
        Command = $item.Command
        ValueKind = $item.ValueKind
        BackupPath = ""
    }

    if ($item.Kind -eq "Registry") {
        Remove-ItemProperty -LiteralPath $item.Source -Name $item.Name -ErrorAction Stop
    } else {
        $destination = Join-Path $script:AppState.DisabledStartupDir ("{0}_{1}" -f $backupId, [IO.Path]::GetFileName($item.Command))
        Move-Item -LiteralPath $item.Command -Destination $destination -Force
        $entry.BackupPath = $destination
    }

    $backups += [pscustomobject]$entry
    Save-StartupBackups -Backups $backups

    Write-Host ("Disabled startup item: {0}" -f $item.Name)
}

function Show-StartupBackups {
    Write-Section "Disabled Startup Items"
    $backups = Get-StartupBackups | Where-Object { -not $_.Restored }
    if ($backups.Count -eq 0) {
        Write-Host "No disabled startup items are available for restore."
        return
    }

    $displayIndex = 1
    $rows = @(
        foreach ($backup in $backups) {
            [pscustomobject]@{
                Index = $displayIndex
                Name = $backup.Name
                Kind = $backup.Kind
                Scope = $backup.Scope
                DisabledAt = $backup.DisabledAt
            }
            $displayIndex++
        }
    )

    $rows | Format-Table -AutoSize
}

function Restore-StartupItem {
    param([int]$SelectedIndex)

    $allBackups = Get-StartupBackups
    $available = @($allBackups | Where-Object { -not $_.Restored })
    if ($SelectedIndex -lt 1 -or $SelectedIndex -gt $available.Count) {
        throw "Restore index $SelectedIndex is out of range."
    }

    $target = $available[$SelectedIndex - 1]

    if ($target.Kind -eq "Registry") {
        if (-not (Test-Path -LiteralPath $target.Source)) {
            New-Item -Path $target.Source -Force | Out-Null
        }

        if (Get-ItemProperty -LiteralPath $target.Source -Name $target.Name -ErrorAction SilentlyContinue) {
            throw "The startup registry value already exists. Restore was skipped."
        }

        New-ItemProperty -LiteralPath $target.Source -Name $target.Name -Value $target.Command -PropertyType $target.ValueKind -Force | Out-Null
    } else {
        if (-not (Test-Path -LiteralPath $target.BackupPath)) {
            throw "The disabled startup file could not be found in backup storage."
        }

        if (-not (Test-Path -LiteralPath $target.Source)) {
            New-Item -ItemType Directory -Path $target.Source -Force | Out-Null
        }

        $destination = Join-Path $target.Source ([IO.Path]::GetFileName($target.Command))
        if (Test-Path -LiteralPath $destination) {
            throw "A file already exists at the original startup location. Restore was skipped."
        }

        Move-Item -LiteralPath $target.BackupPath -Destination $destination -Force
    }

    foreach ($backup in $allBackups) {
        if ($backup.BackupId -eq $target.BackupId) {
            $backup.Restored = $true
            $backup.RestoredAt = (Get-Date).ToString("s")
        }
    }

    Save-StartupBackups -Backups $allBackups
    Write-Host ("Restored startup item: {0}" -f $target.Name)
}

function Get-PSHistoryPath {
    $candidate = Join-Path $env:APPDATA "Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
    return $candidate
}

function Get-RegistryValueNameCount {
    param(
        [string]$RegistryPath,
        [string[]]$ExcludeNames = @()
    )

    if (-not (Test-Path -LiteralPath $RegistryPath)) {
        return 0
    }

    try {
        $item = Get-Item -LiteralPath $RegistryPath
        return @($item.GetValueNames() | Where-Object { $_ -notin $ExcludeNames }).Count
    } catch {
        return 0
    }
}

function Get-PrivacyReport {
    $recentPath = Join-Path $env:APPDATA "Microsoft\Windows\Recent"
    $recentFiles = if (Test-Path -LiteralPath $recentPath) {
        @(Get-ChildItem -LiteralPath $recentPath -Force -File -ErrorAction SilentlyContinue)
    } else {
        @()
    }
    $recentStats = Get-FileStats -Files $recentFiles

    $psHistoryPath = Get-PSHistoryPath
    $historyLines = 0
    if (Test-Path -LiteralPath $psHistoryPath) {
        $historyLines = @(Get-Content -LiteralPath $psHistoryPath -ErrorAction SilentlyContinue).Count
    }

    @(
        [pscustomobject]@{
            Name = "Recent Files Shortcuts"
            Count = $recentStats.FileCount
            Detail = Format-Bytes $recentStats.TotalBytes
        }
        [pscustomobject]@{
            Name = "Explorer Run History"
            Count = (Get-RegistryValueNameCount -RegistryPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU" -ExcludeNames @("MRUList"))
            Detail = "Registry entries"
        }
        [pscustomobject]@{
            Name = "Explorer Typed Paths"
            Count = (Get-RegistryValueNameCount -RegistryPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths")
            Detail = "Registry entries"
        }
        [pscustomobject]@{
            Name = "PowerShell History"
            Count = $historyLines
            Detail = $psHistoryPath
        }
    )
}

function Show-PrivacyReport {
    Write-Section "Privacy Trace Report"
    $report = Get-PrivacyReport
    $report | Format-Table Name, Count, Detail -AutoSize
}

function Clear-PrivacyTraces {
    Write-Section "Clearing Privacy Traces"
    $recentPath = Join-Path $env:APPDATA "Microsoft\Windows\Recent"
    if (Test-Path -LiteralPath $recentPath) {
        Get-ChildItem -LiteralPath $recentPath -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction Stop
            } catch {
            }
        }
    }

    $runMruKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU"
    if (Test-Path -LiteralPath $runMruKey) {
        $key = Get-Item -LiteralPath $runMruKey
        foreach ($name in $key.GetValueNames() | Where-Object { $_ -ne "MRUList" }) {
            try {
                Remove-ItemProperty -LiteralPath $runMruKey -Name $name -ErrorAction Stop
            } catch {
            }
        }
    }

    $typedPathsKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths"
    if (Test-Path -LiteralPath $typedPathsKey) {
        $key = Get-Item -LiteralPath $typedPathsKey
        foreach ($name in $key.GetValueNames()) {
            try {
                Remove-ItemProperty -LiteralPath $typedPathsKey -Name $name -ErrorAction Stop
            } catch {
            }
        }
    }

    $psHistoryPath = Get-PSHistoryPath
    if (Test-Path -LiteralPath $psHistoryPath) {
        Set-Content -LiteralPath $psHistoryPath -Value "" -Encoding UTF8
    }

    Write-Host "Privacy traces cleared."
}

function Find-DuplicateFileGroups {
    param([string]$RootPath)

    if (-not (Test-Path -LiteralPath $RootPath)) {
        throw "The folder '$RootPath' does not exist."
    }

    $resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path
    $candidateFiles = @(Get-ChildItem -LiteralPath $resolvedRoot -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -notlike "$($script:AppState.BaseDir)\*"
    })

    $groupId = 1
    $duplicateGroups = New-Object System.Collections.Generic.List[object]
    foreach ($lengthGroup in ($candidateFiles | Group-Object Length | Where-Object { $_.Count -gt 1 })) {
        $hashBuckets = @{}
        foreach ($file in $lengthGroup.Group) {
            try {
                $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            } catch {
                continue
            }

            if (-not $hashBuckets.ContainsKey($hash)) {
                $hashBuckets[$hash] = New-Object System.Collections.Generic.List[object]
            }

            $hashBuckets[$hash].Add($file)
        }

        foreach ($hash in $hashBuckets.Keys) {
            $files = @($hashBuckets[$hash])
            if ($files.Count -lt 2) {
                continue
            }

            $bytes = 0L
            foreach ($file in $files) {
                $bytes += [long]$file.Length
            }

            $duplicateGroups.Add([pscustomobject]@{
                GroupId = $groupId
                Hash = $hash
                FileCount = $files.Count
                DuplicateCount = $files.Count - 1
                TotalBytes = $bytes
                WastedBytes = $bytes - [long]$files[0].Length
                Files = @($files | ForEach-Object { $_.FullName })
            })
            $groupId++
        }
    }

    return @($duplicateGroups.ToArray() | Sort-Object -Property WastedBytes -Descending)
}

function Save-DuplicateScanCache {
    param(
        [string]$RootPath,
        [object[]]$Groups
    )

    $payload = [pscustomobject]@{
        RootPath = $RootPath
        ScannedAt = (Get-Date).ToString("s")
        Groups = @($Groups)
    }

    ($payload | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $script:AppState.DuplicateScanCacheFile -Encoding UTF8
}

function Get-DuplicateScanCache {
    if (-not (Test-Path -LiteralPath $script:AppState.DuplicateScanCacheFile)) {
        return $null
    }

    return (Get-Content -LiteralPath $script:AppState.DuplicateScanCacheFile -Raw | ConvertFrom-Json)
}

function Show-DuplicateGroups {
    param([object[]]$Groups)

    [object[]]$groupList = @($Groups | Where-Object { $null -ne $_ })
    if ($groupList.Length -eq 0) {
        Write-Host "No duplicate groups were found."
        return
    }

    $groupList | ForEach-Object {
        [pscustomobject]@{
            GroupId = $_.GroupId
            Files = $_.FileCount
            WastedSpace = Format-Bytes ([long]$_.WastedBytes)
            Example = $_.Files[0]
        }
    } | Format-Table -AutoSize

    $totalWasted = ($groupList | Measure-Object -Property WastedBytes -Sum).Sum
    Write-Host ""
    Write-Host ("Duplicate space that could be reclaimed: {0}" -f (Format-Bytes ([long]$totalWasted)))
}

function Get-KeepFile {
    param(
        [string[]]$Files,
        [string]$KeepMode
    )

    $fileObjects = @($Files | ForEach-Object { Get-Item -LiteralPath $_ })
    switch ($KeepMode) {
        "Newest" {
            return ($fileObjects | Sort-Object -Property LastWriteTimeUtc, FullName | Select-Object -Last 1).FullName
        }
        "Oldest" {
            return ($fileObjects | Sort-Object -Property LastWriteTimeUtc, FullName | Select-Object -First 1).FullName
        }
        default {
            return $fileObjects[0].FullName
        }
    }
}

function Invoke-DuplicateQuarantine {
    param(
        [string]$RootPath,
        [object[]]$Groups,
        [string]$KeepMode
    )

    [object[]]$groupList = @($Groups | Where-Object { $null -ne $_ })
    if ($groupList.Length -eq 0) {
        Write-Host "No duplicate groups were found."
        return
    }

    $resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path
    $batchId = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $batchDir = Join-Path $script:AppState.QuarantineDir $batchId
    New-Item -ItemType Directory -Path $batchDir -Force | Out-Null

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($group in $groupList) {
        $keepFile = Get-KeepFile -Files $group.Files -KeepMode $KeepMode
        foreach ($file in $group.Files | Where-Object { $_ -ne $keepFile }) {
            if (-not (Test-Path -LiteralPath $file)) {
                continue
            }

            $relative = Get-RelativePathSafe -BasePath $resolvedRoot -TargetPath $file
            $destination = Join-Path $batchDir $relative
            $destinationDir = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $destinationDir)) {
                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
            }

            Move-Item -LiteralPath $file -Destination $destination -Force
            $entries.Add([pscustomobject]@{
                OriginalPath = $file
                QuarantinePath = $destination
                GroupId = $group.GroupId
                KeptFile = $keepFile
            })
        }
    }

    $manifest = [pscustomobject]@{
        BatchId = $batchId
        CreatedAt = (Get-Date).ToString("s")
        RootPath = $resolvedRoot
        KeepMode = $KeepMode
        FileCount = $entries.Count
        Entries = @($entries)
    }

    ($manifest | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $batchDir "manifest.json") -Encoding UTF8
    Write-Host ("Moved {0} files into quarantine batch {1}" -f $entries.Count, $batchId)
}

function Get-QuarantineBatches {
    if (-not (Test-Path -LiteralPath $script:AppState.QuarantineDir)) {
        return @()
    }

    $batches = New-Object System.Collections.Generic.List[object]
    foreach ($dir in Get-ChildItem -LiteralPath $script:AppState.QuarantineDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending) {
        $manifestPath = Join-Path $dir.FullName "manifest.json"
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            continue
        }

        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $batches.Add($manifest)
        } catch {
        }
    }

    return @($batches.ToArray())
}

function Show-QuarantineBatches {
    Write-Section "Quarantine Batches"
    [object[]]$batches = @(Get-QuarantineBatches | Where-Object { $null -ne $_ })
    if ($batches.Length -eq 0) {
        Write-Host "No quarantine batches found."
        return
    }

    $displayIndex = 1
    $rows = @(
        $batches | ForEach-Object {
            [pscustomobject]@{
                Index = $displayIndex
                BatchId = $_.BatchId
                CreatedAt = $_.CreatedAt
                Files = $_.FileCount
                RootPath = $_.RootPath
            }
            $displayIndex++
        }
    )

    $rows | Format-Table -AutoSize
}

function Restore-QuarantineBatch {
    param([int]$SelectedIndex)

    [object[]]$batches = @(Get-QuarantineBatches | Where-Object { $null -ne $_ })
    if ($SelectedIndex -lt 1 -or $SelectedIndex -gt $batches.Length) {
        throw "Quarantine batch index $SelectedIndex is out of range."
    }

    $batch = $batches[$SelectedIndex - 1]
    $restored = 0
    foreach ($entry in @($batch.Entries)) {
        if (-not (Test-Path -LiteralPath $entry.QuarantinePath)) {
            continue
        }

        $destinationDir = Split-Path -Parent $entry.OriginalPath
        if (-not (Test-Path -LiteralPath $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }

        if (Test-Path -LiteralPath $entry.OriginalPath) {
            continue
        }

        Move-Item -LiteralPath $entry.QuarantinePath -Destination $entry.OriginalPath -Force
        $restored++
    }

    Write-Host ("Restored {0} file(s) from quarantine batch {1}" -f $restored, $batch.BatchId)
}

function Resolve-RequiredPath {
    param([string]$CandidatePath)

    if (-not [string]::IsNullOrWhiteSpace($CandidatePath)) {
        return $CandidatePath
    }

    throw "This action requires -Path."
}

function Prompt-ForPath {
    param([string]$PromptText = "Folder path")

    $value = Read-Host $PromptText
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "A folder path is required."
    }

    return $value
}

function Start-InteractiveMenu {
    while ($true) {
        Write-Section "PC Optimizer"
        Write-Host "1. Show app version"
        Write-Host "2. Check for updates"
        Write-Host "3. Install latest update"
        Write-Host "4. Scan junk files"
        Write-Host "5. Clean junk files"
        Write-Host "6. List startup items"
        Write-Host "7. Disable a startup item"
        Write-Host "8. Restore a disabled startup item"
        Write-Host "9. Privacy trace report"
        Write-Host "10. Clear privacy traces"
        Write-Host "11. Scan duplicate files in a folder"
        Write-Host "12. Quarantine duplicate files in a folder"
        Write-Host "13. List duplicate quarantine batches"
        Write-Host "14. Restore a duplicate quarantine batch"
        Write-Host "0. Exit"
        Write-Host ""

        $choice = Read-Host "Select an option"
        try {
            switch ($choice) {
                "1" { Show-AppVersion }
                "2" { Show-UpdateStatus }
                "3" { Invoke-SelfUpdate }
                "4" { Show-JunkReport }
                "5" { Invoke-JunkCleanup }
                "6" { Show-StartupItems }
                "7" {
                    Show-StartupItems
                    Disable-StartupItem -SelectedIndex ([int](Read-Host "Enter the startup item index to disable"))
                }
                "8" {
                    Show-StartupBackups
                    Restore-StartupItem -SelectedIndex ([int](Read-Host "Enter the restore index"))
                }
                "9" { Show-PrivacyReport }
                "10" { Clear-PrivacyTraces }
                "11" {
                    $scanPath = Prompt-ForPath -PromptText "Enter the folder path to scan for duplicates"
                    $groups = Find-DuplicateFileGroups -RootPath $scanPath
                    Save-DuplicateScanCache -RootPath $scanPath -Groups $groups
                    Write-Section "Duplicate Scan Results"
                    Show-DuplicateGroups -Groups $groups
                }
                "12" {
                    $scanPath = Prompt-ForPath -PromptText "Enter the folder path to scan and quarantine duplicates"
                    $groups = Find-DuplicateFileGroups -RootPath $scanPath
                    Save-DuplicateScanCache -RootPath $scanPath -Groups $groups
                    Write-Section "Duplicate Scan Results"
                    Show-DuplicateGroups -Groups $groups
                    if ((@($groups | Where-Object { $null -ne $_ })).Length -gt 0) {
                        $mode = Read-Host "Keep which file from each group? (First/Oldest/Newest)"
                        if ($mode -notin @("First", "Oldest", "Newest")) {
                            $mode = "Oldest"
                        }
                        Invoke-DuplicateQuarantine -RootPath $scanPath -Groups $groups -KeepMode $mode
                    }
                }
                "13" { Show-QuarantineBatches }
                "14" {
                    Show-QuarantineBatches
                    Restore-QuarantineBatch -SelectedIndex ([int](Read-Host "Enter the quarantine batch index to restore"))
                }
                "0" { break }
                default { Write-Host "Invalid option." }
            }
        } catch {
            Write-Host ("Error: {0}" -f $_.Exception.Message)
        }

        Write-Host ""
        [void](Read-Host "Press Enter to continue")
        Clear-Host
    }
}

if ($script:PCOptimizerImportOnly) {
    Ensure-AppState
    return
}

Ensure-AppState

try {
    switch ($Action) {
        "Menu" {
            Start-InteractiveMenu
        }
        "Version" {
            Show-AppVersion
        }
        "JunkScan" {
            Show-JunkReport
        }
        "JunkClean" {
            Invoke-JunkCleanup
        }
        "StartupList" {
            Show-StartupItems
        }
        "StartupDisable" {
            if ($Index -lt 1) { throw "StartupDisable requires -Index." }
            Disable-StartupItem -SelectedIndex $Index
        }
        "StartupRestore" {
            if ($Index -lt 1) { throw "StartupRestore requires -Index." }
            Restore-StartupItem -SelectedIndex $Index
        }
        "PrivacyAudit" {
            Show-PrivacyReport
        }
        "PrivacyClean" {
            Clear-PrivacyTraces
        }
        "DuplicatesScan" {
            $resolvedPath = Resolve-RequiredPath -CandidatePath $Path
            $groups = Find-DuplicateFileGroups -RootPath $resolvedPath
            Save-DuplicateScanCache -RootPath $resolvedPath -Groups $groups
            Write-Section "Duplicate Scan Results"
            Show-DuplicateGroups -Groups $groups
        }
        "DuplicatesQuarantine" {
            $resolvedPath = Resolve-RequiredPath -CandidatePath $Path
            $groups = Find-DuplicateFileGroups -RootPath $resolvedPath
            Save-DuplicateScanCache -RootPath $resolvedPath -Groups $groups
            Invoke-DuplicateQuarantine -RootPath $resolvedPath -Groups $groups -KeepMode $Keep
        }
        "QuarantineList" {
            Show-QuarantineBatches
        }
        "QuarantineRestore" {
            if ($Index -lt 1) { throw "QuarantineRestore requires -Index." }
            Restore-QuarantineBatch -SelectedIndex $Index
        }
        "UpdateCheck" {
            Show-UpdateStatus
        }
        "SelfUpdate" {
            Invoke-SelfUpdate
        }
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

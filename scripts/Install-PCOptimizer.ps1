[CmdletBinding()]
param(
    [string]$SourceDir = "",
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "Programs\PCOptimizer"),
    [string]$GitHubOwner = "ToxicScape",
    [string]$GitHubRepo = "PCOptimizer",
    [switch]$NoDesktopShortcut,
    [switch]$NoStartMenuShortcut,
    [switch]$NoShow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

if ([string]::IsNullOrWhiteSpace($SourceDir)) {
    $SourceDir = $PSScriptRoot
}

$script:InstallerState = [ordered]@{
    TempDir = Join-Path $env:TEMP ("PCOptimizer-Install-" + [guid]::NewGuid().Guid)
}

function New-UiFont {
    param(
        [string]$Family,
        [float]$Size,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )

    return New-Object System.Drawing.Font($Family, $Size, $Style)
}

function New-Shortcut {
    param(
        [string]$ShortcutPath,
        [string]$TargetPath,
        [string]$WorkingDirectory,
        [string]$Description,
        [string]$IconLocation = ""
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = $Description
    if (-not [string]::IsNullOrWhiteSpace($IconLocation)) {
        $shortcut.IconLocation = $IconLocation
    }
    $shortcut.Save()
}

function Set-InstallerStep {
    param(
        [int]$Percent,
        [string]$Title,
        [string]$Detail
    )

    if ($NoShow) {
        Write-Host ("[{0}%] {1} - {2}" -f $Percent, $Title, $Detail)
        return
    }

    $script:TitleLabel.Text = $Title
    $script:DetailLabel.Text = $Detail
    $script:ProgressBar.Value = [Math]::Min([Math]::Max($Percent, 0), 100)
    [System.Windows.Forms.Application]::DoEvents()
}

function Invoke-DownloadFile {
    param(
        [string]$Uri,
        [string]$DestinationPath,
        [string]$PhaseTitle,
        [int]$BasePercent,
        [int]$RangePercent
    )

    $client = New-Object System.Net.WebClient
    $script:InstallerDownloadComplete = $false
    $script:InstallerDownloadError = $null

    $progressHandler = [System.Net.DownloadProgressChangedEventHandler]{
        param($sender, $args)
        $percent = $BasePercent + [Math]::Floor($args.ProgressPercentage * ($RangePercent / 100.0))
        Set-InstallerStep -Percent $percent -Title $PhaseTitle -Detail ("Downloading package... {0}% ({1} MB / {2} MB)" -f $args.ProgressPercentage, [Math]::Round($args.BytesReceived / 1MB, 1), [Math]::Round($args.TotalBytesToReceive / 1MB, 1))
    }

    $completedHandler = [System.ComponentModel.AsyncCompletedEventHandler]{
        param($sender, $args)
        if ($args.Error) {
            $script:InstallerDownloadError = $args.Error
        }
        $script:InstallerDownloadComplete = $true
    }

    $client.DownloadProgressChanged += $progressHandler
    $client.DownloadFileCompleted += $completedHandler
    $client.DownloadFileAsync([Uri]$Uri, $DestinationPath)

    while (-not $script:InstallerDownloadComplete) {
        Start-Sleep -Milliseconds 120
        if (-not $NoShow) {
            [System.Windows.Forms.Application]::DoEvents()
        }
    }

    $client.Dispose()
    if ($script:InstallerDownloadError) {
        throw $script:InstallerDownloadError
    }
}

function Get-InstallerSourceRoot {
    $candidateRoots = @(
        $SourceDir,
        (Split-Path -Parent $SourceDir)
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($candidate in $candidateRoots) {
        if (Test-Path -LiteralPath (Join-Path $candidate "PCOptimizer.GUI.ps1")) {
            return $candidate
        }
    }

    if (Test-Path -LiteralPath (Join-Path $SourceDir "PCOptimizer.GUI.ps1")) {
        return $SourceDir
    }

    New-Item -ItemType Directory -Path $script:InstallerState.TempDir -Force | Out-Null
    $manifestUrl = "https://github.com/$GitHubOwner/$GitHubRepo/releases/latest/download/latest.json"
    $manifestPath = Join-Path $script:InstallerState.TempDir "latest.json"
    $packagePath = Join-Path $script:InstallerState.TempDir "PCOptimizer.zip"
    $extractPath = Join-Path $script:InstallerState.TempDir "package"

    Set-InstallerStep -Percent 8 -Title "Checking Latest Release" -Detail "Reading the latest release manifest from GitHub."
    Invoke-WebRequest -UseBasicParsing -Uri $manifestUrl -OutFile $manifestPath
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

    if ([string]::IsNullOrWhiteSpace([string]$manifest.package_url)) {
        throw "The latest release manifest does not contain a package_url."
    }

    Set-InstallerStep -Percent 18 -Title "Downloading PC Optimizer" -Detail "Preparing secure download from GitHub Releases."
    Invoke-DownloadFile -Uri ([string]$manifest.package_url) -DestinationPath $packagePath -PhaseTitle "Downloading PC Optimizer" -BasePercent 18 -RangePercent 46

    if ($manifest.sha256) {
        Set-InstallerStep -Percent 66 -Title "Verifying Package" -Detail "Checking the download hash before extraction."
        $actualHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $expectedHash = ([string]$manifest.sha256).ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "Downloaded package hash mismatch. The installer stopped for safety."
        }
    }

    Set-InstallerStep -Percent 74 -Title "Extracting Files" -Detail "Unpacking the app bundle into a temporary workspace."
    if (Test-Path -LiteralPath $extractPath) {
        Remove-Item -LiteralPath $extractPath -Force -Recurse
    }
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
    Expand-Archive -LiteralPath $packagePath -DestinationPath $extractPath -Force
    return $extractPath
}

function Install-AppFiles {
    param([string]$ResolvedSourceDir)

    if (-not (Test-Path -LiteralPath $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    $itemsToCopy = @(
        "PCOptimizer.ps1",
        "PCOptimizer.GUI.ps1",
        "Run-PCOptimizer.bat",
        "Install-PCOptimizer.bat",
        "README.md",
        "appsettings.json",
        "version.json",
        "scripts"
    )

    Set-InstallerStep -Percent 82 -Title "Installing Core Files" -Detail "Copying application files into your local programs folder."
    foreach ($item in $itemsToCopy) {
        $sourcePath = Join-Path $ResolvedSourceDir $item
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            continue
        }

        $destinationPath = Join-Path $InstallDir $item
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force -Recurse
    }
}

function Install-Shortcuts {
    $iconPath = "$env:SystemRoot\System32\shell32.dll,220"
    $launcherPath = Join-Path $InstallDir "Run-PCOptimizer.bat"

    if (-not $NoDesktopShortcut) {
        Set-InstallerStep -Percent 90 -Title "Creating Desktop Shortcut" -Detail "Adding a quick launch icon to your desktop."
        $desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "PC Optimizer.lnk"
        New-Shortcut -ShortcutPath $desktopShortcut -TargetPath $launcherPath -WorkingDirectory $InstallDir -Description "Launch PC Optimizer" -IconLocation $iconPath
    }

    if (-not $NoStartMenuShortcut) {
        Set-InstallerStep -Percent 95 -Title "Creating Start Menu Shortcut" -Detail "Adding PC Optimizer to your Start Menu programs list."
        $startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
        $startMenuShortcut = Join-Path $startMenuDir "PC Optimizer.lnk"
        New-Shortcut -ShortcutPath $startMenuShortcut -TargetPath $launcherPath -WorkingDirectory $InstallDir -Description "Launch PC Optimizer" -IconLocation $iconPath
    }
}

function Invoke-Installer {
    $resolvedSourceDir = Get-InstallerSourceRoot
    Install-AppFiles -ResolvedSourceDir $resolvedSourceDir
    Install-Shortcuts
    Set-InstallerStep -Percent 100 -Title "Installation Complete" -Detail "PC Optimizer is installed and ready to launch."
}

if (-not $NoShow) {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Install PC Optimizer"
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.Size = New-Object System.Drawing.Size(620, 340)
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(246, 241, 232)

    $banner = New-Object System.Windows.Forms.Panel
    $banner.Dock = [System.Windows.Forms.DockStyle]::Top
    $banner.Height = 90
    $banner.BackColor = [System.Drawing.Color]::FromArgb(26, 44, 43)
    $form.Controls.Add($banner)

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = "PC Optimizer Setup"
    $heading.ForeColor = [System.Drawing.Color]::White
    $heading.Location = New-Object System.Drawing.Point(24, 20)
    $heading.AutoSize = $true
    $heading.Font = New-UiFont -Family "Bahnschrift SemiBold" -Size 22.0
    $banner.Controls.Add($heading)

    $subheading = New-Object System.Windows.Forms.Label
    $subheading.Text = "Downloading the latest build, verifying it, creating shortcuts, and installing it into your user profile."
    $subheading.ForeColor = [System.Drawing.Color]::FromArgb(212, 223, 219)
    $subheading.Location = New-Object System.Drawing.Point(26, 56)
    $subheading.AutoSize = $true
    $subheading.Font = New-UiFont -Family "Segoe UI" -Size 9.0
    $banner.Controls.Add($subheading)

    $content = New-Object System.Windows.Forms.Panel
    $content.Dock = [System.Windows.Forms.DockStyle]::Fill
    $content.Padding = New-Object System.Windows.Forms.Padding(28, 26, 28, 24)
    $form.Controls.Add($content)

    $script:TitleLabel = New-Object System.Windows.Forms.Label
    $script:TitleLabel.Text = "Preparing Installer"
    $script:TitleLabel.AutoSize = $true
    $script:TitleLabel.Font = New-UiFont -Family "Bahnschrift SemiBold" -Size 18.0
    $script:TitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(26, 44, 43)
    $script:TitleLabel.Location = New-Object System.Drawing.Point(0, 6)
    $content.Controls.Add($script:TitleLabel)

    $script:DetailLabel = New-Object System.Windows.Forms.Label
    $script:DetailLabel.Text = "Getting the setup workflow ready."
    $script:DetailLabel.AutoSize = $false
    $script:DetailLabel.Size = New-Object System.Drawing.Size(530, 44)
    $script:DetailLabel.Font = New-UiFont -Family "Segoe UI" -Size 10.0
    $script:DetailLabel.ForeColor = [System.Drawing.Color]::FromArgb(90, 101, 97)
    $script:DetailLabel.Location = New-Object System.Drawing.Point(2, 48)
    $content.Controls.Add($script:DetailLabel)

    $script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
    $script:ProgressBar.Location = New-Object System.Drawing.Point(2, 108)
    $script:ProgressBar.Size = New-Object System.Drawing.Size(540, 26)
    $script:ProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $content.Controls.Add($script:ProgressBar)

    $installPathLabel = New-Object System.Windows.Forms.Label
    $installPathLabel.Text = "Install location:"
    $installPathLabel.AutoSize = $true
    $installPathLabel.Font = New-UiFont -Family "Segoe UI Semibold" -Size 9.0
    $installPathLabel.ForeColor = [System.Drawing.Color]::FromArgb(26, 44, 43)
    $installPathLabel.Location = New-Object System.Drawing.Point(2, 156)
    $content.Controls.Add($installPathLabel)

    $installPathValue = New-Object System.Windows.Forms.Label
    $installPathValue.Text = $InstallDir
    $installPathValue.AutoSize = $false
    $installPathValue.Size = New-Object System.Drawing.Size(540, 40)
    $installPathValue.Font = New-UiFont -Family "Segoe UI" -Size 9.0
    $installPathValue.ForeColor = [System.Drawing.Color]::FromArgb(90, 101, 97)
    $installPathValue.Location = New-Object System.Drawing.Point(2, 178)
    $content.Controls.Add($installPathValue)

    $launchButton = New-Object System.Windows.Forms.Button
    $launchButton.Text = "Launch PC Optimizer"
    $launchButton.Size = New-Object System.Drawing.Size(170, 36)
    $launchButton.Location = New-Object System.Drawing.Point(372, 218)
    $launchButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $launchButton.FlatAppearance.BorderSize = 0
    $launchButton.BackColor = [System.Drawing.Color]::FromArgb(56, 112, 85)
    $launchButton.ForeColor = [System.Drawing.Color]::White
    $launchButton.Font = New-UiFont -Family "Segoe UI Semibold" -Size 9.0
    $launchButton.Visible = $false
    $content.Controls.Add($launchButton)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = "Close"
    $closeButton.Size = New-Object System.Drawing.Size(120, 36)
    $closeButton.Location = New-Object System.Drawing.Point(242, 218)
    $closeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $closeButton.FlatAppearance.BorderSize = 0
    $closeButton.BackColor = [System.Drawing.Color]::FromArgb(229, 221, 207)
    $closeButton.ForeColor = [System.Drawing.Color]::FromArgb(26, 44, 43)
    $closeButton.Font = New-UiFont -Family "Segoe UI Semibold" -Size 9.0
    $content.Controls.Add($closeButton)

    $closeButton.Add_Click({ $form.Close() })
    $launchButton.Add_Click({
        Start-Process -FilePath (Join-Path $InstallDir "Run-PCOptimizer.bat")
        $form.Close()
    })

    $form.Add_Shown({
        try {
            Invoke-Installer
            $launchButton.Visible = $true
            $closeButton.Text = "Done"
        } catch {
            $script:TitleLabel.Text = "Installation Failed"
            $script:DetailLabel.Text = $_.Exception.Message
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Install PC Optimizer", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        } finally {
            if (Test-Path -LiteralPath $script:InstallerState.TempDir) {
                Remove-Item -LiteralPath $script:InstallerState.TempDir -Force -Recurse -ErrorAction SilentlyContinue
            }
        }
    })

    [void]$form.ShowDialog()
    return
}

try {
    Invoke-Installer
} finally {
    if (Test-Path -LiteralPath $script:InstallerState.TempDir) {
        Remove-Item -LiteralPath $script:InstallerState.TempDir -Force -Recurse -ErrorAction SilentlyContinue
    }
}

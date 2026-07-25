[CmdletBinding()]
param(
    [switch]$NoShow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:PCOptimizerImportOnly = $true
. (Join-Path $PSScriptRoot "PCOptimizer.ps1")
Remove-Variable -Name PCOptimizerImportOnly -Scope Script -ErrorAction SilentlyContinue

$script:Theme = @{
    Background   = [System.Drawing.Color]::FromArgb(246, 241, 232)
    Surface      = [System.Drawing.Color]::FromArgb(255, 252, 247)
    Panel        = [System.Drawing.Color]::FromArgb(229, 221, 207)
    Ink          = [System.Drawing.Color]::FromArgb(26, 44, 43)
    Muted        = [System.Drawing.Color]::FromArgb(90, 101, 97)
    Accent       = [System.Drawing.Color]::FromArgb(210, 104, 44)
    AccentSoft   = [System.Drawing.Color]::FromArgb(239, 211, 191)
    Success      = [System.Drawing.Color]::FromArgb(56, 112, 85)
    Error        = [System.Drawing.Color]::FromArgb(160, 53, 53)
    GridLine     = [System.Drawing.Color]::FromArgb(215, 206, 191)
}

$script:GuiState = [ordered]@{
    DuplicateGroups = @()
}

function New-UiFont {
    param(
        [string]$Family,
        [float]$Size,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )

    return New-Object System.Drawing.Font($Family, $Size, $Style)
}

function New-FlatButton {
    param(
        [string]$Text,
        [int]$Width = 120,
        [int]$Height = 34,
        [System.Drawing.Color]$BackColor = $script:Theme.Accent,
        [System.Drawing.Color]$ForeColor = [System.Drawing.Color]::White
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Width = $Width
    $button.Height = $Height
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = $BackColor
    $button.ForeColor = $ForeColor
    $button.Font = New-UiFont -Family "Segoe UI Semibold" -Size 9.0
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $button
}

function New-SectionLabel {
    param([string]$Text)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.AutoSize = $true
    $label.ForeColor = $script:Theme.Ink
    $label.Font = New-UiFont -Family "Bahnschrift SemiBold" -Size 12.0
    return $label
}

function New-BodyLabel {
    param([string]$Text)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.AutoSize = $true
    $label.ForeColor = $script:Theme.Muted
    $label.Font = New-UiFont -Family "Segoe UI" -Size 9.0
    return $label
}

function New-ReadOnlyGrid {
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = [System.Windows.Forms.DockStyle]::Fill
    $grid.BackgroundColor = $script:Theme.Surface
    $grid.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.MultiSelect = $false
    $grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $grid.RowHeadersVisible = $false
    $grid.EnableHeadersVisualStyles = $false
    $grid.GridColor = $script:Theme.GridLine
    $grid.ColumnHeadersDefaultCellStyle.BackColor = $script:Theme.Panel
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = $script:Theme.Ink
    $grid.ColumnHeadersDefaultCellStyle.Font = New-UiFont -Family "Segoe UI Semibold" -Size 9.0
    $grid.DefaultCellStyle.BackColor = $script:Theme.Surface
    $grid.DefaultCellStyle.ForeColor = $script:Theme.Ink
    $grid.DefaultCellStyle.SelectionBackColor = $script:Theme.AccentSoft
    $grid.DefaultCellStyle.SelectionForeColor = $script:Theme.Ink
    $grid.DefaultCellStyle.Font = New-UiFont -Family "Segoe UI" -Size 9.0
    return $grid
}

function Set-GridData {
    param(
        [System.Windows.Forms.DataGridView]$Grid,
        [object[]]$Items
    )

    $rows = @($Items | Where-Object { $null -ne $_ })
    $Grid.DataSource = $null
    if ($rows.Count -eq 0) {
        return
    }

    $table = New-Object System.Data.DataTable
    $propertyNames = @($rows[0].PSObject.Properties.Name)
    foreach ($name in $propertyNames) {
        [void]$table.Columns.Add($name)
    }

    foreach ($row in $rows) {
        $dataRow = $table.NewRow()
        foreach ($name in $propertyNames) {
            $value = $row.$name
            if ($value -is [System.Array]) {
                $value = ($value -join "; ")
            }
            $dataRow[$name] = if ($null -eq $value) { "" } else { [string]$value }
        }
        [void]$table.Rows.Add($dataRow)
    }

    $Grid.DataSource = $table
}

function Set-StatusMessage {
    param(
        [string]$Text,
        [System.Drawing.Color]$Color = $script:Theme.Muted
    )

    $script:StatusLabel.Text = $Text
    $script:StatusLabel.ForeColor = $Color
}

function Invoke-UiAction {
    param(
        [scriptblock]$Action,
        [string]$SuccessMessage = "Done."
    )

    try {
        $script:MainForm.UseWaitCursor = $true
        [System.Windows.Forms.Application]::UseWaitCursor = $true
        [System.Windows.Forms.Application]::DoEvents()
        & $Action
        Set-StatusMessage -Text $SuccessMessage -Color $script:Theme.Success
    } catch {
        $message = $_.Exception.Message
        Set-StatusMessage -Text $message -Color $script:Theme.Error
        [System.Windows.Forms.MessageBox]::Show($message, "PC Optimizer", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } finally {
        $script:MainForm.UseWaitCursor = $false
        [System.Windows.Forms.Application]::UseWaitCursor = $false
    }
}

function Get-StartupBackupRows {
    $index = 1
    return @(
        foreach ($backup in @(Get-StartupBackups | Where-Object { -not $_.Restored })) {
            [pscustomobject]@{
                RestoreIndex = $index
                Name = [string]$backup.Name
                Kind = [string]$backup.Kind
                Scope = [string]$backup.Scope
                DisabledAt = [string]$backup.DisabledAt
            }
            $index++
        }
    )
}

function Get-DuplicateGroupRows {
    param([object[]]$Groups)

    return @(
        foreach ($group in @($Groups | Where-Object { $null -ne $_ })) {
            [pscustomobject]@{
                GroupId = [int]$group.GroupId
                Files = [int]$group.FileCount
                WastedSpace = (Format-Bytes ([long]$group.WastedBytes))
                Example = [string]$group.Files[0]
            }
        }
    )
}

function Get-QuarantineBatchRows {
    $index = 1
    return @(
        foreach ($batch in @(Get-QuarantineBatches | Where-Object { $null -ne $_ })) {
            [pscustomobject]@{
                RestoreIndex = $index
                BatchId = [string]$batch.BatchId
                CreatedAt = [string]$batch.CreatedAt
                Files = [int]$batch.FileCount
                RootPath = [string]$batch.RootPath
            }
            $index++
        }
    )
}

function Refresh-Overview {
    $identity = Get-AppIdentity
    $script:VersionValueLabel.Text = $identity.Version
    $script:ChannelValueLabel.Text = $identity.Channel
    $script:PublisherValueLabel.Text = if ([string]::IsNullOrWhiteSpace($identity.Publisher)) { "Unspecified" } else { $identity.Publisher }
    $script:AdminValueLabel.Text = if (Test-IsAdministrator) { "Yes" } else { "No" }

    $junkTotal = ((@(Get-JunkReport)) | Measure-Object -Property Size -Sum).Sum
    $startupCount = (@(Get-StartupItems)).Count
    $privacyCount = ((@(Get-PrivacyReport)) | Measure-Object -Property Count -Sum).Sum

    if ($script:OptimizeStatsLabel) {
        $script:OptimizeStatsLabel.Text = "Junk ready to clean: $(Format-Bytes ([long]$junkTotal))   |   Startup items detected: $startupCount   |   Local traces found: $privacyCount"
    }
    if ($script:OptimizeHintLabel) {
        $script:OptimizeHintLabel.Text = "Quick Optimize safely removes junk files and local privacy traces. It does not disable startup apps or touch personal duplicates without your input."
    }
}

function Invoke-QuickOptimize {
    $junkBefore = ((@(Get-JunkReport)) | Measure-Object -Property Size -Sum).Sum
    $privacyBefore = ((@(Get-PrivacyReport)) | Measure-Object -Property Count -Sum).Sum

    $null = Invoke-JunkCleanup
    $null = Clear-PrivacyTraces

    $junkAfter = ((@(Get-JunkReport)) | Measure-Object -Property Size -Sum).Sum
    $privacyAfter = ((@(Get-PrivacyReport)) | Measure-Object -Property Count -Sum).Sum

    [pscustomobject]@{
        ReclaimedBytes = ([long]$junkBefore - [long]$junkAfter)
        ClearedTraces = ([int]$privacyBefore - [int]$privacyAfter)
    }
}

function Refresh-JunkTab {
    $report = @(Get-JunkReport)
    Set-GridData -Grid $script:JunkGrid -Items $report
    $total = ($report | Measure-Object -Property Size -Sum).Sum
    $script:JunkSummaryLabel.Text = "Potential reclaimable space: $(Format-Bytes ([long]$total))"
}

function Refresh-StartupTab {
    Set-GridData -Grid $script:StartupGrid -Items @(Get-StartupItems)
    Set-GridData -Grid $script:DisabledStartupGrid -Items (Get-StartupBackupRows)
}

function Refresh-PrivacyTab {
    Set-GridData -Grid $script:PrivacyGrid -Items @(Get-PrivacyReport)
}

function Refresh-DuplicateGroups {
    $path = $script:DuplicatePathTextBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($path)) {
        throw "Choose a folder before scanning for duplicates."
    }

    $groups = @(Find-DuplicateFileGroups -RootPath $path)
    Save-DuplicateScanCache -RootPath $path -Groups $groups
    $script:GuiState.DuplicateGroups = $groups
    Set-GridData -Grid $script:DuplicateGrid -Items (Get-DuplicateGroupRows -Groups $groups)

    $totalWasted = ($groups | Measure-Object -Property WastedBytes -Sum).Sum
    $script:DuplicateSummaryLabel.Text = if ($groups.Count -gt 0) {
        "Duplicate groups: $($groups.Count) | Reclaimable space: $(Format-Bytes ([long]$totalWasted))"
    } else {
        "No duplicate groups were found."
    }

    $script:DuplicateDetailsTextBox.Text = ""
    Refresh-QuarantineTab
}

function Refresh-QuarantineTab {
    Set-GridData -Grid $script:QuarantineGrid -Items (Get-QuarantineBatchRows)
}

function Update-DuplicateDetails {
    $script:DuplicateDetailsTextBox.Text = ""
    if ($script:DuplicateGrid.SelectedRows.Count -eq 0) {
        return
    }

    $groupId = [int]$script:DuplicateGrid.SelectedRows[0].Cells["GroupId"].Value
    $group = @($script:GuiState.DuplicateGroups | Where-Object { [int]$_.GroupId -eq $groupId }) | Select-Object -First 1
    if ($null -eq $group) {
        return
    }

    $lines = @(
        "Group ID: $groupId"
        "Files:"
        ""
    ) + @($group.Files)

    $script:DuplicateDetailsTextBox.Text = ($lines -join [Environment]::NewLine)
}

function Open-DuplicateFolderPicker {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Choose a folder to scan for duplicate files"
    $dialog.UseDescriptionForTitle = $true
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:DuplicatePathTextBox.Text = $dialog.SelectedPath
    }
}

$script:MainForm = New-Object System.Windows.Forms.Form
$script:MainForm.Text = "PC Optimizer"
$script:MainForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$script:MainForm.MinimumSize = New-Object System.Drawing.Size(1160, 760)
$script:MainForm.Size = New-Object System.Drawing.Size(1280, 820)
$script:MainForm.BackColor = $script:Theme.Background
$script:MainForm.Font = New-UiFont -Family "Segoe UI" -Size 9.0

$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$headerPanel.Height = 96
$headerPanel.BackColor = $script:Theme.Ink
$script:MainForm.Controls.Add($headerPanel)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "PC Optimizer"
$titleLabel.ForeColor = [System.Drawing.Color]::White
$titleLabel.Location = New-Object System.Drawing.Point(24, 18)
$titleLabel.AutoSize = $true
$titleLabel.Font = New-UiFont -Family "Bahnschrift SemiBold" -Size 24.0
$headerPanel.Controls.Add($titleLabel)

$subtitleLabel = New-Object System.Windows.Forms.Label
$subtitleLabel.Text = "Clean clutter, control startup, remove duplicates, and ship updates from one visual console."
$subtitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(212, 223, 219)
$subtitleLabel.Location = New-Object System.Drawing.Point(27, 58)
$subtitleLabel.AutoSize = $true
$subtitleLabel.Font = New-UiFont -Family "Segoe UI" -Size 10.0
$headerPanel.Controls.Add($subtitleLabel)

$headerOptimizeButton = New-FlatButton -Text "Optimize Now" -Width 170 -Height 46 -BackColor $script:Theme.Accent
$headerOptimizeButton.Location = New-Object System.Drawing.Point(1060, 24)
$headerOptimizeButton.Font = New-UiFont -Family "Bahnschrift SemiBold" -Size 12.0
$headerPanel.Controls.Add($headerOptimizeButton)

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabControl.Appearance = [System.Windows.Forms.TabAppearance]::Normal
$script:MainForm.Controls.Add($tabControl)

$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$statusPanel.Height = 34
$statusPanel.BackColor = $script:Theme.Panel
$script:MainForm.Controls.Add($statusPanel)

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Text = "Ready."
$script:StatusLabel.Location = New-Object System.Drawing.Point(16, 9)
$script:StatusLabel.AutoSize = $true
$script:StatusLabel.Font = New-UiFont -Family "Segoe UI" -Size 9.0
$script:StatusLabel.ForeColor = $script:Theme.Muted
$statusPanel.Controls.Add($script:StatusLabel)

$overviewTab = New-Object System.Windows.Forms.TabPage
$overviewTab.Text = "Overview"
$overviewTab.BackColor = $script:Theme.Background
$null = $tabControl.TabPages.Add($overviewTab)

$overviewLayout = New-Object System.Windows.Forms.TableLayoutPanel
$overviewLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$overviewLayout.Padding = New-Object System.Windows.Forms.Padding(24, 18, 24, 18)
$overviewLayout.RowCount = 4
$overviewLayout.ColumnCount = 2
$null = $overviewLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$null = $overviewLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$null = $overviewLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 180)))
$null = $overviewLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 150)))
$null = $overviewLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 150)))
$null = $overviewLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$overviewTab.Controls.Add($overviewLayout)

function New-InfoCard {
    param(
        [string]$Heading,
        [ref]$ValueLabelRef
    )

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $panel.Margin = New-Object System.Windows.Forms.Padding(8)
    $panel.BackColor = $script:Theme.Surface
    $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $headingLabel = New-Object System.Windows.Forms.Label
    $headingLabel.Text = $Heading
    $headingLabel.Location = New-Object System.Drawing.Point(18, 18)
    $headingLabel.AutoSize = $true
    $headingLabel.Font = New-UiFont -Family "Segoe UI Semibold" -Size 10.0
    $headingLabel.ForeColor = $script:Theme.Muted
    $panel.Controls.Add($headingLabel)

    $valueLabel = New-Object System.Windows.Forms.Label
    $valueLabel.Text = "-"
    $valueLabel.Location = New-Object System.Drawing.Point(18, 62)
    $valueLabel.AutoSize = $true
    $valueLabel.Font = New-UiFont -Family "Bahnschrift SemiBold" -Size 22.0
    $valueLabel.ForeColor = $script:Theme.Ink
    $panel.Controls.Add($valueLabel)

    $ValueLabelRef.Value = $valueLabel
    return $panel
}

$script:VersionValueLabel = $null
$script:ChannelValueLabel = $null
$script:PublisherValueLabel = $null
$script:AdminValueLabel = $null

$optimizePanel = New-Object System.Windows.Forms.Panel
$optimizePanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$optimizePanel.Margin = New-Object System.Windows.Forms.Padding(8)
$optimizePanel.BackColor = $script:Theme.Ink
$optimizePanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$overviewLayout.SetColumnSpan($optimizePanel, 2)
$null = $overviewLayout.Controls.Add($optimizePanel, 0, 0)

$optimizeTitleLabel = New-Object System.Windows.Forms.Label
$optimizeTitleLabel.Text = "One-Click Optimize"
$optimizeTitleLabel.ForeColor = [System.Drawing.Color]::White
$optimizeTitleLabel.Location = New-Object System.Drawing.Point(18, 18)
$optimizeTitleLabel.AutoSize = $true
$optimizeTitleLabel.Font = New-UiFont -Family "Bahnschrift SemiBold" -Size 24.0
$optimizePanel.Controls.Add($optimizeTitleLabel)

$optimizeLeadLabel = New-Object System.Windows.Forms.Label
$optimizeLeadLabel.Text = "Clean junk files and local privacy traces in one pass, then refresh the dashboard so you can see what changed."
$optimizeLeadLabel.ForeColor = [System.Drawing.Color]::FromArgb(212, 223, 219)
$optimizeLeadLabel.Location = New-Object System.Drawing.Point(20, 56)
$optimizeLeadLabel.Size = New-Object System.Drawing.Size(700, 40)
$optimizeLeadLabel.Font = New-UiFont -Family "Segoe UI" -Size 10.0
$optimizePanel.Controls.Add($optimizeLeadLabel)

$script:OptimizeStatsLabel = New-Object System.Windows.Forms.Label
$script:OptimizeStatsLabel.ForeColor = [System.Drawing.Color]::White
$script:OptimizeStatsLabel.Location = New-Object System.Drawing.Point(20, 110)
$script:OptimizeStatsLabel.Size = New-Object System.Drawing.Size(760, 24)
$script:OptimizeStatsLabel.Font = New-UiFont -Family "Segoe UI Semibold" -Size 10.0
$optimizePanel.Controls.Add($script:OptimizeStatsLabel)

$script:OptimizeHintLabel = New-Object System.Windows.Forms.Label
$script:OptimizeHintLabel.ForeColor = [System.Drawing.Color]::FromArgb(212, 223, 219)
$script:OptimizeHintLabel.Location = New-Object System.Drawing.Point(20, 136)
$script:OptimizeHintLabel.Size = New-Object System.Drawing.Size(760, 24)
$script:OptimizeHintLabel.Font = New-UiFont -Family "Segoe UI" -Size 9.0
$optimizePanel.Controls.Add($script:OptimizeHintLabel)

$overviewOptimizeButton = New-FlatButton -Text "Optimize Computer" -Width 190 -Height 48 -BackColor $script:Theme.Accent
$overviewOptimizeButton.Location = New-Object System.Drawing.Point(860, 34)
$overviewOptimizeButton.Font = New-UiFont -Family "Bahnschrift SemiBold" -Size 12.0
$optimizePanel.Controls.Add($overviewOptimizeButton)

$overviewOptimizeNote = New-Object System.Windows.Forms.Label
$overviewOptimizeNote.Text = "Safe mode: no startup changes, no duplicate deletion."
$overviewOptimizeNote.ForeColor = [System.Drawing.Color]::White
$overviewOptimizeNote.Location = New-Object System.Drawing.Point(836, 92)
$overviewOptimizeNote.Size = New-Object System.Drawing.Size(250, 36)
$overviewOptimizeNote.Font = New-UiFont -Family "Segoe UI" -Size 9.0
$optimizePanel.Controls.Add($overviewOptimizeNote)

$null = $overviewLayout.Controls.Add((New-InfoCard -Heading "Installed Version" -ValueLabelRef ([ref]$script:VersionValueLabel)), 0, 1)
$null = $overviewLayout.Controls.Add((New-InfoCard -Heading "Update Channel" -ValueLabelRef ([ref]$script:ChannelValueLabel)), 1, 1)
$null = $overviewLayout.Controls.Add((New-InfoCard -Heading "Publisher" -ValueLabelRef ([ref]$script:PublisherValueLabel)), 0, 2)
$null = $overviewLayout.Controls.Add((New-InfoCard -Heading "Running As Admin" -ValueLabelRef ([ref]$script:AdminValueLabel)), 1, 2)

$updatePanel = New-Object System.Windows.Forms.Panel
$updatePanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$updatePanel.Margin = New-Object System.Windows.Forms.Padding(8)
$updatePanel.BackColor = $script:Theme.Surface
$updatePanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$overviewLayout.SetColumnSpan($updatePanel, 2)
$null = $overviewLayout.Controls.Add($updatePanel, 0, 3)

$updateHeading = New-SectionLabel -Text "Update Controls"
$updateHeading.Location = New-Object System.Drawing.Point(18, 18)
$updatePanel.Controls.Add($updateHeading)

$updateBody = New-BodyLabel -Text "Check the GitHub release feed or install the newest package in place."
$updateBody.Location = New-Object System.Drawing.Point(20, 50)
$updatePanel.Controls.Add($updateBody)

$checkUpdateButton = New-FlatButton -Text "Check For Updates" -Width 150
$checkUpdateButton.Location = New-Object System.Drawing.Point(20, 92)
$updatePanel.Controls.Add($checkUpdateButton)

$installUpdateButton = New-FlatButton -Text "Install Update" -Width 130 -BackColor $script:Theme.Success
$installUpdateButton.Location = New-Object System.Drawing.Point(182, 92)
$updatePanel.Controls.Add($installUpdateButton)

$openReleasesButton = New-FlatButton -Text "Open Releases" -Width 130 -BackColor $script:Theme.Panel -ForeColor $script:Theme.Ink
$openReleasesButton.Location = New-Object System.Drawing.Point(324, 92)
$updatePanel.Controls.Add($openReleasesButton)

$cleanupTab = New-Object System.Windows.Forms.TabPage
$cleanupTab.Text = "Cleanup"
$cleanupTab.BackColor = $script:Theme.Background
$null = $tabControl.TabPages.Add($cleanupTab)

$cleanupPanel = New-Object System.Windows.Forms.Panel
$cleanupPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$cleanupPanel.Padding = New-Object System.Windows.Forms.Padding(24, 18, 24, 18)
$cleanupTab.Controls.Add($cleanupPanel)

$cleanupTopPanel = New-Object System.Windows.Forms.Panel
$cleanupTopPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$cleanupTopPanel.Height = 80
$cleanupPanel.Controls.Add($cleanupTopPanel)

$cleanupHeading = New-SectionLabel -Text "Junk Cleanup"
$cleanupHeading.Location = New-Object System.Drawing.Point(0, 0)
$cleanupTopPanel.Controls.Add($cleanupHeading)

$script:JunkSummaryLabel = New-BodyLabel -Text "Potential reclaimable space: -"
$script:JunkSummaryLabel.Location = New-Object System.Drawing.Point(2, 34)
$cleanupTopPanel.Controls.Add($script:JunkSummaryLabel)

$refreshJunkButton = New-FlatButton -Text "Refresh Scan" -Width 120
$refreshJunkButton.Location = New-Object System.Drawing.Point(760, 22)
$cleanupTopPanel.Controls.Add($refreshJunkButton)

$cleanJunkButton = New-FlatButton -Text "Clean Now" -Width 120 -BackColor $script:Theme.Success
$cleanJunkButton.Location = New-Object System.Drawing.Point(892, 22)
$cleanupTopPanel.Controls.Add($cleanJunkButton)

$script:JunkGrid = New-ReadOnlyGrid
$cleanupPanel.Controls.Add($script:JunkGrid)

$startupTab = New-Object System.Windows.Forms.TabPage
$startupTab.Text = "Startup"
$startupTab.BackColor = $script:Theme.Background
$null = $tabControl.TabPages.Add($startupTab)

$startupSplit = New-Object System.Windows.Forms.SplitContainer
$startupSplit.Dock = [System.Windows.Forms.DockStyle]::Fill
$startupSplit.SplitterDistance = 720
$startupSplit.Panel1.Padding = New-Object System.Windows.Forms.Padding(24, 18, 12, 18)
$startupSplit.Panel2.Padding = New-Object System.Windows.Forms.Padding(12, 18, 24, 18)
$startupTab.Controls.Add($startupSplit)

$activeStartupPanel = New-Object System.Windows.Forms.Panel
$activeStartupPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$activeStartupPanel.BackColor = $script:Theme.Background
$startupSplit.Panel1.Controls.Add($activeStartupPanel)

$activeStartupHeader = New-Object System.Windows.Forms.Panel
$activeStartupHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$activeStartupHeader.Height = 78
$activeStartupPanel.Controls.Add($activeStartupHeader)

$activeStartupHeading = New-SectionLabel -Text "Startup Items"
$activeStartupHeading.Location = New-Object System.Drawing.Point(0, 0)
$activeStartupHeader.Controls.Add($activeStartupHeading)

$activeStartupBody = New-BodyLabel -Text "Select an item below to disable it from launching with Windows."
$activeStartupBody.Location = New-Object System.Drawing.Point(2, 34)
$activeStartupHeader.Controls.Add($activeStartupBody)

$refreshStartupButton = New-FlatButton -Text "Refresh" -Width 110
$refreshStartupButton.Location = New-Object System.Drawing.Point(430, 22)
$activeStartupHeader.Controls.Add($refreshStartupButton)

$disableStartupButton = New-FlatButton -Text "Disable Selected" -Width 140
$disableStartupButton.Location = New-Object System.Drawing.Point(552, 22)
$activeStartupHeader.Controls.Add($disableStartupButton)

$script:StartupGrid = New-ReadOnlyGrid
$activeStartupPanel.Controls.Add($script:StartupGrid)

$disabledStartupPanel = New-Object System.Windows.Forms.Panel
$disabledStartupPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$disabledStartupPanel.BackColor = $script:Theme.Background
$startupSplit.Panel2.Controls.Add($disabledStartupPanel)

$disabledStartupHeader = New-Object System.Windows.Forms.Panel
$disabledStartupHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$disabledStartupHeader.Height = 78
$disabledStartupPanel.Controls.Add($disabledStartupHeader)

$disabledStartupHeading = New-SectionLabel -Text "Disabled Items"
$disabledStartupHeading.Location = New-Object System.Drawing.Point(0, 0)
$disabledStartupHeader.Controls.Add($disabledStartupHeading)

$disabledStartupBody = New-BodyLabel -Text "Restore items you disabled earlier."
$disabledStartupBody.Location = New-Object System.Drawing.Point(2, 34)
$disabledStartupHeader.Controls.Add($disabledStartupBody)

$restoreStartupButton = New-FlatButton -Text "Restore Selected" -Width 140 -BackColor $script:Theme.Success
$restoreStartupButton.Location = New-Object System.Drawing.Point(258, 22)
$disabledStartupHeader.Controls.Add($restoreStartupButton)

$script:DisabledStartupGrid = New-ReadOnlyGrid
$disabledStartupPanel.Controls.Add($script:DisabledStartupGrid)

$privacyTab = New-Object System.Windows.Forms.TabPage
$privacyTab.Text = "Privacy"
$privacyTab.BackColor = $script:Theme.Background
$null = $tabControl.TabPages.Add($privacyTab)

$privacyPanel = New-Object System.Windows.Forms.Panel
$privacyPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$privacyPanel.Padding = New-Object System.Windows.Forms.Padding(24, 18, 24, 18)
$privacyTab.Controls.Add($privacyPanel)

$privacyTopPanel = New-Object System.Windows.Forms.Panel
$privacyTopPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$privacyTopPanel.Height = 80
$privacyPanel.Controls.Add($privacyTopPanel)

$privacyHeading = New-SectionLabel -Text "Privacy Traces"
$privacyHeading.Location = New-Object System.Drawing.Point(0, 0)
$privacyTopPanel.Controls.Add($privacyHeading)

$privacyBody = New-BodyLabel -Text "Inspect and clear recent-file shortcuts, typed paths, Run history, and PowerShell history."
$privacyBody.Location = New-Object System.Drawing.Point(2, 34)
$privacyTopPanel.Controls.Add($privacyBody)

$refreshPrivacyButton = New-FlatButton -Text "Refresh" -Width 110
$refreshPrivacyButton.Location = New-Object System.Drawing.Point(760, 22)
$privacyTopPanel.Controls.Add($refreshPrivacyButton)

$clearPrivacyButton = New-FlatButton -Text "Clear Traces" -Width 120 -BackColor $script:Theme.Success
$clearPrivacyButton.Location = New-Object System.Drawing.Point(882, 22)
$privacyTopPanel.Controls.Add($clearPrivacyButton)

$script:PrivacyGrid = New-ReadOnlyGrid
$privacyPanel.Controls.Add($script:PrivacyGrid)

$duplicatesTab = New-Object System.Windows.Forms.TabPage
$duplicatesTab.Text = "Duplicates"
$duplicatesTab.BackColor = $script:Theme.Background
$null = $tabControl.TabPages.Add($duplicatesTab)

$duplicatesOuterPanel = New-Object System.Windows.Forms.Panel
$duplicatesOuterPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$duplicatesOuterPanel.Padding = New-Object System.Windows.Forms.Padding(24, 18, 24, 18)
$duplicatesTab.Controls.Add($duplicatesOuterPanel)

$duplicateTopPanel = New-Object System.Windows.Forms.Panel
$duplicateTopPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$duplicateTopPanel.Height = 90
$duplicatesOuterPanel.Controls.Add($duplicateTopPanel)

$duplicateHeading = New-SectionLabel -Text "Duplicate Files"
$duplicateHeading.Location = New-Object System.Drawing.Point(0, 0)
$duplicateTopPanel.Controls.Add($duplicateHeading)

$duplicateBody = New-BodyLabel -Text "Choose a folder, scan duplicate groups, then quarantine extra copies instead of deleting them."
$duplicateBody.Location = New-Object System.Drawing.Point(2, 34)
$duplicateTopPanel.Controls.Add($duplicateBody)

$script:DuplicatePathTextBox = New-Object System.Windows.Forms.TextBox
$script:DuplicatePathTextBox.Location = New-Object System.Drawing.Point(4, 58)
$script:DuplicatePathTextBox.Width = 720
$script:DuplicatePathTextBox.Font = New-UiFont -Family "Segoe UI" -Size 9.0
$duplicateTopPanel.Controls.Add($script:DuplicatePathTextBox)

$browseDuplicateButton = New-FlatButton -Text "Browse" -Width 90 -BackColor $script:Theme.Panel -ForeColor $script:Theme.Ink
$browseDuplicateButton.Location = New-Object System.Drawing.Point(736, 54)
$duplicateTopPanel.Controls.Add($browseDuplicateButton)

$scanDuplicateButton = New-FlatButton -Text "Scan" -Width 90
$scanDuplicateButton.Location = New-Object System.Drawing.Point(836, 54)
$duplicateTopPanel.Controls.Add($scanDuplicateButton)

$duplicateSplit = New-Object System.Windows.Forms.SplitContainer
$duplicateSplit.Dock = [System.Windows.Forms.DockStyle]::Fill
$duplicateSplit.SplitterDistance = 660
$duplicatesOuterPanel.Controls.Add($duplicateSplit)

$duplicateLeftPanel = New-Object System.Windows.Forms.Panel
$duplicateLeftPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$duplicateLeftPanel.Padding = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)
$duplicateSplit.Panel1.Controls.Add($duplicateLeftPanel)

$duplicateLeftHeader = New-Object System.Windows.Forms.Panel
$duplicateLeftHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$duplicateLeftHeader.Height = 70
$duplicateLeftPanel.Controls.Add($duplicateLeftHeader)

$script:DuplicateSummaryLabel = New-BodyLabel -Text "No scan yet."
$script:DuplicateSummaryLabel.Location = New-Object System.Drawing.Point(0, 8)
$duplicateLeftHeader.Controls.Add($script:DuplicateSummaryLabel)

$quarantineOldestButton = New-FlatButton -Text "Keep Oldest" -Width 110 -BackColor $script:Theme.Success
$quarantineOldestButton.Location = New-Object System.Drawing.Point(0, 32)
$duplicateLeftHeader.Controls.Add($quarantineOldestButton)

$quarantineNewestButton = New-FlatButton -Text "Keep Newest" -Width 110 -BackColor $script:Theme.Success
$quarantineNewestButton.Location = New-Object System.Drawing.Point(122, 32)
$duplicateLeftHeader.Controls.Add($quarantineNewestButton)

$quarantineFirstButton = New-FlatButton -Text "Keep First" -Width 100 -BackColor $script:Theme.Success
$quarantineFirstButton.Location = New-Object System.Drawing.Point(244, 32)
$duplicateLeftHeader.Controls.Add($quarantineFirstButton)

$script:DuplicateGrid = New-ReadOnlyGrid
$duplicateLeftPanel.Controls.Add($script:DuplicateGrid)

$duplicateRightSplit = New-Object System.Windows.Forms.SplitContainer
$duplicateRightSplit.Dock = [System.Windows.Forms.DockStyle]::Fill
$duplicateRightSplit.Orientation = [System.Windows.Forms.Orientation]::Horizontal
$duplicateRightSplit.SplitterDistance = 270
$duplicateSplit.Panel2.Controls.Add($duplicateRightSplit)

$duplicateDetailsPanel = New-Object System.Windows.Forms.Panel
$duplicateDetailsPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$duplicateDetailsPanel.Padding = New-Object System.Windows.Forms.Padding(12, 0, 0, 12)
$duplicateRightSplit.Panel1.Controls.Add($duplicateDetailsPanel)

$duplicateDetailsHeading = New-SectionLabel -Text "Selected Group Files"
$duplicateDetailsHeading.Location = New-Object System.Drawing.Point(0, 0)
$duplicateDetailsPanel.Controls.Add($duplicateDetailsHeading)

$script:DuplicateDetailsTextBox = New-Object System.Windows.Forms.TextBox
$script:DuplicateDetailsTextBox.Location = New-Object System.Drawing.Point(0, 34)
$script:DuplicateDetailsTextBox.Multiline = $true
$script:DuplicateDetailsTextBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$script:DuplicateDetailsTextBox.ReadOnly = $true
$script:DuplicateDetailsTextBox.Width = 450
$script:DuplicateDetailsTextBox.Height = 210
$script:DuplicateDetailsTextBox.BackColor = $script:Theme.Surface
$script:DuplicateDetailsTextBox.ForeColor = $script:Theme.Ink
$script:DuplicateDetailsTextBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$duplicateDetailsPanel.Controls.Add($script:DuplicateDetailsTextBox)

$quarantinePanel = New-Object System.Windows.Forms.Panel
$quarantinePanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$quarantinePanel.Padding = New-Object System.Windows.Forms.Padding(12, 0, 0, 0)
$duplicateRightSplit.Panel2.Controls.Add($quarantinePanel)

$quarantineHeading = New-SectionLabel -Text "Quarantine Batches"
$quarantineHeading.Location = New-Object System.Drawing.Point(0, 0)
$quarantinePanel.Controls.Add($quarantineHeading)

$refreshQuarantineButton = New-FlatButton -Text "Refresh Batches" -Width 120 -BackColor $script:Theme.Panel -ForeColor $script:Theme.Ink
$refreshQuarantineButton.Location = New-Object System.Drawing.Point(0, 30)
$quarantinePanel.Controls.Add($refreshQuarantineButton)

$restoreQuarantineButton = New-FlatButton -Text "Restore Batch" -Width 120
$restoreQuarantineButton.Location = New-Object System.Drawing.Point(132, 30)
$quarantinePanel.Controls.Add($restoreQuarantineButton)

$script:QuarantineGrid = New-ReadOnlyGrid
$script:QuarantineGrid.Location = New-Object System.Drawing.Point(0, 72)
$script:QuarantineGrid.Height = 190
$quarantinePanel.Controls.Add($script:QuarantineGrid)

$checkUpdateButton.Add_Click({
    Invoke-UiAction -SuccessMessage "Update check finished." -Action {
        $identity = Get-AppIdentity
        $remote = Get-RemoteUpdateInfo
        $remoteVersion = [string]$remote.version
        $installedVersion = [string]$identity.Version
        if ((ConvertTo-VersionObject $remoteVersion) -gt (ConvertTo-VersionObject $installedVersion)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Installed version: $installedVersion`nLatest version: $remoteVersion",
                "Update Available",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "You already have the latest version: $installedVersion",
                "Up To Date",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
    }
})

$installUpdateButton.Add_Click({
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Download and install the newest available version now?",
        "Install Update",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    Invoke-UiAction -SuccessMessage "Updater launched." -Action {
        Invoke-SelfUpdate
    }
})

$openReleasesButton.Add_Click({
    Invoke-UiAction -SuccessMessage "Opened release page." -Action {
        $url = Get-AppReleaseBaseUrl
        if ([string]::IsNullOrWhiteSpace($url)) {
            throw "GitHub release URL is not configured."
        }
        Start-Process $url
    }
})

function Start-QuickOptimizeFromGui {
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Quick Optimize will clean junk files and clear local privacy traces. Continue?",
        "Optimize Computer",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    Invoke-UiAction -SuccessMessage "Quick optimization completed." -Action {
        $summary = Invoke-QuickOptimize
        Refresh-Overview
        Refresh-JunkTab
        Refresh-PrivacyTab
        [System.Windows.Forms.MessageBox]::Show(
            ("Optimization finished.`n`nEstimated space reclaimed: {0}`nPrivacy traces cleared: {1}" -f (Format-Bytes ([long]$summary.ReclaimedBytes)), $summary.ClearedTraces),
            "PC Optimizer",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
}

$headerOptimizeButton.Add_Click({ Start-QuickOptimizeFromGui })
$overviewOptimizeButton.Add_Click({ Start-QuickOptimizeFromGui })

$refreshJunkButton.Add_Click({
    Invoke-UiAction -SuccessMessage "Junk scan refreshed." -Action {
        Refresh-JunkTab
        Refresh-Overview
    }
})

$cleanJunkButton.Add_Click({
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Clean the junk-file targets shown in the list?",
        "Junk Cleanup",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    Invoke-UiAction -SuccessMessage "Junk cleanup completed." -Action {
        Invoke-JunkCleanup | Out-Null
        Refresh-JunkTab
        Refresh-Overview
    }
})

$refreshStartupButton.Add_Click({
    Invoke-UiAction -SuccessMessage "Startup lists refreshed." -Action {
        Refresh-StartupTab
    }
})

$disableStartupButton.Add_Click({
    if ($script:StartupGrid.SelectedRows.Count -eq 0) {
        Set-StatusMessage -Text "Select a startup item first." -Color $script:Theme.Error
        return
    }

    $selectedIndex = [int]$script:StartupGrid.SelectedRows[0].Cells["Index"].Value
    Invoke-UiAction -SuccessMessage "Startup item disabled." -Action {
        Disable-StartupItem -SelectedIndex $selectedIndex
        Refresh-StartupTab
    }
})

$restoreStartupButton.Add_Click({
    if ($script:DisabledStartupGrid.SelectedRows.Count -eq 0) {
        Set-StatusMessage -Text "Select a disabled startup item first." -Color $script:Theme.Error
        return
    }

    $selectedIndex = [int]$script:DisabledStartupGrid.SelectedRows[0].Cells["RestoreIndex"].Value
    Invoke-UiAction -SuccessMessage "Startup item restored." -Action {
        Restore-StartupItem -SelectedIndex $selectedIndex
        Refresh-StartupTab
    }
})

$refreshPrivacyButton.Add_Click({
    Invoke-UiAction -SuccessMessage "Privacy report refreshed." -Action {
        Refresh-PrivacyTab
        Refresh-Overview
    }
})

$clearPrivacyButton.Add_Click({
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Clear the privacy traces shown on this tab?",
        "Clear Privacy Traces",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    Invoke-UiAction -SuccessMessage "Privacy traces cleared." -Action {
        Clear-PrivacyTraces | Out-Null
        Refresh-PrivacyTab
        Refresh-Overview
    }
})

$browseDuplicateButton.Add_Click({
    Open-DuplicateFolderPicker
})

$scanDuplicateButton.Add_Click({
    Invoke-UiAction -SuccessMessage "Duplicate scan finished." -Action {
        Refresh-DuplicateGroups
    }
})

$script:DuplicateGrid.Add_SelectionChanged({
    Update-DuplicateDetails
})

function Invoke-QuarantineFromGui {
    param([string]$KeepMode)

    $path = $script:DuplicatePathTextBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($path)) {
        Set-StatusMessage -Text "Choose and scan a folder first." -Color $script:Theme.Error
        return
    }

    if (@($script:GuiState.DuplicateGroups).Count -eq 0) {
        Set-StatusMessage -Text "No duplicate groups are loaded." -Color $script:Theme.Error
        return
    }

    Invoke-UiAction -SuccessMessage "Duplicate files moved to quarantine." -Action {
        Invoke-DuplicateQuarantine -RootPath $path -Groups $script:GuiState.DuplicateGroups -KeepMode $KeepMode
        Refresh-DuplicateGroups
    }
}

$quarantineOldestButton.Add_Click({ Invoke-QuarantineFromGui -KeepMode "Oldest" })
$quarantineNewestButton.Add_Click({ Invoke-QuarantineFromGui -KeepMode "Newest" })
$quarantineFirstButton.Add_Click({ Invoke-QuarantineFromGui -KeepMode "First" })

$refreshQuarantineButton.Add_Click({
    Invoke-UiAction -SuccessMessage "Quarantine batches refreshed." -Action {
        Refresh-QuarantineTab
    }
})

$restoreQuarantineButton.Add_Click({
    if ($script:QuarantineGrid.SelectedRows.Count -eq 0) {
        Set-StatusMessage -Text "Select a quarantine batch first." -Color $script:Theme.Error
        return
    }

    $selectedIndex = [int]$script:QuarantineGrid.SelectedRows[0].Cells["RestoreIndex"].Value
    Invoke-UiAction -SuccessMessage "Quarantine batch restored." -Action {
        Restore-QuarantineBatch -SelectedIndex $selectedIndex
        Refresh-QuarantineTab
    }
})

$script:MainForm.Add_Shown({
    Invoke-UiAction -SuccessMessage "PC Optimizer is ready." -Action {
        Refresh-Overview
        Refresh-JunkTab
        Refresh-StartupTab
        Refresh-PrivacyTab
        Refresh-QuarantineTab
    }
})

if ($NoShow) {
    Refresh-Overview
    Refresh-JunkTab
    Refresh-StartupTab
    Refresh-PrivacyTab
    Refresh-QuarantineTab
    return
}

[void]$script:MainForm.ShowDialog()

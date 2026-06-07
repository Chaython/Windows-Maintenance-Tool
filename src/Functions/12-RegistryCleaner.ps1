# Functional block generated from WMT-GUI.ps1.
# Dot-source this file; it intentionally shares WMT's script scope.

function Start-RegClean {
    Invoke-UiCommand {
        $bkDir = Join-Path (Get-DataPath) "RegistryBackups"
        if (!(Test-Path $bkDir)) { New-Item -Path $bkDir -ItemType Directory | Out-Null }
        $bkFile = "$bkDir\Backup_$(Get-Date -F 'yyyyMMdd_HHmm').reg"
        reg export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" $bkFile /y | Out-Null
        $keys = Get-ChildItem HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall | Where-Object { $_.PSChildName -match 'IE40|IE4Data|DirectDrawEx|DXM_Runtime|SchedulingAgent' }
        if ($keys) { foreach ($k in $keys) { Remove-Item $k.PSPath -Recurse -Force; Write-Output "Removed: $($k.PSChildName)" } } else { Write-Output "No obsolete keys found." }
        Write-Output "Backup saved to: $bkFile"
    } "Cleaning Registry..."
}

function Show-RegScanSelection {
    # 1. LOAD SETTINGS
    $currentSettings = Get-WmtSettings
    $savedStates = $currentSettings.RegistryScan

    # --- Define Categories ---
    $categories = [ordered]@{
        "Missing Shared DLLs"             = "SharedDLLs"
        "Unused File Extensions (System)" = "Ext"
        "Unused File Extensions (User)"   = "FileExts"
        "ActiveX & COM Issues"            = "ActiveX"
        "Type Libraries (TLB)"            = "TypeLib"
        "Application Paths"               = "AppPaths"
        "Applications (Registered)"       = "Apps"
        "Installer Folders"               = "Installer"
        "Obsolete Software (Uninstall)"   = "Uninstall"
        "Run At Startup"                  = "Startup"
        "Invalid Default Icons"           = "Icons"
        "File Associations"               = "ProgIDs"
        "Windows Services"                = "Services"
        "MUI Cache (MRU Lists)"           = "MuiCache"
        "Compatibility Store (Flags)"     = "AppCompat"
        "Notification Area Icons"         = "NotifyIcons"
        "Obsolete App Module Caches"      = "AppModules"
        "Empty User Software Keys"        = "EmptyUserSoftware"
        "Shell Extensions"                = "ShellExtensions"
        "Explorer Namespace Entries"      = "ExplorerNamespace"
        "Font Entries"                    = "Fonts"
        "App Execution Aliases"           = "AppAliases"
        "Scheduled Task Cache"            = "TaskCache"
        "Scheduled Task Actions"          = "TaskActions"
        "Uninstall Metadata Values"       = "UninstallMetadata"
        "Environment PATH Entries"        = "EnvPath"
        "RunOnce & Policy Startup"        = "StartupExtended"
        "AppCompat Layers"                = "AppCompatLayers"
        "User MRU Caches"                 = "UserMru"
        "Per-User Shell Commands"         = "UserShellCommands"
        "Image File Execution Options"    = "IFEO"
        "Firewall Rules"                  = "Firewall"
    }

    foreach ($savedKey in @($savedStates.Keys)) {
        if ($savedKey -notin @($categories.Values)) {
            [void]$currentSettings.RegistryScan.Remove($savedKey)
        }
    }

    [xml]$regScanXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Select Registry Scan Targets" Width="680" Height="720" MinWidth="620" MinHeight="640"
        WindowStartupLocation="CenterOwner" Background="{DynamicResource BgDark}" Foreground="{DynamicResource TextPrimary}"
        FontFamily="Segoe UI Variable Display, Segoe UI, Arial" FontSize="13">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Height" Value="34"/>
            <Setter Property="MinWidth" Value="106"/>
            <Setter Property="Margin" Value="6,0,0,0"/>
            <Setter Property="Padding" Value="14,0"/>
            <Setter Property="Background" Value="{DynamicResource BgElevated}"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="Margin" Value="0,0,16,10"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
        </Style>
    </Window.Resources>
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Margin="0,0,0,14">
            <TextBlock Text="Select areas to scan" FontSize="18" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}"/>
            <TextBlock Text="Checked targets are saved for future registry scans." Margin="0,4,0,0" Foreground="{DynamicResource TextSecondary}"/>
        </StackPanel>

        <Border Grid.Row="1" Background="{DynamicResource BgPanel}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="4" Padding="14">
            <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <UniformGrid Name="pnlChecks" Columns="2"/>
            </ScrollViewer>
        </Border>

        <Grid Grid.Row="2" Margin="0,14,0,0">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
                <Button Name="btnCancel" Content="Cancel" IsCancel="True"/>
                <Button Name="btnBackupHKLM" Content="Export HKLM"/>
                <Button Name="btnRestore" Content="Import Backup"/>
            </StackPanel>
            <Button Name="btnScan" Content="Start Deep Scan" HorizontalAlignment="Right" Background="{DynamicResource Success}" Foreground="{DynamicResource SuccessText}" IsDefault="True"/>
        </Grid>
    </Grid>
</Window>
'@

    $dialog = New-WmtWindowFromFullXaml -Xaml $regScanXaml

    $pnlChecks = $dialog.FindName("pnlChecks")
    $btnBackupHKLM = $dialog.FindName("btnBackupHKLM")
    $btnRestore = $dialog.FindName("btnRestore")
    $btnScan = $dialog.FindName("btnScan")

    $chkBoxes = [System.Collections.Generic.List[object]]::new()
    foreach ($key in $categories.Keys) {
        $tag = $categories[$key]
        $chk = [System.Windows.Controls.CheckBox]::new()
        $chk.Content = $key
        $chk.Tag = $tag
        $chk.IsChecked = if ($savedStates.ContainsKey($tag)) { [bool]$savedStates[$tag] } else { $true }
        [void]$pnlChecks.Children.Add($chk)
        [void]$chkBoxes.Add($chk)
    }

    $btnBackupHKLM.Add_Click({ Invoke-RegistryTask -Action "BackupHKLM" }.GetNewClosure())
    $btnRestore.Add_Click({ Invoke-RegistryTask -Action "Restore" }.GetNewClosure())
    $btnScan.Add_Click({
            $selected = [System.Collections.Generic.List[object]]::new()
            foreach ($c in $chkBoxes) {
                if ([bool]$c.IsChecked) { [void]$selected.Add($c.Tag) }
                $currentSettings.RegistryScan[$c.Tag] = [bool]$c.IsChecked
            }
            Save-WmtSettings -Settings $currentSettings

            $dialog.Tag = @($selected)
            $dialog.DialogResult = $true
            $dialog.Close()
        }.GetNewClosure())

    if ($dialog.ShowDialog() -eq $true) { return $dialog.Tag }
    return $null
}

function Show-RegistryCleaner {
    param($ScanResults)

    function script:ConvertTo-WmtRegistryResultClipboardText {
        param([object[]]$Rows)

        $selectedRows = @($Rows | Where-Object { $null -ne $_ })
        $lines = [System.Collections.Generic.List[string]]::new()
        [void]$lines.Add("WMT Registry Cleaner Details")
        [void]$lines.Add("Count: $($selectedRows.Count)")
        [void]$lines.Add("")

        $index = 1
        foreach ($row in $selectedRows) {
            $cleanValue = {
                param($Value)
                if ($null -eq $Value) { return "" }
                $text = [string]$Value
                $text = $text -replace '\r?\n', ' '
                $text = $text -replace "`t", ' '
                return $text.Trim()
            }

            [void]$lines.Add("$index) $(& $cleanValue $row.Problem)")
            [void]$lines.Add("   Action: $(& $cleanValue $row.FixAction)")
            [void]$lines.Add("   Risk: $(& $cleanValue $row.Risk)")
            [void]$lines.Add("   Confidence: $(& $cleanValue $row.Confidence)")
            [void]$lines.Add("   Default: $(& $cleanValue $row.DefaultAction)")
            [void]$lines.Add("   Type: $(& $cleanValue $row.Type)")
            [void]$lines.Add("   Value: $(& $cleanValue $row.ValueName)")
            [void]$lines.Add("   Data (Path/Value): $(& $cleanValue $row.Data)")
            [void]$lines.Add("   Display Key: $(& $cleanValue $row.Key)")
            [void]$lines.Add("   Exact Registry Path: $(& $cleanValue $row.FullPath)")
            if (-not [string]::IsNullOrWhiteSpace([string]$row.NewData)) {
                [void]$lines.Add("   New Data: $(& $cleanValue $row.NewData)")
            }
            [void]$lines.Add("   Why Flagged: $(& $cleanValue $row.Details)")
            [void]$lines.Add("")
            $index++
        }

        return ($lines -join [Environment]::NewLine)
    }

    function script:ConvertTo-WmtRegeditPath {
        param([string]$RegistryPath)

        if ([string]::IsNullOrWhiteSpace($RegistryPath)) { return $null }
        $normalized = ([string]$RegistryPath).Trim()
        $normalized = $normalized -replace '/', '\'
        $normalized = $normalized -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
        $normalized = $normalized.TrimEnd('\')

        if ($normalized -match '^(?i)(HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER|HKEY_CLASSES_ROOT|HKEY_USERS|HKEY_CURRENT_CONFIG)(\\.*)?$') {
            return $normalized
        }
        if ($normalized -match '^(?i)HKLM:\\?(?<Rest>.*)$') {
            return "HKEY_LOCAL_MACHINE\$($Matches.Rest.TrimStart('\'))".TrimEnd('\')
        }
        if ($normalized -match '^(?i)HKCU:\\?(?<Rest>.*)$') {
            return "HKEY_CURRENT_USER\$($Matches.Rest.TrimStart('\'))".TrimEnd('\')
        }
        if ($normalized -match '^(?i)HKCR:\\?(?<Rest>.*)$') {
            return "HKEY_CLASSES_ROOT\$($Matches.Rest.TrimStart('\'))".TrimEnd('\')
        }
        if ($normalized -match '^(?i)HKU:\\?(?<Rest>.*)$') {
            return "HKEY_USERS\$($Matches.Rest.TrimStart('\'))".TrimEnd('\')
        }
        if ($normalized -match '^(?i)HKCC:\\?(?<Rest>.*)$') {
            return "HKEY_CURRENT_CONFIG\$($Matches.Rest.TrimStart('\'))".TrimEnd('\')
        }

        return $normalized
    }

    function script:Open-WmtRegistryPathInRegedit {
        param([string]$RegistryPath)

        $regeditPath = ConvertTo-WmtRegeditPath -RegistryPath $RegistryPath
        if ([string]::IsNullOrWhiteSpace($regeditPath)) {
            [System.Windows.MessageBox]::Show("No registry path is available for the selected result.", "Registry Cleaner", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
            return $false
        }

        try {
            $regeditStatePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit'
            if (-not (Test-Path -LiteralPath $regeditStatePath)) {
                [void](New-Item -Path $regeditStatePath -Force)
            }
            Set-ItemProperty -LiteralPath $regeditStatePath -Name LastKey -Value $regeditPath -Force
            Start-Process -FilePath "regedit.exe" | Out-Null
            return $true
        }
        catch {
            [System.Windows.MessageBox]::Show("Could not open Regedit to:`n$regeditPath`n`n$($_.Exception.Message)", "Registry Cleaner", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
            return $false
        }
    }

    function script:Get-WmtVisualParentOfType {
        param(
            [object]$Source,
            [type]$TargetType
        )

        if ($null -eq $Source -or $null -eq $TargetType) { return $null }

        $current = $Source
        while ($null -ne $current) {
            try {
                if ($TargetType.IsInstanceOfType($current)) { return $current }
            }
            catch {
                return $null
            }

            # VisualTreeHelper.GetParent only accepts DependencyObject instances.
            # Right-clicks on headers, scrollbars, adorner elements, or text runs can
            # surface non-visual objects; do not let that bubble into an unhandled WPF
            # event exception and terminate the script.
            if (-not ($current -is [System.Windows.DependencyObject])) { return $null }

            try {
                $current = [System.Windows.Media.VisualTreeHelper]::GetParent([System.Windows.DependencyObject]$current)
            }
            catch {
                return $null
            }
        }
        return $null
    }

    function script:Select-WmtRegistryGridRowFromOriginalSource {
        param(
            [System.Windows.Controls.DataGrid]$Grid,
            [object]$OriginalSource
        )

        if ($null -eq $Grid -or $null -eq $OriginalSource) { return $false }

        try {
            $rowElement = Get-WmtVisualParentOfType -Source $OriginalSource -TargetType ([System.Windows.Controls.DataGridRow])
            if ($null -eq $rowElement) { return $false }

            if (-not $rowElement.IsSelected) {
                try { $Grid.SelectedItems.Clear() } catch {}
                try { $rowElement.IsSelected = $true } catch {}
            }

            try { $Grid.SelectedItem = $rowElement.Item } catch {}
            try { $Grid.CurrentItem = $rowElement.Item } catch {}
            try { [void]$rowElement.Focus() } catch {}
            return $true
        }
        catch {
            try { Write-GuiLog "Registry result right-click row selection failed: $($_.Exception.Message)" } catch {}
            return $false
        }
    }

    function Test-WmtRegistryFindingAutoSelected {
        param($Item)

        if ($Item -and $Item.PSObject.Properties["SafeToFix"]) {
            return [bool]$Item.SafeToFix
        }

        $problem = [string]$Item.Problem
        $type = [string]$Item.Type
        $reviewOnlyPatterns = @(
            '^ActiveX Issue$',
            '^Protected ActiveX Issue$',
            '^Unused Extension$',
            '^Missing App Path$',
            '^Invalid App Command',
            '^Missing Uninstaller$',
            '^Obsolete App Module Cache$',
            '^Empty User Software Key$',
            '^Invalid Shell Extension$',
            '^Invalid Explorer Namespace$',
            '^Invalid Font Entry$',
            '^Orphaned TaskCache',
            '^Invalid User Shell Command$',
            '^Orphaned Service$',
            '^Missing HelpDir$',
            '^Missing TypeLib Path$',
            '^Invalid Default Icon$',
            '^Missing Shared Ref$'
        )

        foreach ($pattern in $reviewOnlyPatterns) {
            if ($problem -match $pattern) { return $false }
        }

        if ($type -eq "Key" -and $problem -ne "Obsolete Notify Icon") {
            return $false
        }

        return $true
    }

    [xml]$registryCleanerXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Deep Registry Cleaner" Width="1280" Height="680" MinWidth="980" MinHeight="560"
        WindowStartupLocation="CenterOwner" Background="{DynamicResource BgDark}" Foreground="{DynamicResource TextPrimary}"
        FontFamily="Segoe UI Variable Display, Segoe UI, Arial" FontSize="13">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Height" Value="34"/>
            <Setter Property="MinWidth" Value="104"/>
            <Setter Property="Margin" Value="6,0,0,0"/>
            <Setter Property="Padding" Value="14,0"/>
            <Setter Property="Background" Value="{DynamicResource BgElevated}"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style TargetType="DataGrid">
            <Setter Property="Background" Value="{DynamicResource BgDark}"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="GridLinesVisibility" Value="Horizontal"/>
            <Setter Property="HorizontalGridLinesBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="VerticalGridLinesBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="RowBackground" Value="{DynamicResource BgDark}"/>
            <Setter Property="AlternatingRowBackground" Value="{DynamicResource BgPanel}"/>
            <Setter Property="CanUserAddRows" Value="False"/>
            <Setter Property="CanUserDeleteRows" Value="False"/>
            <Setter Property="HeadersVisibility" Value="Column"/>
            <Setter Property="SelectionMode" Value="Extended"/>
            <Setter Property="SelectionUnit" Value="FullRow"/>
            <Setter Property="AutoGenerateColumns" Value="False"/>
            <Setter Property="ClipboardCopyMode" Value="IncludeHeader"/>
        </Style>
        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="{DynamicResource BgPanel}"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="0,0,1,1"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>
        <Style TargetType="DataGridCell">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="6,3"/>
        </Style>
        <Style TargetType="DataGridRow">
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="{DynamicResource Accent}"/>
                    <Setter Property="Foreground" Value="{DynamicResource AccentText}"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="{DynamicResource BgPanel}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="4" Padding="14" Margin="0,0,0,12">
            <StackPanel>
                <TextBlock Name="lblStatus" FontSize="18" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}"/>
                <TextBlock Text="Review checked findings before fixing. Missing-file COM server entries are selected by default unless WMT classifies them as protected/merged Microsoft COM registrations. Press Enter to check highlighted rows. Right-click a row to open its key in Regedit or copy details. Review-only rows are never fixed automatically." Margin="0,4,0,0" Foreground="{DynamicResource TextSecondary}"/>
            </StackPanel>
        </Border>

        <DataGrid Name="dgRegistry" Grid.Row="1" AlternationCount="2">
            <DataGrid.Columns>
                <DataGridTemplateColumn Header=" " Width="42" SortMemberPath="Check">
                    <DataGridTemplateColumn.CellTemplate>
                        <DataTemplate>
                            <CheckBox IsChecked="{Binding Check, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"
                                      HorizontalAlignment="Center"
                                      VerticalAlignment="Center"
                                      Focusable="False"/>
                        </DataTemplate>
                    </DataGridTemplateColumn.CellTemplate>
                </DataGridTemplateColumn>
                <DataGridTextColumn Header="Problem" Binding="{Binding Problem}" Width="185" IsReadOnly="True"/>
                <DataGridTextColumn Header="Action" Binding="{Binding FixAction}" Width="90" IsReadOnly="True"/>
                <DataGridTextColumn Header="Risk" Binding="{Binding Risk}" Width="75" IsReadOnly="True"/>
                <DataGridTextColumn Header="Confidence" Binding="{Binding Confidence}" Width="92" IsReadOnly="True"/>
                <DataGridTextColumn Header="Default" Binding="{Binding DefaultAction}" Width="82" IsReadOnly="True"/>
                <DataGridTextColumn Header="Type" Binding="{Binding Type}" Width="80" IsReadOnly="True"/>
                <DataGridTextColumn Header="Value" Binding="{Binding ValueName}" Width="150" IsReadOnly="True"/>
                <DataGridTextColumn Header="Data (Path/Value)" Binding="{Binding Data}" Width="2*" IsReadOnly="True"/>
                <DataGridTextColumn Header="Display Key" Binding="{Binding Key}" Width="1.4*" IsReadOnly="True"/>
                <DataGridTextColumn Header="Exact Registry Path" Binding="{Binding FullPath}" Width="2*" IsReadOnly="True"/>
                <DataGridTextColumn Header="Why Flagged" Binding="{Binding Details}" Width="2*" IsReadOnly="True"/>
            </DataGrid.Columns>
        </DataGrid>

        <Grid Grid.Row="2" Margin="0,12,0,0">
            <Button Name="btnClose" Content="Close" IsCancel="True" HorizontalAlignment="Left"/>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <Button Name="btnCopySelected" Content="Copy Selected Details" MinWidth="160"/>
                <Button Name="btnCopyAll" Content="Copy All Details" MinWidth="140"/>
                <Button Name="btnFix" Content="Fix Selected Issues..." MinWidth="180" Background="{DynamicResource Accent}" Foreground="{DynamicResource AccentText}"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
'@

    $dialog = New-WmtWindowFromFullXaml -Xaml $registryCleanerXaml

    $lblStatus = $dialog.FindName("lblStatus")
    $dg = $dialog.FindName("dgRegistry")
    $btnFix = $dialog.FindName("btnFix")
    $btnCopySelected = $dialog.FindName("btnCopySelected")
    $btnCopyAll = $dialog.FindName("btnCopyAll")
    $btnClose = $dialog.FindName("btnClose")

    $lblStatus.Text = "Scan complete. Issues found: $($ScanResults.Count)"

    $registryRows = @(
        foreach ($item in $ScanResults) {
            $autoSelected = Test-WmtRegistryFindingAutoSelected -Item $item
            $fixAction = if ($item.Type -eq "ReviewOnly") { "Review" } elseif ($item.Type -eq "Key") { "Delete key" } elseif ($item.Type -eq "SetValue") { "Update value" } else { "Delete value" }
            $risk = if ($item.PSObject.Properties["Risk"] -and -not [string]::IsNullOrWhiteSpace([string]$item.Risk)) {
                [string]$item.Risk
            }
            elseif (-not $autoSelected) {
                "Review"
            }
            elseif ($item.Type -eq "Key") {
                "Medium"
            }
            else {
                "Low"
            }
            $confidence = if ($item.PSObject.Properties["Confidence"] -and -not [string]::IsNullOrWhiteSpace([string]$item.Confidence)) {
                [string]$item.Confidence
            }
            elseif ($autoSelected) {
                "High"
            }
            else {
                "Medium"
            }
            $details = if ($item.PSObject.Properties["Details"] -and -not [string]::IsNullOrWhiteSpace([string]$item.Details)) {
                [string]$item.Details
            }
            else {
                $valueText = if ($null -ne $item.ValueName) { "; Value=$($item.ValueName)" } else { "" }
                "$fixAction; Target=$($item.RegPath)$valueText"
            }
            if (-not $autoSelected) {
                $details = "Review only; not selected by default. $details"
            }
            [PSCustomObject]@{
                Check         = $autoSelected
                Problem       = $item.Problem
                Data          = $item.Data
                Key           = $item.DisplayKey
                FullPath      = $item.RegPath
                ValueName     = $item.ValueName
                FixAction     = $fixAction
                Risk          = $risk
                Confidence    = $confidence
                DefaultAction = if ($autoSelected) { "Selected" } else { "Review" }
                Type          = $item.Type
                NewData       = if ($item.PSObject.Properties["NewData"]) { [string]$item.NewData } else { $null }
                Details       = $details
            }
        }
    )
    $dg.ItemsSource = $registryRows

    $registryContextMenu = [System.Windows.Controls.ContextMenu]::new()
    try { Set-WmtContextMenuChrome -ContextMenu $registryContextMenu } catch {}

    $mniOpenRegedit = [System.Windows.Controls.MenuItem]::new()
    $mniOpenRegedit.Header = "Open in Regedit"
    $mniOpenRegedit.Add_Click({
            try {
                $row = $dg.SelectedItem
                if ($null -eq $row -and $dg.CurrentItem) { $row = $dg.CurrentItem }
                if ($null -eq $row) { return }
                [void](Open-WmtRegistryPathInRegedit -RegistryPath ([string]$row.FullPath))
            }
            catch {
                try { Write-GuiLog "Open in Regedit failed: $($_.Exception.Message)" } catch {}
                [System.Windows.MessageBox]::Show("Could not open the selected registry path:`n$($_.Exception.Message)", "Registry Cleaner", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
            }
        }.GetNewClosure())

    $mniCopyContextDetails = [System.Windows.Controls.MenuItem]::new()
    $mniCopyContextDetails.Header = "Copy Selected Details"
    $mniCopyContextDetails.Add_Click({
            try {
                $rowsToCopy = @($dg.SelectedItems | Where-Object { $_ })
                if ($rowsToCopy.Count -eq 0 -and $dg.CurrentItem) { $rowsToCopy = @($dg.CurrentItem) }
                if ($rowsToCopy.Count -eq 0) { return }
                [System.Windows.Clipboard]::SetText((ConvertTo-WmtRegistryResultClipboardText -Rows $rowsToCopy))
            }
            catch {
                try { Write-GuiLog "Copy selected registry details failed: $($_.Exception.Message)" } catch {}
            }
        }.GetNewClosure())

    $mniCheckHighlighted = [System.Windows.Controls.MenuItem]::new()
    $mniCheckHighlighted.Header = "Check Highlighted Rows"
    $mniCheckHighlighted.Add_Click({
            try {
                $changed = Set-WmtRegistryHighlightedRowsChecked -Grid $dg -Checked $true
                if ($changed -gt 0) {
                    $lblStatus.Text = "Scan complete. Issues found: $($ScanResults.Count). Checked $changed highlighted row(s)."
                }
            }
            catch {
                try { Write-GuiLog "Check highlighted registry rows failed: $($_.Exception.Message)" } catch {}
            }
        }.GetNewClosure())

    [void]$registryContextMenu.Items.Add($mniOpenRegedit)
    [void]$registryContextMenu.Items.Add($mniCopyContextDetails)
    [void]$registryContextMenu.Items.Add((New-Object System.Windows.Controls.Separator))
    [void]$registryContextMenu.Items.Add($mniCheckHighlighted)
    try { $registryContextMenu.Placement = [System.Windows.Controls.Primitives.PlacementMode]::MousePoint } catch {}
    $dg.ContextMenu = $registryContextMenu

    $updateRegistryContextMenuState = {
        param([System.Windows.Controls.DataGrid]$Grid)

        $hasSelection = $false
        try {
            $hasSelection = (($null -ne $Grid) -and (($Grid.SelectedItems.Count -gt 0) -or ($null -ne $Grid.CurrentItem)))
        }
        catch {
            $hasSelection = $false
        }

        try { $mniOpenRegedit.IsEnabled = $hasSelection } catch {}
        try { $mniCopyContextDetails.IsEnabled = $hasSelection } catch {}
        try { $mniCheckHighlighted.IsEnabled = $hasSelection } catch {}
        return $hasSelection
    }.GetNewClosure()

    $openRegistryContextMenu = {
        param($gridSender, $mouseArgs)

        try {
            if ($null -eq $dg -or $null -eq $registryContextMenu) { return }

            # Selection is best-effort only.  Never suppress the menu just because the
            # click happened on a TextBlock, header, scrollbar, or empty DataGrid area.
            try {
                $sourceObject = $null
                if ($null -ne $mouseArgs) { $sourceObject = $mouseArgs.OriginalSource }
                if ($null -ne $sourceObject) {
                    [void](Select-WmtRegistryGridRowFromOriginalSource -Grid $dg -OriginalSource $sourceObject)
                }
            }
            catch {
                try { Write-GuiLog "Registry result right-click selection ignored: $($_.Exception.Message)" } catch {}
            }

            [void](& $updateRegistryContextMenuState -Grid $dg)
            try { $registryContextMenu.PlacementTarget = $dg } catch {}

            # Explicitly open the menu.  Some WPF-hosted PowerShell windows do not show a
            # programmatically assigned ContextMenu reliably from ContextMenuOpening alone.
            try {
                $registryContextMenu.IsOpen = $true
                if ($null -ne $mouseArgs) { $mouseArgs.Handled = $true }
            }
            catch {
                try { Write-GuiLog "Registry result context menu open failed: $($_.Exception.Message)" } catch {}
            }
        }
        catch {
            try { Write-GuiLog "Registry result context menu failed: $($_.Exception.Message)" } catch {}
        }
    }.GetNewClosure()

    $dg.Add_PreviewMouseRightButtonDown($openRegistryContextMenu)

    $dg.Add_ContextMenuOpening({
            param($gridSender, $menuArgs)
            try {
                [void](& $updateRegistryContextMenuState -Grid $dg)
            }
            catch {
                # Do not mark Handled here.  Even if state refresh fails, WPF should still
                # display the menu instead of making right-click look broken.
                try { Write-GuiLog "Registry result context menu state refresh failed: $($_.Exception.Message)" } catch {}
            }
        }.GetNewClosure())

    function script:Set-WmtRegistryHighlightedRowsChecked {
        param(
            [System.Windows.Controls.DataGrid]$Grid,
            [bool]$Checked = $true
        )

        if ($null -eq $Grid) { return 0 }
        try {
            [void]$Grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true)
            [void]$Grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
        }
        catch {}

        $selectedRows = @($Grid.SelectedItems | Where-Object { $_ })
        if ($selectedRows.Count -eq 0 -and $Grid.CurrentItem) {
            $selectedRows = @($Grid.CurrentItem)
        }
        if ($selectedRows.Count -eq 0) { return 0 }

        $changed = 0
        foreach ($row in $selectedRows) {
            if ($row.PSObject.Properties["Check"]) {
                $row.Check = $Checked
                $changed++
            }
        }

        try { $Grid.Items.Refresh() } catch {}
        return $changed
    }

    $dg.Add_PreviewKeyDown({
            param($gridSender, $keyArgs)

            if ([string]$keyArgs.Key -notin @("Return", "Enter")) { return }

            $changed = Set-WmtRegistryHighlightedRowsChecked -Grid $gridSender -Checked $true
            if ($changed -gt 0) {
                $lblStatus.Text = "Scan complete. Issues found: $($ScanResults.Count). Checked $changed highlighted row(s)."
                $keyArgs.Handled = $true
            }
        })

    $btnCopySelected.Add_Click({
            $rowsToCopy = @($dg.SelectedItems | Where-Object { $_ })
            if ($rowsToCopy.Count -eq 0) {
                $rowsToCopy = @($registryRows | Where-Object { $_.Check -eq $true })
            }
            if ($rowsToCopy.Count -eq 0) { return }

            try {
                [System.Windows.Clipboard]::SetText((ConvertTo-WmtRegistryResultClipboardText -Rows $rowsToCopy))
                [System.Windows.MessageBox]::Show("Copied $($rowsToCopy.Count) registry result(s).", "Registry Cleaner", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
            }
            catch {
                [System.Windows.MessageBox]::Show("Could not copy details:`n$($_.Exception.Message)", "Registry Cleaner", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
            }
        })

    $btnCopyAll.Add_Click({
            try {
                [System.Windows.Clipboard]::SetText((ConvertTo-WmtRegistryResultClipboardText -Rows @($registryRows)))
                [System.Windows.MessageBox]::Show("Copied $($registryRows.Count) registry result(s).", "Registry Cleaner", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
            }
            catch {
                [System.Windows.MessageBox]::Show("Could not copy details:`n$($_.Exception.Message)", "Registry Cleaner", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
            }
        })

    # --- 7. Fix Button Logic ---
    $btnFix.Add_Click({
            $toFix = [System.Collections.Generic.List[object]]::new()
            try {
                [void]$dg.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true)
                [void]$dg.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
            }
            catch {}
            foreach ($row in $registryRows) {
                if ($row.Check -eq $true) {
                    [void]$toFix.Add([PSCustomObject]@{
                            Problem       = $row.Problem
                            Action        = $row.FixAction
                            Risk          = $row.Risk
                            Confidence    = $row.Confidence
                            DefaultAction = $row.DefaultAction
                            RegPath       = $row.FullPath
                            ValueName     = $row.ValueName
                            Type          = $row.Type
                            DisplayKey    = $row.Key
                            Data          = $row.Data
                            WhyFlagged    = $row.Details
                            NewData       = $row.NewData
                        })
                }
            }

            if ($toFix.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No issues selected.", "Registry Cleaner", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
                return
            }

            # Return results to the main controller
            $dialog.Tag = @($toFix.ToArray())
            $dialog.DialogResult = $true
            $dialog.Close()
        })

    $btnClose.Add_Click({ $dialog.Close() })

    if ($dialog.ShowDialog() -eq $true) { return $dialog.Tag }
    return $null
}

function Test-PathExists {
    param(
        $Path,
        $RegistryView = $null
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

    $rawPathText = ([string]$Path).Trim()
    $expanded = [Environment]::ExpandEnvironmentVariables($rawPathText)
    $expanded = $expanded -replace '^(?i)\\\?\?\\', ''
    $expanded = $expanded -replace '^(?i)\\\\\?\\', ''

    $systemRoot = [Environment]::GetEnvironmentVariable("SystemRoot")
    if ([string]::IsNullOrWhiteSpace($systemRoot)) { $systemRoot = "$env:SystemDrive\Windows" }
    if ($expanded -match '^(?i)\\SystemRoot\\(?<SubPath>.+)$') {
        $expanded = Join-Path $systemRoot $Matches.SubPath
    }
    elseif ($expanded -match '^(?i)System32\\(?<SubPath>.+)$') {
        $expanded = Join-Path (Join-Path $systemRoot "System32") $Matches.SubPath
    }

    if ($expanded -match "%.*%" -or $expanded -match "\$\(.*\)") { return $false }

    $probeCandidates = [System.Collections.Generic.List[string]]::new()
    $seenCandidates = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $addProbeCandidate = {
        param([string]$Candidate)
        if ([string]::IsNullOrWhiteSpace($Candidate)) { return }
        $candidateText = ([string]$Candidate).Trim()
        if ($candidateText -match "%.*%" -or $candidateText -match "\$\(.*\)") { return }
        if ($seenCandidates.Add($candidateText)) { [void]$probeCandidates.Add($candidateText) }
    }
    $useDefaultExpandedCandidate = $true
    if ([Environment]::Is64BitOperatingSystem -and [string]$RegistryView -eq "Registry32") {
        $commonProgramFilesX86 = [Environment]::GetEnvironmentVariable("CommonProgramFiles(x86)")
        if (-not [string]::IsNullOrWhiteSpace($commonProgramFilesX86) -and $rawPathText -match '(?i)%CommonProgramFiles%\\(?<Rest>.+)$') {
            & $addProbeCandidate (Join-Path $commonProgramFilesX86 $Matches.Rest)
            $useDefaultExpandedCandidate = $false
        }
        $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
        if (-not [string]::IsNullOrWhiteSpace($programFilesX86) -and $rawPathText -match '(?i)%ProgramFiles%\\(?<Rest>.+)$') {
            & $addProbeCandidate (Join-Path $programFilesX86 $Matches.Rest)
            $useDefaultExpandedCandidate = $false
        }

        # 32-bit COM values often store REG_EXPAND_SZ like %CommonProgramFiles%.
        # If another helper expanded it first inside 64-bit PowerShell, it becomes
        # C:\Program Files\Common Files, even though the 32-bit COM server normally
        # resolves to C:\Program Files (x86)\Common Files. Probe both forms to avoid
        # false ActiveX findings for legacy DAO/OLE DB registrations.
        $commonProgramFiles64 = [Environment]::GetEnvironmentVariable("CommonProgramFiles")
        if (-not [string]::IsNullOrWhiteSpace($commonProgramFiles64) -and -not [string]::IsNullOrWhiteSpace($commonProgramFilesX86)) {
            $common64Pattern = "^(?i)$([regex]::Escape($commonProgramFiles64))\\(?<Rest>.+)$"
            if ($rawPathText -match $common64Pattern -or $expanded -match $common64Pattern) {
                & $addProbeCandidate (Join-Path $commonProgramFilesX86 $Matches.Rest)
            }
        }

        $programFiles64 = [Environment]::GetEnvironmentVariable("ProgramFiles")
        if (-not [string]::IsNullOrWhiteSpace($programFiles64) -and -not [string]::IsNullOrWhiteSpace($programFilesX86)) {
            $pf64Pattern = "^(?i)$([regex]::Escape($programFiles64))\\(?<Rest>.+)$"
            if ($rawPathText -match $pf64Pattern -or $expanded -match $pf64Pattern) {
                & $addProbeCandidate (Join-Path $programFilesX86 $Matches.Rest)
            }
        }
    }
    if ($useDefaultExpandedCandidate) { & $addProbeCandidate $expanded }

    if ([Environment]::Is64BitOperatingSystem) {
        $system32Pattern = "^(?i)$([regex]::Escape($systemRoot))\\System32\\(?<SubPath>.+)$"
        if ($expanded -match $system32Pattern) {
            if ([string]$RegistryView -eq "Registry32") {
                $wow64Candidate = (Join-Path (Join-Path $systemRoot "SysWOW64") $Matches.SubPath).Trim()
                if ($seenCandidates.Add($wow64Candidate)) { [void]$probeCandidates.Add($wow64Candidate) }
            }
            $sysnativeCandidate = (Join-Path (Join-Path $systemRoot "Sysnative") $Matches.SubPath).Trim()
            if ($seenCandidates.Add($sysnativeCandidate)) { [void]$probeCandidates.Add($sysnativeCandidate) }
        }
    }

    foreach ($candidate in $probeCandidates) {
        try {
            if (Test-Path -LiteralPath $candidate -ErrorAction Stop) { return $true }
        }
        catch [System.UnauthorizedAccessException] { return $true }
        catch [System.Security.SecurityException] { return $true }
        catch {}
        try {
            [void](Get-Item -LiteralPath $candidate -Force -ErrorAction Stop)
            return $true
        }
        catch {
            if ($_.Exception.Message -match '(?i)access.*denied|unauthorized') { return $true }
        }
        if ($candidate -match '^(?i)[a-z]:\\Program Files\\WindowsApps\\(?<PackageName>[^\\]+)') {
            $packageParts = ([string]$Matches.PackageName).Split([char[]]@('_'), [System.StringSplitOptions]::RemoveEmptyEntries)
            if ($packageParts.Length -ge 2) {
                $packageFamily = "$($packageParts[0])_$($packageParts[$packageParts.Length - 1])"
                try {
                    $packageFamilyKey = "SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\PackageFamily\Index\PackageFamilyName\$packageFamily"
                    $root = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($packageFamilyKey)
                    if ($root) { $root.Close(); return $true }
                }
                catch {}
            }
        }
    }

    return $false
}

function Convert-WmtRegistryPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

    $normalized = $Path.Trim()
    $normalized = $normalized -replace "^Registry::", ""
    $normalized = $normalized -replace "^Computer\\", ""
    $normalized = $normalized -replace "^HKEY_LOCAL_MACHINE\\", "HKLM:\"
    $normalized = $normalized -replace "^HKEY_CURRENT_USER\\", "HKCU:\"
    $normalized = $normalized -replace "^HKEY_CLASSES_ROOT\\", "HKCR:\"
    $normalized = $normalized -replace "^HKEY_USERS\\", "HKU:\"

    if ($normalized -notmatch '^(?<Hive>HKLM|HKCU|HKCR|HKU):\\(?<SubPath>.*)$') { return $null }

    $hive = switch ($Matches.Hive) {
        "HKLM" { [Microsoft.Win32.RegistryHive]::LocalMachine }
        "HKCU" { [Microsoft.Win32.RegistryHive]::CurrentUser }
        "HKCR" { [Microsoft.Win32.RegistryHive]::ClassesRoot }
        "HKU" { [Microsoft.Win32.RegistryHive]::Users }
    }

    [PSCustomObject]@{
        Hive    = $hive
        Root    = $Matches.Hive
        SubPath = $Matches.SubPath
    }
}

function Convert-WmtRegistryPathToRegExePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

    $normalized = $Path.Trim()
    $normalized = $normalized -replace "^Registry::", ""
    $normalized = $normalized -replace "^Computer\\", ""
    $normalized = $normalized -replace "^HKLM:?\\", "HKEY_LOCAL_MACHINE\"
    $normalized = $normalized -replace "^HKCU:?\\", "HKEY_CURRENT_USER\"
    $normalized = $normalized -replace "^HKCR:?\\", "HKEY_CLASSES_ROOT\"
    $normalized = $normalized -replace "^HKU:?\\", "HKEY_USERS\"
    return $normalized
}

function Test-WmtRegistryValueExists {
    param(
        [string]$Path,
        [string]$ValueName
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or $null -eq $ValueName) { return $false }

    $parts = Convert-WmtRegistryPath -Path $Path
    if (-not $parts) { return $false }

    $views = @([Microsoft.Win32.RegistryView]::Default)
    foreach ($view in $views) {
        $baseKey = $null
        $key = $null
        try {
            $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($parts.Hive, $view)
            $key = $baseKey.OpenSubKey($parts.SubPath, $false)
            if ($key) {
                return ($key.GetValueNames() -contains $ValueName)
            }
        }
        catch {}
        finally {
            if ($key) { $key.Close() }
            if ($baseKey) { $baseKey.Close() }
        }
    }

    return $false
}

function Remove-WmtRegistryValueNative {
    param(
        [string]$Path,
        [string]$ValueName
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or $null -eq $ValueName) { return $false }

    $parts = Convert-WmtRegistryPath -Path $Path
    if (-not $parts) { return $false }

    $views = @([Microsoft.Win32.RegistryView]::Default)
    foreach ($view in $views) {
        $baseKey = $null
        $key = $null
        try {
            $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($parts.Hive, $view)
            $key = $baseKey.OpenSubKey($parts.SubPath, $true)
            if ($key) {
                $key.DeleteValue($ValueName, $false)
                $key.Close(); $key = $null
                if (-not (Test-WmtRegistryValueExists -Path $Path -ValueName $ValueName)) { return $true }
            }
        }
        catch {}
        finally {
            if ($key) { $key.Close() }
            if ($baseKey) { $baseKey.Close() }
        }
    }

    return $false
}

function Test-WmtRegistryKeyExistsNative {
    param(
        [Microsoft.Win32.RegistryHive]$Hive,
        $View,
        [string]$SubPath
    )
    if ([string]::IsNullOrWhiteSpace($SubPath)) { return $false }

    $baseKey = $null
    $key = $null
    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, $View)
        $key = $baseKey.OpenSubKey($SubPath, $false)
        return ($null -ne $key)
    }
    catch {}
    finally {
        if ($key) { $key.Close() }
        if ($baseKey) { $baseKey.Close() }
    }

    return $false
}

function Remove-WmtRegistryKeyNative {
    param(
        [Microsoft.Win32.RegistryHive]$Hive,
        $View,
        [string]$SubPath
    )
    if ([string]::IsNullOrWhiteSpace($SubPath)) { return $false }

    $baseKey = $null
    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, $View)
        $baseKey.DeleteSubKeyTree($SubPath, $false)
        return (-not (Test-WmtRegistryKeyExistsNative -Hive $Hive -View $View -SubPath $SubPath))
    }
    catch {}
    finally {
        if ($baseKey) { $baseKey.Close() }
    }

    return (-not (Test-WmtRegistryKeyExistsNative -Hive $Hive -View $View -SubPath $SubPath))
}

function Grant-WmtRegistryKeyFullControlNative {
    param(
        [Microsoft.Win32.RegistryHive]$Hive,
        $View,
        [string]$SubPath
    )
    if ([string]::IsNullOrWhiteSpace($SubPath)) { return $false }

    $root = $null
    $changedAny = $false
    try {
        $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, $View)
        $adminSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
        $adminAccount = $adminSid.Translate([System.Security.Principal.NTAccount])
        $rights = [System.Security.AccessControl.RegistryRights]::FullControl
        $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
            $adminAccount,
            $rights,
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $openRights = [System.Security.AccessControl.RegistryRights]::TakeOwnership -bor `
            [System.Security.AccessControl.RegistryRights]::ChangePermissions -bor `
            [System.Security.AccessControl.RegistryRights]::ReadKey -bor `
            [System.Security.AccessControl.RegistryRights]::WriteKey

        $stack = [System.Collections.Generic.Stack[string]]::new()
        $stack.Push(([string]$SubPath).TrimStart('\'))
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        while ($stack.Count -gt 0) {
            $current = $stack.Pop()
            if ([string]::IsNullOrWhiteSpace($current) -or -not $seen.Add($current)) { continue }

            $key = $null
            try {
                $key = $root.OpenSubKey($current, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, $openRights)
                if (-not $key) { continue }

                try {
                    $ownerSecurity = $key.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Owner)
                    $ownerSecurity.SetOwner($adminAccount)
                    $key.SetAccessControl($ownerSecurity)
                    $changedAny = $true
                }
                catch {}

                try {
                    $accessSecurity = $key.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
                    $accessSecurity.SetAccessRule($rule)
                    $key.SetAccessControl($accessSecurity)
                    $changedAny = $true
                }
                catch {}

                try {
                    foreach ($childName in @($key.GetSubKeyNames())) {
                        if (-not [string]::IsNullOrWhiteSpace($childName)) {
                            $stack.Push("$current\$childName")
                        }
                    }
                }
                catch {}
            }
            catch {}
            finally {
                if ($key) { $key.Close() }
            }
        }
    }
    catch {}
    finally {
        if ($root) { $root.Close() }
    }

    return $changedAny
}

function ConvertTo-WmtRegistryDeleteTargetSet {
    param([string]$Path)

    $targets = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $targets }

    $normalized = ([string]$Path).Trim() -replace '^Registry::', '' -replace '^Computer\\', ''
    $normalized = $normalized -replace '^HKEY_LOCAL_MACHINE\\', 'HKLM:\'
    $normalized = $normalized -replace '^HKEY_CURRENT_USER\\', 'HKCU:\'
    $normalized = $normalized -replace '^HKEY_CLASSES_ROOT\\', 'HKCR:\'
    $normalized = $normalized -replace '^HKEY_USERS\\', 'HKU:\'

    $addProvider = {
        param([string]$ProviderPath)
        if ([string]::IsNullOrWhiteSpace($ProviderPath)) { return }
        $k = "P|$ProviderPath"
        if ($seen.Add($k)) {
            [void]$targets.Add([PSCustomObject]@{ Kind = "Provider"; Path = $ProviderPath })
        }
    }

    $addNative = {
        param([Microsoft.Win32.RegistryHive]$Hive, $View, [string]$SubPath, [string]$Label)
        if ([string]::IsNullOrWhiteSpace($SubPath)) { return }
        $sub = ([string]$SubPath).TrimStart('\')
        $k = "N|$Hive|$View|$sub"
        if ($seen.Add($k)) {
            [void]$targets.Add([PSCustomObject]@{ Kind = "Native"; Hive = $Hive; View = $View; SubPath = $sub; Label = $Label })
        }
    }

    & $addProvider $normalized

    if ($normalized -match '^(?i)HKCR:\\WOW6432Node\\(?<Rest>.+)$') {
        $rest = $Matches.Rest
        & $addProvider "HKLM:\SOFTWARE\WOW6432Node\Classes\$rest"
        & $addProvider "HKLM:\SOFTWARE\Classes\WOW6432Node\$rest"
        & $addProvider "HKCU:\Software\Classes\WOW6432Node\$rest"
        & $addNative ([Microsoft.Win32.RegistryHive]::ClassesRoot) ([Microsoft.Win32.RegistryView]::Registry32) $rest "HKCR Registry32"
        & $addNative ([Microsoft.Win32.RegistryHive]::LocalMachine) ([Microsoft.Win32.RegistryView]::Registry32) "SOFTWARE\Classes\$rest" "HKLM Classes Registry32"
        & $addNative ([Microsoft.Win32.RegistryHive]::LocalMachine) ([Microsoft.Win32.RegistryView]::Registry64) "SOFTWARE\WOW6432Node\Classes\$rest" "HKLM physical WOW6432Node Classes"
        & $addNative ([Microsoft.Win32.RegistryHive]::CurrentUser) ([Microsoft.Win32.RegistryView]::Registry32) "Software\Classes\$rest" "HKCU Classes Registry32"
        & $addNative ([Microsoft.Win32.RegistryHive]::CurrentUser) ([Microsoft.Win32.RegistryView]::Registry64) "Software\Classes\WOW6432Node\$rest" "HKCU physical WOW6432Node Classes"
    }
    elseif ($normalized -match '^(?i)HKLM:\\SOFTWARE\\WOW6432Node\\Classes\\(?<Rest>.+)$') {
        $rest = $Matches.Rest
        & $addProvider "HKCR:\WOW6432Node\$rest"
        & $addNative ([Microsoft.Win32.RegistryHive]::LocalMachine) ([Microsoft.Win32.RegistryView]::Registry32) "SOFTWARE\Classes\$rest" "HKLM Classes Registry32"
        & $addNative ([Microsoft.Win32.RegistryHive]::LocalMachine) ([Microsoft.Win32.RegistryView]::Registry64) "SOFTWARE\WOW6432Node\Classes\$rest" "HKLM physical WOW6432Node Classes"
        & $addNative ([Microsoft.Win32.RegistryHive]::ClassesRoot) ([Microsoft.Win32.RegistryView]::Registry32) $rest "HKCR Registry32"
    }
    elseif ($normalized -match '^(?i)HKLM:\\SOFTWARE\\Classes\\(?<Rest>.+)$') {
        $rest = $Matches.Rest
        & $addProvider "HKCR:\$rest"
        & $addNative ([Microsoft.Win32.RegistryHive]::LocalMachine) ([Microsoft.Win32.RegistryView]::Registry64) "SOFTWARE\Classes\$rest" "HKLM Classes Registry64"
        & $addNative ([Microsoft.Win32.RegistryHive]::ClassesRoot) ([Microsoft.Win32.RegistryView]::Registry64) $rest "HKCR Registry64"
    }
    elseif ($normalized -match '^(?i)HKCR:\\(?<Rest>.+)$') {
        $rest = $Matches.Rest
        & $addProvider "HKLM:\SOFTWARE\Classes\$rest"
        & $addProvider "HKCU:\Software\Classes\$rest"
        & $addNative ([Microsoft.Win32.RegistryHive]::ClassesRoot) ([Microsoft.Win32.RegistryView]::Default) $rest "HKCR default"
        & $addNative ([Microsoft.Win32.RegistryHive]::LocalMachine) ([Microsoft.Win32.RegistryView]::Registry64) "SOFTWARE\Classes\$rest" "HKLM Classes Registry64"
        & $addNative ([Microsoft.Win32.RegistryHive]::CurrentUser) ([Microsoft.Win32.RegistryView]::Default) "Software\Classes\$rest" "HKCU Classes default"
    }
    elseif ($normalized -match '^(?i)HKLM:\\(?<Rest>.+)$') {
        $rest = $Matches.Rest
        & $addNative ([Microsoft.Win32.RegistryHive]::LocalMachine) ([Microsoft.Win32.RegistryView]::Default) $rest "HKLM default"
        if ([Environment]::Is64BitOperatingSystem) {
            & $addNative ([Microsoft.Win32.RegistryHive]::LocalMachine) ([Microsoft.Win32.RegistryView]::Registry64) $rest "HKLM Registry64"
            if ($rest -match '^(?i)SOFTWARE\\WOW6432Node\\(?<WowRest>.+)$') {
                & $addNative ([Microsoft.Win32.RegistryHive]::LocalMachine) ([Microsoft.Win32.RegistryView]::Registry32) "SOFTWARE\$($Matches.WowRest)" "HKLM Registry32 redirected"
            }
        }
    }
    elseif ($normalized -match '^(?i)HKCU:\\(?<Rest>.+)$') {
        $rest = $Matches.Rest
        & $addNative ([Microsoft.Win32.RegistryHive]::CurrentUser) ([Microsoft.Win32.RegistryView]::Default) $rest "HKCU default"
        if ([Environment]::Is64BitOperatingSystem) {
            & $addNative ([Microsoft.Win32.RegistryHive]::CurrentUser) ([Microsoft.Win32.RegistryView]::Registry64) $rest "HKCU Registry64"
            if ($rest -match '^(?i)Software\\Classes\\WOW6432Node\\(?<WowRest>.+)$') {
                & $addNative ([Microsoft.Win32.RegistryHive]::CurrentUser) ([Microsoft.Win32.RegistryView]::Registry32) "Software\Classes\$($Matches.WowRest)" "HKCU Registry32 redirected"
            }
        }
    }
    elseif ($normalized -match '^(?i)HKU:\\(?<Rest>.+)$') {
        & $addNative ([Microsoft.Win32.RegistryHive]::Users) ([Microsoft.Win32.RegistryView]::Default) $Matches.Rest "HKU default"
    }

    return $targets
}

function Set-WmtRegistryValueNative {
    param(
        [string]$Path,
        [string]$ValueName,
        [string]$ValueData
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or $null -eq $ValueName) { return $false }

    $parts = Convert-WmtRegistryPath -Path $Path
    if (-not $parts) { return $false }

    $views = @([Microsoft.Win32.RegistryView]::Default)
    foreach ($view in $views) {
        $baseKey = $null
        $key = $null
        try {
            $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($parts.Hive, $view)
            $key = $baseKey.OpenSubKey($parts.SubPath, $true)
            if ($key) {
                $kind = [Microsoft.Win32.RegistryValueKind]::String
                try { $kind = $key.GetValueKind($ValueName) } catch {}
                if ($kind -notin @([Microsoft.Win32.RegistryValueKind]::String, [Microsoft.Win32.RegistryValueKind]::ExpandString)) {
                    $kind = [Microsoft.Win32.RegistryValueKind]::String
                }
                $key.SetValue($ValueName, [string]$ValueData, $kind)
                $written = [string]$key.GetValue($ValueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                return ($written -eq [string]$ValueData)
            }
        }
        catch {}
        finally {
            if ($key) { $key.Close() }
            if ($baseKey) { $baseKey.Close() }
        }
    }

    return $false
}

function Remove-WmtRegistryValueRegExe {
    param(
        [string]$Path,
        [string]$ValueName
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or $null -eq $ValueName) { return $false }

    $regPath = Convert-WmtRegistryPathToRegExePath -Path $Path
    if ([string]::IsNullOrWhiteSpace($regPath)) { return $false }

    foreach ($regExe in @(Get-WmtRegExeCandidatePaths)) {
        try {
            & $regExe delete $regPath /v $ValueName /f 1>$null 2>$null
            if ($LASTEXITCODE -eq 0 -or -not (Test-WmtRegistryValueExists -Path $Path -ValueName $ValueName)) { return $true }
        }
        catch {}
    }

    return (-not (Test-WmtRegistryValueExists -Path $Path -ValueName $ValueName))
}

function Get-WmtRegExeCandidatePaths {
    $paths = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $windir = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    if ([string]::IsNullOrWhiteSpace($windir)) { $windir = $env:WINDIR }

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($windir)) {
        $candidates += (Join-Path $windir 'Sysnative\reg.exe')
        $candidates += (Join-Path $windir 'System32\reg.exe')
        $candidates += (Join-Path $windir 'SysWOW64\reg.exe')
    }
    $candidates += 'reg.exe'

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if ($candidate -ne 'reg.exe' -and -not (Test-Path -LiteralPath $candidate -PathType Leaf -ErrorAction SilentlyContinue)) { continue }
        if ($seen.Add($candidate)) { [void]$paths.Add($candidate) }
    }

    return @($paths)
}

function ConvertTo-WmtComClassParentPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

    $normalized = ([string]$Path).Trim() -replace '^Registry::', '' -replace '^Computer\\', ''
    $normalized = $normalized -replace '^HKEY_LOCAL_MACHINE\\', 'HKLM:\'
    $normalized = $normalized -replace '^HKEY_CURRENT_USER\\', 'HKCU:\'
    $normalized = $normalized -replace '^HKEY_CLASSES_ROOT\\', 'HKCR:\'
    $normalized = $normalized -replace '^HKEY_USERS\\', 'HKU:\'
    $normalized = $normalized -replace '\\+$', ''

    $serverPattern = '^(?<Parent>(?:HKLM:\\SOFTWARE\\(?:WOW6432Node\\)?Classes\\CLSID|HKCR:\\(?:WOW6432Node\\)?CLSID|HKCU:\\Software\\Classes\\(?:WOW6432Node\\)?CLSID|HKU:\\[^\\]+\\Software\\Classes\\(?:WOW6432Node\\)?CLSID)\\\{[0-9A-Fa-f-]+\})\\(?:InProcServer32|LocalServer32)$'
    if ($normalized -match $serverPattern) { return $Matches.Parent }

    return $null
}

function ConvertTo-WmtComClassServerSubPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

    $normalized = ([string]$Path).Trim() -replace '^Registry::', '' -replace '^Computer\\', ''
    $normalized = $normalized -replace '^HKEY_LOCAL_MACHINE\\', 'HKLM:\'
    $normalized = $normalized -replace '^HKEY_CURRENT_USER\\', 'HKCU:\'
    $normalized = $normalized -replace '^HKEY_CLASSES_ROOT\\', 'HKCR:\'
    $normalized = $normalized -replace '^HKEY_USERS\\', 'HKU:\'
    $normalized = $normalized -replace '\\+$', ''

    if ($normalized -match '^(?<Parent>.+?\\CLSID\\\{[0-9A-Fa-f-]+\})\\(?<Server>InProcServer32|LocalServer32)$') {
        return [PSCustomObject]@{ ParentPath = $Matches.Parent; ServerPath = $normalized; ServerSubKey = $Matches.Server }
    }

    return $null
}

function Invoke-WmtRegExeDeleteImportFallback {
    param([object[]]$RegTargets)
    if ($null -eq $RegTargets -or $RegTargets.Count -eq 0) { return $false }

    $deletePaths = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($target in @($RegTargets)) {
        if ($null -eq $target -or [string]::IsNullOrWhiteSpace([string]$target.RegPath)) { continue }
        $path = ([string]$target.RegPath).Trim()
        if ($path -match '^(?i)HKEY_CLASSES_ROOT\\WOW6432Node\\|^HKEY_LOCAL_MACHINE\\SOFTWARE\\WOW6432Node\\|^HKEY_LOCAL_MACHINE\\SOFTWARE\\Classes\\|^HKEY_CURRENT_USER\\Software\\Classes\\|^HKEY_CLASSES_ROOT\\CLSID\\') {
            if ($seen.Add($path)) { [void]$deletePaths.Add($path) }
        }
    }
    if ($deletePaths.Count -eq 0) { return $false }

    $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) ("WMT_RegDelete_{0}.reg" -f ([guid]::NewGuid().ToString('N')))
    try {
        $content = [System.Text.StringBuilder]::new()
        [void]$content.AppendLine('Windows Registry Editor Version 5.00')
        [void]$content.AppendLine('')
        foreach ($path in $deletePaths) {
            [void]$content.AppendLine("[-$path]")
            [void]$content.AppendLine('')
        }
        [System.IO.File]::WriteAllText($tmpFile, $content.ToString(), [System.Text.Encoding]::Unicode)

        foreach ($regExe in @(Get-WmtRegExeCandidatePaths)) {
            try { & $regExe import $tmpFile 1>$null 2>$null } catch {}
        }
    }
    catch {}
    finally {
        Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
    }

    return $true
}

function Add-WmtRegExeTarget {
    param(
        [System.Collections.Generic.List[object]]$Targets,
        [System.Collections.Generic.HashSet[string]]$Seen,
        [string]$RegPath,
        [string]$View
    )
    if ([string]::IsNullOrWhiteSpace($RegPath)) { return }
    $cleanPath = ([string]$RegPath).Trim()
    $cleanView = if ([string]::IsNullOrWhiteSpace($View)) { "" } else { ([string]$View).Trim() }
    $key = "$cleanPath`0$cleanView"
    if ($Seen.Add($key)) {
        [void]$Targets.Add([PSCustomObject]@{ RegPath = $cleanPath; View = $cleanView })
    }
}

function ConvertTo-WmtRegExeKeyDeleteTargets {
    param([string]$Path)

    $targets = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $targets }

    $normalized = ([string]$Path).Trim() -replace '^Registry::', '' -replace '^Computer\\', ''
    $normalized = $normalized -replace '^HKEY_LOCAL_MACHINE\\', 'HKLM:\'
    $normalized = $normalized -replace '^HKEY_CURRENT_USER\\', 'HKCU:\'
    $normalized = $normalized -replace '^HKEY_CLASSES_ROOT\\', 'HKCR:\'
    $normalized = $normalized -replace '^HKEY_USERS\\', 'HKU:\'

    $baseRegPath = Convert-WmtRegistryPathToRegExePath -Path $normalized
    Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath $baseRegPath -View $null

    if ($normalized -match '^(?i)HKCR:\\WOW6432Node\\(?<Rest>.+)$') {
        $rest = $Matches.Rest
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_CLASSES_ROOT\$rest" -View "32"
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_LOCAL_MACHINE\SOFTWARE\Classes\$rest" -View "32"
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Classes\$rest" -View "64"
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_LOCAL_MACHINE\SOFTWARE\Classes\WOW6432Node\$rest" -View "64"
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_CURRENT_USER\Software\Classes\WOW6432Node\$rest" -View "64"
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_CLASSES_ROOT\WOW6432Node\$rest" -View "64"
    }
    elseif ($normalized -match '^(?i)HKLM:\\SOFTWARE\\WOW6432Node\\Classes\\(?<Rest>.+)$') {
        $rest = $Matches.Rest
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_LOCAL_MACHINE\SOFTWARE\Classes\$rest" -View "32"
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Classes\$rest" -View "64"
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_CLASSES_ROOT\$rest" -View "32"
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_CLASSES_ROOT\WOW6432Node\$rest" -View "64"
    }
    elseif ($normalized -match '^(?i)HKLM:\\SOFTWARE\\Classes\\WOW6432Node\\(?<Rest>.+)$') {
        $rest = $Matches.Rest
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_LOCAL_MACHINE\SOFTWARE\Classes\WOW6432Node\$rest" -View "64"
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Classes\$rest" -View "64"
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_LOCAL_MACHINE\SOFTWARE\Classes\$rest" -View "32"
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_CLASSES_ROOT\WOW6432Node\$rest" -View "64"
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_CLASSES_ROOT\$rest" -View "32"
    }
    elseif ($normalized -match '^(?i)HKLM:\\SOFTWARE\\Classes\\(?<Rest>.+)$') {
        $rest = $Matches.Rest
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_LOCAL_MACHINE\SOFTWARE\Classes\$rest" -View "64"
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_CLASSES_ROOT\$rest" -View "64"
    }
    elseif ($normalized -match '^(?i)HKLM:\\SOFTWARE\\WOW6432Node\\(?<Rest>.+)$') {
        $rest = $Matches.Rest
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_LOCAL_MACHINE\SOFTWARE\$rest" -View "32"
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\$rest" -View "64"
    }
    elseif ($normalized -match '^(?i)HKLM:\\(?<Rest>.+)$') {
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_LOCAL_MACHINE\$($Matches.Rest)" -View "64"
    }
    elseif ($normalized -match '^(?i)HKCU:\\Software\\Classes\\WOW6432Node\\(?<Rest>.+)$') {
        $rest = $Matches.Rest
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_CURRENT_USER\Software\Classes\$rest" -View "32"
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_CURRENT_USER\Software\Classes\WOW6432Node\$rest" -View "64"
    }
    elseif ($normalized -match '^(?i)HKCU:\\(?<Rest>.+)$') {
        Add-WmtRegExeTarget -Targets $targets -Seen $seen -RegPath "HKEY_CURRENT_USER\$($Matches.Rest)" -View $null
    }

    return $targets
}

function Test-WmtRegExeKeyExists {
    param(
        [string]$RegPath,
        [string]$View
    )
    if ([string]::IsNullOrWhiteSpace($RegPath)) { return $false }

    $regArgs = @('query', $RegPath)
    if ($View -eq '32') { $regArgs += '/reg:32' }
    elseif ($View -eq '64') { $regArgs += '/reg:64' }

    foreach ($regExe in @(Get-WmtRegExeCandidatePaths)) {
        try {
            & $regExe @regArgs 1>$null 2>$null
            if ($LASTEXITCODE -eq 0) { return $true }
        }
        catch {}
    }

    return $false
}

function Remove-WmtRegistryKeyRegExe {
    param(
        [string]$RegPath,
        [string]$View
    )
    if ([string]::IsNullOrWhiteSpace($RegPath)) { return $false }

    $regArgs = @('delete', $RegPath, '/f')
    if ($View -eq '32') { $regArgs += '/reg:32' }
    elseif ($View -eq '64') { $regArgs += '/reg:64' }

    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($regExe in @(Get-WmtRegExeCandidatePaths)) {
        try {
            $deleteOutput = (& $regExe @regArgs 2>&1 | Out-String).Trim()
            $exit = $LASTEXITCODE
            $stillExistsAfterDelete = Test-WmtRegExeKeyExists -RegPath $RegPath -View $View
            if ($exit -eq 0 -and -not $stillExistsAfterDelete) { return $true }
            if ($exit -ne 0 -or $stillExistsAfterDelete -or -not [string]::IsNullOrWhiteSpace($deleteOutput)) {
                $viewText = if ([string]::IsNullOrWhiteSpace($View)) { 'default' } else { "reg:$View" }
                $statusText = if ($stillExistsAfterDelete) { 'still-exists-after-delete' } else { 'not-present-after-delete' }
                [void]$errors.Add("$regExe $viewText exit=$exit status=$statusText output=$deleteOutput")
            }
        }
        catch {
            $viewText = if ([string]::IsNullOrWhiteSpace($View)) { 'default' } else { "reg:$View" }
            [void]$errors.Add("$regExe $viewText exception=$($_.Exception.Message)")
        }
    }

    if ($errors.Count -gt 0) {
        $script:WmtLastRegExeDeleteError = ($errors -join ' | ')
    }
    return (-not (Test-WmtRegExeKeyExists -RegPath $RegPath -View $View))
}

function Remove-RegKeyForced {
    param($Path, $IsKey, $ValName)

    $script:WmtLastRegistryDeleteFailure = $null
    $script:WmtLastRegExeDeleteError = $null

    $attemptLog = [System.Collections.Generic.List[string]]::new()
    $AddAttempt = {
        param([string]$Message)
        if (-not [string]::IsNullOrWhiteSpace($Message)) { [void]$attemptLog.Add($Message) }
    }
    $GetElevationState = {
        try {
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
            return [bool]$principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
        }
        catch { return $false }
    }
    $SetDeleteFailure = {
        param([string]$Reason)
        $elevated = & $GetElevationState
        $attemptText = if ($attemptLog.Count -gt 0) { " Attempts: " + (($attemptLog | Select-Object -Unique) -join ' | ') } else { " Attempts: none captured" }
        $regExeError = if (-not [string]::IsNullOrWhiteSpace([string]$script:WmtLastRegExeDeleteError)) { " reg.exe detail: $script:WmtLastRegExeDeleteError" } else { "" }
        $elevationHint = if ($elevated) { "Process elevated: True." } else { "Process elevated: False. HKLM/HKCR machine keys usually require Run as administrator." }
        $script:WmtLastRegistryDeleteFailure = "$Reason $elevationHint$attemptText$regExeError"
    }

    try {
        if ([string]::IsNullOrWhiteSpace([string]$Path)) {
            & $SetDeleteFailure "Registry path was blank, so WMT skipped deletion."
            return $false
        }

        $normalizedPath = ([string]$Path).Trim() -replace "^Registry::", "" -replace "^Computer\\", ""
        $normalizedPath = $normalizedPath -replace "^HKEY_CLASSES_ROOT\\", "HKCR:\\"
        $normalizedPath = $normalizedPath -replace "^HKEY_LOCAL_MACHINE\\", "HKLM:\\"
        $normalizedPath = $normalizedPath -replace "^HKEY_CURRENT_USER\\", "HKCU:\\"
        $normalizedPath = $normalizedPath -replace "^HKEY_USERS\\", "HKU:\\"
        & $AddAttempt "normalized=$normalizedPath"

        if (-not $IsKey) {
            $targetPaths = @()
            foreach ($target in @(ConvertTo-WmtRegistryDeleteTargetSet -Path $normalizedPath)) {
                if ($target.Kind -eq "Provider" -and -not [string]::IsNullOrWhiteSpace([string]$target.Path)) {
                    $targetPaths += [string]$target.Path
                }
            }
            if ($targetPaths.Count -eq 0) { $targetPaths = @($normalizedPath) }

            $globalValueSuccess = $true
            $literalValueName = if ($null -ne $ValName) { [System.Management.Automation.WildcardPattern]::Escape([string]$ValName) } else { $ValName }
            foreach ($targetPath in ($targetPaths | Select-Object -Unique)) {
                & $AddAttempt "value-target=$targetPath value=$ValName"
                if (-not (Test-WmtRegistryValueExists -Path $targetPath -ValueName $ValName)) { continue }
                try {
                    [void](Remove-WmtRegistryValueNative -Path $targetPath -ValueName $ValName)
                    if (Test-WmtRegistryValueExists -Path $targetPath -ValueName $ValName) {
                        try { Remove-ItemProperty -LiteralPath $targetPath -Name $literalValueName -ErrorAction Stop } catch { & $AddAttempt "Remove-ItemProperty failed: $($_.Exception.Message)" }
                    }
                    if (Test-WmtRegistryValueExists -Path $targetPath -ValueName $ValName) {
                        [void](Remove-WmtRegistryValueRegExe -Path $targetPath -ValueName $ValName)
                    }
                    if (Test-WmtRegistryValueExists -Path $targetPath -ValueName $ValName) {
                        $globalValueSuccess = $false
                        & $AddAttempt "value-still-exists=$targetPath value=$ValName"
                    }
                }
                catch {
                    $globalValueSuccess = $false
                    & $AddAttempt "value-delete-exception=$targetPath error=$($_.Exception.Message)"
                }
            }
            if (-not $globalValueSuccess) { & $SetDeleteFailure "Value deletion failed verification." }
            return $globalValueSuccess
        }

        $comServerInfo = ConvertTo-WmtComClassServerSubPath -Path $normalizedPath
        $comClassParentPath = if ($comServerInfo) { [string]$comServerInfo.ParentPath } else { $null }
        $allowNativeAclUnlock = ($normalizedPath -match '^(?i)(HKLM:\\SOFTWARE\\(WOW6432Node\\)?Classes\\CLSID\\|HKCR:\\(WOW6432Node\\)?CLSID\\)' -or -not [string]::IsNullOrWhiteSpace($comClassParentPath))
        if (-not [string]::IsNullOrWhiteSpace($comClassParentPath)) {
            & $AddAttempt "COM server path detected; deleting parent CLSID=$comClassParentPath"
        }

        $deleteTargets = @()
        if (-not [string]::IsNullOrWhiteSpace($comClassParentPath)) {
            $deleteTargets += @(ConvertTo-WmtRegistryDeleteTargetSet -Path $comClassParentPath)
        }
        $deleteTargets += @(ConvertTo-WmtRegistryDeleteTargetSet -Path $normalizedPath)
        if ($deleteTargets.Count -eq 0) {
            $deleteTargets = @([PSCustomObject]@{ Kind = "Provider"; Path = $normalizedPath })
        }

        $regExeTargets = @()
        if (-not [string]::IsNullOrWhiteSpace($comClassParentPath)) { $regExeTargets += @(ConvertTo-WmtRegExeKeyDeleteTargets -Path $comClassParentPath) }
        $regExeTargets += @(ConvertTo-WmtRegExeKeyDeleteTargets -Path $normalizedPath)

        $DescribeTarget = {
            param($Target)
            if ($null -eq $Target) { return "<null>" }
            if ($Target.Kind -eq "Native") { return "$($Target.Label): $($Target.SubPath)" }
            return [string]$Target.Path
        }
        $TestTargetExists = {
            param($Target)
            try {
                if ($Target.Kind -eq "Native") {
                    return (Test-WmtRegistryKeyExistsNative -Hive $Target.Hive -View $Target.View -SubPath $Target.SubPath)
                }
                return (Test-Path -LiteralPath ([string]$Target.Path) -ErrorAction SilentlyContinue)
            }
            catch {
                & $AddAttempt "exist-check-exception=$(& $DescribeTarget $Target) error=$($_.Exception.Message)"
                return $false
            }
        }

        foreach ($target in @($deleteTargets)) { & $AddAttempt "candidate=$(& $DescribeTarget $target)" }
        foreach ($target in @($regExeTargets)) {
            $viewText = if ([string]::IsNullOrWhiteSpace([string]$target.View)) { "default" } else { "reg:$($target.View)" }
            & $AddAttempt "reg-candidate=$viewText $($target.RegPath)"
        }

        $UnlockProviderPath = {
            param([string]$ProviderPath)
            if ([string]::IsNullOrWhiteSpace($ProviderPath) -or -not (Test-Path -LiteralPath $ProviderPath -ErrorAction SilentlyContinue)) { return }
            try {
                $sid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
                $adminUser = $sid.Translate([System.Security.Principal.NTAccount])
                $rule = New-Object System.Security.AccessControl.RegistryAccessRule($adminUser, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
                $unlockOne = {
                    param([string]$p)
                    try {
                        $acl = Get-Acl -LiteralPath $p -ErrorAction Stop
                        $acl.SetOwner($adminUser)
                        Set-Acl -LiteralPath $p -AclObject $acl -ErrorAction Stop
                        $acl = Get-Acl -LiteralPath $p -ErrorAction Stop
                        $acl.SetAccessRule($rule)
                        Set-Acl -LiteralPath $p -AclObject $acl -ErrorAction Stop
                    }
                    catch { & $AddAttempt "acl-provider-failed=$p error=$($_.Exception.Message)" }
                }
                try {
                    foreach ($child in @(Get-ChildItem -LiteralPath $ProviderPath -Recurse -ErrorAction SilentlyContinue)) {
                        & $unlockOne ([string]$child.PSPath)
                    }
                }
                catch { & $AddAttempt "acl-enumerate-failed=$ProviderPath error=$($_.Exception.Message)" }
                & $unlockOne $ProviderPath
            }
            catch { & $AddAttempt "acl-provider-wrapper-failed=$ProviderPath error=$($_.Exception.Message)" }
        }

        $existingTargets = @($deleteTargets | Where-Object { & $TestTargetExists $_ })
        $existingRegExeTargets = @($regExeTargets | Where-Object { Test-WmtRegExeKeyExists -RegPath $_.RegPath -View $_.View })
        if ($existingTargets.Count -eq 0 -and $existingRegExeTargets.Count -eq 0) { return $true }
        & $AddAttempt "existing-provider/native=$($existingTargets.Count) existing-regexe=$($existingRegExeTargets.Count)"

        foreach ($target in $existingTargets) {
            if ($target.Kind -eq "Provider") { & $UnlockProviderPath ([string]$target.Path) }
        }
        if ($allowNativeAclUnlock) {
            foreach ($target in $existingTargets) {
                if ($target.Kind -eq "Native") {
                    try {
                        $aclChanged = Grant-WmtRegistryKeyFullControlNative -Hive $target.Hive -View $target.View -SubPath $target.SubPath
                        & $AddAttempt "acl-native=$($target.Label):$($target.SubPath) changed=$aclChanged"
                    }
                    catch { & $AddAttempt "acl-native-exception=$($target.Label):$($target.SubPath) error=$($_.Exception.Message)" }
                }
            }
        }

        foreach ($target in $existingTargets) {
            if (-not (& $TestTargetExists $target)) { continue }
            try {
                if ($target.Kind -eq "Native") {
                    $nativeResult = Remove-WmtRegistryKeyNative -Hive $target.Hive -View $target.View -SubPath $target.SubPath
                    & $AddAttempt "delete-native=$($target.Label):$($target.SubPath) result=$nativeResult"
                }
                else {
                    Remove-Item -LiteralPath ([string]$target.Path) -Recurse -Force -ErrorAction Stop
                    & $AddAttempt "delete-provider=$($target.Path) result=True"
                }
            }
            catch {
                & $AddAttempt "delete-exception=$(& $DescribeTarget $target) error=$($_.Exception.Message)"
                if ($target.Kind -eq "Provider") {
                    try {
                        & $UnlockProviderPath ([string]$target.Path)
                        Remove-Item -LiteralPath ([string]$target.Path) -Recurse -Force -ErrorAction Stop
                        & $AddAttempt "delete-provider-retry=$($target.Path) result=True"
                    }
                    catch { & $AddAttempt "delete-provider-retry-failed=$($target.Path) error=$($_.Exception.Message)" }
                }
            }
        }

        foreach ($target in $existingTargets) {
            if ($target.Kind -eq "Native" -and (& $TestTargetExists $target)) {
                try {
                    if ($allowNativeAclUnlock) { [void](Grant-WmtRegistryKeyFullControlNative -Hive $target.Hive -View $target.View -SubPath $target.SubPath) }
                    $nativeRetryResult = Remove-WmtRegistryKeyNative -Hive $target.Hive -View $target.View -SubPath $target.SubPath
                    & $AddAttempt "delete-native-retry=$($target.Label):$($target.SubPath) result=$nativeRetryResult"
                }
                catch { & $AddAttempt "delete-native-retry-exception=$($target.Label):$($target.SubPath) error=$($_.Exception.Message)" }
            }
        }

        foreach ($regTarget in $regExeTargets) {
            try {
                $viewText = if ([string]::IsNullOrWhiteSpace([string]$regTarget.View)) { "default" } else { "reg:$($regTarget.View)" }
                if (Test-WmtRegExeKeyExists -RegPath $regTarget.RegPath -View $regTarget.View) {
                    $regResult = Remove-WmtRegistryKeyRegExe -RegPath $regTarget.RegPath -View $regTarget.View
                    & $AddAttempt "delete-regexe=$viewText $($regTarget.RegPath) result=$regResult"
                }
                else {
                    & $AddAttempt "delete-regexe-skip-not-found=$viewText $($regTarget.RegPath)"
                }
            }
            catch { & $AddAttempt "delete-regexe-exception=$($regTarget.RegPath) error=$($_.Exception.Message)" }
        }
        if ($allowNativeAclUnlock) {
            try {
                $importResult = Invoke-WmtRegExeDeleteImportFallback -RegTargets $regExeTargets
                & $AddAttempt "delete-reg-import-fallback result=$importResult"
            }
            catch { & $AddAttempt "delete-reg-import-fallback-exception=$($_.Exception.Message)" }
        }

        $remainingTargets = @($deleteTargets | Where-Object { & $TestTargetExists $_ })
        $remainingRegExeTargets = @($regExeTargets | Where-Object { Test-WmtRegExeKeyExists -RegPath $_.RegPath -View $_.View })
        $success = ($remainingTargets.Count -eq 0 -and $remainingRegExeTargets.Count -eq 0)
        if (-not $success) {
            $remainingLabels = @(
                foreach ($target in $remainingTargets) { & $DescribeTarget $target }
                foreach ($target in $remainingRegExeTargets) {
                    $viewText = if ([string]::IsNullOrWhiteSpace([string]$target.View)) { "default" } else { "reg:$($target.View)" }
                    "reg.exe ${viewText}: $($target.RegPath)"
                }
            )
            $likely = if (-not (& $GetElevationState)) {
                "Likely cause: WMT is not elevated, so HKLM/HKCR machine keys cannot be deleted."
            }
            else {
                "Likely cause: ACL protection/ownership blocked deletion, or a Windows/Office component recreated the COM registration before verification."
            }
            & $SetDeleteFailure "Key still exists after all delete attempts. Remaining target(s): $($remainingLabels -join '; '). $likely"
        }
        return $success
    }
    catch {
        & $AddAttempt "top-level-exception=$($_.Exception.Message)"
        & $SetDeleteFailure "Registry delete helper crashed before verification."
        return $false
    }
}

function Backup-RegKey {
    param($ItemObj, $FilePath)
    $path = $ItemObj.RegPath; $targetValue = $ItemObj.ValueName; $type = $ItemObj.Type
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    $comBackupParent = if ($type -eq "Key") { ConvertTo-WmtComClassParentPath -Path $path } else { $null }
    if (-not [string]::IsNullOrWhiteSpace($comBackupParent)) { $path = $comBackupParent }
    $regKeyPath = Convert-WmtRegistryPathToRegExePath -Path $path
    if ([string]::IsNullOrWhiteSpace($regKeyPath)) { return }
    $providerPath = ([string]$path).Trim() -replace "^Registry::", "" -replace "^Computer\\", ""
    $providerPath = $providerPath -replace "^HKEY_LOCAL_MACHINE\\", "Registry::HKEY_LOCAL_MACHINE\"
    $providerPath = $providerPath -replace "^HKEY_CURRENT_USER\\", "Registry::HKEY_CURRENT_USER\"
    $providerPath = $providerPath -replace "^HKEY_CLASSES_ROOT\\", "Registry::HKEY_CLASSES_ROOT\"
    $providerPath = $providerPath -replace "^HKEY_USERS\\", "Registry::HKEY_USERS\"
    $providerPath = $providerPath -replace "^HKLM:?\\", "Registry::HKEY_LOCAL_MACHINE\"
    $providerPath = $providerPath -replace "^HKCU:?\\", "Registry::HKEY_CURRENT_USER\"
    $providerPath = $providerPath -replace "^HKCR:?\\", "Registry::HKEY_CLASSES_ROOT\"
    $providerPath = $providerPath -replace "^HKU:?\\", "Registry::HKEY_USERS\"
    $sb = [System.Text.StringBuilder]::new(); [void]$sb.AppendLine("[$regKeyPath]")
    try {
        if ($type -eq "Key" -or $type -eq "SetValue") {
            $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) ("WMT_RegBackup_{0}.reg" -f ([guid]::NewGuid().ToString("N")))
            try {
                & reg.exe export $regKeyPath $tmpFile /y | Out-Null
                if (Test-Path -LiteralPath $tmpFile) {
                    $content = Get-Content -LiteralPath $tmpFile -Raw -Encoding Unicode
                    $content = $content -replace "^\uFEFF?Windows Registry Editor Version 5\.00\r?\n\r?\n", ""
                    if (-not [string]::IsNullOrWhiteSpace($content)) {
                        Add-Content -Path $FilePath -Value $content -Encoding Unicode
                        return
                    }
                }
            }
            catch {}
            finally {
                Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
            }
        }
        elseif ($type -eq "Value") {
            $val = Get-ItemProperty -Path $providerPath -Name $targetValue -ErrorAction SilentlyContinue
            if ($val) { 
                $vData = $val.$targetValue
                if ($vData -is [string]) { $vData = '"' + ($vData -replace '\\', '\\' -replace '"', '\"') + '"' } 
                elseif ($vData -is [int]) { $vData = "dword:{0:x8}" -f $vData }
                [void]$sb.AppendLine("`"$targetValue`"=$vData") 
            }
        }
        [void]$sb.AppendLine(""); Add-Content -Path $FilePath -Value $sb.ToString() -Encoding Unicode
    }
    catch {}
}

function Show-SafetyDialog {
    param($Count)

    [xml]$safetyXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Safety Pre-Check" Width="480" Height="330" ResizeMode="NoResize" WindowStartupLocation="CenterOwner"
        Background="{DynamicResource BgDark}" Foreground="{DynamicResource TextPrimary}"
        FontFamily="Segoe UI Variable Display, Segoe UI, Arial" FontSize="13">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Text="Registry cleanup safety check" FontSize="18" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}"/>
        <TextBlock Name="lblMessage" Grid.Row="1" Margin="0,12,0,14" Foreground="{DynamicResource TextSecondary}" LineHeight="19"/>

        <StackPanel Grid.Row="2">
            <Button Name="btnRestore" Content="Create Restore Point &amp; Clean" Height="40" Background="{DynamicResource Success}" Foreground="{DynamicResource SuccessText}" Margin="0,0,0,8"/>
            <Button Name="btnBackup" Content="Clean With .reg Backup Only" Height="38" Background="{DynamicResource Danger}" Foreground="{DynamicResource DangerText}" Margin="0,0,0,8"/>
            <Button Name="btnCancel" Content="Cancel" Height="36" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
'@

    $dialog = New-WmtWindowFromFullXaml -Xaml $safetyXaml

    $dialog.FindName("lblMessage").Text = "You are about to apply $Count selected registry cleanup action(s).`n`nWMT creates a .reg backup first. Value cleanup is usually low risk; key deletion and review-selected items carry more risk."
    $dialog.Tag = "Cancel"
    $dialog.FindName("btnRestore").Add_Click({
            $dialog.Tag = "Yes"
            $dialog.DialogResult = $true
        }.GetNewClosure())
    $dialog.FindName("btnBackup").Add_Click({
            $dialog.Tag = "No"
            $dialog.DialogResult = $true
        }.GetNewClosure())
    $dialog.FindName("btnCancel").Add_Click({
            $dialog.Tag = "Cancel"
            $dialog.DialogResult = $false
        }.GetNewClosure())

    $dialog.ShowDialog() | Out-Null
    return [string]$dialog.Tag
}

function Invoke-RegistryTask {
    param([string]$Action)

    $bkDir = Join-Path (Get-DataPath) "RegistryBackups"
    if (-not (Test-Path $bkDir)) { New-Item -Path $bkDir -ItemType Directory | Out-Null }

    # --- PRIVILEGE BOOSTER ---
    # Only adding the type if it doesn't exist to prevent errors on re-run
    if (-not ([System.Management.Automation.PSTypeName]'Win32.TokenManipulator').Type) {
        Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        namespace Win32 {
            public class TokenManipulator {
                [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
                internal static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall, ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);
                [DllImport("kernel32.dll", ExactSpelling = true)]
                internal static extern IntPtr GetCurrentProcess();
                [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
                internal static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);
                [DllImport("advapi32.dll", SetLastError = true)]
                internal static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);
                [StructLayout(LayoutKind.Sequential, Pack = 1)]
                internal struct TokPriv1Luid { public int Count; public long Luid; public int Attr; }
                internal const int SE_PRIVILEGE_ENABLED = 0x00000002;
                internal const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;
                internal const int TOKEN_QUERY = 0x00000008;
                public static bool EnablePrivilege(string privilege) {
                    try {
                        IntPtr htok = IntPtr.Zero;
                        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok)) return false;
                        TokPriv1Luid tp; tp.Count = 1; tp.Attr = SE_PRIVILEGE_ENABLED; tp.Luid = 0;
                        if (!LookupPrivilegeValue(null, privilege, ref tp.Luid)) return false;
                        if (!AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero)) return false;
                        return true;
                    } catch { return false; }
                }
            }
        }
"@
    }
    try {
        [Win32.TokenManipulator]::EnablePrivilege("SeTakeOwnershipPrivilege") | Out-Null
        [Win32.TokenManipulator]::EnablePrivilege("SeRestorePrivilege") | Out-Null
    }
    catch {}

    if ($Action -eq "BackupHKLM") {
        Invoke-UiCommand {
            param($BackupDirectory)

            if (-not (Test-Path -LiteralPath $BackupDirectory)) {
                New-Item -Path $BackupDirectory -ItemType Directory -Force | Out-Null
            }

            $bkFile = Join-Path $BackupDirectory ("HKLM_Backup_{0}.reg" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
            Write-Output "Exporting HKLM to: $bkFile"
            & reg.exe export "HKLM" $bkFile /y 2>&1 | ForEach-Object { Write-Output $_ }

            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $bkFile)) {
                throw "HKLM backup failed. reg.exe exit code: $LASTEXITCODE"
            }

            Show-WmtMessageBox -Message "HKLM export saved to:`n$bkFile" -Title "Registry Export" -Image Information | Out-Null
        } "Exporting HKLM hive..." -ArgumentList $bkDir
        return
    }

    if ($Action -eq "Restore") {
        $dlg = [Microsoft.Win32.OpenFileDialog]::new()
        $dlg.Title = "Select Registry Backup to Import"
        $dlg.Filter = "Registry backup (*.reg)|*.reg|All files (*.*)|*.*"
        if (Test-Path -LiteralPath $bkDir) {
            try { $dlg.InitialDirectory = (Resolve-Path -LiteralPath $bkDir).Path } catch {}
        }

        if ($dlg.ShowDialog() -ne $true) { return }
        $restoreFile = $dlg.FileName

        $confirm = Show-WmtMessageBox -Message "Import this registry backup?`n`n$restoreFile`n`nThis can overwrite current registry values." -Title "Import Registry Backup" -Button YesNo -Image Warning
        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

        Invoke-UiCommand {
            param($BackupFile)

            if (-not (Test-Path -LiteralPath $BackupFile)) {
                throw "Backup file not found: $BackupFile"
            }

            Write-Output "Importing registry backup: $BackupFile"
            & reg.exe import $BackupFile 2>&1 | ForEach-Object { Write-Output $_ }
            if ($LASTEXITCODE -ne 0) {
                throw "Registry restore failed. reg.exe exit code: $LASTEXITCODE"
            }

            Show-WmtMessageBox -Message "Registry backup imported from:`n$BackupFile" -Title "Registry Import" -Image Information | Out-Null
        } "Importing registry backup..." -ArgumentList $restoreFile
        return
    }

    # --- MAIN SCAN LOGIC ---
    if ($Action -eq "DeepClean") {
        $selectedScans = Show-RegScanSelection
        if (-not $selectedScans) { return }
        if (@($selectedScans).Count -eq 0) {
            Show-WmtMessageBox -Message "No registry scan targets selected." -Title "Registry Cleaner" -Image Information | Out-Null
            return
        }

        # Progress UI
        [xml]$registryProgressXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Scanning Registry" Width="640" Height="218" MinWidth="600" MinHeight="200" ResizeMode="NoResize" WindowStartupLocation="CenterOwner"
        Background="{DynamicResource BgDark}" Foreground="{DynamicResource TextPrimary}"
        FontFamily="Segoe UI Variable Display, Segoe UI, Arial" FontSize="13">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="56"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <TextBlock Name="pLabel" Grid.Row="0" Text="Initializing Background Scan..." Foreground="{DynamicResource TextPrimary}"
                   TextTrimming="CharacterEllipsis" TextWrapping="NoWrap" Height="46" MaxHeight="46"
                   VerticalAlignment="Center" ToolTip="{Binding Text, RelativeSource={RelativeSource Self}}"/>
        <ProgressBar Name="pBar" Grid.Row="1" Minimum="0" Maximum="100" Height="12" Margin="0,6,0,0"/>
        <Grid Grid.Row="2" Margin="0,16,0,0">
            <Button Name="btnCancelScan" Content="Cancel" Width="100" Height="34" HorizontalAlignment="Right" VerticalAlignment="Bottom"/>
        </Grid>
    </Grid>
</Window>
'@
        $pForm = New-WmtWindowFromFullXaml -Xaml $registryProgressXaml
        $pLabel = $pForm.FindName("pLabel")
        $pBar = $pForm.FindName("pBar")
        $btnCancelScan = $pForm.FindName("btnCancelScan")

        # Shared Data for Thread
        $syncHash = [hashtable]::Synchronized(@{
                Findings        = [System.Collections.ArrayList]::new()
                Status          = "Starting..."
                Progress        = 0
                IsCompleted     = $false
                CancelRequested = $false
                Error           = $null
            })

        $btnCancelScan.Add_Click({
                $syncHash.CancelRequested = $true
                $syncHash.Status = "Canceling scan..."
                $syncHash.Error = "Registry scan canceled."
                $syncHash.IsCompleted = $true
                try { if ($ps) { $ps.Stop() } } catch {}
            }.GetNewClosure())
        $pForm.Show()

        # --- RUNSPACE CONFIGURATION ---
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $iss.Commands.Add([System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new("Test-PathExists", ${function:Test-PathExists}.ToString()))
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
        # STA Mode is critical for Registry (HKCR) scans to work correctly
        $rs.ApartmentState = "STA"
        $rs.ThreadOptions = "ReuseThread"
        $rs.Open()
        
        $rs.SessionStateProxy.SetVariable("SyncHash", $syncHash)
        $rs.SessionStateProxy.SetVariable("SelectedScans", $selectedScans)

        $ps = [PowerShell]::Create()
        $ps.Runspace = $rs
        
        # --- SCANNING SCRIPT BLOCK ---
        [void]$ps.AddScript({
                Import-Module Microsoft.PowerShell.Management
                Import-Module Microsoft.PowerShell.Security
                $SelectedScans = @($SelectedScans)
                # Registry skip tokens are intentionally split into two groups.
                # Do not let a broad token hide an absolute filesystem path such as:
                #   C:\Program Files\...\WebView2\...\some.dll
                #   C:\BadPath\rundll32.exe
                # Absolute paths must always flow through Test-PathExists / protected-path checks.
                $RegistrySafeNonPathTokens = [string[]]@(
                    "TetheringSettingHandler", "CrossDevice", "Windows.Media.Protection",
                    "System.Data.dll", "System.EnterpriseServices", "AppX", "WindowsApps",
                    "UIEOrchestrator", "Diagnostic.Perfmon", "QuickActionsPS", "VailAudioProxy"
                )
                $RegistrySafeCommandTokens = [string[]]@(
                    "rundll32", "rundll32.exe", "explorer", "explorer.exe", "notepad", "notepad.exe",
                    "write", "write.exe", "mspaint", "mspaint.exe", "svchost", "svchost.exe",
                    "dllhost", "dllhost.exe", "wmiprvse", "wmiprvse.exe", "mmgaserver", "mmgaserver.exe",
                    "pickerhost", "pickerhost.exe", "castsrv", "castsrv.exe", "uihelper", "uihelper.exe",
                    "backgroundtaskhost", "backgroundtaskhost.exe", "smartscreen", "smartscreen.exe",
                    "runtimebroker", "runtimebroker.exe", "mousocoreworker", "mousocoreworker.exe",
                    "spatialaudiolicensesrv", "spatialaudiolicensesrv.exe", "speechruntime", "speechruntime.exe",
                    "mstsc", "mstsc.exe", "searchprotocolhost", "searchprotocolhost.exe", "control", "control.exe",
                    "sdclt", "sdclt.exe", "provtool", "provtool.exe", "perfmon", "perfmon.exe"
                )
                $RegistrySystemRoot = [Environment]::GetEnvironmentVariable("SystemRoot")
                if ([string]::IsNullOrWhiteSpace($RegistrySystemRoot)) { $RegistrySystemRoot = "$env:SystemDrive\Windows" }
                $RegistryProtectedWindowsFolders = @(
                    foreach ($folder in [string[]]@("System32", "SysWOW64", "Sysnative", "WinSxS", "servicing", "SystemApps", "Microsoft.NET", "Fonts")) {
                        Join-Path $RegistrySystemRoot $folder
                    }
                )
                $RegistryPathExistsCache = [System.Collections.Generic.Dictionary[string, bool]]::new([System.StringComparer]::OrdinalIgnoreCase)

                # Internal Helper: skip known virtual/non-path registrations only.
                # Broad substring allow-listing against absolute paths caused stale COM DLLs to be hidden.
                function Test-IsWhitelisted {
                    param($Path)
                    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

                    $pathText = [Environment]::ExpandEnvironmentVariables(([string]$Path).Trim().Trim('"'))
                    if ([string]::IsNullOrWhiteSpace($pathText)) { return $false }

                    # If this value contains a real filesystem-style path, never whitelist it here.
                    # Let Test-IsProtectedWindowsPath and Test-PathExists decide whether it is safe/valid.
                    if ($pathText -match '(?i)([a-z]:\\|\\\\[^\\]+\\[^\\]+\\|%ProgramFiles%|%ProgramFiles\(x86\)%|%LocalAppData%|%AppData%|%ProgramData%|%SystemDrive%|%SystemRoot%|%windir%|\\SystemRoot\\)') {
                        return $false
                    }

                    $firstToken = ($pathText -split '\s+', 2)[0].Trim('"')
                    $firstTokenName = [System.IO.Path]::GetFileName($firstToken)
                    foreach ($safeCommand in $RegistrySafeCommandTokens) {
                        if ($firstTokenName.Equals($safeCommand, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
                    }

                    foreach ($safe in $RegistrySafeNonPathTokens) {
                        if ($pathText.IndexOf($safe, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
                    }

                    return $false
                }

                function Test-IsProtectedWindowsPath {
                    param($Path)
                    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

                    $text = [Environment]::ExpandEnvironmentVariables(([string]$Path).Trim().Trim('"'))
                    $text = $text -replace '^(?i)\\\?\?\\', ''
                    $text = $text -replace '^(?i)\\\\\?\\', ''

                    if ($text -match '^(?i)(%SystemRoot%|%windir%|\\SystemRoot\\|System32\\)') { return $true }
                    foreach ($protectedRoot in $RegistryProtectedWindowsFolders) {
                        if ($text.Equals($protectedRoot, [System.StringComparison]::OrdinalIgnoreCase) -or $text.StartsWith("$protectedRoot\", [System.StringComparison]::OrdinalIgnoreCase)) {
                            return $true
                        }
                    }

                    return $false
                }

                function Test-PathExists {
                    param(
                        $Path,
                        $RegistryView = $null
                    )
                    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

                    $rawPathText = ([string]$Path).Trim()
                    $expanded = [Environment]::ExpandEnvironmentVariables($rawPathText)
                    $expanded = $expanded -replace '^(?i)\\\?\?\\', ''
                    $expanded = $expanded -replace '^(?i)\\\\\?\\', ''

                    $systemRoot = $RegistrySystemRoot
                    if ($expanded -match '^(?i)\\SystemRoot\\(?<SubPath>.+)$') {
                        $expanded = Join-Path $systemRoot $Matches.SubPath
                    }
                    elseif ($expanded -match '^(?i)System32\\(?<SubPath>.+)$') {
                        $expanded = Join-Path (Join-Path $systemRoot "System32") $Matches.SubPath
                    }

                    if ($expanded -match "%.*%" -or $expanded -match "\$\(.*\)") { return $false }

                    $cacheKey = "$([string]$RegistryView)`0$expanded"
                    if ($RegistryPathExistsCache.ContainsKey($cacheKey)) { return $RegistryPathExistsCache[$cacheKey] }

                    $probeCandidates = [System.Collections.Generic.List[string]]::new()
                    $seenCandidates = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $addProbeCandidate = {
                        param([string]$Candidate)
                        if ([string]::IsNullOrWhiteSpace($Candidate)) { return }
                        $candidateText = ([string]$Candidate).Trim()
                        if ($candidateText -match "%.*%" -or $candidateText -match "\$\(.*\)") { return }
                        if ($seenCandidates.Add($candidateText)) { [void]$probeCandidates.Add($candidateText) }
                    }
                    $useDefaultExpandedCandidate = $true
                    if ([Environment]::Is64BitOperatingSystem -and [string]$RegistryView -eq "Registry32") {
                        $commonProgramFilesX86 = [Environment]::GetEnvironmentVariable("CommonProgramFiles(x86)")
                        if (-not [string]::IsNullOrWhiteSpace($commonProgramFilesX86) -and $rawPathText -match '(?i)%CommonProgramFiles%\\(?<Rest>.+)$') {
                            & $addProbeCandidate (Join-Path $commonProgramFilesX86 $Matches.Rest)
                            $useDefaultExpandedCandidate = $false
                        }
                        $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
                        if (-not [string]::IsNullOrWhiteSpace($programFilesX86) -and $rawPathText -match '(?i)%ProgramFiles%\\(?<Rest>.+)$') {
                            & $addProbeCandidate (Join-Path $programFilesX86 $Matches.Rest)
                            $useDefaultExpandedCandidate = $false
                        }

                        # 32-bit COM values often store REG_EXPAND_SZ like %CommonProgramFiles%.
                        # If another helper expanded it first inside 64-bit PowerShell, it becomes
                        # C:\Program Files\Common Files, even though the 32-bit COM server normally
                        # resolves to C:\Program Files (x86)\Common Files. Probe both forms to avoid
                        # false ActiveX findings for legacy DAO/OLE DB registrations.
                        $commonProgramFiles64 = [Environment]::GetEnvironmentVariable("CommonProgramFiles")
                        if (-not [string]::IsNullOrWhiteSpace($commonProgramFiles64) -and -not [string]::IsNullOrWhiteSpace($commonProgramFilesX86)) {
                            $common64Pattern = "^(?i)$([regex]::Escape($commonProgramFiles64))\\(?<Rest>.+)$"
                            if ($rawPathText -match $common64Pattern -or $expanded -match $common64Pattern) {
                                & $addProbeCandidate (Join-Path $commonProgramFilesX86 $Matches.Rest)
                            }
                        }

                        $programFiles64 = [Environment]::GetEnvironmentVariable("ProgramFiles")
                        if (-not [string]::IsNullOrWhiteSpace($programFiles64) -and -not [string]::IsNullOrWhiteSpace($programFilesX86)) {
                            $pf64Pattern = "^(?i)$([regex]::Escape($programFiles64))\\(?<Rest>.+)$"
                            if ($rawPathText -match $pf64Pattern -or $expanded -match $pf64Pattern) {
                                & $addProbeCandidate (Join-Path $programFilesX86 $Matches.Rest)
                            }
                        }
                    }
                    if ($useDefaultExpandedCandidate) { & $addProbeCandidate $expanded }

                    if ([Environment]::Is64BitOperatingSystem) {
                        $system32Pattern = "^(?i)$([regex]::Escape($systemRoot))\\System32\\(?<SubPath>.+)$"
                        if ($expanded -match $system32Pattern) {
                            if ([string]$RegistryView -eq "Registry32") {
                                $wow64Candidate = (Join-Path (Join-Path $systemRoot "SysWOW64") $Matches.SubPath).Trim()
                                if ($seenCandidates.Add($wow64Candidate)) { [void]$probeCandidates.Add($wow64Candidate) }
                            }
                            $sysnativeCandidate = (Join-Path (Join-Path $systemRoot "Sysnative") $Matches.SubPath).Trim()
                            if ($seenCandidates.Add($sysnativeCandidate)) { [void]$probeCandidates.Add($sysnativeCandidate) }
                        }
                    }

                    foreach ($candidate in $probeCandidates) {
                        try {
                            if (Test-Path -LiteralPath $candidate -ErrorAction Stop) {
                                $RegistryPathExistsCache[$cacheKey] = $true
                                return $true
                            }
                        }
                        catch [System.UnauthorizedAccessException] { $RegistryPathExistsCache[$cacheKey] = $true; return $true }
                        catch [System.Security.SecurityException] { $RegistryPathExistsCache[$cacheKey] = $true; return $true }
                        catch {}
                        try {
                            [void](Get-Item -LiteralPath $candidate -Force -ErrorAction Stop)
                            $RegistryPathExistsCache[$cacheKey] = $true
                            return $true
                        }
                        catch {
                            if ($_.Exception.Message -match '(?i)access.*denied|unauthorized') {
                                $RegistryPathExistsCache[$cacheKey] = $true
                                return $true
                            }
                        }
                        if ($candidate -match '^(?i)[a-z]:\\Program Files\\WindowsApps\\(?<PackageName>[^\\]+)') {
                            $packageParts = ([string]$Matches.PackageName).Split([char[]]@('_'), [System.StringSplitOptions]::RemoveEmptyEntries)
                            if ($packageParts.Length -ge 2) {
                                $packageFamily = "$($packageParts[0])_$($packageParts[$packageParts.Length - 1])"
                                try {
                                    $packageFamilyKey = "SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\PackageFamily\Index\PackageFamilyName\$packageFamily"
                                    $root = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($packageFamilyKey)
                                    if ($root) {
                                        $root.Close()
                                        $RegistryPathExistsCache[$cacheKey] = $true
                                        return $true
                                    }
                                }
                                catch {}
                            }
                        }
                    }

                    $RegistryPathExistsCache[$cacheKey] = $false
                    return $false
                }

                # Internal Helper: Clean Path Strings
                function Get-RealExePath {
                    param($RawString)
                    if ([string]::IsNullOrWhiteSpace($RawString)) { return $null }
                    $clean = $RawString.Trim()
                    if ($clean -match "^(.*?),\s*-?\d+$") { $clean = $matches[1].Trim() }
                    if ($clean.StartsWith('"')) {
                        $endQuote = $clean.IndexOf('"', 1)
                        if ($endQuote -gt 1) {
                            $quotedPart = $clean.Substring(1, $endQuote - 1)
                            if ($quotedPart -match "^(.*?),\s*-?\d+$") { $quotedPart = $matches[1].Trim() }
                            if (Test-PathExists $quotedPart) { return $quotedPart }
                            $clean = $quotedPart 
                        }
                    }
                    if (Test-PathExists $clean) { return $clean }
                    if ($clean.Contains(" ")) {
                        $parts = $clean -split " "
                        $candidate = $parts[0]
                        if ((Test-PathExists $candidate) -or (Test-PathExists "$candidate.exe")) { return $candidate }
                        for ($i = 1; $i -lt $parts.Count; $i++) {
                            $candidate += " " + $parts[$i]
                            if ((Test-PathExists $candidate) -or (Test-PathExists "$candidate.exe")) { return $candidate }
                        }
                    }
                    return $clean
                }

                function Test-IsRegistryFlagEnabled {
                    param($Value)
                    if ($null -eq $Value) { return $false }
                    try { return ([int]$Value -eq 1) }
                    catch { return ([string]$Value -eq "1") }
                }

                function Test-IsWindowsInstallerCommand {
                    param($RawString)
                    if ([string]::IsNullOrWhiteSpace($RawString)) { return $false }
                    $expanded = [Environment]::ExpandEnvironmentVariables($RawString.Trim())
                    return ($expanded -match '(?i)(^|[\\/"\s])msiexec(\.exe)?(?=$|[\s/"])')
                }

                function Get-UninstallExecutablePath {
                    param($RawString)
                    if ([string]::IsNullOrWhiteSpace($RawString)) { return $null }
                    $cmd = [Environment]::ExpandEnvironmentVariables($RawString.Trim())
                    if ([string]::IsNullOrWhiteSpace($cmd) -or (Test-IsWindowsInstallerCommand $cmd)) { return $null }

                    $candidate = $null
                    if ($cmd -match '^\s*"([^"]+)"') {
                        $candidate = $matches[1].Trim()
                    }
                    elseif ($cmd -match '^\s*(?<Path>[a-zA-Z]:\\.+?\.(?:exe|msi|cmd|bat|com))(?=$|\s)') {
                        $candidate = $matches.Path.Trim()
                    }
                    elseif ($cmd -match '^\s*(?<Path>[a-zA-Z]:\\[^\s]+)') {
                        $candidate = $matches.Path.Trim()
                    }

                    if ([string]::IsNullOrWhiteSpace($candidate)) { return $null }
                    $candidate = [Environment]::ExpandEnvironmentVariables($candidate)
                    if ($candidate -notmatch '^[a-zA-Z]:\\') { return $null }
                    if ($candidate -match '%.*%' -or $candidate -match '\$\(.*\)') { return $null }
                    return $candidate
                }

                function Get-WmtMalformedComServerCommandIssue {
                    param(
                        $RawString,
                        $RegistryView = $null
                    )
                    if ([string]::IsNullOrWhiteSpace($RawString)) { return $null }

                    $rawText = ([string]$RawString).Trim()
                    if ([string]::IsNullOrWhiteSpace($rawText)) { return $null }

                    $expanded = [Environment]::ExpandEnvironmentVariables($rawText)
                    $expanded = $expanded -replace '^(?i)\\\?\?\\', ''
                    $expanded = $expanded -replace '^(?i)\\\\\?\\', ''

                    $systemRoot = [Environment]::GetEnvironmentVariable("SystemRoot")
                    if ([string]::IsNullOrWhiteSpace($systemRoot)) { $systemRoot = "$env:SystemDrive\Windows" }
                    if ($expanded -match '^(?i)\\SystemRoot\\(?<SubPath>.+)$') {
                        $expanded = Join-Path $systemRoot $Matches.SubPath
                    }
                    elseif ($expanded -match '^(?i)System32\\(?<SubPath>.+)$') {
                        $expanded = Join-Path (Join-Path $systemRoot "System32") $Matches.SubPath
                    }

                    $exePath = $null
                    $argumentText = $null

                    # Some LocalServer32 registrations are malformed as:
                    #   C:\Program Files\App\App.exe/Automation
                    # The executable exists, but the argument is glued directly to the .exe path.
                    # Older WMT path parsing fell through to the first-space fallback and displayed C:\Program.
                    if ($expanded -match '^\s*"(?<Path>[^"]+?\.(?:exe|com|bat|cmd))(?<Args>/[^"]+)"\s*$') {
                        $exePath = $Matches.Path.Trim()
                        $argumentText = $Matches.Args.Trim()
                    }
                    elseif ($expanded -match '^\s*(?<Path>[a-zA-Z]:\\.+?\.(?:exe|com|bat|cmd))(?<Args>/\S.*)$') {
                        $exePath = $Matches.Path.Trim()
                        $argumentText = $Matches.Args.Trim()
                    }

                    if ([string]::IsNullOrWhiteSpace($exePath) -or [string]::IsNullOrWhiteSpace($argumentText)) { return $null }

                    # Keep both the displayed bad command and the rewritten COM command single-line.
                    # Registry Editor/UI wrapping can make this look like a newline, but the value we write must be:
                    #   "C:\Path With Spaces\App.exe" /Automation
                    # not:
                    #   "C:\Path With Spaces\App.exe"
                    #   /Automation
                    $rawCommandSingleLine = (($expanded -replace '[\r\n]+', ' ') -replace '\s{2,}', ' ').Trim()
                    $exePath = (($exePath -replace '[\r\n]+', ' ') -replace '\s{2,}', ' ').Trim()
                    $argumentText = (($argumentText -replace '[\r\n]+', ' ') -replace '\s{2,}', ' ').Trim()

                    if ([string]::IsNullOrWhiteSpace($exePath) -or [string]::IsNullOrWhiteSpace($argumentText)) { return $null }
                    if ($argumentText -notmatch '^/') { return $null }
                    if ($exePath -notmatch '^(?i)[a-z]:\\') { return $null }
                    if ($exePath -match '%.*%' -or $exePath -match '\$\(.*\)') { return $null }
                    if (-not (Test-PathExists -Path $exePath -RegistryView $RegistryView)) { return $null }

                    $fixedCommand = ('"{0}" {1}' -f $exePath, $argumentText).Trim()
                    $fixedCommand = (($fixedCommand -replace '[\r\n]+', ' ') -replace '\s{2,}', ' ').Trim()
                    return [PSCustomObject]@{
                        RawCommand   = $rawCommandSingleLine
                        ExePath      = $exePath
                        Arguments    = $argumentText
                        FixedCommand = $fixedCommand
                    }
                }

                function Get-ServiceImageExecutablePath {
                    param(
                        $RawString,
                        $RegistryView = $null
                    )
                    if ([string]::IsNullOrWhiteSpace($RawString)) { return $null }

                    $cmd = [Environment]::ExpandEnvironmentVariables(([string]$RawString).Trim())
                    $cmd = $cmd -replace '^(?i)\\\?\?\\', ''
                    $cmd = $cmd -replace '^(?i)\\\\\?\\', ''
                    $systemRoot = [Environment]::GetEnvironmentVariable("SystemRoot")
                    if ([string]::IsNullOrWhiteSpace($systemRoot)) { $systemRoot = "$env:SystemDrive\Windows" }
                    if ($cmd -match '^(?i)\\SystemRoot\\(?<SubPath>.+)$') {
                        $cmd = Join-Path $systemRoot $Matches.SubPath
                    }
                    elseif ($cmd -match '^(?i)System32\\(?<SubPath>.+)$') {
                        $cmd = Join-Path (Join-Path $systemRoot "System32") $Matches.SubPath
                    }
                    if ([string]::IsNullOrWhiteSpace($cmd)) { return $null }

                    $candidate = $null
                    if ($cmd -match '^\s*"([^"]+)"') {
                        $candidate = $matches[1].Trim()
                    }
                    elseif (Test-PathExists -Path $cmd -RegistryView $RegistryView) {
                        $candidate = $cmd
                    }
                    elseif ($cmd -match '^\s*(?<Path>[a-zA-Z]:\\.+?\.(?:exe|com|bat|cmd|sys|dll))(?=$|[\s/])') {
                        $candidate = $matches.Path.Trim()
                    }
                    elseif ($cmd -match '^\s*(?<Path>[a-zA-Z]:\\[^\s]+)') {
                        $candidate = $matches.Path.Trim()
                    }

                    if ([string]::IsNullOrWhiteSpace($candidate)) { return $null }
                    if ($candidate -match '%.*%' -or $candidate -match '\$\(.*\)') { return $null }
                    if ($candidate -notmatch '^[a-zA-Z]:\\') { return $null }
                    return $candidate
                }

                function New-PerUserRegistryTargets {
                    param(
                        [string]$SubPath,
                        [string]$HkcuLabel
                    )

                    $targets = New-Object System.Collections.Generic.List[object]
                    $currentSid = $null
                    try { $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch {}

                    $usersRoot = [Microsoft.Win32.Registry]::Users
                    $currentRegPrefix = "HKEY_CURRENT_USER\$SubPath"
                    $currentLabel = $HkcuLabel
                    if (-not [string]::IsNullOrWhiteSpace($currentSid)) {
                        $currentHive = $null
                        try { $currentHive = $usersRoot.OpenSubKey($currentSid) } catch {}
                        if ($currentHive) {
                            $currentHive.Close()
                            $currentRegPrefix = "HKEY_USERS\$currentSid\$SubPath"
                            $currentLabel = "Current user ($currentSid)\$SubPath"
                        }
                    }

                    [void]$targets.Add([PSCustomObject]@{
                            BaseKey   = [Microsoft.Win32.Registry]::CurrentUser
                            SubPath   = $SubPath
                            RegPrefix = $currentRegPrefix
                            Label     = $currentLabel
                        })

                    $sidNames = @($usersRoot.GetSubKeyNames() | Where-Object { $_ -match '^S-1-5-21-.+-\d+$' -and $_ -notmatch '_Classes$' })
                    foreach ($sid in $sidNames) {
                        if (-not [string]::IsNullOrWhiteSpace($currentSid) -and $sid -eq $currentSid) { continue }
                        [void]$targets.Add([PSCustomObject]@{
                                BaseKey   = $usersRoot
                                SubPath   = "$sid\$SubPath"
                                RegPrefix = "HKEY_USERS\$sid\$SubPath"
                                Label     = "$sid\$SubPath"
                            })
                    }

                    return $targets
                }

                function ConvertTo-WmtComparableAppName {
                    param([string]$Name)
                    if ([string]::IsNullOrWhiteSpace($Name)) { return "" }
                    return (($Name.ToLowerInvariant()) -replace '[^a-z0-9]', '')
                }

                function Add-WmtInstalledAppNameToken {
                    param(
                        [System.Collections.Generic.HashSet[string]]$TokenSet,
                        [string]$Name
                    )
                    $token = ConvertTo-WmtComparableAppName $Name
                    if ($token.Length -ge 5) { [void]$TokenSet.Add($token) }
                }

                function Get-WmtInstalledAppNameTokens {
                    if ($script:WmtInstalledAppNameTokens) { return $script:WmtInstalledAppNameTokens }

                    $tokens = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $uninstallRoots = @(
                        @{ Hive = [Microsoft.Win32.Registry]::LocalMachine; Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" },
                        @{ Hive = [Microsoft.Win32.Registry]::LocalMachine; Path = "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" },
                        @{ Hive = [Microsoft.Win32.Registry]::CurrentUser; Path = "Software\Microsoft\Windows\CurrentVersion\Uninstall" }
                    )

                    foreach ($rootInfo in $uninstallRoots) {
                        try {
                            $root = $rootInfo.Hive.OpenSubKey($rootInfo.Path)
                            if ($root) {
                                foreach ($subName in $root.GetSubKeyNames()) {
                                    $sub = $null
                                    try {
                                        $sub = $root.OpenSubKey($subName)
                                        if ($sub) {
                                            Add-WmtInstalledAppNameToken -TokenSet $tokens -Name ([string]$sub.GetValue("DisplayName"))
                                            Add-WmtInstalledAppNameToken -TokenSet $tokens -Name ([string]$sub.GetValue("Publisher"))
                                        }
                                    }
                                    catch {}
                                    finally {
                                        if ($sub) { $sub.Close() }
                                    }
                                }
                                $root.Close()
                            }
                        }
                        catch {}
                    }

                    foreach ($packagePath in @(
                            "SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\PackageFamily\Index\PackageFamilyName",
                            "SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Package\Index\PackageFullName"
                        )) {
                        try {
                            $root = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($packagePath)
                            if ($root) {
                                foreach ($subName in $root.GetSubKeyNames()) {
                                    Add-WmtInstalledAppNameToken -TokenSet $tokens -Name $subName
                                }
                                $root.Close()
                            }
                        }
                        catch {}
                    }

                    $script:WmtInstalledAppNameTokens = $tokens
                    return $script:WmtInstalledAppNameTokens
                }

                function Test-IsInstalledAppName {
                    param([string]$Name)
                    $token = ConvertTo-WmtComparableAppName $Name
                    if ($token.Length -lt 5) { return $false }

                    foreach ($installedToken in (Get-WmtInstalledAppNameTokens)) {
                        if ($installedToken.Length -lt 5) { continue }
                        if ($installedToken.Contains($token) -or ($token.Length -ge 8 -and $token.Contains($installedToken))) {
                            return $true
                        }
                    }

                    return $false
                }

                function Test-IsUserSoftwareKeyExcluded {
                    param([string]$Name)
                    if ([string]::IsNullOrWhiteSpace($Name)) { return $true }

                    $excluded = @(
                        "Classes",
                        "Clients",
                        "Microsoft",
                        "ODBC",
                        "Policies",
                        "RegisteredApplications",
                        "WOW6432Node"
                    )

                    foreach ($item in $excluded) {
                        if ($Name.Equals($item, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
                    }

                    if (Test-IsInstalledAppName $Name) { return $true }

                    return $false
                }

                function ConvertTo-WmtClsid {
                    param([string]$Value)
                    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
                    if ($Value -match '\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}') {
                        return $Matches[0].ToUpperInvariant()
                    }
                    return $null
                }

                function Get-WmtRegistryViews {
                    $views = New-Object System.Collections.Generic.List[object]

                    if ([Environment]::Is64BitOperatingSystem) {
                        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
                            $probe = $null
                            try {
                                $probe = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
                                if ($probe) { [void]$views.Add($view) }
                            }
                            catch {}
                            finally {
                                if ($probe) { $probe.Close() }
                            }
                        }
                    }

                    if ($views.Count -eq 0) { [void]$views.Add([Microsoft.Win32.RegistryView]::Default) }
                    return $views.ToArray()
                }

                function Get-WmtRegistryViewLabel {
                    param($View)

                    switch ([string]$View) {
                        "Registry64" { return "64-bit" }
                        "Registry32" { return "32-bit" }
                        default { return "default" }
                    }
                }

                function ConvertTo-WmtHklmViewPath {
                    param(
                        [string]$SubPath,
                        $View
                    )

                    $effectivePath = ([string]$SubPath).TrimStart('\')
                    if ([string]$View -eq "Registry32" -and $effectivePath -match '^(?i)SOFTWARE\\(?!WOW6432Node\\)(?<Rest>.+)$') {
                        $effectivePath = "SOFTWARE\WOW6432Node\$($Matches.Rest)"
                    }

                    return "HKLM:\$effectivePath"
                }

                function ConvertTo-WmtClassesViewPath {
                    param(
                        [string]$SubPath,
                        $View
                    )

                    $effectivePath = ([string]$SubPath).TrimStart('\')
                    if ([string]$View -eq "Registry32" -and [Environment]::Is64BitOperatingSystem) {
                        # Store the real writable backing path, not the merged HKCR\WOW6432Node view.
                        # HKCR is merged/virtual, and deleting through HKCR\WOW6432Node can fail or hit the wrong view.
                        return "HKLM:\SOFTWARE\WOW6432Node\Classes\$effectivePath"
                    }
                    if ([string]$View -eq "Registry64") {
                        return "HKLM:\SOFTWARE\Classes\$effectivePath"
                    }

                    return "HKCR:\$effectivePath"
                }

                function Get-WmtMissingRegistryPathTarget {
                    param(
                        $RawValue,
                        $RegistryView = $null
                    )

                    if ($null -eq $RawValue) { return $null }
                    $cleanPath = Get-RealExePath ([string]$RawValue)
                    if ([string]::IsNullOrWhiteSpace($cleanPath)) { return $null }
                    if ($cleanPath -notmatch '^[a-zA-Z]:\\') { return $null }
                    if (Test-IsWhitelisted $cleanPath) { return $null }
                    if (Test-IsProtectedWindowsPath $cleanPath) { return $null }
                    if (Test-PathExists -Path $cleanPath -RegistryView $RegistryView) { return $null }

                    if ($cleanPath -match '^(?<Path>[a-zA-Z]:\\.+\.(?:dll|exe|ocx|tlb|olb))\\-?\d+$') {
                        $resourceHostPath = $Matches.Path
                        if ((-not (Test-IsProtectedWindowsPath $resourceHostPath)) -and (Test-PathExists -Path $resourceHostPath -RegistryView $RegistryView)) {
                            return $null
                        }
                    }

                    return $cleanPath
                }

                function Test-WmtClsidExists {
                    param([string]$Clsid)
                    $normalized = ConvertTo-WmtClsid $Clsid
                    if (-not $normalized) { return $false }

                    foreach ($view in @(Get-WmtRegistryViews)) {
                        $root = $null; $key = $null
                        try {
                            $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::ClassesRoot, $view)
                            $key = $root.OpenSubKey("CLSID\$normalized", $false)
                            if ($key) { return $true }
                        }
                        catch {}
                        finally {
                            if ($key) { $key.Close() }
                            if ($root) { $root.Close() }
                        }
                    }

                    return $false
                }

                function Test-WmtClsidExistsForTarget {
                    param(
                        [string]$Clsid,
                        [object]$Target
                    )
                    $normalized = ConvertTo-WmtClsid $Clsid
                    if (-not $normalized) { return $false }
                    if (Test-WmtClsidExists $normalized) { return $true }

                    $userClassesPath = $null
                    if ($Target -and [string]$Target.RegPrefix -match '^HKEY_USERS\\(?<Sid>[^\\]+)\\') {
                        $userClassesPath = "$($Matches.Sid)\Software\Classes\CLSID\$normalized"
                        $usersRoot = [Microsoft.Win32.Registry]::Users
                        $key = $null
                        try {
                            $key = $usersRoot.OpenSubKey($userClassesPath, $false)
                            return ($null -ne $key)
                        }
                        catch { return $false }
                        finally {
                            if ($key) { $key.Close() }
                        }
                    }
                    elseif ($Target -and [string]$Target.RegPrefix -match '^(HKEY_CURRENT_USER|HKCU:)') {
                        $key = $null
                        try {
                            $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Classes\CLSID\$normalized", $false)
                            return ($null -ne $key)
                        }
                        catch { return $false }
                        finally {
                            if ($key) { $key.Close() }
                        }
                    }

                    return $false
                }

                function Get-WmtClsidReferenceIssue {
                    param(
                        [string]$Clsid,
                        $View = $null
                    )
                    $normalized = ConvertTo-WmtClsid $Clsid
                    if (-not $normalized) { return $null }

                    $viewsToScan = if ($null -ne $View) { @($View) } else { @(Get-WmtRegistryViews) }
                    $foundClsid = $false

                    foreach ($scanView in $viewsToScan) {
                        $viewLabel = Get-WmtRegistryViewLabel $scanView
                        $root = $null; $clsidKey = $null
                        try {
                            $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::ClassesRoot, $scanView)
                            $clsidKey = $root.OpenSubKey("CLSID\$normalized", $false)
                            if (-not $clsidKey) { continue }

                            $foundClsid = $true
                            foreach ($serverName in @("InProcServer32", "LocalServer32")) {
                                $serverKey = $null
                                try {
                                    $serverKey = $clsidKey.OpenSubKey($serverName, $false)
                                    if ($serverKey) {
                                        $rawServer = [string]$serverKey.GetValue($null)
                                        $serverPath = Get-ServiceImageExecutablePath -RawString $rawServer -RegistryView $scanView
                                        if ($serverPath -and -not (Test-IsWhitelisted $serverPath) -and -not (Test-IsProtectedWindowsPath $serverPath) -and -not (Test-PathExists -Path $serverPath -RegistryView $scanView)) {
                                            return [PSCustomObject]@{ IsBroken = $true; Data = $serverPath; Details = "Referenced CLSID $normalized ($viewLabel registry view) points to missing COM server $serverPath." }
                                        }
                                    }
                                }
                                catch {}
                                finally {
                                    if ($serverKey) { $serverKey.Close() }
                                }
                            }
                        }
                        catch {}
                        finally {
                            if ($clsidKey) { $clsidKey.Close() }
                            if ($root) { $root.Close() }
                        }
                    }

                    if (-not $foundClsid) {
                        $viewText = if ($null -ne $View) { "$(Get-WmtRegistryViewLabel $View) registry view" } else { "available registry views" }
                        return [PSCustomObject]@{ IsBroken = $true; Data = $normalized; Details = "Referenced CLSID $normalized does not exist under $viewText." }
                    }

                    return [PSCustomObject]@{ IsBroken = $false; Data = $normalized; Details = "" }
                }

                function Get-WmtMissingPathSegments {
                    param([string]$PathValue)
                    $missing = New-Object System.Collections.Generic.List[string]
                    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $missing.ToArray() }

                    foreach ($segment in ($PathValue -split ';')) {
                        $candidate = ([string]$segment).Trim()
                        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
                        if ($candidate -match '[\*\?]' -or $candidate -match '^\.+$') { continue }
                        if ($candidate -notmatch '^(?i)([a-z]:\\|%[^%]+%\\|\\\\)') { continue }
                        if (-not (Test-PathExists $candidate)) { [void]$missing.Add($candidate) }
                    }

                    return $missing.ToArray()
                }

                function Get-WmtCleanedPathValue {
                    param(
                        [string]$PathValue,
                        [string[]]$MissingSegments
                    )
                    $missingSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($segment in @($MissingSegments)) {
                        if (-not [string]::IsNullOrWhiteSpace($segment)) { [void]$missingSet.Add($segment.Trim()) }
                    }

                    $kept = New-Object System.Collections.Generic.List[string]
                    foreach ($segment in ($PathValue -split ';')) {
                        $trimmed = ([string]$segment).Trim()
                        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
                        if (-not $missingSet.Contains($trimmed)) { [void]$kept.Add($trimmed) }
                    }

                    return ($kept -join ';')
                }

                function Get-WmtTaskTreeEntries {
                    param(
                        [Microsoft.Win32.RegistryKey]$Key,
                        [string]$RelativePath
                    )

                    $entries = New-Object System.Collections.Generic.List[object]
                    foreach ($childName in $Key.GetSubKeyNames()) {
                        $child = $null
                        try {
                            $child = $Key.OpenSubKey($childName, $false)
                            if ($child) {
                                $childRelativePath = if ([string]::IsNullOrWhiteSpace($RelativePath)) { $childName } else { "$RelativePath\$childName" }
                                $taskId = [string]$child.GetValue("Id")
                                if (-not [string]::IsNullOrWhiteSpace($taskId)) {
                                    [void]$entries.Add([PSCustomObject]@{ RelativePath = $childRelativePath; Id = $taskId })
                                }
                                foreach ($entry in @(Get-WmtTaskTreeEntries -Key $child -RelativePath $childRelativePath)) {
                                    [void]$entries.Add($entry)
                                }
                            }
                        }
                        catch {}
                        finally {
                            if ($child) { $child.Close() }
                        }
                    }

                    return $entries.ToArray()
                }

                function Get-WmtTaskFilePath {
                    param([string]$TaskPath)
                    if ([string]::IsNullOrWhiteSpace($TaskPath)) { return $null }
                    $relative = $TaskPath.TrimStart('\')
                    if ([string]::IsNullOrWhiteSpace($relative)) { return $null }
                    return (Join-Path (Join-Path $env:windir "System32\Tasks") $relative)
                }

                function Test-WmtProtectedSystemTaskPath {
                    param([string]$TaskPath)
                    if ([string]::IsNullOrWhiteSpace($TaskPath)) { return $false }
                    $relative = ([string]$TaskPath).Trim().TrimStart('\')
                    return ($relative -match '^(?i)Microsoft\\(Windows|OneCore)\\')
                }

                function Get-WmtPathState {
                    param(
                        [string]$Path,
                        [string]$PathType = "Any"
                    )
                    if ([string]::IsNullOrWhiteSpace($Path)) { return "Unknown" }

                    try {
                        if (Test-Path -LiteralPath $Path -PathType $PathType -ErrorAction Stop) { return "Exists" }
                    }
                    catch [System.UnauthorizedAccessException] { return "Unknown" }
                    catch [System.Security.SecurityException] { return "Unknown" }
                    catch {}

                    try {
                        [void](Get-Item -LiteralPath $Path -Force -ErrorAction Stop)
                        return "Exists"
                    }
                    catch {
                        if ($_.CategoryInfo.Category -eq [System.Management.Automation.ErrorCategory]::ObjectNotFound) { return "Missing" }
                        if ($_.Exception.Message -match '(?i)access.*denied|unauthorized') { return "Unknown" }
                    }

                    return "Unknown"
                }

                function Get-WmtTaskSchedulerService {
                    if ($script:WmtTaskSchedulerServiceChecked) { return $script:WmtTaskSchedulerService }
                    $script:WmtTaskSchedulerServiceChecked = $true
                    $script:WmtTaskSchedulerService = $null

                    try {
                        $service = New-Object -ComObject "Schedule.Service"
                        $service.Connect()
                        $script:WmtTaskSchedulerService = $service
                    }
                    catch {
                        $script:WmtTaskSchedulerService = $null
                    }

                    return $script:WmtTaskSchedulerService
                }

                function Get-WmtScheduledTaskState {
                    param([string]$TaskPath)
                    if ([string]::IsNullOrWhiteSpace($TaskPath)) { return "Unknown" }

                    $service = Get-WmtTaskSchedulerService
                    if (-not $service) { return "Unknown" }

                    $normalized = ([string]$TaskPath).Trim() -replace '/', '\'
                    $normalized = $normalized.Trim('\')
                    if ([string]::IsNullOrWhiteSpace($normalized)) { return "Unknown" }

                    $parts = @($normalized -split '\\' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                    if ($parts.Count -eq 0) { return "Unknown" }

                    $taskName = $parts[$parts.Count - 1]
                    $folderPath = "\"
                    if ($parts.Count -gt 1) {
                        $folderPath = "\" + (($parts[0..($parts.Count - 2)]) -join "\")
                    }

                    $folder = $null; $task = $null
                    try {
                        $folder = $service.GetFolder($folderPath)
                        $task = $folder.GetTask($taskName)
                        return "Exists"
                    }
                    catch {
                        $hr = $_.Exception.HResult
                        $msg = [string]$_.Exception.Message
                        if ($hr -eq -2147024894 -or $msg -match '(?i)(cannot find|not found|does not exist|0x80070002)') { return "Missing" }
                        if ($hr -eq -2147024891 -or $msg -match '(?i)access.*denied|unauthorized|0x80070005') { return "Unknown" }
                    }
                    finally {
                        try { if ($task) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($task) } } catch {}
                        try { if ($folder) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($folder) } } catch {}
                    }

                    return "Unknown"
                }

                try {
                    $categoryWeight = 100.0 / ($SelectedScans.Count)
                    $currentBaseProgress = 0.0

                    # Tick Helper
                    $Tick = {
                        param($DetailText, $CurrentIndex, $TotalEstimated)
                        if ($CurrentIndex % 50 -eq 0) {
                            $SyncHash.Status = $DetailText
                            $fraction = [math]::Min(($CurrentIndex / $TotalEstimated), 1.0)
                            $realVal = $currentBaseProgress + ($fraction * $categoryWeight)
                            $SyncHash.Progress = [int]$realVal
                        }
                    }
                    $EndCategory = {
                        $currentBaseProgress += $categoryWeight
                        $SyncHash.Progress = [int]$currentBaseProgress
                    }

                    # 1. ACTIVEX & COM
                    if ($SelectedScans -contains "ActiveX") {
                        $SyncHash.Status = "Scanning ActiveX/COM..."

                        $seenComFindings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        $comTargets = [System.Collections.Generic.List[object]]::new()

                        function Add-WmtComClassScanTarget {
                            param(
                                [System.Collections.Generic.List[object]]$Targets,
                                [Microsoft.Win32.RegistryHive]$Hive,
                                $View,
                                [string]$SubPath,
                                [string]$RegPathPrefix,
                                [string]$Label
                            )

                            if ([string]::IsNullOrWhiteSpace($SubPath) -or [string]::IsNullOrWhiteSpace($RegPathPrefix)) { return }

                            $root = $null
                            $probe = $null
                            try {
                                $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, $View)
                                $probe = $root.OpenSubKey($SubPath, $false)
                                if ($probe) {
                                    [void]$Targets.Add([PSCustomObject]@{
                                            Root          = $root
                                            SubPath       = $SubPath
                                            RegPathPrefix = $RegPathPrefix
                                            Label         = $Label
                                            View          = $View
                                        })
                                    $root = $null
                                }
                            }
                            catch {}
                            finally {
                                if ($probe) { $probe.Close() }
                                if ($root) { $root.Close() }
                            }
                        }

                        function Get-WmtComServerProtectionClassification {
                            param(
                                [string]$CleanServerPath,
                                [string]$RawServerPath,
                                [string]$RegPath,
                                [string]$TargetLabel
                            )

                            $clean = [string]$CleanServerPath
                            $raw = [string]$RawServerPath
                            $reg = [string]$RegPath
                            $label = [string]$TargetLabel

                            $isMachineClassStore = ($reg -match '^(?i)(HKLM:\\SOFTWARE\\(WOW6432Node\\)?Classes\\CLSID\\|HKCR:\\(WOW6432Node\\)?CLSID\\)') -or ($label -match '(?i)Machine classes|HKCR merged view')
                            $isMicrosoftSharedCom = ($clean -match '(?i)\\Common Files\\Microsoft Shared\\DAO\\dao360\.dll$') -or `
                            ($clean -match '(?i)\\Common Files\\System\\Ole DB\\msdaora\.dll$') -or `
                            ($raw -match '(?i)%CommonProgramFiles%\\(Microsoft Shared\\DAO|System\\Ole DB)\\')
                            $isWindowsCrossDeviceCom = ($clean -match '(?i)\\ProgramData\\CrossDevice\\CrossDevice\.Streaming\.Source\.dll$') -or `
                            ($raw -match '(?i)%PROGRAMDATA%\\CrossDevice\\CrossDevice\.Streaming\.Source\.dll')

                            if ($isMachineClassStore -and ($isMicrosoftSharedCom -or $isWindowsCrossDeviceCom)) {
                                $reason = if ($isWindowsCrossDeviceCom) {
                                    "Windows CrossDevice machine COM registration. These entries are commonly ACL-protected and may be recreated by Windows components."
                                }
                                else {
                                    "Legacy Microsoft DAO/OLE DB machine COM registration in the merged Classes store. These entries are often Windows/Office shared component registrations, ACL-protected, redirected between 32-bit/64-bit views, or recreated."
                                }
                                return [PSCustomObject]@{
                                    IsProtected = $true
                                    Reason      = $reason
                                    Risk        = "Review"
                                    Confidence  = "Medium"
                                }
                            }

                            if ($label -match '(?i)^HKCR merged view' -and $reg -match '(?i)^HKCR:\\WOW6432Node\\CLSID\\') {
                                return [PSCustomObject]@{
                                    IsProtected = $true
                                    Reason      = "HKCR WOW6432Node is a merged/redirected COM view, not a simple writable cleanup location. WMT can report the stale reference, but automatic deletion through this alias has proven unreliable on this system."
                                    Risk        = "Review"
                                    Confidence  = "Medium"
                                }
                            }

                            return [PSCustomObject]@{
                                IsProtected = $false
                                Reason      = ""
                                Risk        = "Medium"
                                Confidence  = "High"
                            }
                        }

                        function Add-WmtMissingComServerFinding {
                            param(
                                [string]$Clsid,
                                [string]$ServerSubKey,
                                [string]$RawServerPath,
                                [string]$RegPath,
                                [string]$TargetLabel,
                                $RegistryView
                            )

                            if ([string]::IsNullOrWhiteSpace($Clsid) -or [string]::IsNullOrWhiteSpace($RawServerPath)) { return }
                            if (Test-IsWhitelisted $RawServerPath) { return }

                            if ($ServerSubKey -eq "LocalServer32") {
                                $malformedCommand = Get-WmtMalformedComServerCommandIssue -RawString $RawServerPath -RegistryView $RegistryView
                                if ($malformedCommand) {
                                    $dedupeMalformedKey = "$Clsid`0$ServerSubKey`0MalformedAttachedArgument`0$($malformedCommand.RawCommand)"
                                    if (-not $seenComFindings.Add($dedupeMalformedKey)) { return }

                                    [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                            Problem    = "Invalid COM LocalServer Command"
                                            Data       = [string]$malformedCommand.RawCommand
                                            DisplayKey = "$Clsid (COM EXE, $TargetLabel)"
                                            RegPath    = $RegPath
                                            ValueName  = ""
                                            Type       = "SetValue"
                                            NewData    = [string]$malformedCommand.FixedCommand
                                            SafeToFix  = $true
                                            Risk       = "Low"
                                            Confidence = "High"
                                            Details    = "LocalServer32 has an argument attached directly to the executable path. Executable exists: $($malformedCommand.ExePath). WMT will rewrite the default value to: $($malformedCommand.FixedCommand). Registry view/source: $TargetLabel. Raw value: $RawServerPath"
                                        })
                                    return
                                }
                            }

                            $cleanServerPath = Get-ServiceImageExecutablePath -RawString $RawServerPath -RegistryView $RegistryView
                            if ([string]::IsNullOrWhiteSpace($cleanServerPath)) { $cleanServerPath = Get-RealExePath $RawServerPath }
                            if ([string]::IsNullOrWhiteSpace($cleanServerPath)) { return }
                            if ($cleanServerPath -notmatch '^(?i)[a-z]:\\') { return }
                            if (Test-IsWhitelisted $cleanServerPath) { return }
                            if (Test-IsProtectedWindowsPath $cleanServerPath) { return }
                            if (Test-PathExists -Path $cleanServerPath -RegistryView $RegistryView) { return }

                            $dedupeKey = "$Clsid`0$ServerSubKey`0$cleanServerPath"
                            if (-not $seenComFindings.Add($dedupeKey)) { return }

                            $serverKind = if ($ServerSubKey -eq "InProcServer32") { "COM DLL" } else { "COM EXE" }
                            $protection = Get-WmtComServerProtectionClassification -CleanServerPath $cleanServerPath -RawServerPath $RawServerPath -RegPath $RegPath -TargetLabel $TargetLabel
                            $isProtectedCom = [bool]$protection.IsProtected
                            $findingProblem = if ($isProtectedCom) { "Protected ActiveX Issue" } else { "ActiveX Issue" }
                            $findingType = if ($isProtectedCom) { "ReviewOnly" } else { "Key" }
                            $findingRisk = if ($isProtectedCom) { [string]$protection.Risk } else { "Medium" }
                            $findingConfidence = if ($isProtectedCom) { [string]$protection.Confidence } else { "High" }
                            $findingDetails = if ($isProtectedCom) {
                                "$serverKind registration points to a missing file, but WMT will not select or delete it automatically because it appears to be a protected/merged Microsoft COM registration. $($protection.Reason) Registry view/source: $TargetLabel. Raw value: $RawServerPath"
                            }
                            else {
                                "$serverKind registration points to a missing file. The target file does not exist and the path is not under a protected Windows folder, so this stale COM server key is selected by default. Registry view/source: $TargetLabel. Raw value: $RawServerPath"
                            }

                            [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                    Problem    = $findingProblem
                                    Data       = $cleanServerPath
                                    DisplayKey = "$Clsid ($serverKind, $TargetLabel)"
                                    RegPath    = $RegPath
                                    ValueName  = $null
                                    Type       = $findingType
                                    SafeToFix  = (-not $isProtectedCom)
                                    Risk       = $findingRisk
                                    Confidence = $findingConfidence
                                    Details    = $findingDetails
                                })
                        }

                        try {
                            foreach ($view in @(Get-WmtRegistryViews)) {
                                $viewLabel = Get-WmtRegistryViewLabel $view
                                Add-WmtComClassScanTarget -Targets $comTargets -Hive ([Microsoft.Win32.RegistryHive]::LocalMachine) -View $view -SubPath "SOFTWARE\Classes\CLSID" -RegPathPrefix (ConvertTo-WmtClassesViewPath -SubPath "CLSID" -View $view) -Label "Machine classes, $viewLabel"
                            }

                            Add-WmtComClassScanTarget -Targets $comTargets -Hive ([Microsoft.Win32.RegistryHive]::CurrentUser) -View ([Microsoft.Win32.RegistryView]::Default) -SubPath "Software\Classes\CLSID" -RegPathPrefix "HKCU:\Software\Classes\CLSID" -Label "Current user classes"
                            if ([Environment]::Is64BitOperatingSystem) {
                                Add-WmtComClassScanTarget -Targets $comTargets -Hive ([Microsoft.Win32.RegistryHive]::CurrentUser) -View ([Microsoft.Win32.RegistryView]::Default) -SubPath "Software\Classes\WOW6432Node\CLSID" -RegPathPrefix "HKCU:\Software\Classes\WOW6432Node\CLSID" -Label "Current user classes, 32-bit"
                            }

                            $currentSid = $null
                            try { $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch {}
                            $usersRoot = $null
                            try {
                                $usersRoot = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::Users, [Microsoft.Win32.RegistryView]::Default)
                                foreach ($sid in @($usersRoot.GetSubKeyNames())) {
                                    if ($sid -notmatch '^S-1-5-21-.+-\d+$' -or $sid -match '_Classes$') { continue }
                                    if (-not [string]::IsNullOrWhiteSpace($currentSid) -and $sid -eq $currentSid) { continue }

                                    Add-WmtComClassScanTarget -Targets $comTargets -Hive ([Microsoft.Win32.RegistryHive]::Users) -View ([Microsoft.Win32.RegistryView]::Default) -SubPath "$sid\Software\Classes\CLSID" -RegPathPrefix "HKU:\$sid\Software\Classes\CLSID" -Label "User classes, $sid"
                                    if ([Environment]::Is64BitOperatingSystem) {
                                        Add-WmtComClassScanTarget -Targets $comTargets -Hive ([Microsoft.Win32.RegistryHive]::Users) -View ([Microsoft.Win32.RegistryView]::Default) -SubPath "$sid\Software\Classes\WOW6432Node\CLSID" -RegPathPrefix "HKU:\$sid\Software\Classes\WOW6432Node\CLSID" -Label "User classes, $sid, 32-bit"
                                    }
                                }
                            }
                            catch {}
                            finally {
                                if ($usersRoot) { $usersRoot.Close() }
                            }

                            # HKCR is a merged view. Scan it as a final fallback because some orphaned COM registrations
                            # are visible to the PowerShell provider under HKCR even when they are not found through the
                            # machine-only Classes paths above. On 64-bit Windows, 32-bit COM entries can also appear under
                            # HKCR:\WOW6432Node\CLSID when viewed from the 64-bit registry provider.
                            Add-WmtComClassScanTarget -Targets $comTargets -Hive ([Microsoft.Win32.RegistryHive]::ClassesRoot) -View ([Microsoft.Win32.RegistryView]::Default) -SubPath "CLSID" -RegPathPrefix "HKCR:\CLSID" -Label "HKCR merged view"
                            if ([Environment]::Is64BitOperatingSystem) {
                                Add-WmtComClassScanTarget -Targets $comTargets -Hive ([Microsoft.Win32.RegistryHive]::ClassesRoot) -View ([Microsoft.Win32.RegistryView]::Default) -SubPath "WOW6432Node\CLSID" -RegPathPrefix "HKCR:\WOW6432Node\CLSID" -Label "HKCR merged view, 32-bit"
                            }

                            foreach ($target in @($comTargets)) {
                                $clsidKey = $null
                                try {
                                    $clsidKey = $target.Root.OpenSubKey([string]$target.SubPath, $false)
                                    if (-not $clsidKey) { continue }

                                    $subKeys = $clsidKey.GetSubKeyNames()
                                    $total = [math]::Max($subKeys.Count, 1)
                                    $i = 0

                                    foreach ($id in $subKeys) {
                                        $i++
                                        & $Tick "Scanning CLSID ($($target.Label)): $id" $i $total

                                        foreach ($serverSubKey in @("InProcServer32", "LocalServer32")) {
                                            $serverKey = $null
                                            try {
                                                $serverKey = $clsidKey.OpenSubKey("$id\$serverSubKey", $false)
                                                if (-not $serverKey) { continue }

                                                $rawServerPath = [string]$serverKey.GetValue($null, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                                                if ([string]::IsNullOrWhiteSpace($rawServerPath)) { continue }

                                                $regPath = "$($target.RegPathPrefix)\$id\$serverSubKey"
                                                Add-WmtMissingComServerFinding -Clsid $id -ServerSubKey $serverSubKey -RawServerPath $rawServerPath -RegPath $regPath -TargetLabel ([string]$target.Label) -RegistryView $target.View
                                            }
                                            catch {}
                                            finally {
                                                if ($serverKey) { $serverKey.Close() }
                                            }
                                        }
                                    }
                                }
                                catch {}
                                finally {
                                    if ($clsidKey) { $clsidKey.Close() }
                                }
                            }
                        }
                        finally {
                            foreach ($target in @($comTargets)) {
                                try { if ($target.Root) { $target.Root.Close() } } catch {}
                            }
                        }

                        & $EndCategory
                    }

                    # 2. FILE EXTENSIONS
                    if ($SelectedScans -contains "Ext") { 
                        $SyncHash.Status = "Scanning File Extensions..."
                        $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::ClassesRoot, [Microsoft.Win32.RegistryView]::Default)
                        $names = $root.GetSubKeyNames(); $total = $names.Count; $i = 0
                        foreach ($ext in $names) { 
                            $i++; & $Tick "Scanning Ext: $ext" $i $total
                            if ($ext.StartsWith(".")) { 
                                try { 
                                    $sub = $root.OpenSubKey($ext)
                                    if ($sub.SubKeyCount -eq 0 -and $sub.ValueCount -eq 0 -and $null -eq $sub.GetValue($null)) { 
                                        [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Unused Extension"; Data = $ext; DisplayKey = $ext; RegPath = "HKCR:\$ext"; ValueName = $null; Type = "Key" }) 
                                    }; $sub.Close() 
                                }
                                catch {} 
                            } 
                        }
                        & $EndCategory
                    }

                    # 3. USER FILE EXTS
                    if ($SelectedScans -contains "FileExts") {
                        $SyncHash.Status = "Scanning User File Associations..."
                        $path = "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts"
                        $root = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path)
                        if ($root) {
                            $names = $root.GetSubKeyNames(); $total = $names.Count; $i = 0
                            foreach ($ext in $names) {
                                $i++; & $Tick "Scanning UserExt: $ext" $i $total
                                $owl = $root.OpenSubKey("$ext\OpenWithList")
                                if ($owl) {
                                    foreach ($valName in $owl.GetValueNames()) {
                                        if ($valName -match "^[a-z]$") { 
                                            $val = $owl.GetValue($valName)
                                            if ($val -match '^[a-zA-Z]:\\') {
                                                $cleanPath = Get-RealExePath $val
                                                if (-not (Test-PathExists $cleanPath)) { [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Invalid FileExt MRU"; Data = $cleanPath; DisplayKey = $ext; RegPath = "HKCU:\$path\$ext\OpenWithList"; ValueName = $valName; Type = "Value" }) }
                                            }
                                        }
                                    }
                                    $owl.Close()
                                }
                            }
                            $root.Close()
                        }
                        & $EndCategory
                    }

                    # 4. APP PATHS
                    if ($SelectedScans -contains "AppPaths") {
                        $SyncHash.Status = "Scanning App Paths..."
                        $key = "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths"
                        foreach ($view in @(Get-WmtRegistryViews)) {
                            $baseKey = $null; $root = $null
                            try {
                                $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
                                $root = $baseKey.OpenSubKey($key)
                                if ($root) {
                                    $viewLabel = Get-WmtRegistryViewLabel $view
                                    $names = $root.GetSubKeyNames(); $total = $names.Count; $i = 0
                                    foreach ($app in $names) {
                                        $i++; & $Tick "Scanning AppPath ($viewLabel): $app" $i $total
                                        try {
                                            $sub = $root.OpenSubKey($app)
                                            $path = $sub.GetValue($null)
                                            if ($path -and $path -match '^[a-zA-Z]:\\' -and -not (Test-IsWhitelisted $path)) {
                                                $clean = Get-RealExePath $path
                                                if (-not (Test-IsProtectedWindowsPath $clean) -and -not (Test-PathExists $clean)) { [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Missing App Path"; Data = $clean; DisplayKey = "$app ($viewLabel)"; RegPath = "$(ConvertTo-WmtHklmViewPath -SubPath $key -View $view)\$app"; ValueName = $null; Type = "Key"; Details = "App Paths target is missing in the $viewLabel registry view." }) }
                                            }
                                            $pathValue = [string]$sub.GetValue("Path", $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                                            $missingSegments = @(Get-WmtMissingPathSegments $pathValue)
                                            if ($missingSegments.Count -gt 0) {
                                                $newPath = Get-WmtCleanedPathValue -PathValue $pathValue -MissingSegments $missingSegments
                                                $data = $missingSegments[0]
                                                if ($missingSegments.Count -gt 1) { $data = "$data ($($missingSegments.Count) missing App Paths entries)" }
                                                [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                                        Problem    = "Invalid App Paths PATH Entry"
                                                        Data       = $data
                                                        DisplayKey = "$app ($viewLabel)"
                                                        RegPath    = "$(ConvertTo-WmtHklmViewPath -SubPath $key -View $view)\$app"
                                                        ValueName  = "Path"
                                                        Type       = "SetValue"
                                                        NewData    = $newPath
                                                        SafeToFix  = $true
                                                        Risk       = "Low"
                                                        Confidence = "High"
                                                        Details    = "Rewrites this App Paths PATH value after removing missing segment(s): $($missingSegments -join '; ')"
                                                    })
                                            }
                                            $sub.Close()
                                        }
                                        catch {}
                                    }
                                }
                            }
                            catch {}
                            finally {
                                if ($root) { $root.Close() }
                                if ($baseKey) { $baseKey.Close() }
                            }
                        }
                        & $EndCategory
                    }

                    # 5. APPLICATIONS & PROGIDs
                    if ($SelectedScans -contains "Apps" -or $SelectedScans -contains "ProgIDs") {
                        $SyncHash.Status = "Scanning Apps & ProgIDs..."
                        $searchRoots = @()
                        if ($SelectedScans -contains "Apps") { 
                            $cr = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::ClassesRoot, [Microsoft.Win32.RegistryView]::Default)
                            $searchRoots += $cr.OpenSubKey("Applications") 
                        }
                        if ($SelectedScans -contains "ProgIDs") { 
                            $searchRoots += [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::ClassesRoot, [Microsoft.Win32.RegistryView]::Default)
                        }

                        foreach ($root in $searchRoots) {
                            if ($root) {
                                $names = $root.GetSubKeyNames(); $total = $names.Count; $i = 0
                                foreach ($app in $names) {
                                    $i++; & $Tick "Scanning App: $app" $i $total
                                    try {
                                        $appKey = $root.OpenSubKey($app); $shellKey = $appKey.OpenSubKey("shell")
                                        if ($shellKey) {
                                            foreach ($verb in $shellKey.GetSubKeyNames()) {
                                                try {
                                                    $cmdKey = $shellKey.OpenSubKey("$verb\command")
                                                    if ($cmdKey) {
                                                        $cmd = $cmdKey.GetValue($null)
                                                        if ($cmd) {
                                                            $clean = Get-RealExePath $cmd
                                                            if ($clean -and $clean -match '^[a-zA-Z]:\\' -and -not (Test-IsWhitelisted $clean)) {
                                                                if (-not (Test-IsProtectedWindowsPath $clean) -and -not (Test-PathExists $clean) -and $clean -notmatch "%1") {
                                                                    [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Invalid App Command ($verb)"; Data = $clean; DisplayKey = $app; RegPath = "$($root.Name)\$app\shell\$verb\command"; ValueName = $null; Type = "Key" })
                                                                }
                                                            }
                                                        }
                                                        $cmdKey.Close()
                                                    }
                                                }
                                                catch {}
                                            }
                                            $shellKey.Close()
                                        }
                                        $appKey.Close()
                                    }
                                    catch {}
                                }
                            }
                        }
                        & $EndCategory
                    }

                    # 6. UNINSTALLERS
                    if ($SelectedScans -contains "Uninstall") {
                        $SyncHash.Status = "Scanning Uninstallers..."
                        $uninstallTargets = New-Object System.Collections.Generic.List[object]
                        $uninstallPath = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
                        foreach ($view in @(Get-WmtRegistryViews)) {
                            try {
                                $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
                                [void]$uninstallTargets.Add([PSCustomObject]@{ BaseKey = $baseKey; SubPath = $uninstallPath; RegPrefix = (ConvertTo-WmtHklmViewPath -SubPath $uninstallPath -View $view); Label = "HKLM $(Get-WmtRegistryViewLabel $view)"; OwnsBaseKey = $true })
                            }
                            catch {}
                        }
                        foreach ($target in @(New-PerUserRegistryTargets -SubPath "Software\Microsoft\Windows\CurrentVersion\Uninstall" -HkcuLabel "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall")) {
                            [void]$uninstallTargets.Add([PSCustomObject]@{ BaseKey = $target.BaseKey; SubPath = $target.SubPath; RegPrefix = $target.RegPrefix; Label = $target.Label; OwnsBaseKey = $false })
                        }

                        $total = [math]::Max($uninstallTargets.Count * 100, 1); $i = 0
                        foreach ($target in $uninstallTargets) {
                            $rk = $null
                            try {
                                $rk = $target.BaseKey.OpenSubKey($target.SubPath)
                                if ($rk) {
                                    foreach ($subName in $rk.GetSubKeyNames()) {
                                        $i++; & $Tick "Scanning Uninstaller: $subName" $i $total
                                        $sub = $null
                                        try {
                                            $sub = $rk.OpenSubKey($subName)
                                            if (-not $sub) { continue }
                                            $uString = $sub.GetValue("UninstallString")
                                            $displayName = [string]$sub.GetValue("DisplayName")
                                            $isWindowsInstaller = (Test-IsRegistryFlagEnabled $sub.GetValue("WindowsInstaller")) -or (Test-IsWindowsInstallerCommand $uString)
                                            $isSystemComponent = Test-IsRegistryFlagEnabled $sub.GetValue("SystemComponent")
                                            $isNoRemove = Test-IsRegistryFlagEnabled $sub.GetValue("NoRemove")
                                            if ($uString -and -not ([string]::IsNullOrWhiteSpace($displayName)) -and -not $isWindowsInstaller -and -not $isSystemComponent -and -not $isNoRemove) {
                                                $clean = Get-UninstallExecutablePath $uString
                                                if ($clean -and -not (Test-IsWhitelisted $clean) -and -not (Test-IsProtectedWindowsPath $clean) -and -not (Test-PathExists $clean)) {
                                                    [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Missing Uninstaller"; Data = $clean; DisplayKey = "$displayName ($($target.Label))"; RegPath = "$($target.RegPrefix)\$subName"; ValueName = $null; Type = "Key"; Details = "Uninstall command points to a missing executable." })
                                                }
                                            }
                                        }
                                        catch {}
                                        finally {
                                            if ($sub) { $sub.Close() }
                                        }
                                    }
                                }
                            }
                            catch {}
                            finally {
                                if ($rk) { $rk.Close() }
                                if ($target.OwnsBaseKey -and $target.BaseKey) { $target.BaseKey.Close() }
                            }
                        }
                        & $EndCategory
                    }

                    # 7. MUI CACHE
                    if ($SelectedScans -contains "MuiCache") {
                        $SyncHash.Status = "Scanning MuiCache..."
                        $key = "Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache"
                        $root = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($key)
                        if ($root) {
                            $names = $root.GetValueNames(); $total = $names.Count; $i = 0
                            foreach ($valName in $names) {
                                $i++; & $Tick "Scanning MuiCache: $valName" $i $total
                                $cleanPath = $valName -replace '\.(FriendlyAppName|ApplicationCompany)$', ''
                                if ($cleanPath -match '^[a-zA-Z]:\\' -and -not (Test-IsWhitelisted $cleanPath)) {
                                    if (-not (Test-PathExists $cleanPath)) { [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Obsolete MuiCache"; Data = $cleanPath; DisplayKey = "MuiCache"; RegPath = "HKCU:\$key"; ValueName = $valName; Type = "Value" }) }
                                }
                            }
                            $root.Close()
                        }
                        & $EndCategory
                    }

                    # 8. APPCOMPAT FLAGS
                    if ($SelectedScans -contains "AppCompat") {
                        $SyncHash.Status = "Scanning Compatibility Store..."
                        $key = "Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store"
                        $root = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($key)
                        if ($root) {
                            $names = $root.GetValueNames(); $total = $names.Count; $i = 0
                            foreach ($valName in $names) {
                                $i++; & $Tick "Scanning AppCompat: $valName" $i $total
                                if ($valName -match '^[a-zA-Z]:\\' -and -not (Test-IsWhitelisted $valName)) {
                                    if (-not (Test-PathExists $valName)) { [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Obsolete Compatibility Ref"; Data = $valName; DisplayKey = "AppCompat"; RegPath = "HKCU:\$key"; ValueName = $valName; Type = "Value" }) }
                                }
                            }
                            $root.Close()
                        }
                        & $EndCategory
                    }

                    # 8B. APPCOMPAT LAYERS
                    if ($SelectedScans -contains "AppCompatLayers") {
                        $SyncHash.Status = "Scanning AppCompat Layers..."
                        $layerTargets = New-Object System.Collections.Generic.List[object]
                        $layerPath = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
                        foreach ($view in @(Get-WmtRegistryViews)) {
                            try {
                                $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
                                [void]$layerTargets.Add([PSCustomObject]@{ BaseKey = $baseKey; SubPath = $layerPath; RegPrefix = (ConvertTo-WmtHklmViewPath -SubPath $layerPath -View $view); Label = "HKLM $(Get-WmtRegistryViewLabel $view) AppCompat Layers"; OwnsBaseKey = $true })
                            }
                            catch {}
                        }
                        foreach ($target in @(New-PerUserRegistryTargets -SubPath "Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers" -HkcuLabel "HKCU\AppCompat Layers")) {
                            [void]$layerTargets.Add([PSCustomObject]@{ BaseKey = $target.BaseKey; SubPath = $target.SubPath; RegPrefix = $target.RegPrefix; Label = $target.Label; OwnsBaseKey = $false })
                        }

                        $total = [math]::Max($layerTargets.Count, 1); $i = 0
                        foreach ($target in $layerTargets) {
                            $i++; & $Tick "Scanning AppCompat Layers: $($target.Label)" $i $total
                            $root = $null
                            try {
                                $root = $target.BaseKey.OpenSubKey($target.SubPath, $false)
                                if ($root) {
                                    foreach ($valName in $root.GetValueNames()) {
                                        if ($valName -match '^(?i)([a-z]:\\|\\\\)' -and -not (Test-IsWhitelisted $valName) -and -not (Test-IsProtectedWindowsPath $valName) -and -not (Test-PathExists $valName)) {
                                            [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                                    Problem    = "Obsolete AppCompat Layer"
                                                    Data       = $valName
                                                    DisplayKey = $target.Label
                                                    RegPath    = $target.RegPrefix
                                                    ValueName  = $valName
                                                    Type       = "Value"
                                                    SafeToFix  = $true
                                                    Risk       = "Low"
                                                    Confidence = "High"
                                                    Details    = "Compatibility layer value points to a missing executable. Cleanup deletes only this value."
                                                })
                                        }
                                    }
                                }
                            }
                            catch {}
                            finally {
                                if ($root) { $root.Close() }
                                if ($target.OwnsBaseKey -and $target.BaseKey) { $target.BaseKey.Close() }
                            }
                        }
                        & $EndCategory
                    }

                    # 8C. USER MRU CACHES
                    if ($SelectedScans -contains "UserMru") {
                        $SyncHash.Status = "Scanning User MRU Caches..."
                        $mruDefinitions = @(
                            [PSCustomObject]@{ SubPath = "Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs"; Label = "Recent documents"; Risk = "Low" },
                            [PSCustomObject]@{ SubPath = "Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSavePidlMRU"; Label = "Open/save dialog history"; Risk = "Low" },
                            [PSCustomObject]@{ SubPath = "Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRU"; Label = "Last visited dialog history"; Risk = "Low" },
                            [PSCustomObject]@{ SubPath = "Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2"; Label = "Mounted device/network location cache"; Risk = "Medium" }
                        )

                        $total = [math]::Max($mruDefinitions.Count, 1); $i = 0
                        foreach ($definition in $mruDefinitions) {
                            $i++; & $Tick "Scanning MRU cache: $($definition.Label)" $i $total
                            foreach ($target in @(New-PerUserRegistryTargets -SubPath $definition.SubPath -HkcuLabel "HKCU\$($definition.Label)")) {
                                $root = $null
                                try {
                                    $root = $target.BaseKey.OpenSubKey($target.SubPath, $false)
                                    if ($root -and ($root.SubKeyCount -gt 0 -or $root.ValueCount -gt 0)) {
                                        [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                                Problem    = "User MRU Cache"
                                                Data       = $definition.Label
                                                DisplayKey = $target.Label
                                                RegPath    = $target.RegPrefix
                                                ValueName  = $null
                                                Type       = "Key"
                                                SafeToFix  = $false
                                                Risk       = $definition.Risk
                                                Confidence = "High"
                                                Details    = "Per-user history/cache key. Windows recreates it as needed; cleanup removes stored MRU entries under this key."
                                            })
                                    }
                                }
                                catch {}
                                finally {
                                    if ($root) { $root.Close() }
                                }
                            }
                        }
                        & $EndCategory
                    }

                    # 9. NOTIFICATION AREA ICONS
                    if ($SelectedScans -contains "NotifyIcons") {
                        $SyncHash.Status = "Scanning Notification Area Icons..."
                        $notifyTargets = @(New-PerUserRegistryTargets -SubPath "Control Panel\NotifyIconSettings" -HkcuLabel "HKCU\Control Panel\NotifyIconSettings")

                        $total = [math]::Max($notifyTargets.Count, 1); $i = 0
                        foreach ($target in $notifyTargets) {
                            $i++; & $Tick "Scanning Notify Icons: $($target.Label)" $i $total
                            try {
                                $root = $target.BaseKey.OpenSubKey($target.SubPath)
                                if ($root) {
                                    foreach ($entry in $root.GetSubKeyNames()) {
                                        try {
                                            $sub = $root.OpenSubKey($entry)
                                            if ($sub) {
                                                $exePath = [string]$sub.GetValue("ExecutablePath")
                                                if (-not [string]::IsNullOrWhiteSpace($exePath)) {
                                                    $clean = Get-ServiceImageExecutablePath $exePath
                                                    if ($clean -and -not (Test-IsWhitelisted $clean) -and -not (Test-IsProtectedWindowsPath $clean) -and -not (Test-PathExists $clean)) {
                                                        [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Obsolete Notify Icon"; Data = $clean; DisplayKey = "$($target.Label)\$entry"; RegPath = "$($target.RegPrefix)\$entry"; ValueName = $null; Type = "Key" })
                                                    }
                                                }
                                                $sub.Close()
                                            }
                                        }
                                        catch {}
                                    }
                                    $root.Close()
                                }
                            }
                            catch {}
                        }
                        & $EndCategory
                    }

                    # 10. APP MODULE CACHES
                    if ($SelectedScans -contains "AppModules") {
                        $SyncHash.Status = "Scanning App Module Caches..."
                        $softwareTargets = @(New-PerUserRegistryTargets -SubPath "Software" -HkcuLabel "HKCU\Software")

                        $total = [math]::Max($softwareTargets.Count, 1); $i = 0
                        foreach ($target in $softwareTargets) {
                            $i++; & $Tick "Scanning App Modules: $($target.Label)" $i $total
                            try {
                                $softwareRoot = $target.BaseKey.OpenSubKey($target.SubPath)
                                if ($softwareRoot) {
                                    foreach ($appName in $softwareRoot.GetSubKeyNames()) {
                                        if (Test-IsUserSoftwareKeyExcluded $appName) { continue }

                                        try {
                                            $appKey = $softwareRoot.OpenSubKey($appName)
                                            if (-not $appKey) { continue }

                                            $modulesKey = $appKey.OpenSubKey("Modules")
                                            if ($modulesKey) {
                                                $modulePaths = New-Object System.Collections.Generic.List[string]
                                                $hasValidPath = $false

                                                foreach ($moduleName in $modulesKey.GetSubKeyNames()) {
                                                    try {
                                                        $moduleKey = $modulesKey.OpenSubKey($moduleName)
                                                        if ($moduleKey) {
                                                            foreach ($valueName in @("path_x64", "path_x86")) {
                                                                $modulePath = [string]$moduleKey.GetValue($valueName)
                                                                if (-not [string]::IsNullOrWhiteSpace($modulePath)) {
                                                                    [void]$modulePaths.Add($modulePath)
                                                                    if (Test-PathExists $modulePath) { $hasValidPath = $true }
                                                                }
                                                            }
                                                            $moduleKey.Close()
                                                        }
                                                    }
                                                    catch {}
                                                }

                                                if ($modulePaths.Count -gt 0 -and -not $hasValidPath) {
                                                    $data = $modulePaths[0]
                                                    if ($modulePaths.Count -gt 1) { $data = "$data ($($modulePaths.Count) missing module paths)" }
                                                    $details = "All populated module path_x64/path_x86 values under $($target.RegPrefix)\$appName\Modules are missing. Cleanup target is the app root key."
                                                    [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Obsolete App Module Cache"; Data = $data; DisplayKey = "$appName (Modules cache)"; RegPath = "$($target.RegPrefix)\$appName"; ValueName = $null; Type = "Key"; Details = $details })
                                                }

                                                $modulesKey.Close()
                                            }

                                            $appKey.Close()
                                        }
                                        catch {}
                                    }
                                    $softwareRoot.Close()
                                }
                            }
                            catch {}
                        }
                        & $EndCategory
                    }

                    # 11. EMPTY USER SOFTWARE KEYS
                    if ($SelectedScans -contains "EmptyUserSoftware") {
                        $SyncHash.Status = "Scanning User Software Keys..."
                        $softwareTargets = @(New-PerUserRegistryTargets -SubPath "Software" -HkcuLabel "HKCU\Software")

                        $total = [math]::Max($softwareTargets.Count, 1); $i = 0
                        foreach ($target in $softwareTargets) {
                            $i++; & $Tick "Scanning User Software: $($target.Label)" $i $total
                            try {
                                $softwareRoot = $target.BaseKey.OpenSubKey($target.SubPath)
                                if ($softwareRoot) {
                                    foreach ($appName in $softwareRoot.GetSubKeyNames()) {
                                        if (Test-IsUserSoftwareKeyExcluded $appName) { continue }

                                        $appKey = $null
                                        try {
                                            $appKey = $softwareRoot.OpenSubKey($appName)
                                            if (-not $appKey) { continue }

                                            if ($appKey.SubKeyCount -eq 0 -and $appKey.ValueCount -eq 0) {
                                                $details = "Direct child of $($target.RegPrefix) has no values and no subkeys."
                                                [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Empty User Software Key"; Data = "(empty registry key)"; DisplayKey = "$appName (empty user software key)"; RegPath = "$($target.RegPrefix)\$appName"; ValueName = $null; Type = "Key"; Details = $details })
                                                continue
                                            }
                                        }
                                        catch {}
                                        finally {
                                            if ($appKey) { $appKey.Close() }
                                        }
                                    }
                                    $softwareRoot.Close()
                                }
                            }
                            catch {}
                        }
                        & $EndCategory
                    }

                    # 12. SHELL EXTENSIONS
                    if ($SelectedScans -contains "ShellExtensions") {
                        $SyncHash.Status = "Scanning Shell Extensions..."
                        $handlerRoots = @(
                            "*\shellex\ContextMenuHandlers",
                            "*\shellex\PropertySheetHandlers",
                            "AllFilesystemObjects\shellex\ContextMenuHandlers",
                            "Directory\shellex\ContextMenuHandlers",
                            "Directory\Background\shellex\ContextMenuHandlers",
                            "Directory\shellex\CopyHookHandlers",
                            "Directory\shellex\DragDropHandlers",
                            "Drive\shellex\ContextMenuHandlers",
                            "Drive\shellex\DragDropHandlers",
                            "Folder\shellex\ColumnHandlers",
                            "Folder\shellex\ContextMenuHandlers",
                            "Folder\shellex\PropertySheetHandlers",
                            "LibraryFolder\shellex\ContextMenuHandlers",
                            "lnkfile\shellex\ContextMenuHandlers",
                            "exefile\shellex\ContextMenuHandlers"
                        )

                        foreach ($view in @([Microsoft.Win32.RegistryView]::Default)) {
                            $classesRoot = $null
                            try {
                                $classesRoot = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::ClassesRoot, $view)
                                $viewLabel = Get-WmtRegistryViewLabel $view
                                $total = $handlerRoots.Count; $i = 0
                                foreach ($handlerRootPath in $handlerRoots) {
                                    $i++; & $Tick "Scanning Shell Extensions ($viewLabel): $handlerRootPath" $i $total
                                    $handlerRoot = $null
                                    try {
                                        $handlerRoot = $classesRoot.OpenSubKey($handlerRootPath, $false)
                                        if ($handlerRoot) {
                                            foreach ($handlerName in $handlerRoot.GetSubKeyNames()) {
                                                $handlerKey = $null
                                                try {
                                                    $handlerKey = $handlerRoot.OpenSubKey($handlerName, $false)
                                                    if (-not $handlerKey) { continue }

                                                    $clsid = ConvertTo-WmtClsid ([string]$handlerKey.GetValue($null))
                                                    if (-not $clsid) { $clsid = ConvertTo-WmtClsid $handlerName }
                                                    if (-not $clsid) { continue }

                                                    $issue = Get-WmtClsidReferenceIssue -Clsid $clsid -View $view
                                                    if ($issue -and $issue.IsBroken) {
                                                        [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                                                Problem    = "Invalid Shell Extension"
                                                                Data       = $issue.Data
                                                                DisplayKey = "$handlerRootPath\$handlerName ($viewLabel)"
                                                                RegPath    = (ConvertTo-WmtClassesViewPath -SubPath "$handlerRootPath\$handlerName" -View $view)
                                                                ValueName  = $null
                                                                Type       = "Key"
                                                                Details    = $issue.Details
                                                            })
                                                    }
                                                }
                                                catch {}
                                                finally {
                                                    if ($handlerKey) { $handlerKey.Close() }
                                                }
                                            }
                                        }
                                    }
                                    catch {}
                                    finally {
                                        if ($handlerRoot) { $handlerRoot.Close() }
                                    }
                                }

                                foreach ($directHandlerPath in @("exefile\shellex\IconHandler", "lnkfile\shellex\IconHandler")) {
                                    $handlerKey = $null
                                    try {
                                        $handlerKey = $classesRoot.OpenSubKey($directHandlerPath, $false)
                                        if ($handlerKey) {
                                            $clsid = ConvertTo-WmtClsid ([string]$handlerKey.GetValue($null))
                                            $issue = Get-WmtClsidReferenceIssue -Clsid $clsid -View $view
                                            if ($issue -and $issue.IsBroken) {
                                                [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                                        Problem    = "Invalid Shell Extension"
                                                        Data       = $issue.Data
                                                        DisplayKey = "$directHandlerPath ($viewLabel)"
                                                        RegPath    = (ConvertTo-WmtClassesViewPath -SubPath $directHandlerPath -View $view)
                                                        ValueName  = $null
                                                        Type       = "Key"
                                                        Details    = $issue.Details
                                                    })
                                            }
                                        }
                                    }
                                    catch {}
                                    finally {
                                        if ($handlerKey) { $handlerKey.Close() }
                                    }
                                }
                            }
                            catch {}
                            finally {
                                if ($classesRoot) { $classesRoot.Close() }
                            }
                        }
                        & $EndCategory
                    }

                    # 13. EXPLORER NAMESPACE
                    if ($SelectedScans -contains "ExplorerNamespace") {
                        $SyncHash.Status = "Scanning Explorer Namespace Entries..."
                        $namespaceTargets = New-Object System.Collections.Generic.List[object]
                        foreach ($path in @(
                                "SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace",
                                "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace",
                                "SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace",
                                "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace",
                                "SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel\NameSpace",
                                "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel\NameSpace"
                            )) {
                            [void]$namespaceTargets.Add([PSCustomObject]@{ BaseKey = [Microsoft.Win32.Registry]::LocalMachine; SubPath = $path; RegPrefix = "HKLM:\$path"; Label = "HKLM:\$path" })
                        }
                        foreach ($userPath in @(
                                "Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace",
                                "Software\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace",
                                "Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel\NameSpace"
                            )) {
                            foreach ($target in @(New-PerUserRegistryTargets -SubPath $userPath -HkcuLabel "HKCU\$userPath")) {
                                [void]$namespaceTargets.Add($target)
                            }
                        }

                        $total = [math]::Max($namespaceTargets.Count, 1); $i = 0
                        foreach ($target in $namespaceTargets) {
                            $i++; & $Tick "Scanning Namespace: $($target.Label)" $i $total
                            $root = $null
                            try {
                                $root = $target.BaseKey.OpenSubKey($target.SubPath, $false)
                                if ($root) {
                                    foreach ($entry in $root.GetSubKeyNames()) {
                                        $clsid = ConvertTo-WmtClsid $entry
                                        if ($clsid -and -not (Test-WmtClsidExistsForTarget -Clsid $clsid -Target $target)) {
                                            [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                                    Problem    = "Invalid Explorer Namespace"
                                                    Data       = $clsid
                                                    DisplayKey = "$($target.Label)\$entry"
                                                    RegPath    = "$($target.RegPrefix)\$entry"
                                                    ValueName  = $null
                                                    Type       = "Key"
                                                    Details    = "Explorer namespace entry references missing CLSID $clsid."
                                                })
                                        }
                                    }
                                }
                            }
                            catch {}
                            finally {
                                if ($root) { $root.Close() }
                            }
                        }
                        & $EndCategory
                    }
                    # 14. FONT ENTRIES
                    if ($SelectedScans -contains "Fonts") {
                        $SyncHash.Status = "Scanning Font Registry Entries..."
                        $fontTargets = New-Object System.Collections.Generic.List[object]
                        [void]$fontTargets.Add([PSCustomObject]@{ BaseKey = [Microsoft.Win32.Registry]::LocalMachine; SubPath = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"; RegPrefix = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"; Label = "Machine Fonts" })
                        foreach ($target in @(New-PerUserRegistryTargets -SubPath "Software\Microsoft\Windows NT\CurrentVersion\Fonts" -HkcuLabel "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts")) {
                            [void]$fontTargets.Add($target)
                        }

                        $fontDir = Join-Path $env:windir "Fonts"
                        $total = [math]::Max($fontTargets.Count, 1); $i = 0
                        foreach ($target in $fontTargets) {
                            $i++; & $Tick "Scanning Fonts: $($target.Label)" $i $total
                            $root = $null
                            try {
                                $root = $target.BaseKey.OpenSubKey($target.SubPath, $false)
                                if ($root) {
                                    foreach ($valueName in $root.GetValueNames()) {
                                        $fontValue = [string]$root.GetValue($valueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                                        if ([string]::IsNullOrWhiteSpace($fontValue)) { continue }

                                        $fontPath = $fontValue.Trim('"')
                                        if ($fontPath -notmatch '^(?i)([a-z]:\\|\\\\|%[^%]+%\\)') {
                                            $fontPath = Join-Path $fontDir $fontPath
                                        }

                                        if (-not (Test-IsProtectedWindowsPath $fontPath) -and -not (Test-PathExists $fontPath)) {
                                            [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                                    Problem    = "Invalid Font Entry"
                                                    Data       = $fontPath
                                                    DisplayKey = $valueName
                                                    RegPath    = $target.RegPrefix
                                                    ValueName  = $valueName
                                                    Type       = "Value"
                                                    Details    = "Font registry value points to a missing font file."
                                                })
                                        }
                                    }
                                }
                            }
                            catch {}
                            finally {
                                if ($root) { $root.Close() }
                            }
                        }
                        & $EndCategory
                    }

                    # 15. APP EXECUTION ALIASES
                    if ($SelectedScans -contains "AppAliases") {
                        $SyncHash.Status = "Scanning App Execution Aliases..."
                        $aliasTargets = @(New-PerUserRegistryTargets -SubPath "Software\Microsoft\Windows\CurrentVersion\App Paths" -HkcuLabel "HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths")

                        $total = [math]::Max($aliasTargets.Count, 1); $i = 0
                        foreach ($target in $aliasTargets) {
                            $i++; & $Tick "Scanning App Aliases: $($target.Label)" $i $total
                            $root = $null
                            try {
                                $root = $target.BaseKey.OpenSubKey($target.SubPath, $false)
                                if ($root) {
                                    foreach ($aliasName in $root.GetSubKeyNames()) {
                                        $aliasKey = $null
                                        try {
                                            $aliasKey = $root.OpenSubKey($aliasName, $false)
                                            if (-not $aliasKey) { continue }

                                            $rawTarget = [string]$aliasKey.GetValue($null)
                                            $targetPath = Get-ServiceImageExecutablePath $rawTarget
                                            if ($targetPath -and -not (Test-IsWhitelisted $targetPath) -and -not (Test-IsProtectedWindowsPath $targetPath) -and -not (Test-PathExists $targetPath)) {
                                                [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                                        Problem    = "Invalid App Execution Alias"
                                                        Data       = $targetPath
                                                        DisplayKey = $aliasName
                                                        RegPath    = "$($target.RegPrefix)\$aliasName"
                                                        ValueName  = $null
                                                        Type       = "Key"
                                                        Details    = "Per-user App Paths alias target is missing."
                                                    })
                                            }
                                        }
                                        catch {}
                                        finally {
                                            if ($aliasKey) { $aliasKey.Close() }
                                        }
                                    }
                                }
                            }
                            catch {}
                            finally {
                                if ($root) { $root.Close() }
                            }
                        }
                        & $EndCategory
                    }

                    # 16. SCHEDULED TASK CACHE
                    if ($SelectedScans -contains "TaskCache") {
                        $SyncHash.Status = "Scanning Scheduled Task Cache..."
                        $treePath = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree"
                        $tasksPath = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks"
                        $treeRoot = $null; $tasksRoot = $null
                        try {
                            $treeRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($treePath, $false)
                            $tasksRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($tasksPath, $false)
                            if ($treeRoot -and $tasksRoot) {
                                $treeEntries = @(Get-WmtTaskTreeEntries -Key $treeRoot -RelativePath "")
                                $treeIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                                foreach ($entry in $treeEntries) {
                                    if (-not [string]::IsNullOrWhiteSpace([string]$entry.Id)) { [void]$treeIds.Add([string]$entry.Id) }
                                }

                                $taskIds = @()
                                $taskIdsSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                                $canEnumerateTaskIds = $false
                                try {
                                    $taskIds = @($tasksRoot.GetSubKeyNames())
                                    foreach ($taskId in $taskIds) { [void]$taskIdsSet.Add($taskId) }
                                    $canEnumerateTaskIds = $true
                                }
                                catch {
                                    $canEnumerateTaskIds = $false
                                }

                                $total = [math]::Max($treeEntries.Count, 1); $i = 0
                                foreach ($entry in $treeEntries) {
                                    $i++; & $Tick "Scanning TaskCache Tree: $($entry.RelativePath)" $i $total
                                    if (Test-WmtProtectedSystemTaskPath $entry.RelativePath) { continue }

                                    $taskFile = Get-WmtTaskFilePath $entry.RelativePath
                                    $taskGuidState = if ($canEnumerateTaskIds) {
                                        if ($taskIdsSet.Contains([string]$entry.Id)) { "Exists" } else { "Missing" }
                                    }
                                    else {
                                        "Unknown"
                                    }
                                    $registeredTaskState = Get-WmtScheduledTaskState $entry.RelativePath
                                    $taskFileState = Get-WmtPathState -Path $taskFile -PathType "Leaf"

                                    if ($taskGuidState -eq "Missing" -and $registeredTaskState -eq "Missing" -and $taskFileState -eq "Missing") {
                                        [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                                Problem    = "Orphaned TaskCache Tree Entry"
                                                Data       = $taskFile
                                                DisplayKey = $entry.RelativePath
                                                RegPath    = "HKLM:\$treePath\$($entry.RelativePath)"
                                                ValueName  = $null
                                                Type       = "Key"
                                                Details    = "TaskCache Tree entry has no matching Tasks GUID key, Task Scheduler cannot find the task, and the task file is definitely missing."
                                            })
                                    }
                                }

                                $total = [math]::Max($taskIds.Count, 1); $i = 0
                                foreach ($taskId in $taskIds) {
                                    $i++; & $Tick "Scanning TaskCache Tasks: $taskId" $i $total
                                    $taskKey = $null
                                    try {
                                        $taskKey = $tasksRoot.OpenSubKey($taskId, $false)
                                        if (-not $taskKey) { continue }

                                        $taskPathValue = [string]$taskKey.GetValue("Path")
                                        if ([string]::IsNullOrWhiteSpace($taskPathValue)) { continue }
                                        if (Test-WmtProtectedSystemTaskPath $taskPathValue) { continue }

                                        $taskFile = Get-WmtTaskFilePath $taskPathValue
                                        $registeredTaskState = Get-WmtScheduledTaskState $taskPathValue
                                        $taskFileState = Get-WmtPathState -Path $taskFile -PathType "Leaf"
                                        $treeGuidState = if ($treeIds.Contains($taskId)) { "Exists" } else { "Missing" }

                                        if ($treeGuidState -eq "Missing" -and $registeredTaskState -eq "Missing" -and $taskFileState -eq "Missing") {
                                            [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                                    Problem    = "Orphaned TaskCache Task Entry"
                                                    Data       = $taskFile
                                                    DisplayKey = $taskPathValue
                                                    RegPath    = "HKLM:\$tasksPath\$taskId"
                                                    ValueName  = $null
                                                    Type       = "Key"
                                                    Details    = "TaskCache Tasks GUID key has no matching Tree entry, Task Scheduler cannot find the task, and the task file is definitely missing."
                                                })
                                        }
                                    }
                                    catch {}
                                    finally {
                                        if ($taskKey) { $taskKey.Close() }
                                    }
                                }
                            }
                        }
                        catch {}
                        finally {
                            if ($treeRoot) { $treeRoot.Close() }
                            if ($tasksRoot) { $tasksRoot.Close() }
                        }
                        & $EndCategory
                    }

                    # 16B. SCHEDULED TASK ACTIONS
                    if ($SelectedScans -contains "TaskActions") {
                        $SyncHash.Status = "Scanning Scheduled Task Actions..."
                        $taskRootPath = Join-Path (Join-Path $env:windir "System32") "Tasks"
                        $taskFiles = [System.Collections.Generic.List[string]]::new()
                        if ([System.IO.Directory]::Exists($taskRootPath)) {
                            $pendingDirs = [System.Collections.Generic.Stack[string]]::new()
                            $pendingDirs.Push($taskRootPath)
                            while ($pendingDirs.Count -gt 0) {
                                $dir = $pendingDirs.Pop()
                                try {
                                    foreach ($file in [System.IO.Directory]::EnumerateFiles($dir, "*", [System.IO.SearchOption]::TopDirectoryOnly)) {
                                        [void]$taskFiles.Add($file)
                                    }
                                }
                                catch {}
                                try {
                                    foreach ($childDir in [System.IO.Directory]::EnumerateDirectories($dir, "*", [System.IO.SearchOption]::TopDirectoryOnly)) {
                                        [void]$pendingDirs.Push($childDir)
                                    }
                                }
                                catch {}
                            }
                        }

                        $total = [math]::Max($taskFiles.Count, 1); $i = 0
                        foreach ($taskFile in $taskFiles) {
                            $i++; & $Tick "Scanning Task Action: $taskFile" $i $total
                            $relativeTask = $taskFile.Substring($taskRootPath.Length).TrimStart('\')
                            if (Test-WmtProtectedSystemTaskPath $relativeTask) { continue }

                            try {
                                [xml]$taskXml = Get-Content -LiteralPath $taskFile -Raw -ErrorAction Stop
                                $execNodes = $taskXml.SelectNodes("//*[local-name()='Exec']")
                                foreach ($execNode in $execNodes) {
                                    $commandNode = $execNode.SelectSingleNode("*[local-name()='Command']")
                                    if (-not $commandNode) { continue }

                                    $command = [string]$commandNode.InnerText
                                    $commandPath = Get-ServiceImageExecutablePath $command
                                    if ([string]::IsNullOrWhiteSpace($commandPath)) { continue }
                                    if (Test-IsWhitelisted $commandPath) { continue }
                                    if (Test-IsProtectedWindowsPath $commandPath) { continue }
                                    if (Test-PathExists $commandPath) { continue }

                                    $argumentNode = $execNode.SelectSingleNode("*[local-name()='Arguments']")
                                    $argumentText = if ($argumentNode) { [string]$argumentNode.InnerText } else { "" }
                                    [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                            Problem    = "Broken Scheduled Task Action"
                                            Data       = $commandPath
                                            DisplayKey = "\$relativeTask"
                                            RegPath    = $taskFile
                                            ValueName  = $null
                                            Type       = "ReviewOnly"
                                            SafeToFix  = $false
                                            Risk       = "Review"
                                            Confidence = "High"
                                            Details    = "Scheduled task Exec action points to a missing command. Command: $command Arguments: $argumentText. Review or edit the task in Task Scheduler."
                                        })
                                }
                            }
                            catch {}
                        }
                        & $EndCategory
                    }

                    # 17. UNINSTALL METADATA VALUES
                    if ($SelectedScans -contains "UninstallMetadata") {
                        $SyncHash.Status = "Scanning Uninstall Metadata..."
                        $uninstallTargets = New-Object System.Collections.Generic.List[object]
                        $uninstallPath = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
                        foreach ($view in @(Get-WmtRegistryViews)) {
                            try {
                                $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
                                [void]$uninstallTargets.Add([PSCustomObject]@{ BaseKey = $baseKey; SubPath = $uninstallPath; RegPrefix = (ConvertTo-WmtHklmViewPath -SubPath $uninstallPath -View $view); Label = "HKLM $(Get-WmtRegistryViewLabel $view)"; OwnsBaseKey = $true })
                            }
                            catch {}
                        }
                        foreach ($target in @(New-PerUserRegistryTargets -SubPath "Software\Microsoft\Windows\CurrentVersion\Uninstall" -HkcuLabel "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall")) {
                            [void]$uninstallTargets.Add([PSCustomObject]@{ BaseKey = $target.BaseKey; SubPath = $target.SubPath; RegPrefix = $target.RegPrefix; Label = $target.Label; OwnsBaseKey = $false })
                        }

                        $metadataValues = @("DisplayIcon", "InstallLocation", "InstallSource", "ModifyPath", "QuietUninstallString", "Readme", "HelpLink", "URLInfoAbout")
                        $total = [math]::Max($uninstallTargets.Count, 1); $i = 0
                        foreach ($target in $uninstallTargets) {
                            $i++; & $Tick "Scanning Uninstall Metadata: $($target.Label)" $i $total
                            $root = $null
                            try {
                                $root = $target.BaseKey.OpenSubKey($target.SubPath, $false)
                                if ($root) {
                                    foreach ($appKeyName in $root.GetSubKeyNames()) {
                                        $appKey = $null
                                        try {
                                            $appKey = $root.OpenSubKey($appKeyName, $false)
                                            if (-not $appKey) { continue }

                                            $displayName = [string]$appKey.GetValue("DisplayName")
                                            if ([string]::IsNullOrWhiteSpace($displayName)) { $displayName = $appKeyName }

                                            foreach ($valueName in $metadataValues) {
                                                $rawValue = [string]$appKey.GetValue($valueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                                                if ([string]::IsNullOrWhiteSpace($rawValue)) { continue }
                                                if ($rawValue -match '^(?i)(https?|mailto):') { continue }

                                                $candidate = if ($valueName -eq "ModifyPath" -or $valueName -eq "QuietUninstallString") { Get-ServiceImageExecutablePath $rawValue } elseif ($valueName -eq "DisplayIcon") { Get-RealExePath $rawValue } else { [Environment]::ExpandEnvironmentVariables($rawValue.Trim('"')) }
                                                if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
                                                if ($candidate -notmatch '^(?i)([a-z]:\\|\\\\)') { continue }
                                                if (Test-IsWhitelisted $candidate) { continue }
                                                if (Test-IsProtectedWindowsPath $candidate) { continue }
                                                if (Test-PathExists $candidate) { continue }

                                                $isCommandMetadata = ($valueName -eq "ModifyPath" -or $valueName -eq "QuietUninstallString")

                                                [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                                        Problem    = "Invalid Uninstall Metadata"
                                                        Data       = $candidate
                                                        DisplayKey = "$displayName [$valueName]"
                                                        RegPath    = "$($target.RegPrefix)\$appKeyName"
                                                        ValueName  = $valueName
                                                        Type       = "Value"
                                                        SafeToFix  = (-not $isCommandMetadata)
                                                        Risk       = if ($isCommandMetadata) { "Review" } else { "Low" }
                                                        Confidence = "High"
                                                        Details    = if ($isCommandMetadata) { "Uninstall command metadata points to a missing executable. Review before deleting because the app may still be installed." } else { "Uninstall metadata value points to a missing local path. Cleanup deletes only this value, not the uninstall key." }
                                                    })
                                            }
                                        }
                                        catch {}
                                        finally {
                                            if ($appKey) { $appKey.Close() }
                                        }
                                    }
                                }
                            }
                            catch {}
                            finally {
                                if ($root) { $root.Close() }
                                if ($target.OwnsBaseKey -and $target.BaseKey) { $target.BaseKey.Close() }
                            }
                        }
                        & $EndCategory
                    }

                    # 18. ENVIRONMENT PATH ENTRIES
                    if ($SelectedScans -contains "EnvPath") {
                        $SyncHash.Status = "Scanning Environment PATH Entries..."
                        $envTargets = New-Object System.Collections.Generic.List[object]
                        [void]$envTargets.Add([PSCustomObject]@{ BaseKey = [Microsoft.Win32.Registry]::LocalMachine; SubPath = "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; RegPrefix = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; Label = "Machine PATH" })
                        foreach ($target in @(New-PerUserRegistryTargets -SubPath "Environment" -HkcuLabel "HKCU\Environment")) {
                            [void]$envTargets.Add([PSCustomObject]@{ BaseKey = $target.BaseKey; SubPath = $target.SubPath; RegPrefix = $target.RegPrefix; Label = "$($target.Label) PATH" })
                        }

                        $total = [math]::Max($envTargets.Count, 1); $i = 0
                        foreach ($target in $envTargets) {
                            $i++; & $Tick "Scanning PATH: $($target.Label)" $i $total
                            $root = $null
                            try {
                                $root = $target.BaseKey.OpenSubKey($target.SubPath, $false)
                                if ($root) {
                                    $pathValue = [string]$root.GetValue("Path", $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                                    $missingSegments = @(Get-WmtMissingPathSegments $pathValue)
                                    if ($missingSegments.Count -gt 0) {
                                        $newPath = Get-WmtCleanedPathValue -PathValue $pathValue -MissingSegments $missingSegments
                                        $data = $missingSegments[0]
                                        if ($missingSegments.Count -gt 1) { $data = "$data ($($missingSegments.Count) missing PATH entries)" }
                                        [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                                Problem    = "Invalid PATH Entry"
                                                Data       = $data
                                                DisplayKey = $target.Label
                                                RegPath    = $target.RegPrefix
                                                ValueName  = "Path"
                                                Type       = "SetValue"
                                                NewData    = $newPath
                                                Details    = "Rewrites PATH after removing missing segment(s): $($missingSegments -join '; ')"
                                            })
                                    }
                                }
                            }
                            catch {}
                            finally {
                                if ($root) { $root.Close() }
                            }
                        }
                        & $EndCategory
                    }

                    # 19. PER-USER SHELL COMMANDS
                    if ($SelectedScans -contains "UserShellCommands") {
                        $SyncHash.Status = "Scanning Per-User Shell Commands..."
                        $classTargets = @(New-PerUserRegistryTargets -SubPath "Software\Classes" -HkcuLabel "HKCU\Software\Classes")

                        $total = [math]::Max($classTargets.Count, 1); $i = 0
                        foreach ($target in $classTargets) {
                            $i++; & $Tick "Scanning User Shell Commands: $($target.Label)" $i $total
                            $root = $null
                            try {
                                $root = $target.BaseKey.OpenSubKey($target.SubPath, $false)
                                if ($root) {
                                    foreach ($className in $root.GetSubKeyNames()) {
                                        $classKey = $null
                                        try {
                                            $classKey = $root.OpenSubKey($className, $false)
                                            if (-not $classKey) { continue }

                                            $shellKey = $classKey.OpenSubKey("shell", $false)
                                            if ($shellKey) {
                                                foreach ($verb in $shellKey.GetSubKeyNames()) {
                                                    $cmdKey = $null
                                                    try {
                                                        $cmdKey = $shellKey.OpenSubKey("$verb\command", $false)
                                                        if (-not $cmdKey) { continue }

                                                        $cmd = [string]$cmdKey.GetValue($null)
                                                        $clean = Get-ServiceImageExecutablePath $cmd
                                                        if ($clean -and -not (Test-IsWhitelisted $clean) -and -not (Test-IsProtectedWindowsPath $clean) -and -not (Test-PathExists $clean)) {
                                                            [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                                                    Problem    = "Invalid User Shell Command"
                                                                    Data       = $clean
                                                                    DisplayKey = "$className\$verb"
                                                                    RegPath    = "$($target.RegPrefix)\$className\shell\$verb\command"
                                                                    ValueName  = $null
                                                                    Type       = "Key"
                                                                    Details    = "Per-user file association command points to a missing executable."
                                                                })
                                                        }
                                                    }
                                                    catch {}
                                                    finally {
                                                        if ($cmdKey) { $cmdKey.Close() }
                                                    }
                                                }
                                                $shellKey.Close()
                                            }
                                        }
                                        catch {}
                                        finally {
                                            if ($classKey) { $classKey.Close() }
                                        }
                                    }
                                }
                            }
                            catch {}
                            finally {
                                if ($root) { $root.Close() }
                            }
                        }
                        & $EndCategory
                    }

                    # 19B. IMAGE FILE EXECUTION OPTIONS
                    if ($SelectedScans -contains "IFEO") {
                        $SyncHash.Status = "Scanning Image File Execution Options..."
                        $ifeoPath = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
                        $silentPath = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\SilentProcessExit"

                        foreach ($view in @(Get-WmtRegistryViews)) {
                            $baseKey = $null; $ifeoRoot = $null; $silentRoot = $null
                            try {
                                $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
                                $viewLabel = Get-WmtRegistryViewLabel $view

                                $ifeoRoot = $baseKey.OpenSubKey($ifeoPath, $false)
                                if ($ifeoRoot) {
                                    $names = $ifeoRoot.GetSubKeyNames(); $total = [math]::Max($names.Count, 1); $i = 0
                                    foreach ($imageName in $names) {
                                        $i++; & $Tick "Scanning IFEO ($viewLabel): $imageName" $i $total
                                        $imageKey = $null
                                        try {
                                            $imageKey = $ifeoRoot.OpenSubKey($imageName, $false)
                                            if (-not $imageKey) { continue }

                                            $debugger = [string]$imageKey.GetValue("Debugger", $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                                            $debuggerPath = Get-ServiceImageExecutablePath $debugger
                                            if ($debuggerPath -and -not (Test-IsWhitelisted $debuggerPath) -and -not (Test-IsProtectedWindowsPath $debuggerPath) -and -not (Test-PathExists $debuggerPath)) {
                                                [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                                        Problem    = "Invalid IFEO Debugger"
                                                        Data       = $debuggerPath
                                                        DisplayKey = "$imageName ($viewLabel)"
                                                        RegPath    = "$(ConvertTo-WmtHklmViewPath -SubPath $ifeoPath -View $view)\$imageName"
                                                        ValueName  = "Debugger"
                                                        Type       = "Value"
                                                        SafeToFix  = $false
                                                        Risk       = "Review"
                                                        Confidence = "Medium"
                                                        Details    = "Image File Execution Options Debugger points to a missing executable. Review before deleting because IFEO can be intentionally configured."
                                                    })
                                            }

                                            $verifierDlls = [string]$imageKey.GetValue("VerifierDlls", $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                                            foreach ($dllPath in @($verifierDlls -split ';')) {
                                                $candidate = Get-RealExePath $dllPath
                                                if ($candidate -and $candidate -match '^(?i)([a-z]:\\|\\\\)' -and -not (Test-IsWhitelisted $candidate) -and -not (Test-IsProtectedWindowsPath $candidate) -and -not (Test-PathExists $candidate)) {
                                                    [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                                            Problem    = "Invalid IFEO Verifier DLL"
                                                            Data       = $candidate
                                                            DisplayKey = "$imageName ($viewLabel)"
                                                            RegPath    = "$(ConvertTo-WmtHklmViewPath -SubPath $ifeoPath -View $view)\$imageName"
                                                            ValueName  = "VerifierDlls"
                                                            Type       = "Value"
                                                            SafeToFix  = $false
                                                            Risk       = "Review"
                                                            Confidence = "Medium"
                                                            Details    = "IFEO VerifierDlls references a missing DLL. Review before deleting because verifier settings can be intentional."
                                                        })
                                                }
                                            }
                                        }
                                        catch {}
                                        finally {
                                            if ($imageKey) { $imageKey.Close() }
                                        }
                                    }
                                }

                                $silentRoot = $baseKey.OpenSubKey($silentPath, $false)
                                if ($silentRoot) {
                                    $names = $silentRoot.GetSubKeyNames(); $total = [math]::Max($names.Count, 1); $i = 0
                                    foreach ($imageName in $names) {
                                        $i++; & $Tick "Scanning SilentProcessExit ($viewLabel): $imageName" $i $total
                                        $imageKey = $null
                                        try {
                                            $imageKey = $silentRoot.OpenSubKey($imageName, $false)
                                            if (-not $imageKey) { continue }

                                            $monitor = [string]$imageKey.GetValue("MonitorProcess", $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                                            $monitorPath = Get-ServiceImageExecutablePath $monitor
                                            if ($monitorPath -and -not (Test-IsWhitelisted $monitorPath) -and -not (Test-IsProtectedWindowsPath $monitorPath) -and -not (Test-PathExists $monitorPath)) {
                                                [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                                        Problem    = "Invalid SilentProcessExit Monitor"
                                                        Data       = $monitorPath
                                                        DisplayKey = "$imageName ($viewLabel)"
                                                        RegPath    = "$(ConvertTo-WmtHklmViewPath -SubPath $silentPath -View $view)\$imageName"
                                                        ValueName  = "MonitorProcess"
                                                        Type       = "Value"
                                                        SafeToFix  = $false
                                                        Risk       = "Review"
                                                        Confidence = "Medium"
                                                        Details    = "SilentProcessExit monitor points to a missing executable. Review before deleting because process-monitor settings can be intentional."
                                                    })
                                            }
                                        }
                                        catch {}
                                        finally {
                                            if ($imageKey) { $imageKey.Close() }
                                        }
                                    }
                                }
                            }
                            catch {}
                            finally {
                                if ($ifeoRoot) { $ifeoRoot.Close() }
                                if ($silentRoot) { $silentRoot.Close() }
                                if ($baseKey) { $baseKey.Close() }
                            }
                        }
                        & $EndCategory
                    }

                    # 20. FIREWALL
                    if ($SelectedScans -contains "Firewall") {
                        $SyncHash.Status = "Scanning Firewall Rules..."
                        $key = "SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules"
                        $root = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($key)
                        if ($root) {
                            $names = $root.GetValueNames(); $total = $names.Count; $i = 0
                            foreach ($valName in $names) {
                                $i++; & $Tick "Scanning Firewall: $valName" $i $total
                                $data = $root.GetValue($valName)
                                if ($data -match "App=([^|]+)") {
                                    $appPath = $matches[1]; $expanded = [Environment]::ExpandEnvironmentVariables($appPath)
                                    if ($expanded -match '^[a-zA-Z]:\\' -and -not (Test-IsWhitelisted $expanded)) {
                                        if (-not (Test-IsProtectedWindowsPath $expanded) -and -not (Test-PathExists $expanded)) { [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Invalid Firewall Rule"; Data = $expanded; DisplayKey = $valName; RegPath = "HKLM:\$key"; ValueName = $valName; Type = "Value" }) }
                                    }
                                }
                            }
                            $root.Close()
                        }
                        & $EndCategory
                    }

                    # 13. SERVICES
                    if ($SelectedScans -contains "Services") {
                        $SyncHash.Status = "Scanning Services..."
                        $serviceRoots = New-Object System.Collections.Generic.List[string]
                        try {
                            $systemRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM")
                            if ($systemRoot) {
                                foreach ($controlSet in $systemRoot.GetSubKeyNames()) {
                                    if ($controlSet -match '^ControlSet\d{3}$') {
                                        [void]$serviceRoots.Add("SYSTEM\$controlSet\Services")
                                    }
                                }
                                $systemRoot.Close()
                            }
                        }
                        catch {}
                        if ($serviceRoots.Count -eq 0) { [void]$serviceRoots.Add("SYSTEM\CurrentControlSet\Services") }

                        foreach ($key in $serviceRoots) {
                            $root = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($key)
                            if ($root) {
                                $names = $root.GetSubKeyNames(); $total = $names.Count; $i = 0
                                foreach ($svc in $names) {
                                    $i++; & $Tick "Scanning Service: $svc" $i $total
                                    try {
                                        $sub = $root.OpenSubKey($svc)
                                        $img = [string]$sub.GetValue("ImagePath")
                                        if ($img -and $img -notmatch "\\drivers\\") {
                                            $clean = Get-ServiceImageExecutablePath $img
                                            if ($clean -and -not (Test-IsWhitelisted $clean) -and -not (Test-IsProtectedWindowsPath $clean) -and -not (Test-PathExists $clean)) {
                                                [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Orphaned Service"; Data = $clean; DisplayKey = "$key\$svc"; RegPath = "HKLM:\$key\$svc"; ValueName = $null; Type = "Key" })
                                            }
                                        }
                                        $sub.Close()
                                    }
                                    catch {}
                                }
                                $root.Close()
                            }
                        }
                        & $EndCategory
                    }

                    # 12. TYPE LIBRARIES
                    if ($SelectedScans -contains "TypeLib") {
                        $SyncHash.Status = "Scanning Type Libraries..."
                        foreach ($view in @(Get-WmtRegistryViews)) {
                            $root = $null; $tlKey = $null
                            try {
                                $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::ClassesRoot, $view)
                                $tlKey = $root.OpenSubKey("TypeLib", $false)
                                if ($tlKey) {
                                    $viewLabel = Get-WmtRegistryViewLabel $view
                                    $names = @($tlKey.GetSubKeyNames()); $total = [math]::Max($names.Count, 1); $i = 0
                                    foreach ($guid in $names) {
                                        $i++; & $Tick "Scanning TypeLib ($viewLabel): $guid" $i $total
                                        try {
                                            $verKey = $tlKey.OpenSubKey($guid)
                                            if ($verKey) {
                                                foreach ($ver in @($verKey.GetSubKeyNames())) {
                                                    $numKey = $null
                                                    try {
                                                        $numKey = $verKey.OpenSubKey($ver)
                                                        if (-not $numKey) { continue }

                                                        $helpDirValue = $numKey.GetValue("HELPDIR", $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                                                        $missingHelpDir = Get-WmtMissingRegistryPathTarget -RawValue $helpDirValue -RegistryView $view
                                                        if ($missingHelpDir) {
                                                            [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Missing HelpDir"; Data = $missingHelpDir; DisplayKey = "$guid\$ver ($viewLabel)"; RegPath = (ConvertTo-WmtClassesViewPath -SubPath "TypeLib\$guid\$ver" -View $view); ValueName = "HELPDIR"; Type = "Value"; Details = "Type library HELPDIR value points to a missing path in the $viewLabel registry view." })
                                                        }

                                                        $helpKey = $null
                                                        try {
                                                            $helpKey = $numKey.OpenSubKey("HELPDIR", $false)
                                                            if ($helpKey) {
                                                                $helpDir = $helpKey.GetValue($null, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                                                                $missingHelpDir = Get-WmtMissingRegistryPathTarget -RawValue $helpDir -RegistryView $view
                                                                if ($missingHelpDir) {
                                                                    [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Missing HelpDir"; Data = $missingHelpDir; DisplayKey = "$guid\$ver\HELPDIR ($viewLabel)"; RegPath = (ConvertTo-WmtClassesViewPath -SubPath "TypeLib\$guid\$ver\HELPDIR" -View $view); ValueName = $null; Type = "Key"; Details = "Type library HELPDIR default path points to a missing path in the $viewLabel registry view." })
                                                                }
                                                            }
                                                        }
                                                        catch {}
                                                        finally {
                                                            if ($helpKey) { $helpKey.Close() }
                                                        }

                                                        foreach ($locale in @($numKey.GetSubKeyNames())) {
                                                            if ($locale -ieq "HELPDIR") { continue }

                                                            $localeKey = $null
                                                            try {
                                                                $localeKey = $numKey.OpenSubKey($locale, $false)
                                                                if (-not $localeKey) { continue }

                                                                foreach ($platform in @($localeKey.GetSubKeyNames())) {
                                                                    if ($platform -notmatch '^(?i)win') { continue }

                                                                    $platformKey = $null
                                                                    try {
                                                                        $platformKey = $localeKey.OpenSubKey($platform, $false)
                                                                        if (-not $platformKey) { continue }

                                                                        $typeLibPath = $platformKey.GetValue($null, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                                                                        $missingTypeLibPath = Get-WmtMissingRegistryPathTarget -RawValue $typeLibPath -RegistryView $view
                                                                        if ($missingTypeLibPath) {
                                                                            [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Missing TypeLib Path"; Data = $missingTypeLibPath; DisplayKey = "$guid\$ver\$locale\$platform ($viewLabel)"; RegPath = (ConvertTo-WmtClassesViewPath -SubPath "TypeLib\$guid\$ver\$locale\$platform" -View $view); ValueName = $null; Type = "Key"; Details = "Type library $platform default path points to a missing file or folder in the $viewLabel registry view." })
                                                                        }
                                                                    }
                                                                    catch {}
                                                                    finally {
                                                                        if ($platformKey) { $platformKey.Close() }
                                                                    }
                                                                }
                                                            }
                                                            catch {}
                                                            finally {
                                                                if ($localeKey) { $localeKey.Close() }
                                                            }
                                                        }
                                                    }
                                                    catch {}
                                                    finally {
                                                        if ($numKey) { $numKey.Close() }
                                                    }
                                                }
                                                $verKey.Close()
                                            }
                                        }
                                        catch {}
                                    }
                                }
                            }
                            catch {}
                            finally {
                                if ($tlKey) { $tlKey.Close() }
                                if ($root) { $root.Close() }
                            }
                        }
                        & $EndCategory
                    }

                    # 13. DEFAULT ICONS
                    if ($SelectedScans -contains "Icons") {
                        $SyncHash.Status = "Scanning Default Icons..."
                        foreach ($view in @([Microsoft.Win32.RegistryView]::Default)) {
                            $root = $null
                            try {
                                $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::ClassesRoot, $view)
                                $viewLabel = Get-WmtRegistryViewLabel $view
                                $names = $root.GetSubKeyNames(); $total = $names.Count; $i = 0
                                foreach ($ext in $names) {
                                    $i++; & $Tick "Scanning Icon ($viewLabel): $ext" $i $total
                                    try {
                                        $iconKey = $root.OpenSubKey("$ext\DefaultIcon")
                                        if ($iconKey) {
                                            $val = $iconKey.GetValue($null)
                                            if ($val) {
                                                $cleanPath = Get-RealExePath $val
                                                if ($cleanPath -match '^[a-zA-Z]:\\' -and -not (Test-IsWhitelisted $cleanPath) -and -not (Test-IsProtectedWindowsPath $cleanPath) -and -not (Test-PathExists $cleanPath) -and $cleanPath -notmatch "%1") {
                                                    [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Invalid Default Icon"; Data = $cleanPath; DisplayKey = "$ext ($viewLabel)"; RegPath = (ConvertTo-WmtClassesViewPath -SubPath "$ext\DefaultIcon" -View $view); ValueName = $null; Type = "Key"; Details = "DefaultIcon path is missing in the $viewLabel registry view." })
                                                }
                                            }
                                            $iconKey.Close()
                                        }
                                    }
                                    catch {}
                                }
                            }
                            catch {}
                            finally {
                                if ($root) { $root.Close() }
                            }
                        }
                        & $EndCategory
                    }

                    # 14. SHARED DLLs
                    if ($SelectedScans -contains "SharedDLLs") { 
                        $SyncHash.Status = "Scanning Shared DLLs..."
                        $key = "SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDlls"
                        foreach ($view in @(Get-WmtRegistryViews)) {
                            $baseKey = $null; $rk = $null
                            try {
                                $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
                                $rk = $baseKey.OpenSubKey($key)
                                if ($rk) {
                                    $viewLabel = Get-WmtRegistryViewLabel $view
                                    $names = $rk.GetValueNames(); $total = $names.Count; $i = 0
                                    foreach ($val in $names) {
                                        $i++; & $Tick "Scanning DLL ($viewLabel): $val" $i $total
                                        if ($val -match '^[a-zA-Z]:\\' -and -not (Test-IsProtectedWindowsPath $val) -and -not(Test-PathExists -Path $val -RegistryView $view)) { [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Missing Shared Ref"; Data = $val; DisplayKey = "SharedDlls ($viewLabel)"; RegPath = (ConvertTo-WmtHklmViewPath -SubPath $key -View $view); ValueName = $val; Type = "Value"; Details = "SharedDlls value points to a missing path in the $viewLabel registry view." }) }
                                    }
                                }
                            }
                            catch {}
                            finally {
                                if ($rk) { $rk.Close() }
                                if ($baseKey) { $baseKey.Close() }
                            }
                        }
                        & $EndCategory
                    }

                    # 15. STARTUP
                    if ($SelectedScans -contains "Startup") { 
                        $SyncHash.Status = "Scanning Startup Items..."
                        $paths = @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Run", "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")
                        foreach ($p in $paths) { 
                            if (Test-Path $p) { 
                                $props = Get-ItemProperty $p
                                $names = $props.PSObject.Properties.Name; $total = $names.Count; $i = 0
                                foreach ($n in $names) { 
                                    $i++; & $Tick "Scanning Startup: $n" $i $total
                                    $v = $props.$n
                                    if ($v -is [string] -and $v -match '^[a-zA-Z]:\\') { 
                                        $cleanExe = Get-RealExePath $v
                                        if (-not (Test-IsProtectedWindowsPath $cleanExe) -and -not (Test-PathExists $cleanExe)) { [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Broken Startup"; Data = $cleanExe; DisplayKey = $n; RegPath = $p; ValueName = $n; Type = "Value" }) } 
                                    } 
                                } 
                            } 
                        } 
                        & $EndCategory
                    }

                    # 15B. RUNONCE AND POLICY STARTUP
                    if ($SelectedScans -contains "StartupExtended") {
                        $SyncHash.Status = "Scanning RunOnce and Policy Startup..."
                        $startupTargets = New-Object System.Collections.Generic.List[object]
                        $startupSubPaths = @(
                            "SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
                            "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"
                        )
                        foreach ($subPath in $startupSubPaths) {
                            foreach ($view in @(Get-WmtRegistryViews)) {
                                try {
                                    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
                                    [void]$startupTargets.Add([PSCustomObject]@{ BaseKey = $baseKey; SubPath = $subPath; RegPrefix = (ConvertTo-WmtHklmViewPath -SubPath $subPath -View $view); Label = "HKLM $(Get-WmtRegistryViewLabel $view)\$subPath"; OwnsBaseKey = $true })
                                }
                                catch {}
                            }
                            $userSubPath = $subPath -replace '^SOFTWARE\\', 'Software\'
                            foreach ($target in @(New-PerUserRegistryTargets -SubPath $userSubPath -HkcuLabel "HKCU\$userSubPath")) {
                                [void]$startupTargets.Add([PSCustomObject]@{ BaseKey = $target.BaseKey; SubPath = $target.SubPath; RegPrefix = $target.RegPrefix; Label = $target.Label; OwnsBaseKey = $false })
                            }
                        }

                        $total = [math]::Max($startupTargets.Count, 1); $i = 0
                        foreach ($target in $startupTargets) {
                            $i++; & $Tick "Scanning Startup Extension: $($target.Label)" $i $total
                            $root = $null
                            try {
                                $root = $target.BaseKey.OpenSubKey($target.SubPath, $false)
                                if ($root) {
                                    foreach ($valName in $root.GetValueNames()) {
                                        $rawValue = [string]$root.GetValue($valName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                                        $cleanExe = Get-ServiceImageExecutablePath $rawValue
                                        if ($cleanExe -and -not (Test-IsWhitelisted $cleanExe) -and -not (Test-IsProtectedWindowsPath $cleanExe) -and -not (Test-PathExists $cleanExe)) {
                                            [void]$SyncHash.Findings.Add([PSCustomObject]@{
                                                    Problem    = "Broken Startup Extension"
                                                    Data       = $cleanExe
                                                    DisplayKey = "$($target.Label)\$valName"
                                                    RegPath    = $target.RegPrefix
                                                    ValueName  = $valName
                                                    Type       = "Value"
                                                    SafeToFix  = $true
                                                    Risk       = "Low"
                                                    Confidence = "High"
                                                    Details    = "RunOnce or policy startup value points to a missing executable. Cleanup deletes only this startup value."
                                                })
                                        }
                                    }
                                }
                            }
                            catch {}
                            finally {
                                if ($root) { $root.Close() }
                                if ($target.OwnsBaseKey -and $target.BaseKey) { $target.BaseKey.Close() }
                            }
                        }
                        & $EndCategory
                    }

                    # 15. INSTALLER FOLDERS
                    if ($SelectedScans -contains "Installer") { 
                        $SyncHash.Status = "Scanning Installer Folders..."
                        $k = "SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\Folders"
                        $rk = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($k)
                        if ($rk) { 
                            $names = $rk.GetValueNames(); $total = $names.Count; $i = 0
                            foreach ($val in $names) { 
                                $i++; & $Tick "Scanning Installer: $val" $i $total
                                if ($val -match '^[a-zA-Z]:\\' -and -not (Test-IsProtectedWindowsPath $val) -and -not(Test-PathExists $val)) { [void]$SyncHash.Findings.Add([PSCustomObject]@{ Problem = "Missing Installer Folder"; Data = $val; DisplayKey = "Installer"; RegPath = "HKLM:\$k"; ValueName = $val; Type = "Value" }) } 
                            }; $rk.Close() 
                        } 
                        & $EndCategory
                    }

                    $SyncHash.IsCompleted = $true
                }
                catch {
                    $SyncHash.Error = $_.Exception.Message
                    $SyncHash.IsCompleted = $true
                }
            })

        [void]$ps.BeginInvoke()
        
        # --- UI TIMER (Main Thread) ---
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(100)
        
        $timer.Add_Tick({
                $statusText = [string]$syncHash.Status
                $statusText = ($statusText -replace '[\r\n\t]+', '  ').Trim()
                if ($statusText.Length -gt 220) { $statusText = $statusText.Substring(0, 217) + '...' }
                $pLabel.Text = $statusText
                $pBar.Value = $syncHash.Progress
            
                if ($syncHash.IsCompleted) {
                    $timer.Stop()
                    $pForm.Close()
                    $ps.Dispose()
                    $rs.Dispose()

                    if ($syncHash.Error) {
                        if ([string]$syncHash.Error -eq "Registry scan canceled.") {
                            Write-GuiLog "Registry scan canceled."
                            return
                        }
                        Show-WmtMessageBox -Message "Scan Error: $($syncHash.Error)" -Title "Error" -Image Error | Out-Null
                        return
                    }

                    $findings = $syncHash.Findings
                    $uniqueFindings = [System.Collections.Generic.List[object]]::new()
                    $seenFindings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($finding in @($findings)) {
                        if ($null -eq $finding) { continue }
                        $newData = if ($finding.PSObject.Properties["NewData"]) { [string]$finding.NewData } else { "" }
                        $key = "$($finding.Type)`0$($finding.RegPath)`0$($finding.ValueName)`0$($finding.Problem)`0$newData"
                        if ($seenFindings.Add($key)) { [void]$uniqueFindings.Add($finding) }
                    }
                    $findings = $uniqueFindings
                
                    # --- RESULTS PROCESSING ---
                    if ($findings.Count -eq 0) {
                        Show-WmtMessageBox -Message "Registry Cleaner: No issues found!" -Title "Scan Complete" -Image Information | Out-Null
                        return
                    }
                
                    $rawSelection = Show-RegistryCleaner -ScanResults ($findings | Select-Object *)
                
                    $toDelete = @()
                    if ($rawSelection) {
                        $toDelete = $rawSelection | Where-Object { $null -ne $_ -and $null -ne $_.RegPath }
                    }

                    if ($toDelete.Count -eq 0) { return }

                    # --- SAFETY PROMPT ---
                    $res = Show-SafetyDialog -Count $toDelete.Count
                    if ($res -eq "Cancel") { return }
                    if ($res -eq "Yes") {
                        Invoke-UiCommand { try { Checkpoint-Computer -Description "WMT DeepClean" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop; "Restore Point created." } catch { "Restore Point failed (Disabled?). Continuing..." } } "Creating Restore Point..."
                    }

                    # --- EXECUTE FIX (Background Runspace) ---
                    Start-WmtRegistryCleanupBackground -Items $toDelete -BackupDirectory $bkDir
                }
            }.GetNewClosure())

        $timer.Start()
    }
}

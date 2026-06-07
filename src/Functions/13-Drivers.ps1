# Functional block generated from WMT-GUI.ps1.
# Dot-source this file; it intentionally shares WMT's script scope.

function Show-DriverCleanupDialog {
    $rawOutput = pnputil.exe /enum-drivers 2>&1
    $drivers = @()
    $current = $null

    foreach ($line in $rawOutput) {
        $line = $line.ToString().Trim()
        if (-not $line.Contains(":")) { continue }

        $parts = $line -split ":", 2
        $key = $parts[0].Trim()
        $val = $parts[1].Trim()
        if ($val -match '^(oem\d+\.inf)$') {
            if ($current) { $drivers += [PSCustomObject]$current }
            $current = [ordered]@{
                PublishedName = $val
                OriginalName  = $null
                Provider      = "Unknown"
                Version       = [Version]"0.0.0.0"
                DisplayVer    = "Unknown"
                SortDate      = [DateTime]::MinValue
                DisplayDate   = "Unknown"
            }
            continue
        }

        if (-not $current) { continue }
        if ($key -match "Original Name" -and $val -notmatch '^oem\d+\.inf$') { $current.OriginalName = $val }
        elseif ($key -match "Provider") { $current.Provider = $val }
        elseif ($key -match "Version") {
            if ($val -match '(\d+(\.\d+){1,3})') {
                $current.DisplayVer = $matches[1]
                try { $current.Version = [Version]$matches[1] } catch {}
            }
            else { $current.DisplayVer = $val }
            if ($current.DisplayDate -eq "Unknown" -and $val -match '(\d{2}[/\-]\d{2}[/\-]\d{4})' -and ($matches[1] -as [DateTime])) {
                $current.DisplayDate = $matches[1]
                $current.SortDate = [DateTime]$matches[1]
            }
        }
        elseif ($key -match "Date") {
            if ($val -as [DateTime]) { $current.DisplayDate = $val; $current.SortDate = [DateTime]$val }
            elseif ($val -match '(\d{2}[/\-]\d{2}[/\-]\d{4})' -and ($matches[1] -as [DateTime])) { $current.DisplayDate = $matches[1]; $current.SortDate = [DateTime]$matches[1] }
        }
        elseif ($null -eq $current.OriginalName -and $val -match '\.inf$') { $current.OriginalName = $val }
    }
    if ($current) { $drivers += [PSCustomObject]$current }

    $toDelete = @()
    foreach ($group in @($drivers | Where-Object { $_.OriginalName } | Group-Object OriginalName)) {
        if ($group.Count -gt 1) { $toDelete += @($group.Group | Sort-Object SortDate, Version -Descending | Select-Object -Skip 1) }
    }

    if (-not $toDelete -or $toDelete.Count -eq 0) {
        Show-WmtMessageBox -Message "Driver store is already clean. No duplicates found." -Title "Clean Old Drivers" -Image Information | Out-Null
        return
    }

    $content = @"
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <DataGrid Name="dgDrivers" IsReadOnly="True" CanUserAddRows="False" CanUserDeleteRows="False" AlternationCount="2"/>
        <Grid Grid.Row="1" Margin="0,12,0,0">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
                <Button Name="btnRemoveAll" Content="Remove All" MinWidth="116" Background="{DynamicResource Success}" Foreground="{DynamicResource SuccessText}" Margin="0,0,8,0"/>
                <Button Name="btnRemoveSel" Content="Remove Selected" MinWidth="140" Background="{DynamicResource Danger}" Foreground="{DynamicResource DangerText}"/>
            </StackPanel>
            <Button Name="btnClose" Content="Close" Width="90" HorizontalAlignment="Right" IsCancel="True"/>
        </Grid>
    </Grid>
"@
    $dialog = New-WmtWindowFromXaml -Title "Clean Old Drivers" -ContentXaml $content -Width 960 -Height 620 -MinWidth 760 -MinHeight 480
    $dg = $dialog.FindName("dgDrivers")
    $btnRemoveAll = $dialog.FindName("btnRemoveAll")
    $btnRemoveSel = $dialog.FindName("btnRemoveSel")
    $btnClose = $dialog.FindName("btnClose")

    $currentList = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @($toDelete)) { [void]$currentList.Add($item) }
    $rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $dg.ItemsSource = $rows
    Set-WmtDataGridColumns -DataGrid $dg -Columns @("PublishedName", "OriginalName", "Provider", "Version", "Date") -Widths @{ PublishedName = 120; OriginalName = "*"; Provider = 180; Version = 120; Date = 110 }

    $loadGrid = {
        $rows.Clear()
        foreach ($d in @($currentList.ToArray())) {
            [void]$rows.Add([PSCustomObject]@{
                    PublishedName = [string]$d.PublishedName
                    OriginalName  = [string]$d.OriginalName
                    Provider      = [string]$d.Provider
                    Version       = [string]$d.DisplayVer
                    Date          = [string]$d.DisplayDate
                    Source        = $d
                })
        }
        $dialog.Title = "Clean Old Drivers ($($rows.Count) duplicate package(s))"
    }.GetNewClosure()

    $chooseCleanupMode = {
        param([int]$Count)
        $choiceContent = @"
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Name="lblPrompt" TextWrapping="Wrap"/>
        <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0">
            <Button Name="btnBackup" Content="Backup and Clean" MinWidth="132" Background="{DynamicResource Success}" Foreground="{DynamicResource SuccessText}" Margin="0,0,8,0"/>
            <Button Name="btnNoBackup" Content="Clean Only" MinWidth="112" Background="{DynamicResource Danger}" Foreground="{DynamicResource DangerText}" Margin="0,0,8,0"/>
            <Button Name="btnCancel" Content="Cancel" Width="92" IsCancel="True"/>
        </StackPanel>
    </Grid>
"@
        $choice = New-WmtWindowFromXaml -Title "Confirm Driver Cleanup" -ContentXaml $choiceContent -Width 470 -Height 170 -NoResize
        try { $choice.Owner = $dialog } catch {}
        $choice.FindName("lblPrompt").Text = "You are about to remove $Count driver package(s). How would you like to proceed?"
        $state = @{ Result = "Cancel" }
        $choice.FindName("btnBackup").Add_Click({ $state.Result = "Backup"; $choice.DialogResult = $true }.GetNewClosure())
        $choice.FindName("btnNoBackup").Add_Click({ $state.Result = "NoBackup"; $choice.DialogResult = $true }.GetNewClosure())
        $choice.FindName("btnCancel").Add_Click({ $choice.Close() }.GetNewClosure())
        $choice.ShowDialog() | Out-Null
        return $state.Result
    }.GetNewClosure()

    $doRemove = {
        param([object[]]$Items, [bool]$CloseWindow)
        $itemsToRemove = @($Items | ForEach-Object { if ($_.PSObject.Properties["Source"]) { $_.Source } else { $_ } })
        if ($itemsToRemove.Count -eq 0) { return }

        $mode = & $chooseCleanupMode -Count $itemsToRemove.Count
        if ($mode -eq "Cancel") { return }

        Set-WmtBusyCursor -Busy
        $backupCount = 0
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmm'
        $mainBkPath = Join-Path (Get-DataPath) "Drivers_Backup_$timestamp"
        try {
            if ($mode -eq "Backup") {
                if (-not (Test-Path $mainBkPath)) { New-Item -Path $mainBkPath -ItemType Directory -Force | Out-Null }
                $i = 1
                foreach ($item in $itemsToRemove) {
                    $dialog.Title = "Backing up ($i/$($itemsToRemove.Count)): $($item.OriginalName)..."
                    Invoke-WmtDispatcherPump -Dispatcher $dialog.Dispatcher
                    $folderName = if ($item.OriginalName) { $item.OriginalName } else { $item.PublishedName }
                    $drvPath = Join-Path $mainBkPath $folderName
                    New-Item -Path $drvPath -ItemType Directory -Force | Out-Null
                    $proc = Start-Process pnputil.exe -ArgumentList "/export-driver", $item.PublishedName, "`"$drvPath`"" -NoNewWindow -Wait -PassThru
                    if ($proc.ExitCode -eq 0) { $backupCount++ }
                    $i++
                }
            }

            $deleted = 0
            $failed = 0
            foreach ($item in $itemsToRemove) {
                $name = [string]$item.PublishedName
                $dialog.Title = "Removing $name..."
                Invoke-WmtDispatcherPump -Dispatcher $dialog.Dispatcher
                $p = [System.Diagnostics.Process]::new()
                $p.StartInfo.FileName = "pnputil.exe"
                $p.StartInfo.Arguments = "/delete-driver $name /uninstall"
                $p.StartInfo.RedirectStandardOutput = $true
                $p.StartInfo.RedirectStandardError = $true
                $p.StartInfo.UseShellExecute = $false
                $p.StartInfo.CreateNoWindow = $true
                $p.Start() | Out-Null
                $stdOut = $p.StandardOutput.ReadToEnd()
                $stdErr = $p.StandardError.ReadToEnd()
                $p.WaitForExit()
                if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) { $deleted++ }
                else {
                    $warnMsg = "Driver: $($item.OriginalName) ($name)`n`nError:`n$($stdOut)`n$($stdErr)`n`nForce delete?"
                    if ((Show-WmtMessageBox -Owner $dialog -Message $warnMsg -Title "Deletion Failed" -Button YesNo -Image Error) -eq [System.Windows.MessageBoxResult]::Yes) {
                        $procForce = Start-Process pnputil.exe -ArgumentList "/delete-driver $name /uninstall /force" -NoNewWindow -Wait -PassThru
                        if ($procForce.ExitCode -eq 0 -or $procForce.ExitCode -eq 3010) { $deleted++ } else { $failed++ }
                    }
                    else { $failed++ }
                }
            }

            $resMsg = "Done.`nDeleted: $deleted`nFailed: $failed"
            if ($mode -eq "Backup") { $resMsg += "`nBackups: $backupCount`nPath: $mainBkPath" }
            Show-WmtMessageBox -Owner $dialog -Message $resMsg -Title "Result" -Image Information | Out-Null

            if ($deleted -gt 0) {
                foreach ($item in $itemsToRemove) {
                    for ($idx = $currentList.Count - 1; $idx -ge 0; $idx--) {
                        if ($currentList[$idx].PublishedName -eq $item.PublishedName) { $currentList.RemoveAt($idx) }
                    }
                }
                & $loadGrid
            }
        }
        finally {
            $dialog.Title = "Clean Old Drivers"
            Set-WmtBusyCursor
        }
        if ($CloseWindow) { $dialog.Close() }
    }.GetNewClosure()

    $btnRemoveAll.Add_Click({ & $doRemove -Items @($currentList.ToArray()) -CloseWindow $true }.GetNewClosure())
    $btnRemoveSel.Add_Click({ & $doRemove -Items @($dg.SelectedItems) -CloseWindow $false }.GetNewClosure())
    $btnClose.Add_Click({ $dialog.Close() }.GetNewClosure())
    & $loadGrid
    $dialog.ShowDialog() | Out-Null
}

function Invoke-DriverReport {
    Invoke-UiCommand {
        $outfile = Join-Path (Get-DataPath) "Installed_Drivers.txt"
        driverquery /v > $outfile
        Write-Output "Driver report saved to $outfile"
    } "Creating driver report..."
}

function Invoke-ExportDrivers {
    Write-GuiLog "Starting Driver Export Tool..."
    $dataPath = try { Get-DataPath } catch { Join-Path $env:PUBLIC "WMT_Exports" }

    Set-WmtBusyCursor -Busy
    try {
        $drivers = @()
        foreach ($d in @(Get-WindowsDriver -Online -All | Where-Object { $_.Inbox -eq $false })) {
            $classProbe = "$($d.ClassName) $($d.ProviderName)".ToLowerInvariant()
            $class = "Other"
            if ($classProbe -match "display|graphics|nvidia|amd|intel.*graphics") { $class = "Display" }
            elseif ($classProbe -match "net|network|wifi|ethernet|realtek|broadcom|intel.*network") { $class = "Network" }
            elseif ($classProbe -match "audio|sound") { $class = "Audio" }
            elseif ($classProbe -match "storage|sata|nvme|raid|disk") { $class = "Storage" }
            elseif ($classProbe -match "usb") { $class = "USB" }
            elseif ($classProbe -match "print") { $class = "Printer" }
            elseif ($classProbe -match "system|chipset|acpi") { $class = "System" }

            $drivers += [PSCustomObject]@{
                PublishedName = [string]$d.Driver
                OriginalName  = [string]$d.OriginalFileName
                Class         = $class
                Provider      = [string]$d.ProviderName
                Version       = [string]$d.Version
                Date          = if ($d.Date) { $d.Date.ToString("yyyy-MM-dd") } else { "" }
            }
        }
    }
    finally { Set-WmtBusyCursor }

    if (-not $drivers -or $drivers.Count -eq 0) {
        Show-WmtMessageBox -Message "No 3rd-party drivers found to export." -Title "Driver Export Tool" -Image Information | Out-Null
        return
    }

    $content = @"
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid Grid.Row="0" Margin="0,0,0,12">
            <Grid.ColumnDefinitions><ColumnDefinition Width="220"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <TextBlock Text="Class" Foreground="{DynamicResource TextSecondary}"/>
            <TextBox Name="txtSearch" Grid.Column="1" Height="34" VerticalContentAlignment="Center"/>
        </Grid>
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions><ColumnDefinition Width="220"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <ListBox Name="lstClasses"/>
            <DataGrid Name="dgDrivers" Grid.Column="2" IsReadOnly="True" SelectionMode="Extended" CanUserAddRows="False" CanUserDeleteRows="False" AlternationCount="2"/>
        </Grid>
        <Grid Grid.Row="2" Margin="0,12,0,0">
            <TextBlock Name="lblStatus" Text="Ready" VerticalAlignment="Center" Foreground="{DynamicResource Accent}"/>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <Button Name="btnExportSel" Content="Export Selected" MinWidth="128" Background="{DynamicResource Success}" Foreground="{DynamicResource SuccessText}" Margin="0,0,8,0"/>
                <Button Name="btnExportAll" Content="Export All" MinWidth="104" Margin="0,0,8,0"/>
                <Button Name="btnClose" Content="Close" Width="90" IsCancel="True"/>
            </StackPanel>
        </Grid>
    </Grid>
"@
    $dialog = New-WmtWindowFromXaml -Title "Driver Export Tool" -ContentXaml $content -Width 940 -Height 680 -MinWidth 760 -MinHeight 520
    $lstClasses = $dialog.FindName("lstClasses")
    $txtSearch = $dialog.FindName("txtSearch")
    $dg = $dialog.FindName("dgDrivers")
    $lblStatus = $dialog.FindName("lblStatus")
    $btnExportSel = $dialog.FindName("btnExportSel")
    $btnExportAll = $dialog.FindName("btnExportAll")
    $btnClose = $dialog.FindName("btnClose")

    Set-WmtDataGridColumns -DataGrid $dg -Columns @("PublishedName", "OriginalName", "Provider", "Version", "Date", "Class") -Widths @{ PublishedName = 130; OriginalName = "*"; Provider = 160; Version = 110; Date = 90; Class = 90 }
    $rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $dg.ItemsSource = $rows

    $classes = @([PSCustomObject]@{ Display = "All ($($drivers.Count))"; Class = "" })
    $classes += @($drivers | Group-Object Class | Sort-Object Name | ForEach-Object { [PSCustomObject]@{ Display = "$($_.Name) ($($_.Count))"; Class = $_.Name } })
    $lstClasses.DisplayMemberPath = "Display"
    $lstClasses.ItemsSource = $classes
    $lstClasses.SelectedIndex = 0

    $refresh = {
        $rows.Clear()
        $selectedClass = if ($lstClasses.SelectedItem) { [string]$lstClasses.SelectedItem.Class } else { "" }
        $search = ([string]$txtSearch.Text).Trim().ToLowerInvariant()
        foreach ($d in @($drivers)) {
            if ($selectedClass -and $d.Class -ne $selectedClass) { continue }
            $haystack = "$($d.PublishedName) $($d.OriginalName) $($d.Provider) $($d.Version)".ToLowerInvariant()
            if ($search -and -not $haystack.Contains($search)) { continue }
            [void]$rows.Add($d)
        }
        $lblStatus.Text = "$($rows.Count) shown / $($drivers.Count) drivers"
    }.GetNewClosure()

    $exportDrivers = {
        param([object[]]$DriversToExport)
        $targets = @($DriversToExport | Where-Object { $_ })
        if ($targets.Count -eq 0) {
            Show-WmtMessageBox -Owner $dialog -Message "Please select at least one driver to export." -Title "Driver Export Tool" -Image Warning | Out-Null
            return
        }

        $exportPath = Join-Path $dataPath "Drivers_Backup_$(Get-Date -Format yyyyMMdd_HHmm)"
        New-Item -ItemType Directory -Path $exportPath -Force | Out-Null
        Set-WmtBusyCursor -Busy
        $dialog.IsEnabled = $false
        try {
            $done = 0
            foreach ($drv in $targets) {
                $done++
                $lblStatus.Text = "Exporting $done / $($targets.Count): $($drv.PublishedName)"
                Invoke-WmtDispatcherPump -Dispatcher $dialog.Dispatcher
                $dir = Join-Path $exportPath $drv.Class
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                $process = Start-Process pnputil -ArgumentList "/export-driver", $drv.PublishedName, "`"$dir`"" -NoNewWindow -Wait -PassThru
                if ($process.ExitCode -ne 0) { Write-GuiLog "Driver export failed for $($drv.PublishedName) (exit $($process.ExitCode))." }
            }
            $lblStatus.Text = "Done"
            Show-WmtMessageBox -Owner $dialog -Message "Export Complete!`n`nSaved to:`n$exportPath" -Title "Success" -Image Information | Out-Null
        }
        catch {
            $lblStatus.Text = "Error"
            Show-WmtMessageBox -Owner $dialog -Message "An error occurred during export:`n`n$($_.Exception.Message)" -Title "Error" -Image Error | Out-Null
        }
        finally {
            $dialog.IsEnabled = $true
            Set-WmtBusyCursor
        }
    }.GetNewClosure()

    $lstClasses.Add_SelectionChanged({ & $refresh }.GetNewClosure())
    $txtSearch.Add_TextChanged({ & $refresh }.GetNewClosure())
    $btnExportSel.Add_Click({ & $exportDrivers -DriversToExport @($dg.SelectedItems) }.GetNewClosure())
    $btnExportAll.Add_Click({ & $exportDrivers -DriversToExport @($drivers) }.GetNewClosure())
    $btnClose.Add_Click({ $dialog.Close() }.GetNewClosure())
    & $refresh
    $dialog.ShowDialog() | Out-Null
}

function Show-GhostDevicesDialog {
    $content = @"
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <DataGrid Name="dgGhost" IsReadOnly="True" CanUserAddRows="False" CanUserDeleteRows="False" AlternationCount="2"/>
        <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button Name="btnRefresh" Content="Refresh" Width="104" Margin="0,0,8,0" Background="{DynamicResource Accent}" Foreground="{DynamicResource AccentText}"/>
            <Button Name="btnRemoveSel" Content="Remove Selected" MinWidth="132" Margin="0,0,8,0" Background="{DynamicResource Danger}" Foreground="{DynamicResource DangerText}"/>
            <Button Name="btnRemoveAll" Content="Remove All" Width="108" Margin="0,0,8,0" Background="{DynamicResource Danger}" Foreground="{DynamicResource DangerText}"/>
            <Button Name="btnClose" Content="Close" Width="90" IsCancel="True"/>
        </StackPanel>
    </Grid>
"@
    $dialog = New-WmtWindowFromXaml -Title "Ghost Devices" -ContentXaml $content -Width 840 -Height 520 -MinWidth 680 -MinHeight 420
    $dg = $dialog.FindName("dgGhost")
    $btnRefresh = $dialog.FindName("btnRefresh")
    $btnRemoveSel = $dialog.FindName("btnRemoveSel")
    $btnRemoveAll = $dialog.FindName("btnRemoveAll")
    $btnClose = $dialog.FindName("btnClose")

    $items = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $dg.ItemsSource = $items
    Set-WmtDataGridColumns -DataGrid $dg -Columns @("InstanceId", "Class", "FriendlyName") -Widths @{ InstanceId = "*"; Class = 120; FriendlyName = 260 }

    $load = {
        $items.Clear()
        Set-WmtBusyCursor -Busy
        try {
            foreach ($d in @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Unknown' })) {
                [void]$items.Add([PSCustomObject]@{
                        InstanceId   = [string]$d.InstanceId
                        Class        = [string]$d.Class
                        FriendlyName = [string]$d.FriendlyName
                    })
            }
            if ($items.Count -eq 0) {
                Show-WmtMessageBox -Owner $dialog -Message "No hidden/ghost devices found." -Title "Ghost Devices" -Image Information | Out-Null
            }
        }
        finally { Set-WmtBusyCursor }
    }.GetNewClosure()

    $removeRows = {
        param([object[]]$Rows)
        foreach ($row in @($Rows)) {
            $id = [string]$row.InstanceId
            if (-not [string]::IsNullOrWhiteSpace($id)) { pnputil /remove-device $id | Out-Null }
        }
        & $load
    }.GetNewClosure()

    $btnRefresh.Add_Click({ & $load }.GetNewClosure())
    $btnRemoveSel.Add_Click({ & $removeRows -Rows @($dg.SelectedItems) }.GetNewClosure())
    $btnRemoveAll.Add_Click({ & $removeRows -Rows @($items) }.GetNewClosure())
    $btnClose.Add_Click({ $dialog.Close() }.GetNewClosure())
    $dialog.Add_ContentRendered({ & $load }.GetNewClosure())
    $dialog.ShowDialog() | Out-Null
}

function Invoke-DriverUpdates {
    param([bool]$Enable)
    $value = if ($Enable) { 0 } else { 1 }
    $msg = if ($Enable) { "Enabled automatic driver updates." } else { "Disabled automatic driver updates." }
    Invoke-UiCommand {
        param($value, $msg)
        $path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "SearchOrderConfig" -Value $value -Type DWord
        Write-Output $msg
    } "Updating driver update policy..." -ArgumentList $value, $msg
}

function Invoke-DeviceMetadata {
    param([bool]$Enable)
    $value = if ($Enable) { 0 } else { 1 }
    $msg = if ($Enable) { "Device metadata downloads enabled." } else { "Device metadata downloads disabled." }
    Invoke-UiCommand {
        param($value, $msg)
        $path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "PreventDeviceMetadataFromNetwork" -Value $value -Type DWord
        Write-Output $msg
    } "Updating device metadata policy..." -ArgumentList $value, $msg
}

function Invoke-RestoreDrivers {
    $dataPath = Get-DataPath
    $backups = @()
    try {
        $backups = @([System.IO.Directory]::EnumerateDirectories($dataPath) | ForEach-Object { [System.IO.DirectoryInfo]::new($_) } | Where-Object { $_.Name -match '^DriverBackup_' -or $_.Name -match '^Drivers_Backup_' })
    }
    catch {}

    $selectedPath = $null
    if ($backups -and $backups.Count -gt 0) {
        $items = @($backups | Sort-Object LastWriteTime -Descending | ForEach-Object {
                [PSCustomObject]@{
                    Name    = $_.Name
                    Path    = $_.FullName
                    Display = "{0}  (modified {1})" -f $_.Name, $_.LastWriteTime
                }
            })

        $content = @"
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <ListBox Name="lstBackups" DisplayMemberPath="Display"/>
        <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button Name="btnUse" Content="Use Selected" MinWidth="118" Background="{DynamicResource Success}" Foreground="{DynamicResource SuccessText}" Margin="0,0,8,0"/>
            <Button Name="btnBrowse" Content="Browse" Width="96" Margin="0,0,8,0"/>
            <Button Name="btnCancel" Content="Cancel" Width="96" IsCancel="True"/>
        </StackPanel>
    </Grid>
"@
        $dialog = New-WmtWindowFromXaml -Title "Select Driver Backup" -ContentXaml $content -Width 640 -Height 420 -MinWidth 520 -MinHeight 340
        $lstBackups = $dialog.FindName("lstBackups")
        $btnUse = $dialog.FindName("btnUse")
        $btnBrowse = $dialog.FindName("btnBrowse")
        $btnCancel = $dialog.FindName("btnCancel")
        $lstBackups.ItemsSource = $items
        if ($items.Count -gt 0) { $lstBackups.SelectedIndex = 0 }
        $dialogState = @{ Browse = $false; Selected = $null }
        $btnUse.Add_Click({ if ($lstBackups.SelectedItem) { $dialogState.Selected = [string]$lstBackups.SelectedItem.Path; $dialog.DialogResult = $true } }.GetNewClosure())
        $btnBrowse.Add_Click({ $dialogState.Browse = $true; $dialog.DialogResult = $true }.GetNewClosure())
        $btnCancel.Add_Click({ $dialog.Close() }.GetNewClosure())
        $dialog.ShowDialog() | Out-Null
        if ($dialogState.Selected) { $selectedPath = $dialogState.Selected }
        elseif (-not $dialogState.Browse) { return }
    }

    if (-not $selectedPath) {
        $selectedPath = Select-WmtFolder -Description "Select DriverBackup folder" -InitialDirectory $dataPath
        if ([string]::IsNullOrWhiteSpace($selectedPath)) { return }
    }

    Invoke-UiCommand {
        param($Path)
        if (-not (Test-Path $Path)) {
            Write-Output "Restore failed: path not found $Path"
            Show-WmtMessageBox -Message "Restore failed: path not found.`n$Path" -Title "Restore Drivers" -Image Error | Out-Null
            return
        }

        $firstInf = Find-WmtFirstEnumeratedFile -Path $Path -Filter "*.inf"
        if (-not $firstInf) {
            Write-Output "Restore aborted: no INF files found in $Path"
            Show-WmtMessageBox -Message "No INF files found in:`n$Path" -Title "Restore Drivers" -Image Warning | Out-Null
            return
        }

        $output = pnputil.exe /add-driver "$Path\*.inf" /subdirs 2>&1
        $code = $LASTEXITCODE
        Write-Output $output
        if ($code -eq 0 -or $code -eq 3010) {
            Write-Output "Drivers restored from $Path"
            Show-WmtMessageBox -Message "Drivers restored from:`n$Path" -Title "Restore Drivers" -Image Information | Out-Null
        }
        else {
            Write-Output "Restore failed (exit $code)."
            $msg = "Restore failed (exit $code)." + "`n`nOutput:`n" + ($output | Out-String)
            Show-WmtMessageBox -Message $msg -Title "Restore Drivers" -Image Error | Out-Null
        }
    } "Restoring drivers..." -ArgumentList $selectedPath
}

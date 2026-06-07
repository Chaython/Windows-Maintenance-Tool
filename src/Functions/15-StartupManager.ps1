# Functional block generated from WMT-GUI.ps1.
# Dot-source this file; it intentionally shares WMT's script scope.

function ConvertTo-WmtScheduledTaskIdentity {
    param(
        [string]$FullName = "",
        [string]$TaskName = "",
        [string]$TaskPath = ""
    )

    if ([string]::IsNullOrWhiteSpace($TaskName) -and -not [string]::IsNullOrWhiteSpace($FullName)) {
        $normalized = ([string]$FullName).Trim() -replace '/', '\'
        if (-not $normalized.StartsWith("\")) { $normalized = "\$normalized" }
        $parts = @($normalized.Trim("\") -split '\\' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($parts.Count -gt 0) {
            $TaskName = $parts[$parts.Count - 1]
            if ($parts.Count -gt 1) { $TaskPath = "\" + (($parts[0..($parts.Count - 2)]) -join "\") + "\" }
            else { $TaskPath = "\" }
        }
    }

    $TaskName = ([string]$TaskName).Trim()
    $TaskPath = ([string]$TaskPath).Trim() -replace '/', '\'
    if ([string]::IsNullOrWhiteSpace($TaskPath)) { $TaskPath = "\" }
    if (-not $TaskPath.StartsWith("\")) { $TaskPath = "\$TaskPath" }
    if (-not $TaskPath.EndsWith("\")) { $TaskPath = "$TaskPath\" }

    $full = if ($TaskPath -eq "\") { "\$TaskName" } else { "$TaskPath$TaskName" }
    [PSCustomObject]@{
        TaskName = $TaskName
        TaskPath = $TaskPath
        FullName = $full
    }
}

function Get-WmtScheduledTaskByIdentity {
    param(
        [string]$FullName = "",
        [string]$TaskName = "",
        [string]$TaskPath = ""
    )

    $id = ConvertTo-WmtScheduledTaskIdentity -FullName $FullName -TaskName $TaskName -TaskPath $TaskPath
    if ([string]::IsNullOrWhiteSpace($id.TaskName)) { return $null }

    try {
        return Get-ScheduledTask -TaskName $id.TaskName -TaskPath $id.TaskPath -ErrorAction Stop | Select-Object -First 1
    }
    catch {
        try {
            return Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName -eq $id.TaskName -and $_.TaskPath -eq $id.TaskPath } | Select-Object -First 1
        }
        catch {}
    }
    return $null
}

function Get-WmtScheduledTaskRows {
    param(
        [string[]]$FullPaths = @(),
        [string[]]$TaskPaths = @()
    )

    $tasks = @()
    if ($FullPaths -and $FullPaths.Count -gt 0) {
        foreach ($fullPath in $FullPaths) {
            $task = Get-WmtScheduledTaskByIdentity -FullName $fullPath
            if ($task) { $tasks += $task }
        }
    }
    else {
        try {
            $tasks = @(Get-ScheduledTask -ErrorAction Stop)
            if ($TaskPaths -and $TaskPaths.Count -gt 0) {
                $normalizedPaths = @($TaskPaths | ForEach-Object { (ConvertTo-WmtScheduledTaskIdentity -TaskPath $_ -TaskName "_").TaskPath })
                $tasks = @($tasks | Where-Object { $_.TaskPath -in $normalizedPaths })
            }
        }
        catch {
            $tasks = @()
        }
    }

    foreach ($task in @($tasks)) {
        $id = ConvertTo-WmtScheduledTaskIdentity -TaskName $task.TaskName -TaskPath $task.TaskPath
        [PSCustomObject]@{
            TaskName    = [string]$id.TaskName
            TaskPath    = [string]$id.TaskPath
            State       = [string]$task.State
            Enabled     = if ([string]$task.State -eq "Disabled") { "No" } else { "Yes" }
            Author      = [string]$task.Author
            Description = [string]$task.Description
            FullName    = [string]$id.FullName
        }
    }
}

function Invoke-WmtScheduledTaskAction {
    param(
        [ValidateSet("Enable", "Disable", "Delete")][string]$Action,
        [string]$FullName = "",
        [string]$TaskName = "",
        [string]$TaskPath = ""
    )

    $id = ConvertTo-WmtScheduledTaskIdentity -FullName $FullName -TaskName $TaskName -TaskPath $TaskPath
    try {
        $task = Get-WmtScheduledTaskByIdentity -TaskName $id.TaskName -TaskPath $id.TaskPath
        if (-not $task) { throw "Task not found: $($id.FullName)" }

        switch ($Action) {
            "Enable" { Enable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null }
            "Disable" { Disable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null }
            "Delete" { Unregister-ScheduledTask -InputObject $task -Confirm:$false -ErrorAction Stop | Out-Null }
        }

        [PSCustomObject]@{ Success = $true; Task = $id.FullName; Message = "$Action succeeded." }
    }
    catch {
        [PSCustomObject]@{ Success = $false; Task = $id.FullName; Message = $_.Exception.Message }
    }
}

function Show-WmtScheduledTasksDialog {
    param(
        [string]$Title = "Scheduled Tasks",
        [string[]]$FullPaths = @(),
        [string[]]$TaskPaths = @()
    )

    $content = @'
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <DataGrid Name="dgTasks" IsReadOnly="True" SelectionMode="Extended" CanUserAddRows="False" CanUserDeleteRows="False" AlternationCount="2"/>
        <TextBlock Name="lblStatus" Grid.Row="1" Foreground="{DynamicResource TextSecondary}" Margin="0,10,0,0"/>
        <WrapPanel Grid.Row="2" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button Name="btnRefresh" Content="Refresh" MinWidth="92" Background="{DynamicResource Accent}" Foreground="{DynamicResource AccentText}" Margin="0,0,8,8"/>
            <Button Name="btnEnable" Content="Enable" MinWidth="92" Background="{DynamicResource Success}" Foreground="{DynamicResource SuccessText}" Margin="0,0,8,8"/>
            <Button Name="btnDisable" Content="Disable" MinWidth="92" Background="{DynamicResource Warning}" Foreground="{DynamicResource WarningText}" Margin="0,0,8,8"/>
            <Button Name="btnClose" Content="Close" Width="92" IsCancel="True" Margin="0,0,8,8"/>
        </WrapPanel>
    </Grid>
'@
    $dialog = New-WmtWindowFromXaml -Title $Title -ContentXaml $content -Width 960 -Height 560 -MinWidth 760 -MinHeight 420
    $dg = $dialog.FindName("dgTasks")
    $lblStatus = $dialog.FindName("lblStatus")
    $btnRefresh = $dialog.FindName("btnRefresh")
    $btnEnable = $dialog.FindName("btnEnable")
    $btnDisable = $dialog.FindName("btnDisable")
    $btnClose = $dialog.FindName("btnClose")

    $state = @{ Table = $null }
    $load = {
        $rows = @(Get-WmtScheduledTaskRows -FullPaths $FullPaths -TaskPaths $TaskPaths)
        $table = New-WmtDataTable -Columns @("TaskName", "TaskPath", "State", "Enabled", "Author", "Description", "FullName") -Rows $rows
        $state.Table = $table
        $dg.ItemsSource = $table.DefaultView
        Set-WmtDataGridColumns -DataGrid $dg -Columns @("TaskName", "TaskPath", "State", "Enabled", "Author", "Description", "FullName") -Widths @{ TaskName = "*"; TaskPath = 260; State = 100; Enabled = 80; Author = 180; Description = "2*" } -Hidden @("FullName")
        $lblStatus.Text = if ($table.Rows.Count -gt 0) { "$($table.Rows.Count) task(s)" } else { "No scheduled tasks found. Try running WMT as administrator." }
    }.GetNewClosure()

    $invokeSelected = {
        param([string]$Action)
        $selected = @(Get-WmtDataGridSelectedRows -DataGrid $dg)
        if ($selected.Count -eq 0) { return }
        $failures = @()
        foreach ($row in $selected) {
            $result = Invoke-WmtScheduledTaskAction -Action $Action -TaskName ([string]$row["TaskName"]) -TaskPath ([string]$row["TaskPath"])
            if (-not $result.Success) { $failures += "$($result.Task): $($result.Message)" }
        }
        & $load
        if ($failures.Count -gt 0) {
            Show-WmtMessageBox -Owner $dialog -Message ($failures -join "`r`n") -Title "Scheduled Tasks" -Image Warning | Out-Null
        }
    }.GetNewClosure()

    $btnRefresh.Add_Click({ & $load }.GetNewClosure())
    $btnEnable.Add_Click({ & $invokeSelected "Enable" }.GetNewClosure())
    $btnDisable.Add_Click({ & $invokeSelected "Disable" }.GetNewClosure())
    $btnClose.Add_Click({ $dialog.Close() }.GetNewClosure())
    $dialog.Add_ContentRendered({ & $load }.GetNewClosure())
    $dialog.ShowDialog() | Out-Null
}

function Show-StartupManager {
    param([string]$DefaultTab = "Windows")

    $content = @'
    <Grid Margin="0" Background="{DynamicResource BgDark}">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <Border Grid.Row="0" Background="{DynamicResource BgDark}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="0,0,0,1" Padding="14,10">
            <StackPanel Name="tabHeader" Orientation="Horizontal"/>
        </Border>
        <Grid Name="mainHost" Grid.Row="1" Background="{DynamicResource BgDark}"/>
    </Grid>
'@
    $dialog = New-WmtWindowFromXaml -Title "Startup Manager" -ContentXaml $content -Width 1220 -Height 720 -MinWidth 960 -MinHeight 560
    $tabHeader = $dialog.FindName("tabHeader")
    $mainHost = $dialog.FindName("mainHost")
    $tabs = @{}
    $tabButtons = @{}
    $tabLoaded = @{
        "Windows"         = $false
        "Scheduled Tasks" = $false
        "Context Menu"    = $false
        "Services"        = $false
    }

    function Set-StartupButtonRole {
        param(
            [System.Windows.Controls.Button]$Button,
            [string]$Role = "Standard"
        )
        if (-not $Button) { return }
        $bgKey = switch ($Role) {
            "Success" { "Success"; break }
            "Danger" { "Danger"; break }
            "Warning" { "Warning"; break }
            "Primary" { "Accent"; break }
            default { "BgElevated"; break }
        }
        $fgKey = switch ($Role) {
            "Success" { "SuccessText"; break }
            "Danger" { "DangerText"; break }
            "Warning" { "WarningText"; break }
            "Primary" { "AccentText"; break }
            default { "TextPrimary"; break }
        }
        Set-WmtThemedBrush -Object $Button -Property ([System.Windows.Controls.Control]::BackgroundProperty) -ColorOrKey $bgKey
        Set-WmtThemedBrush -Object $Button -Property ([System.Windows.Controls.Control]::ForegroundProperty) -ColorOrKey $fgKey
        Set-WmtThemedBrush -Object $Button -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -ColorOrKey "BorderBrush"
    }

    function New-StartupButton {
        param(
            [System.Windows.Controls.Panel]$Parent,
            [string]$Text,
            [string]$Role = "Standard"
        )
        $button = [System.Windows.Controls.Button]::new()
        $button.Content = $Text
        $button.MinWidth = 108
        $button.Height = 34
        $button.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
        $button.Padding = [System.Windows.Thickness]::new(14, 0, 14, 0)
        $button.BorderThickness = [System.Windows.Thickness]::new(1)
        $button.FocusVisualStyle = $null
        Set-StartupButtonRole -Button $button -Role $Role
        [void]$Parent.Children.Add($button)
        return $button
    }

    function New-TabButton {
        param([string]$Text)
        $button = [System.Windows.Controls.Button]::new()
        $button.Content = $Text
        $button.Width = 160
        $button.Height = 32
        $button.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
        $button.Padding = [System.Windows.Thickness]::new(12, 0, 12, 0)
        $button.BorderThickness = [System.Windows.Thickness]::new(1)
        $button.FocusVisualStyle = $null
        $button.Cursor = [System.Windows.Input.Cursors]::Hand
        Set-StartupButtonRole -Button $button -Role "Standard"
        Set-WmtThemedBrush -Object $button -Property ([System.Windows.Controls.Control]::ForegroundProperty) -ColorOrKey "TextSecondary"
        [void]$tabHeader.Children.Add($button)
        $tabButtons[$Text] = $button
        return $button
    }

    function Set-TabButtonActive {
        param([string]$Title)
        foreach ($key in @($tabButtons.Keys)) {
            $button = $tabButtons[$key]
            if ($key -eq $Title) {
                Set-WmtThemedBrush -Object $button -Property ([System.Windows.Controls.Control]::BackgroundProperty) -ColorOrKey "BgElevated"
                Set-WmtThemedBrush -Object $button -Property ([System.Windows.Controls.Control]::ForegroundProperty) -ColorOrKey "TextPrimary"
                Set-WmtThemedBrush -Object $button -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -ColorOrKey "Accent"
            }
            else {
                Set-WmtThemedBrush -Object $button -Property ([System.Windows.Controls.Control]::BackgroundProperty) -ColorOrKey "BgPanel"
                Set-WmtThemedBrush -Object $button -Property ([System.Windows.Controls.Control]::ForegroundProperty) -ColorOrKey "TextSecondary"
                Set-WmtThemedBrush -Object $button -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -ColorOrKey "BorderBrush"
            }
        }
    }

    function New-StartupPage {
        param([string]$Title)

        $root = [System.Windows.Controls.Grid]::new()
        $root.Background = $dialog.Resources["BgDark"]
        $root.Visibility = [System.Windows.Visibility]::Collapsed
        foreach ($h in @("Auto", "*", "Auto")) {
            $row = [System.Windows.Controls.RowDefinition]::new()
            $row.Height = if ($h -eq "*") { [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) } else { [System.Windows.GridLength]::Auto }
            [void]$root.RowDefinitions.Add($row)
        }
        [void]$mainHost.Children.Add($root)

        $topBorder = [System.Windows.Controls.Border]::new()
        $topBorder.Padding = [System.Windows.Thickness]::new(14, 10, 14, 10)
        $topBorder.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
        Set-WmtThemedBrush -Object $topBorder -Property ([System.Windows.Controls.Border]::BackgroundProperty) -ColorOrKey "BgPanel"
        Set-WmtThemedBrush -Object $topBorder -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -ColorOrKey "BorderBrush"
        $top = [System.Windows.Controls.Grid]::new()
        foreach ($width in @("Auto", "360", "Auto", "Auto", "*")) {
            $col = [System.Windows.Controls.ColumnDefinition]::new()
            $col.Width = if ($width -eq "*") { [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) } elseif ($width -eq "Auto") { [System.Windows.GridLength]::Auto } else { [System.Windows.GridLength]::new([double]$width) }
            [void]$top.ColumnDefinitions.Add($col)
        }
        $label = [System.Windows.Controls.TextBlock]::new()
        $label.Text = "Search:"
        $label.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $label.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
        $label.FontWeight = [System.Windows.FontWeights]::SemiBold
        Set-WmtThemedBrush -Object $label -Property ([System.Windows.Controls.TextBlock]::ForegroundProperty) -ColorOrKey "TextPrimary"
        [void]$top.Children.Add($label)

        $search = [System.Windows.Controls.TextBox]::new()
        $search.Height = 34
        $search.FocusVisualStyle = $null
        $search.VerticalContentAlignment = [System.Windows.VerticalAlignment]::Center
        [System.Windows.Controls.Grid]::SetColumn($search, 1)
        [void]$top.Children.Add($search)

        $clear = [System.Windows.Controls.Button]::new()
        $clear.Content = "Clear"
        $clear.Height = 32
        $clear.MinWidth = 72
        $clear.Margin = [System.Windows.Thickness]::new(8, 0, 12, 0)
        $clear.FocusVisualStyle = $null
        Set-StartupButtonRole -Button $clear -Role "Standard"
        [System.Windows.Controls.Grid]::SetColumn($clear, 2)
        [void]$top.Children.Add($clear)

        $count = [System.Windows.Controls.TextBlock]::new()
        $count.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $count.Text = "0 items"
        Set-WmtThemedBrush -Object $count -Property ([System.Windows.Controls.TextBlock]::ForegroundProperty) -ColorOrKey "TextSecondary"
        [System.Windows.Controls.Grid]::SetColumn($count, 3)
        [void]$top.Children.Add($count)
        $topBorder.Child = $top
        [System.Windows.Controls.Grid]::SetRow($topBorder, 0)
        [void]$root.Children.Add($topBorder)

        $grid = [System.Windows.Controls.DataGrid]::new()
        $grid.IsReadOnly = $true
        $grid.CanUserAddRows = $false
        $grid.CanUserDeleteRows = $false
        $grid.SelectionMode = [System.Windows.Controls.DataGridSelectionMode]::Extended
        $grid.SelectionUnit = [System.Windows.Controls.DataGridSelectionUnit]::FullRow
        $grid.AlternationCount = 2
        $grid.BorderThickness = [System.Windows.Thickness]::new(0)
        $grid.FocusVisualStyle = $null
        $grid.HeadersVisibility = [System.Windows.Controls.DataGridHeadersVisibility]::Column
        $grid.GridLinesVisibility = [System.Windows.Controls.DataGridGridLinesVisibility]::Horizontal
        Set-WmtThemedBrush -Object $grid -Property ([System.Windows.Controls.Control]::BackgroundProperty) -ColorOrKey "BgDark"
        Set-WmtThemedBrush -Object $grid -Property ([System.Windows.Controls.Control]::ForegroundProperty) -ColorOrKey "TextPrimary"
        Set-WmtThemedBrush -Object $grid -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -ColorOrKey "BorderBrush"
        [System.Windows.Controls.Grid]::SetRow($grid, 1)
        [void]$root.Children.Add($grid)

        $bottomBorder = [System.Windows.Controls.Border]::new()
        $bottomBorder.Padding = [System.Windows.Thickness]::new(14, 12, 14, 12)
        $bottomBorder.BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0)
        Set-WmtThemedBrush -Object $bottomBorder -Property ([System.Windows.Controls.Border]::BackgroundProperty) -ColorOrKey "BgPanel"
        Set-WmtThemedBrush -Object $bottomBorder -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -ColorOrKey "BorderBrush"
        $buttons = [System.Windows.Controls.WrapPanel]::new()
        $buttons.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
        $bottomBorder.Child = $buttons
        [System.Windows.Controls.Grid]::SetRow($bottomBorder, 2)
        [void]$root.Children.Add($bottomBorder)

        $grid.Add_PreviewMouseRightButtonDown({
                param($eventSource, $e)
                $row = Get-WmtVisualAncestor -Element $e.OriginalSource -AncestorType ([System.Windows.Controls.DataGridRow])
                if ($row) {
                    if (-not $row.IsSelected) {
                        $eventSource.SelectedItems.Clear()
                        $row.IsSelected = $true
                    }
                    try { $row.Focus() | Out-Null } catch {}
                }
            }.GetNewClosure())

        $obj = [PSCustomObject]@{ Header = $Title; Root = $root; Grid = $grid; SearchBox = $search; CountLabel = $count; ClearButton = $clear; Buttons = $buttons; Meta = $null }
        $tabs[$Title] = $obj
        return $obj
    }

    function Set-StartupTabData {
        param($TabObj, [System.Data.DataTable]$DataTable, [string[]]$SearchColumns, [string[]]$Hidden = @(), [hashtable]$Widths = @{})
        $TabObj.Grid.ItemsSource = $DataTable.DefaultView
        Set-WmtDataGridColumns -DataGrid $TabObj.Grid -Columns @($DataTable.Columns | ForEach-Object { $_.ColumnName }) -Widths $Widths -Hidden $Hidden
        $TabObj.Meta = [PSCustomObject]@{ Table = $DataTable; View = $DataTable.DefaultView; SearchColumns = $SearchColumns }
        $TabObj.CountLabel.Text = "$($DataTable.Rows.Count) items"
    }

    function Update-StartupTabFilter {
        param($TabObj)
        if (-not $TabObj -or -not $TabObj.Meta) { return }
        $q = $TabObj.SearchBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($q)) {
            $TabObj.Meta.View.RowFilter = ""
            $TabObj.CountLabel.Text = "$($TabObj.Meta.Table.Rows.Count) items"
            return
        }
        $safe = $q.Replace("'", "''").Replace("[", "[[]").Replace("%", "[%]").Replace("*", "[*]")
        $clauses = @()
        foreach ($col in $TabObj.Meta.SearchColumns) {
            if ($TabObj.Meta.Table.Columns.Contains($col)) { $clauses += "CONVERT([$col], 'System.String') LIKE '%$safe%'" }
        }
        try { $TabObj.Meta.View.RowFilter = ($clauses -join " OR ") } catch { $TabObj.Meta.View.RowFilter = "" }
        $TabObj.CountLabel.Text = "$($TabObj.Meta.View.Count) shown / $($TabObj.Meta.Table.Rows.Count) total"
    }

    function Show-StartupRowDetails {
        param($TabObj, [string]$Title)

        $selectedRows = @(Get-WmtDataGridSelectedRows -DataGrid $TabObj.Grid)
        if ($selectedRows.Count -eq 0) {
            Show-WmtMessageBox -Owner $dialog -Message "Select one startup entry first." -Title "Startup Manager" -Image Information | Out-Null
            return
        }

        $row = $selectedRows | Select-Object -First 1
        $tabName = [string]$TabObj.Header

        function Get-StartupCellValue {
            param($Row, [string]$Name)
            try {
                if ($Row -is [System.Data.DataRow]) {
                    if ($Row.Table.Columns.Contains($Name)) { return [string]$Row[$Name] }
                }
                elseif ($Row -is [System.Data.DataRowView]) {
                    if ($Row.Row.Table.Columns.Contains($Name)) { return [string]$Row.Row[$Name] }
                }
                elseif ($Row -is [System.Collections.IDictionary]) {
                    if ($Row.Contains($Name)) { return [string]$Row[$Name] }
                }
                else {
                    $prop = $Row.PSObject.Properties[$Name]
                    if ($prop) { return [string]$prop.Value }
                }
            }
            catch {}
            return ""
        }

        function Set-StartupCellValue {
            param($Row, [string]$Name, [string]$Value)
            try {
                if ($Row -is [System.Data.DataRow]) {
                    if ($Row.Table.Columns.Contains($Name)) { $Row[$Name] = $Value }
                }
                elseif ($Row -is [System.Data.DataRowView]) {
                    if ($Row.Row.Table.Columns.Contains($Name)) { $Row.Row[$Name] = $Value }
                }
                elseif ($Row -is [System.Collections.IDictionary]) {
                    $Row[$Name] = $Value
                }
                else {
                    $prop = $Row.PSObject.Properties[$Name]
                    if ($prop) { $prop.Value = $Value }
                }
            }
            catch {}
        }

        function Set-StartupEditorVisibility {
            param([object[]]$Controls, [bool]$Visible)
            $visibility = if ($Visible) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
            foreach ($control in @($Controls)) {
                try { if ($control) { $control.Visibility = $visibility } } catch {}
            }
        }

        function Split-WmtStartupCommandLine {
            param([string]$CommandLine)
            $cmd = ([string]$CommandLine).Trim()
            if ([string]::IsNullOrWhiteSpace($cmd)) { return [PSCustomObject]@{ Target = ""; Arguments = "" } }
            if ($cmd.StartsWith('"')) {
                $closingQuote = $cmd.IndexOf('"', 1)
                if ($closingQuote -gt 1) {
                    return [PSCustomObject]@{
                        Target    = $cmd.Substring(1, $closingQuote - 1)
                        Arguments = $cmd.Substring($closingQuote + 1).Trim()
                    }
                }
            }
            $exeMatch = [regex]::Match($cmd, '^(?<target>.+?\.exe)(?<args>\s+.*)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($exeMatch.Success) {
                return [PSCustomObject]@{
                    Target    = $exeMatch.Groups['target'].Value.Trim()
                    Arguments = $exeMatch.Groups['args'].Value.Trim()
                }
            }
            $firstSpace = $cmd.IndexOf(' ')
            if ($firstSpace -gt 0) {
                return [PSCustomObject]@{
                    Target    = $cmd.Substring(0, $firstSpace).Trim()
                    Arguments = $cmd.Substring($firstSpace + 1).Trim()
                }
            }
            return [PSCustomObject]@{ Target = $cmd; Arguments = "" }
        }

        function Get-WmtShortcutCommandLine {
            param([string]$ShortcutPath)
            if ([string]::IsNullOrWhiteSpace($ShortcutPath) -or -not $ShortcutPath.EndsWith(".lnk", [System.StringComparison]::OrdinalIgnoreCase) -or -not [System.IO.File]::Exists($ShortcutPath)) { return "" }
            $shell = $null
            try {
                $shell = New-Object -ComObject WScript.Shell
                $shortcut = $shell.CreateShortcut($ShortcutPath)
                $target = [string]$shortcut.TargetPath
                $arguments = [string]$shortcut.Arguments
                if ([string]::IsNullOrWhiteSpace($target)) { return "" }
                if ($target -match '\s') { $target = '"{0}"' -f $target }
                return (($target, $arguments) -join " ").Trim()
            }
            catch { return "" }
            finally { try { if ($shell) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) } } catch {} }
        }

        function Set-WmtShortcutCommandLine {
            param([string]$ShortcutPath, [string]$CommandLine)
            if ([string]::IsNullOrWhiteSpace($ShortcutPath) -or -not $ShortcutPath.EndsWith(".lnk", [System.StringComparison]::OrdinalIgnoreCase)) { return }
            if (-not [System.IO.File]::Exists($ShortcutPath)) { throw "Shortcut file was not found: $ShortcutPath" }
            $parts = Split-WmtStartupCommandLine $CommandLine
            if ([string]::IsNullOrWhiteSpace([string]$parts.Target)) { throw "Shortcut target cannot be blank." }
            $shell = $null
            try {
                $shell = New-Object -ComObject WScript.Shell
                $shortcut = $shell.CreateShortcut($ShortcutPath)
                $shortcut.TargetPath = [string]$parts.Target
                $shortcut.Arguments = [string]$parts.Arguments
                $expandedTarget = [Environment]::ExpandEnvironmentVariables(([string]$parts.Target).Trim('"'))
                if ([System.IO.File]::Exists($expandedTarget)) {
                    $targetDir = [System.IO.Path]::GetDirectoryName($expandedTarget)
                    if (-not [string]::IsNullOrWhiteSpace($targetDir) -and [System.IO.Directory]::Exists($targetDir)) { $shortcut.WorkingDirectory = $targetDir }
                }
                $shortcut.Save()
            }
            finally { try { if ($shell) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) } } catch {} }
        }

        function Get-WmtRegistryDefaultValue {
            param([string]$Path)
            try {
                if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
                    $key = Get-Item -LiteralPath $Path -ErrorAction Stop
                    return [string]$key.GetValue("")
                }
            }
            catch {}
            return ""
        }

        function Set-WmtRegistryDefaultValue {
            param([string]$Path, [string]$Value)
            if ([string]::IsNullOrWhiteSpace($Path)) { return }
            if (-not (Test-Path -LiteralPath $Path)) { throw "Registry key was not found: $Path" }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            $key.SetValue("", [string]$Value)
        }

        $content = @'
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Margin="0,0,0,12">
            <TextBlock Name="lblHeading" FontSize="18" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}"/>
            <TextBlock Name="lblHint" Margin="0,4,0,0" TextWrapping="Wrap" Foreground="{DynamicResource TextSecondary}"/>
        </StackPanel>

        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="140"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <TextBlock Name="lblName" Grid.Row="0" Grid.Column="0" Text="Name" Margin="0,0,12,10" VerticalAlignment="Center" Foreground="{DynamicResource TextSecondary}"/>
                <TextBox Name="txtName" Grid.Row="0" Grid.Column="1" Height="34" Margin="0,0,0,10" VerticalContentAlignment="Center"/>

                <TextBlock Name="lblDisplayName" Grid.Row="1" Grid.Column="0" Text="Display name" Margin="0,0,12,10" VerticalAlignment="Center" Foreground="{DynamicResource TextSecondary}"/>
                <TextBox Name="txtDisplayName" Grid.Row="1" Grid.Column="1" Height="34" Margin="0,0,0,10" VerticalContentAlignment="Center"/>

                <TextBlock Name="lblCommand" Grid.Row="2" Grid.Column="0" Text="Command" Margin="0,0,12,10" VerticalAlignment="Top" Foreground="{DynamicResource TextSecondary}"/>
                <TextBox Name="txtCommand" Grid.Row="2" Grid.Column="1" Height="96" Margin="0,0,0,10" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>

                <TextBlock Name="lblLocation" Grid.Row="3" Grid.Column="0" Text="Location" Margin="0,0,12,10" VerticalAlignment="Center" Foreground="{DynamicResource TextSecondary}"/>
                <TextBox Name="txtLocation" Grid.Row="3" Grid.Column="1" Height="34" Margin="0,0,0,10" IsReadOnly="True" VerticalContentAlignment="Center"/>

                <TextBlock Name="lblValueName" Grid.Row="4" Grid.Column="0" Text="Value / path" Margin="0,0,12,10" VerticalAlignment="Center" Foreground="{DynamicResource TextSecondary}"/>
                <TextBox Name="txtValueName" Grid.Row="4" Grid.Column="1" Height="34" Margin="0,0,0,10" IsReadOnly="True" VerticalContentAlignment="Center"/>

                <TextBlock Name="lblStartupType" Grid.Row="5" Grid.Column="0" Text="Startup type" Margin="0,0,12,10" VerticalAlignment="Center" Foreground="{DynamicResource TextSecondary}"/>
                <ComboBox Name="cboStartupType" Grid.Row="5" Grid.Column="1" Height="34" Margin="0,0,0,10"/>

                <TextBlock Name="lblEnabled" Grid.Row="6" Grid.Column="0" Text="Enabled" Margin="0,0,12,10" VerticalAlignment="Center" Foreground="{DynamicResource TextSecondary}"/>
                <CheckBox Name="chkEnabled" Grid.Row="6" Grid.Column="1" Margin="0,0,0,10" VerticalAlignment="Center" Content="Enabled" Foreground="{DynamicResource TextPrimary}"/>
            </Grid>
        </ScrollViewer>

        <Grid Grid.Row="2" Margin="0,14,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Name="lblStatus" Grid.Column="0" VerticalAlignment="Center" TextWrapping="Wrap" Foreground="{DynamicResource Warning}"/>
            <WrapPanel Grid.Column="1" HorizontalAlignment="Right">
                <Button Name="btnBrowse" Content="Browse Command" MinWidth="124" Margin="0,0,8,8"/>
                <Button Name="btnOpenLocation" Content="Open Location" MinWidth="112" Margin="0,0,8,8"/>
                <Button Name="btnOpenNative" Content="Open Native Editor" MinWidth="136" Margin="0,0,8,8"/>
                <Button Name="btnSave" Content="Save" MinWidth="94" IsDefault="True" Background="{DynamicResource Success}" Foreground="{DynamicResource SuccessText}" Margin="0,0,8,8"/>
                <Button Name="btnClose" Content="Close" MinWidth="94" IsCancel="True" Margin="0,0,0,8"/>
            </WrapPanel>
        </Grid>
    </Grid>
'@

        $editor = New-WmtWindowFromXaml -Title $Title -ContentXaml $content -Width 820 -Height 560 -MinWidth 680 -MinHeight 460
        try { $editor.Owner = $dialog } catch {}

        $lblHeading = $editor.FindName("lblHeading")
        $lblHint = $editor.FindName("lblHint")
        $lblName = $editor.FindName("lblName")
        $txtName = $editor.FindName("txtName")
        $lblDisplayName = $editor.FindName("lblDisplayName")
        $txtDisplayName = $editor.FindName("txtDisplayName")
        $lblCommand = $editor.FindName("lblCommand")
        $txtCommand = $editor.FindName("txtCommand")
        $lblLocation = $editor.FindName("lblLocation")
        $txtLocation = $editor.FindName("txtLocation")
        $lblValueName = $editor.FindName("lblValueName")
        $txtValueName = $editor.FindName("txtValueName")
        $lblStartupType = $editor.FindName("lblStartupType")
        $cboStartupType = $editor.FindName("cboStartupType")
        $lblEnabled = $editor.FindName("lblEnabled")
        $chkEnabled = $editor.FindName("chkEnabled")
        $lblStatus = $editor.FindName("lblStatus")
        $btnBrowse = $editor.FindName("btnBrowse")
        $btnOpenLocation = $editor.FindName("btnOpenLocation")
        $btnOpenNative = $editor.FindName("btnOpenNative")
        $btnSave = $editor.FindName("btnSave")
        $btnClose = $editor.FindName("btnClose")

        [void]$cboStartupType.Items.Add("Automatic")
        [void]$cboStartupType.Items.Add("Manual")
        [void]$cboStartupType.Items.Add("Disabled")

        $entryType = Get-StartupCellValue $row "Type"
        $itemPath = Get-StartupCellValue $row "ItemPath"
        $valueName = Get-StartupCellValue $row "ValueName"
        $rootRunPath = Get-StartupCellValue $row "RootRunPath"
        $ctxPath = Get-StartupCellValue $row "Path"
        $serviceName = Get-StartupCellValue $row "Name"
        $taskName = Get-StartupCellValue $row "TaskName"
        $taskPath = Get-StartupCellValue $row "Path"

        $lblHeading.Text = "Edit $tabName entry"
        $lblHint.Text = "Changes are written immediately when you press Save. Protected/all-users entries may require running WMT as administrator."
        $txtName.Text = Get-StartupCellValue $row "Name"
        $txtDisplayName.Text = Get-StartupCellValue $row "DisplayName"
        $txtCommand.Text = Get-StartupCellValue $row "Command"
        $txtLocation.Text = Get-StartupCellValue $row "Location"
        $txtValueName.Text = $valueName
        $chkEnabled.IsChecked = ((Get-StartupCellValue $row "Enabled") -ne "No")

        Set-StartupEditorVisibility @($lblDisplayName, $txtDisplayName, $lblStartupType, $cboStartupType, $btnOpenNative) $false
        $btnBrowse.Visibility = [System.Windows.Visibility]::Visible

        switch ($tabName) {
            "Windows" {
                if ($entryType -eq "StartupFolder") {
                    $shortcutCommand = Get-WmtShortcutCommandLine $itemPath
                    if (-not [string]::IsNullOrWhiteSpace($shortcutCommand)) { $txtCommand.Text = $shortcutCommand }
                    $txtValueName.Text = $itemPath
                    $lblCommand.Text = "Shortcut target"
                    $lblValueName.Text = "File path"
                    $lblHint.Text = "For Startup Folder shortcuts, Save can rename the file and update .lnk targets/arguments. Non-shortcut startup files can be renamed here."
                }
                else {
                    $lblCommand.Text = "Run command"
                    $lblValueName.Text = "Registry value"
                    $lblHint.Text = "Edit the Run value name, command, and StartupApproved enabled state. HKLM entries may require administrator rights."
                }
            }
            "Scheduled Tasks" {
                $txtName.Text = $taskName
                $txtName.IsReadOnly = $true
                $txtCommand.Text = "Use the native Task Scheduler editor for actions, triggers, conditions, and arguments. This WMT editor can enable or disable the task."
                $txtCommand.IsReadOnly = $true
                $txtLocation.Text = $taskPath
                $txtValueName.Text = ("{0}{1}" -f $taskPath, $taskName)
                $chkEnabled.IsChecked = ((Get-StartupCellValue $row "State") -ne "Disabled")
                $lblCommand.Text = "Notes"
                $lblLocation.Text = "Task path"
                $lblValueName.Text = "Task identity"
                Set-StartupEditorVisibility @($btnBrowse, $btnOpenNative) $true
                $btnBrowse.Visibility = [System.Windows.Visibility]::Collapsed
                $btnOpenNative.Content = "Open Task Scheduler"
                $lblHint.Text = "Task names/paths are read-only here. Use Save to enable or disable, or open Task Scheduler for advanced edits."
            }
            "Context Menu" {
                $display = Get-WmtRegistryDefaultValue $ctxPath
                if ([string]::IsNullOrWhiteSpace($display)) { $display = Get-StartupCellValue $row "Name" }
                $txtName.Text = $display
                $cmdPath = if ([string]::IsNullOrWhiteSpace($ctxPath)) { "" } else { "$ctxPath\command" }
                $txtCommand.Text = Get-WmtRegistryDefaultValue $cmdPath
                $txtLocation.Text = $ctxPath
                $txtValueName.Text = Get-StartupCellValue $row "KeyName"
                $chkEnabled.IsChecked = ((Get-StartupCellValue $row "Enabled") -ne "No")
                $lblName.Text = "Menu text"
                $lblCommand.Text = "Command"
                $lblLocation.Text = "Registry key"
                $lblValueName.Text = "Key name"
                $lblHint.Text = "Edit the menu text/default value, command subkey, and LegacyDisable enabled state."
            }
            "Services" {
                $txtName.Text = $serviceName
                $txtName.IsReadOnly = $true
                $txtDisplayName.Text = Get-StartupCellValue $row "DisplayName"
                $txtCommand.Text = "Service binary paths are not edited here. Use Registry Editor or sc.exe config for advanced service path changes."
                $txtCommand.IsReadOnly = $true
                $txtLocation.Text = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
                $txtValueName.Text = $serviceName
                $currentStartType = Get-StartupCellValue $row "StartType"
                if (-not (@("Automatic", "Manual", "Disabled") -contains $currentStartType) -and -not [string]::IsNullOrWhiteSpace($currentStartType)) { [void]$cboStartupType.Items.Add($currentStartType) }
                $cboStartupType.SelectedItem = $currentStartType
                Set-StartupEditorVisibility @($lblDisplayName, $txtDisplayName, $lblStartupType, $cboStartupType, $btnOpenNative) $true
                Set-StartupEditorVisibility @($lblEnabled, $chkEnabled, $btnBrowse) $false
                $btnOpenNative.Content = "Open Services"
                $lblName.Text = "Service name"
                $lblCommand.Text = "Notes"
                $lblLocation.Text = "Registry key"
                $lblValueName.Text = "Service name"
                $lblHint.Text = "Edit the service display name and startup type. Service name and binary path are kept read-only for safety."
            }
        }

        $btnBrowse.Add_Click({
                $picker = [Microsoft.Win32.OpenFileDialog]::new()
                $picker.Filter = "Programs and scripts|*.exe;*.bat;*.cmd;*.ps1;*.vbs;*.lnk|All files|*.*"
                $existingParts = Split-WmtStartupCommandLine $txtCommand.Text
                $existingTarget = [Environment]::ExpandEnvironmentVariables(([string]$existingParts.Target).Trim('"'))
                try {
                    if (-not [string]::IsNullOrWhiteSpace($existingTarget) -and [System.IO.File]::Exists($existingTarget)) {
                        $picker.InitialDirectory = [System.IO.Path]::GetDirectoryName($existingTarget)
                        $picker.FileName = [System.IO.Path]::GetFileName($existingTarget)
                    }
                }
                catch {}
                if ($picker.ShowDialog($editor) -eq $true) {
                    $picked = [string]$picker.FileName
                    if ($picked -match '\s') { $picked = '"{0}"' -f $picked }
                    $txtCommand.Text = $picked
                }
            }.GetNewClosure())

        $btnOpenLocation.Add_Click({
                try {
                    switch ($tabName) {
                        "Windows" {
                            if ($entryType -eq "StartupFolder" -and -not [string]::IsNullOrWhiteSpace($itemPath) -and [System.IO.File]::Exists($itemPath)) { Start-Process explorer.exe -ArgumentList ("/select,`"{0}`"" -f $itemPath) }
                            elseif (-not [string]::IsNullOrWhiteSpace($rootRunPath)) { Start-Process regedit.exe }
                        }
                        "Scheduled Tasks" { Start-Process taskschd.msc }
                        "Context Menu" { Start-Process regedit.exe }
                        "Services" { Start-Process services.msc }
                    }
                }
                catch { $lblStatus.Text = "Open failed: $($_.Exception.Message)" }
            }.GetNewClosure())

        $btnOpenNative.Add_Click({
                try {
                    switch ($tabName) {
                        "Scheduled Tasks" { Start-Process taskschd.msc }
                        "Services" { Start-Process services.msc }
                        default { Start-Process regedit.exe }
                    }
                }
                catch { $lblStatus.Text = "Open failed: $($_.Exception.Message)" }
            }.GetNewClosure())

        $btnSave.Add_Click({
                Set-WmtBusyCursor -Busy
                $lblStatus.Text = "Saving..."
                try {
                    switch ($tabName) {
                        "Windows" {
                            $newName = ([string]$txtName.Text).Trim()
                            $newCommand = ([string]$txtCommand.Text).Trim()
                            $enabled = [bool]$chkEnabled.IsChecked
                            if ([string]::IsNullOrWhiteSpace($newName)) { throw "Name cannot be blank." }

                            if ($entryType -eq "Registry") {
                                $runPath = if ([string]::IsNullOrWhiteSpace($rootRunPath)) { $itemPath } else { $rootRunPath }
                                if ([string]::IsNullOrWhiteSpace($runPath)) { throw "Registry path is missing." }
                                if ([string]::IsNullOrWhiteSpace($newCommand)) { throw "Run command cannot be blank." }
                                if (-not (Test-Path -LiteralPath $runPath)) { New-Item -Path $runPath -Force -ErrorAction Stop | Out-Null }
                                Set-ItemProperty -Path $runPath -Name $newName -Value $newCommand -ErrorAction Stop
                                if ($valueName -and $newName -ne $valueName) {
                                    Remove-ItemProperty -Path $runPath -Name $valueName -ErrorAction SilentlyContinue
                                }
                                & $fnSetStartupApprovedState "Registry" $runPath $newName $enabled
                                Set-StartupCellValue $row "Name" $newName
                                Set-StartupCellValue $row "Command" $newCommand
                                Set-StartupCellValue $row "ItemPath" $runPath
                                Set-StartupCellValue $row "ValueName" $newName
                                Set-StartupCellValue $row "RootRunPath" $runPath
                                Set-StartupCellValue $row "Enabled" $(if ($enabled) { "Yes" } else { "No" })
                            }
                            elseif ($entryType -eq "StartupFolder") {
                                if ([string]::IsNullOrWhiteSpace($itemPath) -or -not [System.IO.File]::Exists($itemPath)) { throw "Startup folder item was not found." }
                                $directory = [System.IO.Path]::GetDirectoryName($itemPath)
                                $extension = [System.IO.Path]::GetExtension($itemPath)
                                if ([string]::IsNullOrWhiteSpace($extension)) { $extension = ".lnk" }
                                $newFileName = $newName
                                if ([System.IO.Path]::GetExtension($newFileName) -eq "") { $newFileName = "$newFileName$extension" }
                                if ($newFileName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) { throw "Name contains invalid file-name characters." }
                                $newPath = Join-Path $directory $newFileName
                                if ($newPath -ne $itemPath) {
                                    Move-Item -LiteralPath $itemPath -Destination $newPath -Force -ErrorAction Stop
                                    $itemPath = $newPath
                                    $valueName = [System.IO.Path]::GetFileName($newPath)
                                }
                                if ($itemPath.EndsWith(".lnk", [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace($newCommand)) {
                                    Set-WmtShortcutCommandLine -ShortcutPath $itemPath -CommandLine $newCommand
                                }
                                & $fnSetStartupApprovedState "StartupFolder" $directory ([System.IO.Path]::GetFileName($itemPath)) $enabled
                                Set-StartupCellValue $row "Name" ([System.IO.Path]::GetFileNameWithoutExtension($itemPath))
                                Set-StartupCellValue $row "Command" $(if ($itemPath.EndsWith(".lnk", [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace($newCommand)) { $newCommand } else { $itemPath })
                                Set-StartupCellValue $row "Location" $directory
                                Set-StartupCellValue $row "ItemPath" $itemPath
                                Set-StartupCellValue $row "ValueName" ([System.IO.Path]::GetFileName($itemPath))
                                Set-StartupCellValue $row "RootRunPath" $directory
                                Set-StartupCellValue $row "Enabled" $(if ($enabled) { "Yes" } else { "No" })
                            }
                        }
                        "Scheduled Tasks" {
                            if ([string]::IsNullOrWhiteSpace($taskName)) { throw "Task name is missing." }
                            if ([bool]$chkEnabled.IsChecked) {
                                Enable-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction Stop | Out-Null
                                Set-StartupCellValue $row "State" "Ready"
                            }
                            else {
                                Disable-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction Stop | Out-Null
                                Set-StartupCellValue $row "State" "Disabled"
                            }
                        }
                        "Context Menu" {
                            if ([string]::IsNullOrWhiteSpace($ctxPath)) { throw "Registry key is missing." }
                            $newDisplayName = ([string]$txtName.Text).Trim()
                            $newCommand = ([string]$txtCommand.Text).Trim()
                            if (-not (Test-Path -LiteralPath $ctxPath)) { throw "Registry key was not found." }
                            if (-not [string]::IsNullOrWhiteSpace($newDisplayName)) {
                                Set-WmtRegistryDefaultValue -Path $ctxPath -Value $newDisplayName
                                Set-ItemProperty -LiteralPath $ctxPath -Name "MUIVerb" -Value $newDisplayName -ErrorAction SilentlyContinue
                                Set-StartupCellValue $row "Name" $newDisplayName
                            }
                            if (-not [string]::IsNullOrWhiteSpace($newCommand)) {
                                Set-WmtRegistryDefaultValue -Path "$ctxPath\command" -Value $newCommand
                            }
                            if ([bool]$chkEnabled.IsChecked) {
                                Remove-ItemProperty -LiteralPath $ctxPath -Name "LegacyDisable" -ErrorAction SilentlyContinue
                                Set-StartupCellValue $row "Enabled" "Yes"
                            }
                            else {
                                Set-ItemProperty -LiteralPath $ctxPath -Name "LegacyDisable" -Value "" -ErrorAction Stop
                                Set-StartupCellValue $row "Enabled" "No"
                            }
                        }
                        "Services" {
                            if ([string]::IsNullOrWhiteSpace($serviceName)) { throw "Service name is missing." }
                            $newDisplayName = ([string]$txtDisplayName.Text).Trim()
                            $newStartType = [string]$cboStartupType.SelectedItem
                            if (-not [string]::IsNullOrWhiteSpace($newDisplayName)) {
                                Set-Service -Name $serviceName -DisplayName $newDisplayName -ErrorAction Stop
                                Set-StartupCellValue $row "DisplayName" $newDisplayName
                            }
                            if (@("Automatic", "Manual", "Disabled") -contains $newStartType) {
                                Set-Service -Name $serviceName -StartupType $newStartType -ErrorAction Stop
                                Set-StartupCellValue $row "StartType" $newStartType
                            }
                        }
                    }
                    try { $TabObj.Grid.Items.Refresh() } catch {}
                    & $fnUpdateStartupTabFilter $TabObj
                    $lblStatus.Text = "Saved."
                    $editor.DialogResult = $true
                }
                catch {
                    $lblStatus.Text = "Save failed: $($_.Exception.Message)"
                    Show-WmtMessageBox -Owner $editor -Message "Could not save changes.`n$($_.Exception.Message)" -Title "Startup Manager" -Image Error | Out-Null
                }
                finally { Set-WmtBusyCursor }
            }.GetNewClosure())

        $btnClose.Add_Click({ $editor.Close() }.GetNewClosure())
        $editor.ShowDialog() | Out-Null
    }

    function Remove-WmtDataRows {
        param($TabObj, [object[]]$Rows)
        foreach ($row in @($Rows)) { try { $row.Delete() } catch {} }
        $TabObj.Meta.Table.AcceptChanges()
        & $fnUpdateStartupTabFilter $TabObj
    }

    function Get-StartupApprovedState {
        param([string]$Type, [string]$RootPath, [string]$ValueName)
        $approvedPath = if ($Type -eq "Registry") {
            if ($RootPath -match "(?i)WOW6432Node") { $RootPath -replace "(?i)WOW6432Node\\", "" -replace "(?i)CurrentVersion\\Run", "CurrentVersion\Explorer\StartupApproved\Run32" }
            else { $RootPath -replace "(?i)CurrentVersion\\Run", "CurrentVersion\Explorer\StartupApproved\Run" }
        }
        else {
            if ($RootPath -match "(?i)Roaming") { "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder" }
            else { "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder" }
        }
        if ($approvedPath -and (Test-Path $approvedPath)) {
            $val = Get-ItemProperty -Path $approvedPath -ErrorAction SilentlyContinue
            if ($null -ne $val.$ValueName) { return ($val.$ValueName[0] % 2 -eq 0) }
        }
        return $true
    }

    function Set-StartupApprovedState {
        param([string]$Type, [string]$RootPath, [string]$ValueName, [bool]$Enable)
        $approvedPath = if ($Type -eq "Registry") {
            if ($RootPath -match "(?i)WOW6432Node") { $RootPath -replace "(?i)WOW6432Node\\", "" -replace "(?i)CurrentVersion\\Run", "CurrentVersion\Explorer\StartupApproved\Run32" }
            else { $RootPath -replace "(?i)CurrentVersion\\Run", "CurrentVersion\Explorer\StartupApproved\Run" }
        }
        else {
            if ($RootPath -match "(?i)Roaming") { "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder" }
            else { "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder" }
        }
        if (-not (Test-Path $approvedPath)) { New-Item -Path $approvedPath -Force | Out-Null }
        $stateByte = if ($Enable) { [byte]0x02 } else { [byte]0x03 }
        $payload = [byte[]]($stateByte, 0x00, 0x00, 0x00) + [BitConverter]::GetBytes([DateTime]::Now.ToFileTime())
        Set-ItemProperty -Path $approvedPath -Name $ValueName -Value $payload -Type Binary -ErrorAction SilentlyContinue
    }

    function Get-RegRunEntries {
        param([string]$Path, [string]$Scope)
        $items = @()
        if (-not (Test-Path $Path)) { return $items }
        $props = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
        if (-not $props) { return $items }
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -in @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider")) { continue }
            $items += [PSCustomObject]@{
                Name        = $p.Name
                Command     = "$($p.Value)"
                Location    = $Path
                EntryType   = "Registry"
                Scope       = $Scope
                Enabled     = (& $fnGetStartupApprovedState "Registry" $Path $p.Name)
                ItemPath    = $Path
                ValueName   = $p.Name
                RootRunPath = $Path
            }
        }
        return $items
    }

    function Get-StartupFolderEntries {
        param([string]$Path, [string]$Scope)
        $items = @()
        if (-not (Test-Path $Path)) { return $items }
        foreach ($filePath in Get-WmtEnumeratedFiles -Path $Path) {
            $file = [System.IO.FileInfo]::new($filePath)
            $items += [PSCustomObject]@{
                Name        = $file.BaseName
                Command     = $file.FullName
                Location    = $Path
                EntryType   = "StartupFolder"
                Scope       = $Scope
                Enabled     = (& $fnGetStartupApprovedState "StartupFolder" $Path $file.Name)
                ItemPath    = $file.FullName
                ValueName   = $file.Name
                RootRunPath = $Path
            }
        }
        return $items
    }

    function Add-GridContextMenu {
        param($TabObj, [System.Windows.Controls.Button[]]$Buttons)
        $menu = [System.Windows.Controls.ContextMenu]::new()
        Set-WmtContextMenuChrome -ContextMenu $menu
        foreach ($button in @($Buttons)) {
            $item = [System.Windows.Controls.MenuItem]::new()
            $item.Header = [string]$button.Content
            $item.Tag = $button
            $item.Add_Click({
                    param($eventSource, $e)
                    $button = [System.Windows.Controls.Button]$eventSource.Tag
                    $button.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, $button))
                }.GetNewClosure())
            [void]$menu.Items.Add($item)
        }
        $TabObj.Grid.ContextMenu = $menu
    }

    function Invoke-StartupWindowsLoad {
        $items = @()
        $items += & $fnGetRegRunEntries "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" "Current User"
        $items += & $fnGetRegRunEntries "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" "All Users"
        $items += & $fnGetRegRunEntries "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" "All Users (32-bit)"
        $items += & $fnGetStartupFolderEntries "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" "Current User"
        $items += & $fnGetStartupFolderEntries "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup" "All Users"

        $table = [System.Data.DataTable]::new()
        foreach ($name in @("Name", "Enabled", "Scope", "Type", "Command", "Location", "ItemPath", "ValueName", "RootRunPath")) { [void]$table.Columns.Add($name) }
        foreach ($item in @($items)) {
            $row = $table.NewRow()
            $row["Name"] = [string]$item.Name
            $row["Enabled"] = if ([bool]$item.Enabled) { "Yes" } else { "No" }
            $row["Scope"] = [string]$item.Scope
            $row["Type"] = [string]$item.EntryType
            $row["Command"] = [string]$item.Command
            $row["Location"] = [string]$item.Location
            $row["ItemPath"] = [string]$item.ItemPath
            $row["ValueName"] = [string]$item.ValueName
            $row["RootRunPath"] = [string]$item.RootRunPath
            [void]$table.Rows.Add($row)
        }
        & $fnSetStartupTabData $winTab $table @("Name", "Enabled", "Scope", "Type", "Command", "Location") @("Command", "Location", "ItemPath", "ValueName", "RootRunPath") @{ Name = "44*"; Enabled = "12*"; Scope = "24*"; Type = "20*" }
        & $fnUpdateStartupTabFilter $winTab
    }

    function Invoke-StartupTasksLoad {
        $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Select-Object TaskName, TaskPath, State)
        $table = [System.Data.DataTable]::new()
        foreach ($name in @("TaskName", "Path", "State")) { [void]$table.Columns.Add($name) }
        foreach ($task in @($tasks)) {
            $row = $table.NewRow()
            $row["TaskName"] = [string]$task.TaskName
            $row["Path"] = [string]$task.TaskPath
            $row["State"] = [string]$task.State
            [void]$table.Rows.Add($row)
        }
        & $fnSetStartupTabData $taskTab $table @("TaskName", "Path", "State") @() @{ TaskName = "*"; Path = 260; State = 120 }
        & $fnUpdateStartupTabFilter $taskTab
    }

    function Invoke-StartupContextMenuLoad {
        if (-not (Get-PSDrive HKCR -ErrorAction SilentlyContinue)) { New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -ErrorAction SilentlyContinue | Out-Null }
        $table = [System.Data.DataTable]::new()
        foreach ($name in @("Name", "Enabled", "Root", "Path", "KeyName")) { [void]$table.Columns.Add($name) }
        foreach ($rootInfo in @(
                @{ Path = "HKCR:\*\shell"; RootName = "All Files (*)" },
                @{ Path = "HKCR:\Directory\shell"; RootName = "Directory" },
                @{ Path = "HKCR:\Directory\Background\shell"; RootName = "Directory Background" },
                @{ Path = "HKCR:\Drive\shell"; RootName = "Drive" }
            )) {
            if (-not (Test-Path -LiteralPath $rootInfo.Path -ErrorAction SilentlyContinue)) { continue }
            foreach ($subKey in @(Get-ChildItem -LiteralPath $rootInfo.Path -ErrorAction SilentlyContinue)) {
                $row = $table.NewRow()
                $row["Name"] = [string]$subKey.PSChildName
                $row["Enabled"] = if ($null -ne (Get-ItemProperty -LiteralPath $subKey.PSPath -Name "LegacyDisable" -ErrorAction SilentlyContinue)) { "No" } else { "Yes" }
                $row["Root"] = [string]$rootInfo.RootName
                $row["Path"] = [string]$subKey.PSPath
                $row["KeyName"] = [string]$subKey.Name
                [void]$table.Rows.Add($row)
            }
        }
        & $fnSetStartupTabData $ctxTab $table @("Name", "Enabled", "Root", "KeyName") @("Path", "KeyName") @{ Name = "68*"; Enabled = "12*"; Root = "20*" }
        & $fnUpdateStartupTabFilter $ctxTab
    }

    function Invoke-StartupServicesLoad {
        $table = [System.Data.DataTable]::new()
        foreach ($name in @("Name", "DisplayName", "StartType", "State")) { [void]$table.Columns.Add($name) }
        foreach ($service in @(Get-Service -ErrorAction SilentlyContinue | Sort-Object DisplayName)) {
            $startType = "Unknown"
            try {
                $rawStart = (Get-ItemProperty -Path ("HKLM:\SYSTEM\CurrentControlSet\Services\" + $service.Name) -Name Start -ErrorAction SilentlyContinue).Start
                switch ($rawStart) {
                    0 { $startType = "Boot" }
                    1 { $startType = "System" }
                    2 { $startType = "Automatic" }
                    3 { $startType = "Manual" }
                    4 { $startType = "Disabled" }
                    default { if ($null -ne $rawStart) { $startType = [string]$rawStart } }
                }
            }
            catch {}
            $row = $table.NewRow()
            $row["Name"] = [string]$service.Name
            $row["DisplayName"] = [string]$service.DisplayName
            $row["StartType"] = [string]$startType
            $row["State"] = [string]$service.Status
            [void]$table.Rows.Add($row)
        }
        & $fnSetStartupTabData $svcTab $table @("Name", "DisplayName", "StartType", "State") @() @{ DisplayName = "56*"; Name = "24*"; StartType = "10*"; State = "10*" }
        & $fnUpdateStartupTabFilter $svcTab
    }

    function Invoke-StartupTabLoad {
        param([string]$TabName, [bool]$Force = $false)
        if (-not $Force -and $tabLoaded.ContainsKey($TabName) -and $tabLoaded[$TabName]) { return }
        Set-WmtBusyCursor -Busy
        try {
            switch ($TabName) {
                "Windows" { & $LoadWindowsStartup }
                "Scheduled Tasks" { & $LoadScheduledTasks }
                "Context Menu" { & $LoadContextMenu }
                "Services" { & $LoadServices }
            }
            if ($tabLoaded.ContainsKey($TabName)) { $tabLoaded[$TabName] = $true }
        }
        catch {
            Show-WmtMessageBox -Owner $dialog -Message "Failed to load tab '$TabName'.`n$($_.Exception.Message)" -Title "Startup Manager" -Image Error | Out-Null
        }
        finally {
            Set-WmtBusyCursor
        }
    }

    function Set-StartupView {
        param([string]$Title)
        foreach ($key in @($tabs.Keys)) {
            $tabs[$key].Root.Visibility = if ($key -eq $Title) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        }
        & $fnSetTabButtonActive $Title
        & $fnInvokeStartupTabLoad $Title $false
    }

    function Invoke-WmtStartupTaskSelection {
        param([ValidateSet("Enable", "Disable", "Delete")][string]$Action)

        $selected = @(Get-WmtDataGridSelectedRows -DataGrid $taskTab.Grid)
        if ($selected.Count -eq 0) { return }
        if ($Action -eq "Delete") {
            $confirm = Show-WmtMessageBox -Owner $dialog -Message "Delete $($selected.Count) selected scheduled task(s)?" -Title "Confirm" -Button YesNo -Image Warning
            if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }
        }

        Set-WmtBusyCursor -Busy
        $failures = @()
        try {
            foreach ($row in $selected) {
                $name = [string]$row["TaskName"]
                $path = [string]$row["Path"]
                $result = Invoke-WmtScheduledTaskAction -Action $Action -TaskName $name -TaskPath $path
                if ($result.Success) {
                    if ($Action -eq "Enable") { $row["State"] = "Ready" }
                    elseif ($Action -eq "Disable") { $row["State"] = "Disabled" }
                    elseif ($Action -eq "Delete") { $row.Delete() }
                }
                else {
                    $failures += "$($result.Task): $($result.Message)"
                }
            }
            if ($Action -eq "Delete") { $taskTab.Meta.Table.AcceptChanges() }
            & $fnUpdateStartupTabFilter $taskTab
        }
        finally {
            Set-WmtBusyCursor
        }

        if ($failures.Count -gt 0) {
            Show-WmtMessageBox -Owner $dialog -Message ($failures -join "`r`n") -Title "Scheduled Tasks" -Image Warning | Out-Null
        }
    }

    $btnWinTab = New-TabButton "Windows"
    $btnTaskTab = New-TabButton "Scheduled Tasks"
    $btnCtxTab = New-TabButton "Context Menu"
    $btnSvcTab = New-TabButton "Services"

    $winTab = New-StartupPage "Windows"
    $taskTab = New-StartupPage "Scheduled Tasks"
    $ctxTab = New-StartupPage "Context Menu"
    $svcTab = New-StartupPage "Services"

    $fnSetTabButtonActive = ${function:Set-TabButtonActive}.GetNewClosure()
    $fnSetStartupTabData = ${function:Set-StartupTabData}.GetNewClosure()
    $fnUpdateStartupTabFilter = ${function:Update-StartupTabFilter}.GetNewClosure()
    $fnShowStartupRowDetails = ${function:Show-StartupRowDetails}.GetNewClosure()
    $fnGetStartupApprovedState = ${function:Get-StartupApprovedState}.GetNewClosure()
    $fnSetStartupApprovedState = ${function:Set-StartupApprovedState}.GetNewClosure()
    $fnRemoveWmtDataRows = ${function:Remove-WmtDataRows}.GetNewClosure()
    $fnGetRegRunEntries = ${function:Get-RegRunEntries}.GetNewClosure()
    $fnGetStartupFolderEntries = ${function:Get-StartupFolderEntries}.GetNewClosure()
    $LoadWindowsStartup = ${function:Invoke-StartupWindowsLoad}.GetNewClosure()
    $LoadScheduledTasks = ${function:Invoke-StartupTasksLoad}.GetNewClosure()
    $LoadContextMenu = ${function:Invoke-StartupContextMenuLoad}.GetNewClosure()
    $LoadServices = ${function:Invoke-StartupServicesLoad}.GetNewClosure()
    $fnInvokeStartupTabLoad = ${function:Invoke-StartupTabLoad}.GetNewClosure()
    $fnSetStartupView = ${function:Set-StartupView}.GetNewClosure()
    $fnInvokeStartupTaskSelection = ${function:Invoke-WmtStartupTaskSelection}.GetNewClosure()

    $btnWinTab.Add_Click({ & $fnSetStartupView "Windows" }.GetNewClosure())
    $btnTaskTab.Add_Click({ & $fnSetStartupView "Scheduled Tasks" }.GetNewClosure())
    $btnCtxTab.Add_Click({ & $fnSetStartupView "Context Menu" }.GetNewClosure())
    $btnSvcTab.Add_Click({ & $fnSetStartupView "Services" }.GetNewClosure())

    foreach ($t in @($winTab, $taskTab, $ctxTab, $svcTab)) {
        $t.SearchBox.Tag = $t
        $t.Grid.Tag = $t
        $t.ClearButton.Tag = $t
        $t.SearchBox.Add_TextChanged({
                param($eventSource, $e)
                & $fnUpdateStartupTabFilter $eventSource.Tag
            }.GetNewClosure())
        $t.ClearButton.Add_Click({
                param($eventSource, $e)
                $eventSource.Tag.SearchBox.Text = ""
            }.GetNewClosure())
        $t.Grid.Add_MouseDoubleClick({
                param($eventSource, $e)
                & $fnShowStartupRowDetails $eventSource.Tag "$($eventSource.Tag.Header) Details"
            }.GetNewClosure())
    }

    $btnWinRefresh = New-StartupButton $winTab.Buttons "Refresh" "Standard"
    $btnWinDetails = New-StartupButton $winTab.Buttons "Details" "Standard"
    $btnWinEnable = New-StartupButton $winTab.Buttons "Enable" "Success"
    $btnWinDisable = New-StartupButton $winTab.Buttons "Disable" "Warning"
    $btnWinDelete = New-StartupButton $winTab.Buttons "Delete" "Danger"
    Add-GridContextMenu -TabObj $winTab -Buttons @($btnWinRefresh, $btnWinDetails, $btnWinEnable, $btnWinDisable, $btnWinDelete)

    $btnTaskRefresh = New-StartupButton $taskTab.Buttons "Refresh" "Standard"
    $btnTaskDetails = New-StartupButton $taskTab.Buttons "Details" "Standard"
    $btnTaskEnable = New-StartupButton $taskTab.Buttons "Enable" "Success"
    $btnTaskDisable = New-StartupButton $taskTab.Buttons "Disable" "Warning"
    $btnTaskDelete = New-StartupButton $taskTab.Buttons "Delete" "Danger"
    Add-GridContextMenu -TabObj $taskTab -Buttons @($btnTaskRefresh, $btnTaskDetails, $btnTaskEnable, $btnTaskDisable, $btnTaskDelete)

    $btnCtxRefresh = New-StartupButton $ctxTab.Buttons "Refresh" "Standard"
    $btnCtxDetails = New-StartupButton $ctxTab.Buttons "Details" "Standard"
    $btnCtxEnable = New-StartupButton $ctxTab.Buttons "Enable" "Success"
    $btnCtxDisable = New-StartupButton $ctxTab.Buttons "Disable" "Warning"
    $btnCtxDelete = New-StartupButton $ctxTab.Buttons "Delete" "Danger"
    Add-GridContextMenu -TabObj $ctxTab -Buttons @($btnCtxRefresh, $btnCtxDetails, $btnCtxEnable, $btnCtxDisable, $btnCtxDelete)

    $btnSvcRefresh = New-StartupButton $svcTab.Buttons "Refresh" "Standard"
    $btnSvcDetails = New-StartupButton $svcTab.Buttons "Details" "Standard"
    $btnSvcEnable = New-StartupButton $svcTab.Buttons "Enable Auto" "Success"
    $btnSvcManual = New-StartupButton $svcTab.Buttons "Manual" "Primary"
    $btnSvcDisable = New-StartupButton $svcTab.Buttons "Disable" "Warning"
    $btnSvcDelete = New-StartupButton $svcTab.Buttons "Delete" "Danger"
    Add-GridContextMenu -TabObj $svcTab -Buttons @($btnSvcRefresh, $btnSvcDetails, $btnSvcEnable, $btnSvcManual, $btnSvcDisable, $btnSvcDelete)

    $btnWinRefresh.Add_Click({ & $fnInvokeStartupTabLoad "Windows" $true }.GetNewClosure())
    $btnWinDetails.Add_Click({ & $fnShowStartupRowDetails $winTab "Windows Startup Details" }.GetNewClosure())
    $btnWinEnable.Add_Click({ foreach ($row in Get-WmtDataGridSelectedRows $winTab.Grid) { & $fnSetStartupApprovedState ([string]$row["Type"]) ([string]$row["RootRunPath"]) ([string]$row["ValueName"]) $true; $row["Enabled"] = "Yes" } }.GetNewClosure())
    $btnWinDisable.Add_Click({ foreach ($row in Get-WmtDataGridSelectedRows $winTab.Grid) { & $fnSetStartupApprovedState ([string]$row["Type"]) ([string]$row["RootRunPath"]) ([string]$row["ValueName"]) $false; $row["Enabled"] = "No" } }.GetNewClosure())
    $btnWinDelete.Add_Click({
            $selected = @(Get-WmtDataGridSelectedRows $winTab.Grid)
            if ($selected.Count -eq 0) { return }
            if ((Show-WmtMessageBox -Owner $dialog -Message "Delete selected entries?" -Title "Confirm" -Button YesNo -Image Warning) -ne [System.Windows.MessageBoxResult]::Yes) { return }
            foreach ($row in $selected) {
                $type = [string]$row["Type"]
                $itemPath = [string]$row["ItemPath"]
                $valueName = [string]$row["ValueName"]
                if ($type -eq "StartupFolder") { Remove-Item -LiteralPath $itemPath -Force -ErrorAction SilentlyContinue }
                elseif ($type -eq "Registry" -and $itemPath -and $valueName) { Remove-ItemProperty -Path $itemPath -Name $valueName -ErrorAction SilentlyContinue }
            }
            & $fnRemoveWmtDataRows $winTab $selected
        }.GetNewClosure())

    $btnTaskRefresh.Add_Click({ & $fnInvokeStartupTabLoad "Scheduled Tasks" $true }.GetNewClosure())
    $btnTaskDetails.Add_Click({ & $fnShowStartupRowDetails $taskTab "Task Details" }.GetNewClosure())
    $btnTaskEnable.Add_Click({ & $fnInvokeStartupTaskSelection Enable }.GetNewClosure())
    $btnTaskDisable.Add_Click({ & $fnInvokeStartupTaskSelection Disable }.GetNewClosure())
    $btnTaskDelete.Add_Click({ & $fnInvokeStartupTaskSelection Delete }.GetNewClosure())

    $btnCtxRefresh.Add_Click({ & $fnInvokeStartupTabLoad "Context Menu" $true }.GetNewClosure())
    $btnCtxDetails.Add_Click({ & $fnShowStartupRowDetails $ctxTab "Context Menu Details" }.GetNewClosure())
    $btnCtxEnable.Add_Click({ foreach ($row in Get-WmtDataGridSelectedRows $ctxTab.Grid) { $path = [string]$row["Path"]; if ($path -and (Test-Path -LiteralPath $path)) { Remove-ItemProperty -LiteralPath $path -Name "LegacyDisable" -ErrorAction SilentlyContinue; $row["Enabled"] = "Yes" } } }.GetNewClosure())
    $btnCtxDisable.Add_Click({ foreach ($row in Get-WmtDataGridSelectedRows $ctxTab.Grid) { $path = [string]$row["Path"]; if ($path -and (Test-Path -LiteralPath $path)) { Set-ItemProperty -LiteralPath $path -Name "LegacyDisable" -Value "" -ErrorAction SilentlyContinue; $row["Enabled"] = "No" } } }.GetNewClosure())
    $btnCtxDelete.Add_Click({
            $selected = @(Get-WmtDataGridSelectedRows $ctxTab.Grid)
            if ($selected.Count -eq 0) { return }
            if ((Show-WmtMessageBox -Owner $dialog -Message "Delete selected context menu entries?" -Title "Confirm" -Button YesNo -Image Warning) -ne [System.Windows.MessageBoxResult]::Yes) { return }
            foreach ($row in $selected) { $path = [string]$row["Path"]; if ($path -and (Test-Path -LiteralPath $path)) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue } }
            & $fnRemoveWmtDataRows $ctxTab $selected
        }.GetNewClosure())

    $btnSvcRefresh.Add_Click({ & $fnInvokeStartupTabLoad "Services" $true }.GetNewClosure())
    $btnSvcDetails.Add_Click({ & $fnShowStartupRowDetails $svcTab "Service Details" }.GetNewClosure())
    $btnSvcEnable.Add_Click({ foreach ($row in Get-WmtDataGridSelectedRows $svcTab.Grid) { $name = [string]$row["Name"]; if ($name) { Set-Service -Name $name -StartupType Automatic -ErrorAction SilentlyContinue; $row["StartType"] = "Automatic" } } }.GetNewClosure())
    $btnSvcManual.Add_Click({ foreach ($row in Get-WmtDataGridSelectedRows $svcTab.Grid) { $name = [string]$row["Name"]; if ($name) { Set-Service -Name $name -StartupType Manual -ErrorAction SilentlyContinue; $row["StartType"] = "Manual" } } }.GetNewClosure())
    $btnSvcDisable.Add_Click({ foreach ($row in Get-WmtDataGridSelectedRows $svcTab.Grid) { $name = [string]$row["Name"]; if ($name) { Set-Service -Name $name -StartupType Disabled -ErrorAction SilentlyContinue; $row["StartType"] = "Disabled" } } }.GetNewClosure())
    $btnSvcDelete.Add_Click({
            $selected = @(Get-WmtDataGridSelectedRows $svcTab.Grid)
            if ($selected.Count -eq 0) { return }
            if ((Show-WmtMessageBox -Owner $dialog -Message "Delete selected services? This is risky." -Title "Confirm" -Button YesNo -Image Warning) -ne [System.Windows.MessageBoxResult]::Yes) { return }
            foreach ($row in $selected) { $name = [string]$row["Name"]; if ($name) { sc.exe delete $name | Out-Null } }
            & $fnRemoveWmtDataRows $svcTab $selected
        }.GetNewClosure())

    $dialog.Add_ContentRendered({
            switch ($DefaultTab) {
                "Scheduled Tasks" { & $fnSetStartupView "Scheduled Tasks" }
                "Context Menu" { & $fnSetStartupView "Context Menu" }
                "Services" { & $fnSetStartupView "Services" }
                default { & $fnSetStartupView "Windows" }
            }
        }.GetNewClosure())
    $dialog.ShowDialog() | Out-Null
}

# Functional block generated from WMT-GUI.ps1.
# Dot-source this file; it intentionally shares WMT's script scope.

function Invoke-FirewallExport {
    $target = Join-Path (Get-DataPath) ("firewall_rules_{0}.wfw" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    Invoke-UiCommand { param($target) netsh advfirewall export "$target" } "Exporting firewall rules..." -ArgumentList $target
}

function Invoke-FirewallImport {
    $dlg = [Microsoft.Win32.OpenFileDialog]::new()
    $dlg.Filter = "Windows Firewall Policy (*.wfw)|*.wfw"
    if ($dlg.ShowDialog() -ne $true) { return }
    $file = $dlg.FileName
    Invoke-UiCommand { param($file) netsh advfirewall import "$file" } "Importing firewall rules..." -ArgumentList $file
}

function Invoke-FirewallDefaults {
    $confirm = [System.Windows.MessageBox]::Show("Restore default Windows Firewall rules? Custom rules will be removed.", "Restore Defaults", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($confirm -ne "Yes") { return }
    Invoke-UiCommand { netsh advfirewall reset } "Restoring default firewall rules..."
}

function Invoke-FirewallPurge {
    $confirm = [System.Windows.MessageBox]::Show("Delete ALL firewall rules? This is destructive.", "Delete All Rules", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($confirm -ne "Yes") { return }
    Invoke-UiCommand { Remove-NetFirewallRule -All } "Deleting all firewall rules..."
}

function Test-FirewallSearchIsBlank {
    param([string]$Text)
    return ([string]::IsNullOrWhiteSpace($Text) -or $Text -in @("Search Rules...", "Search rules..."))
}

function Set-FirewallStatus {
    param(
        [string]$Text,
        [bool]$Visible = $true
    )
    if (-not $lblFwStatus) { return }
    if ([string]::IsNullOrWhiteSpace($Text)) { $Text = "Ready" }
    $lblFwStatus.Text = $Text
    $lblFwStatus.Visibility = if ($Visible) { "Visible" } else { "Collapsed" }
}

function Set-FirewallRuleProperty {
    param($Rule, [string]$Name, $Value)
    if (-not $Rule -or [string]::IsNullOrWhiteSpace($Name)) { return }
    $prop = $Rule.PSObject.Properties[$Name]
    if ($prop) {
        $prop.Value = $Value
    }
    else {
        $Rule | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
}

function Format-FirewallFilterValue {
    param([object[]]$Values)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $clean = [System.Collections.Generic.List[string]]::new()
    foreach ($value in $Values) {
        $text = if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { "Any" } else { [string]$value }
        if ($seen.Add($text)) { [void]$clean.Add($text) }
    }

    if ($clean.Count -eq 0) { return "Any" }
    return [string]::Join(", ", $clean)
}

function Get-FirewallRuleDetails {
    param([string]$Name)
    try {
        $rule = Get-NetFirewallRule -Name $Name -ErrorAction Stop
        $filters = @($rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue)
        if ($filters.Count -eq 0) {
            return [PSCustomObject]@{ Success = $true; Name = $Name; Protocol = "Any"; LocalPort = "Any"; Error = "" }
        }

        $protocolValues = [System.Collections.Generic.List[object]]::new()
        $localPortValues = [System.Collections.Generic.List[object]]::new()
        foreach ($filter in $filters) {
            [void]$protocolValues.Add($filter.Protocol)
            [void]$localPortValues.Add($filter.LocalPort)
        }

        $protocol = Format-FirewallFilterValue -Values $protocolValues.ToArray()
        $localPort = Format-FirewallFilterValue -Values $localPortValues.ToArray()
        return [PSCustomObject]@{ Success = $true; Name = $Name; Protocol = $protocol; LocalPort = $localPort; Error = "" }
    }
    catch {
        return [PSCustomObject]@{ Success = $false; Name = $Name; Protocol = ""; LocalPort = ""; Error = $_.Exception.Message }
    }
}

function Set-FirewallRuleDetails {
    param($Rule, $Details)
    if (-not $Rule -or -not $Details) { return }
    if ($Details.Success) {
        Set-FirewallRuleProperty -Rule $Rule -Name "Protocol" -Value $Details.Protocol
        Set-FirewallRuleProperty -Rule $Rule -Name "LocalPort" -Value $Details.LocalPort
        Set-FirewallRuleProperty -Rule $Rule -Name "DetailsLoaded" -Value $true
    }
    Set-FirewallRuleProperty -Rule $Rule -Name "DetailsLoading" -Value $false
}

function Test-FirewallRuleMatchesQuery {
    param($Rule, [string]$Query)
    if (-not $Rule) { return $false }
    if ([string]::IsNullOrWhiteSpace($Query)) { return $true }

    $fields = @(
        $Rule.Name,
        $Rule.DisplayName,
        $Rule.Direction,
        $Rule.Action,
        $Rule.Enabled,
        $Rule.Protocol,
        $Rule.LocalPort
    )
    foreach ($field in $fields) {
        if ($null -ne $field -and ([string]$field).IndexOf($Query, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }
    return $false
}

function Update-FirewallListView {
    if (-not $lstFw) { return }
    $selectedName = if ($lstFw.SelectedItem) { [string]$lstFw.SelectedItem.Name } else { $null }
    $query = if ($txtFwSearch) { [string]$txtFwSearch.Text } else { "" }
    $rules = $script:AllFw

    if (-not (Test-FirewallSearchIsBlank $query)) {
        $query = $query.Trim()
        $filtered = [System.Collections.Generic.List[object]]::new()
        foreach ($rule in $rules) {
            if (Test-FirewallRuleMatchesQuery -Rule $rule -Query $query) { [void]$filtered.Add($rule) }
        }
        $rules = $filtered
    }

    $lstFw.Items.Clear()
    foreach ($rule in $rules) { [void]$lstFw.Items.Add($rule) }
    if ($script:FirewallSortChain -and $script:FirewallSortChain.Count -gt 0) {
        Set-ListViewSort -ListView $lstFw -Chain $script:FirewallSortChain
    }
    if ($selectedName) {
        foreach ($item in $lstFw.Items) {
            if ($item.Name -eq $selectedName) {
                $lstFw.SelectedItem = $item
                break
            }
        }
    }
}

function Stop-FirewallDetailLoad {
    if ($script:FirewallDetailTimer) {
        try { $script:FirewallDetailTimer.Stop() } catch {}
        $script:FirewallDetailTimer = $null
    }
    if ($script:FirewallDetailJob) {
        try { $script:FirewallDetailJob.PowerShell.Stop() } catch {}
        try { $script:FirewallDetailJob.PowerShell.Dispose() } catch {}
        $script:FirewallDetailJob = $null
    }
}

function Stop-FirewallRuleLoad {
    if ($script:FirewallLoadTimer) {
        try { $script:FirewallLoadTimer.Stop() } catch {}
        $script:FirewallLoadTimer = $null
    }
    if ($script:FirewallLoadRunspace) {
        try { $script:FirewallLoadRunspace.Stop() } catch {}
        try { $script:FirewallLoadRunspace.Dispose() } catch {}
        $script:FirewallLoadRunspace = $null
    }
    $script:FirewallLoadAsyncResult = $null
    $script:FirewallLoadInProgress = $false
    $script:FirewallLoadPreloadMode = $false
    if ($btnFwRefresh) { $btnFwRefresh.IsEnabled = $true }
}

function Start-FirewallRuleDetailLoad {
    param($Rule)
    if (-not $Rule -or [string]::IsNullOrWhiteSpace([string]$Rule.Name)) { return }
    if ($Rule.PSObject.Properties["DetailsLoaded"] -and $Rule.DetailsLoaded) { return }

    $name = [string]$Rule.Name
    if ($script:FirewallDetailCache.ContainsKey($name)) {
        Set-FirewallRuleDetails -Rule $Rule -Details $script:FirewallDetailCache[$name]
        if ($lstFw) { $lstFw.Items.Refresh() }
        return
    }

    if ($script:FirewallDetailJob -and $script:FirewallDetailJob.Name -eq $name) { return }
    Stop-FirewallDetailLoad

    Set-FirewallRuleProperty -Rule $Rule -Name "Protocol" -Value "..."
    Set-FirewallRuleProperty -Rule $Rule -Name "LocalPort" -Value "..."
    Set-FirewallRuleProperty -Rule $Rule -Name "DetailsLoading" -Value $true
    if ($lstFw) { $lstFw.Items.Refresh() }

    $script:FirewallDetailToken++
    $token = $script:FirewallDetailToken
    Set-FirewallStatus "Loading selected rule details..." -Visible $true

    $ps = [PowerShell]::Create().AddScript({
            param([string]$RuleName)
            function Format-RuleValue {
                param([object[]]$Values)
                $clean = @(
                    $Values | ForEach-Object {
                        if ($null -eq $_ -or [string]::IsNullOrWhiteSpace([string]$_)) { "Any" }
                        else { [string]$_ }
                    } | Select-Object -Unique
                )
                if ($clean.Count -eq 0) { return "Any" }
                return ($clean -join ", ")
            }

            try {
                $rule = Get-NetFirewallRule -Name $RuleName -ErrorAction Stop
                $filters = @($rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue)
                if ($filters.Count -eq 0) {
                    return [PSCustomObject]@{ Success = $true; Name = $RuleName; Protocol = "Any"; LocalPort = "Any"; Error = "" }
                }

                $protocol = Format-RuleValue -Values @($filters | ForEach-Object { $_.Protocol })
                $localPort = Format-RuleValue -Values @($filters | ForEach-Object { $_.LocalPort })
                return [PSCustomObject]@{ Success = $true; Name = $RuleName; Protocol = $protocol; LocalPort = $localPort; Error = "" }
            }
            catch {
                return [PSCustomObject]@{ Success = $false; Name = $RuleName; Protocol = ""; LocalPort = ""; Error = $_.Exception.Message }
            }
        }).AddArgument($name)

    $async = $ps.BeginInvoke()
    $script:FirewallDetailJob = [PSCustomObject]@{ Name = $name; PowerShell = $ps; Async = $async; Token = $token }
    $script:FirewallDetailTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:FirewallDetailTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:FirewallDetailTimer.Add_Tick({
            if (-not $script:FirewallDetailJob -or -not $script:FirewallDetailJob.Async.IsCompleted) { return }

            $job = $script:FirewallDetailJob
            $script:FirewallDetailTimer.Stop()
            try {
                $result = $job.PowerShell.EndInvoke($job.Async)
                if ($result -and $result.Count -eq 1) { $result = $result[0] }

                $target = @($script:AllFw | Where-Object { $_.Name -eq $job.Name } | Select-Object -First 1)
                if ($result -and $result.Success) {
                    $script:FirewallDetailCache[$result.Name] = $result
                    if ($target.Count -gt 0) { Set-FirewallRuleDetails -Rule $target[0] -Details $result }
                }
                else {
                    if ($target.Count -gt 0) {
                        Set-FirewallRuleProperty -Rule $target[0] -Name "Protocol" -Value ""
                        Set-FirewallRuleProperty -Rule $target[0] -Name "LocalPort" -Value ""
                        Set-FirewallRuleProperty -Rule $target[0] -Name "DetailsLoading" -Value $false
                    }
                    if ($result -and $result.Error) { Write-GuiLog "[Firewall] Failed to load selected rule details: $($result.Error)" }
                }

                if ($txtFwSearch -and -not (Test-FirewallSearchIsBlank $txtFwSearch.Text)) {
                    Update-FirewallListView
                }
                elseif ($lstFw) {
                    $lstFw.Items.Refresh()
                }
            }
            catch {
                Write-GuiLog "[Firewall] Failed to load selected rule details: $($_.Exception.Message)"
            }
            finally {
                try { $job.PowerShell.Dispose() } catch {}
                if ($script:FirewallDetailJob -and $script:FirewallDetailJob.Token -eq $job.Token) { $script:FirewallDetailJob = $null }
                $script:FirewallDetailTimer = $null
                Set-FirewallStatus "" -Visible $false
            }
        })
    $script:FirewallDetailTimer.Start()
}

function Initialize-FirewallRuleDetails {
    param($Rule, [switch]$Synchronous)
    if (-not $Rule -or [string]::IsNullOrWhiteSpace([string]$Rule.Name)) { return }
    if ($Rule.PSObject.Properties["DetailsLoaded"] -and $Rule.DetailsLoaded) { return }

    $name = [string]$Rule.Name
    if ($script:FirewallDetailCache.ContainsKey($name)) {
        Set-FirewallRuleDetails -Rule $Rule -Details $script:FirewallDetailCache[$name]
        if ($lstFw) { $lstFw.Items.Refresh() }
        return
    }

    if ($Synchronous) {
        Stop-FirewallDetailLoad
        Set-FirewallStatus "Loading selected rule details..." -Visible $true
        $details = Get-FirewallRuleDetails -Name $name
        if ($details.Success) {
            $script:FirewallDetailCache[$name] = $details
            Set-FirewallRuleDetails -Rule $Rule -Details $details
        }
        else {
            Set-FirewallRuleProperty -Rule $Rule -Name "DetailsLoading" -Value $false
            Write-GuiLog "[Firewall] Failed to load selected rule details: $($details.Error)"
        }
        if ($lstFw) { $lstFw.Items.Refresh() }
        Set-FirewallStatus "" -Visible $false
        return
    }

    Start-FirewallRuleDetailLoad -Rule $Rule
}

function Start-FirewallRuleLoad {
    param([switch]$Force, [switch]$Preload)
    if ($script:FirewallLoadInProgress) {
        if (-not $Force) {
            if ($script:FirewallLoadPreloadMode -and -not $Preload) {
                $script:FirewallLoadPreloadMode = $false
                Set-FirewallStatus "Loading firewall rules..." -Visible $true
            }
            return
        }
        Stop-FirewallRuleLoad
    }
    if ($script:FirewallRulesLoaded -and -not $Force) {
        if (-not $Preload) { Update-FirewallListView }
        return
    }

    Stop-FirewallDetailLoad
    $script:FirewallLoadInProgress = $true
    $script:FirewallRulesLoaded = $false
    $script:FirewallLoadPreloadMode = [bool]$Preload
    $script:FirewallDetailCache = @{}
    if ($btnFwRefresh) { $btnFwRefresh.IsEnabled = $false }
    if (-not $Preload -and $lstFw) { $lstFw.Items.Clear() }
    if (-not $Preload) {
        Set-FirewallStatus "Loading firewall rules..." -Visible $true
        Write-GuiLog "[Firewall] Loading base rule list..."
    }

    $script:FirewallLoadRunspace = [PowerShell]::Create().AddScript({
            try {
                $rules = @(Get-NetFirewallRule -ErrorAction Stop | ForEach-Object {
                        $displayName = if ([string]::IsNullOrWhiteSpace([string]$_.DisplayName)) { $_.Name } else { $_.DisplayName }
                        [PSCustomObject]@{
                            Name           = [string]$_.Name
                            DisplayName    = [string]$displayName
                            Enabled        = $_.Enabled.ToString()
                            Direction      = $_.Direction.ToString()
                            Action         = $_.Action.ToString()
                            Protocol       = ""
                            LocalPort      = ""
                            DetailsLoaded  = $false
                            DetailsLoading = $false
                        }
                    })
                return [PSCustomObject]@{ Success = $true; Rules = $rules; Error = "" }
            }
            catch {
                return [PSCustomObject]@{ Success = $false; Rules = @(); Error = $_.Exception.Message }
            }
        })
    $script:FirewallLoadAsyncResult = $script:FirewallLoadRunspace.BeginInvoke()

    $script:FirewallLoadTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:FirewallLoadTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:FirewallLoadTimer.Add_Tick({
            if (-not $script:FirewallLoadAsyncResult -or -not $script:FirewallLoadAsyncResult.IsCompleted) { return }

            $script:FirewallLoadTimer.Stop()
            try {
                $result = $script:FirewallLoadRunspace.EndInvoke($script:FirewallLoadAsyncResult)
                if ($result -and $result.Count -eq 1) { $result = $result[0] }

                if ($result -and $result.Success) {
                    $script:AllFw = @($result.Rules | Where-Object { $null -ne $_ })
                    $script:FirewallRulesLoaded = $true
                    if ($script:FirewallLoadPreloadMode) {
                        if ($lblFwStatus) { Set-FirewallStatus "" -Visible $false }
                    }
                    else {
                        Update-FirewallListView
                        Write-GuiLog "[Firewall] Loaded $($script:AllFw.Count) base rules."
                        Set-FirewallStatus "" -Visible $false
                    }
                }
                else {
                    $script:AllFw = @()
                    $err = if ($result -and $result.Error) { $result.Error } else { "Unknown error" }
                    if (-not $script:FirewallLoadPreloadMode) {
                        Set-FirewallStatus "Firewall load failed" -Visible $true
                        Write-GuiLog "[Firewall] Load failed: $err"
                    }
                }
            }
            catch {
                $script:AllFw = @()
                if (-not $script:FirewallLoadPreloadMode) {
                    Set-FirewallStatus "Firewall load failed" -Visible $true
                    Write-GuiLog "[Firewall] Load failed: $($_.Exception.Message)"
                }
            }
            finally {
                try { $script:FirewallLoadRunspace.Dispose() } catch {}
                $script:FirewallLoadRunspace = $null
                $script:FirewallLoadAsyncResult = $null
                $script:FirewallLoadInProgress = $false
                $script:FirewallLoadPreloadMode = $false
                $script:FirewallLoadTimer = $null
                if ($btnFwRefresh) { $btnFwRefresh.IsEnabled = $true }
            }
        })
    $script:FirewallLoadTimer.Start()
}

function Resolve-FirewallSortProperty {
    param([string]$Header)
    switch ($Header) {
        "Rule Name" { return "Name" }
        "Direction" { return "Direction" }
        "Action" { return "Action" }
        "Status" { return "Enabled" }
        "Protocol" { return "Protocol" }
        "Port" { return "LocalPort" }
        default { return $Header }
    }
}

function Show-RuleDialog {
    param($Title, $RuleObj = $null)

    $content = @"
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Margin="0,0,0,10"><TextBlock Text="Rule Name" Foreground="{DynamicResource TextSecondary}"/><TextBox Name="txtName" Height="34" VerticalContentAlignment="Center"/></StackPanel>
        <StackPanel Grid.Row="1" Margin="0,0,0,10"><TextBlock Text="Direction" Foreground="{DynamicResource TextSecondary}"/><ComboBox Name="cmbDirection" Height="34"/></StackPanel>
        <StackPanel Grid.Row="2" Margin="0,0,0,10"><TextBlock Text="Action" Foreground="{DynamicResource TextSecondary}"/><ComboBox Name="cmbAction" Height="34"/></StackPanel>
        <StackPanel Grid.Row="3" Margin="0,0,0,10"><TextBlock Text="Protocol" Foreground="{DynamicResource TextSecondary}"/><ComboBox Name="cmbProtocol" Height="34"/></StackPanel>
        <StackPanel Grid.Row="4" Margin="0,0,0,14"><TextBlock Text="Local Port" Foreground="{DynamicResource TextSecondary}"/><TextBox Name="txtPort" Height="34" VerticalContentAlignment="Center"/></StackPanel>
        <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Name="btnCancel" Content="Cancel" Width="92" IsCancel="True" Margin="0,0,8,0"/>
            <Button Name="btnSave" Content="Save" Width="110" IsDefault="True" Background="{DynamicResource Success}" Foreground="{DynamicResource SuccessText}"/>
        </StackPanel>
    </Grid>
"@
    $dialog = New-WmtWindowFromXaml -Title $Title -ContentXaml $content -Width 460 -Height 440 -MinWidth 400 -MinHeight 410 -NoResize
    $txtName = $dialog.FindName("txtName")
    $cmbDirection = $dialog.FindName("cmbDirection")
    $cmbAction = $dialog.FindName("cmbAction")
    $cmbProtocol = $dialog.FindName("cmbProtocol")
    $txtPort = $dialog.FindName("txtPort")
    $btnSave = $dialog.FindName("btnSave")
    $btnCancel = $dialog.FindName("btnCancel")

    foreach ($item in @("Inbound", "Outbound")) { [void]$cmbDirection.Items.Add($item) }
    foreach ($item in @("Allow", "Block")) { [void]$cmbAction.Items.Add($item) }
    foreach ($item in @("TCP", "UDP", "Any")) { [void]$cmbProtocol.Items.Add($item) }

    $txtName.Text = if ($RuleObj) { [string]$RuleObj.DisplayName } else { "" }
    $cmbDirection.SelectedItem = if ($RuleObj) { [string]$RuleObj.Direction } else { "Inbound" }
    $cmbAction.SelectedItem = if ($RuleObj) { [string]$RuleObj.Action } else { "Block" }
    $cmbProtocol.SelectedItem = if ($RuleObj) { [string]$RuleObj.Protocol } else { "TCP" }
    $txtPort.Text = if ($RuleObj) { [string]$RuleObj.LocalPort } else { "" }
    if ($RuleObj) { $txtName.IsReadOnly = $true }

    $state = @{ Result = $null }
    $btnSave.Add_Click({
            $state.Result = @{
                Name      = [string]$txtName.Text
                Direction = [string]$cmbDirection.SelectedItem
                Action    = [string]$cmbAction.SelectedItem
                Protocol  = [string]$cmbProtocol.SelectedItem
                Port      = [string]$txtPort.Text
            }
            $dialog.DialogResult = $true
        }.GetNewClosure())
    $btnCancel.Add_Click({ $dialog.Close() }.GetNewClosure())
    $dialog.ShowDialog() | Out-Null
    return $state.Result
}

# Functional block generated from WMT-GUI.ps1.
# Dot-source this file; it intentionally shares WMT's script scope.

function New-WmtNetworkTextBlock {
    param(
        [string]$Text,
        [string]$Color = "TextSecondary",
        [double]$FontSize = 12,
        [string]$FontWeight = "Normal",
        [string]$Margin = "0"
    )

    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Text
    Set-WmtThemedBrush -Object $tb -Property ([System.Windows.Controls.TextBlock]::ForegroundProperty) -ColorOrKey $Color
    $tb.FontSize = $FontSize
    $tb.Margin = $Margin
    $tb.TextWrapping = "Wrap"
    $tb.LineHeight = 17
    if ($FontWeight -eq "SemiBold") { $tb.FontWeight = [System.Windows.FontWeights]::SemiBold }
    elseif ($FontWeight -eq "Bold") { $tb.FontWeight = [System.Windows.FontWeights]::Bold }
    return $tb
}

function Copy-MyDeviceNetworkValue {
    param(
        [string]$Label,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    try {
        [System.Windows.Clipboard]::SetText($Value)
        Write-GuiLog "[Network] Copied $Label to clipboard."
    }
    catch {
        Write-GuiLog "[Network] Failed to copy $Label`: $($_.Exception.Message)"
    }
}

function Open-MyDeviceNetworkConnections {
    try {
        Start-Process -FilePath "ncpa.cpl"
        Write-GuiLog "[Network] Opened Network Connections."
    }
    catch {
        try {
            Start-Process -FilePath "control.exe" -ArgumentList "netconnections"
            Write-GuiLog "[Network] Opened Network Connections."
        }
        catch {
            Write-GuiLog "[Network] Failed to open Network Connections: $($_.Exception.Message)"
        }
    }
}

function Open-MyDeviceDnsSettings {
    param([string]$AdapterName)

    if (-not [string]::IsNullOrWhiteSpace($AdapterName)) {
        try {
            $shell = New-Object -ComObject Shell.Application
            $connections = $shell.Namespace(0x31)
            if (-not $connections) { $connections = $shell.Namespace("shell:ConnectionsFolder") }
            if ($connections) {
                $adapterItem = @($connections.Items()) | Where-Object { $_.Name -eq $AdapterName } | Select-Object -First 1
                if (-not $adapterItem) {
                    $adapterItem = @($connections.Items()) | Where-Object { $_.Name -like "*$AdapterName*" -or $AdapterName -like "*$($_.Name)*" } | Select-Object -First 1
                }
                if ($adapterItem) {
                    try { $adapterItem.InvokeVerb("properties") }
                    catch {
                        $propertiesVerb = @($adapterItem.Verbs()) | Where-Object { (($_.Name -replace "&", "").Trim()) -match "(?i)^properties$" } | Select-Object -First 1
                        if ($propertiesVerb) { $propertiesVerb.DoIt() }
                        else { throw }
                    }
                    Write-GuiLog "[Network] Opened adapter properties for $AdapterName. Select IPv4 or IPv6 to edit DNS."
                    return
                }
            }
            Write-GuiLog "[Network] Could not find adapter '$AdapterName' in Network Connections."
        }
        catch {
            Write-GuiLog "[Network] Failed to open adapter DNS properties for $AdapterName`: $($_.Exception.Message)"
        }
    }

    try {
        Start-Process -FilePath "ms-settings:network-advancedsettings"
        Write-GuiLog "[Network] Opened advanced network settings for DNS assignment."
    }
    catch {
        try {
            Start-Process -FilePath "ncpa.cpl"
            Write-GuiLog "[Network] Opened Network Connections for DNS settings."
        }
        catch {
            Write-GuiLog "[Network] Failed to open DNS settings: $($_.Exception.Message)"
        }
    }
}

function Add-WmtNetworkLine {
    param(
        [System.Windows.Controls.Panel]$Panel,
        [string]$Label,
        [string]$Value,
        [scriptblock]$ClickAction = $null,
        [string]$ToolTip = "",
        [string]$Margin = "0,2,0,0"
    )

    if (-not $Panel -or [string]::IsNullOrWhiteSpace($Value)) { return }

    $tb = New-Object System.Windows.Controls.TextBlock
    Set-WmtThemedBrush -Object $tb -Property ([System.Windows.Controls.TextBlock]::ForegroundProperty) -ColorOrKey "TextSecondary"
    $tb.FontSize = 12
    $tb.TextWrapping = "Wrap"
    $tb.LineHeight = 17
    $tb.Margin = $Margin

    $labelRun = New-Object System.Windows.Documents.Run
    $labelRun.Text = ("{0}: " -f $Label)
    Set-WmtThemedBrush -Object $labelRun -Property ([System.Windows.Documents.TextElement]::ForegroundProperty) -ColorOrKey "TextSecondary"
    $labelRun.FontWeight = [System.Windows.FontWeights]::SemiBold
    [void]$tb.Inlines.Add($labelRun)

    if ($ClickAction) {
        $action = $ClickAction
        $link = New-Object System.Windows.Documents.Hyperlink
        Set-WmtThemedBrush -Object $link -Property ([System.Windows.Documents.TextElement]::ForegroundProperty) -ColorOrKey "Accent"
        $link.Cursor = [System.Windows.Input.Cursors]::Hand
        if (-not [string]::IsNullOrWhiteSpace($ToolTip)) { $link.ToolTip = $ToolTip }
        $valueRun = New-Object System.Windows.Documents.Run
        $valueRun.Text = $Value
        [void]$link.Inlines.Add($valueRun)
        $link.Add_Click({
                param($s, $e)
                & $action
                $e.Handled = $true
            }.GetNewClosure())
        [void]$tb.Inlines.Add($link)
    }
    else {
        $valueRun = New-Object System.Windows.Documents.Run
        $valueRun.Text = $Value
        [void]$tb.Inlines.Add($valueRun)
    }

    [void]$Panel.Children.Add($tb)
}

function Get-WmtNetworkStatusBrush {
    param([string]$StatusText)

    if ([string]::IsNullOrWhiteSpace($StatusText)) { return "#8B949E" }
    if ($StatusText -match "(?i)disconnect|down|failed|disabled|malfunction|not present") { return "#F85149" }
    if ($StatusText -match "(?i)local|limited|notraffic|authenticating|connecting") { return "#D29922" }
    if ($StatusText -match "(?i)internet|connected|up") { return "#3FB950" }
    return "#8B949E"
}

function Set-MyDeviceNetworkDetails {
    param($Adapters)

    $panel = Get-Ctrl "pnlDeviceNetworkList"
    $summary = Get-Ctrl "txtDeviceNetwork"
    if (-not $panel) { return }

    $panel.Children.Clear()
    $adapterList = @($Adapters | Where-Object { $null -ne $_ })

    if (-not $adapterList -or $adapterList.Count -eq 0) {
        if ($summary -and [string]::IsNullOrWhiteSpace($summary.Text)) { $summary.Text = "No active physical network adapters found." }
        return
    }

    if ($summary) {
        $primary = @($adapterList | Where-Object { $_.GatewayText -and $_.GatewayText -ne "None" } | Select-Object -First 1)
        $summary.Text = if ($primary.Count -gt 0) { "Active physical adapters: $($adapterList.Count) | Primary: $($primary[0].Name)" } else { "Active physical adapters: $($adapterList.Count)" }
    }

    for ($i = 0; $i -lt $adapterList.Count; $i++) {
        $d = $adapterList[$i]

        $header = New-Object System.Windows.Controls.Grid
        $header.Margin = if ($i -eq 0) { "0,8,0,0" } else { "0,12,0,0" }
        $colMain = New-Object System.Windows.Controls.ColumnDefinition
        $colMain.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $colStatus = New-Object System.Windows.Controls.ColumnDefinition
        $colStatus.Width = [System.Windows.GridLength]::Auto
        [void]$header.ColumnDefinitions.Add($colMain)
        [void]$header.ColumnDefinitions.Add($colStatus)

        $adapterTitle = New-WmtNetworkTextBlock -Text $d.Name -Color "Accent" -FontSize 13 -FontWeight "SemiBold"
        $adapterTitle.Cursor = [System.Windows.Input.Cursors]::Hand
        $adapterTitle.TextDecorations = [System.Windows.TextDecorations]::Underline
        $adapterTitle.ToolTip = "Open Network Connections"
        $adapterTitle.Add_MouseLeftButtonUp({
                param($s, $e)
                Open-MyDeviceNetworkConnections
                $e.Handled = $true
            })
        [void]$header.Children.Add($adapterTitle)

        $statusText = New-WmtNetworkTextBlock -Text $d.Status -Color (Get-WmtNetworkStatusBrush "$($d.Status) $($d.Connectivity)") -FontSize 12 -FontWeight "SemiBold" -Margin "8,0,0,0"
        [System.Windows.Controls.Grid]::SetColumn($statusText, 1)
        [void]$header.Children.Add($statusText)
        [void]$panel.Children.Add($header)

        Add-WmtNetworkLine -Panel $panel -Label "Adapter" -Value $d.Description -Margin "0,4,0,0"
        Add-WmtNetworkLine -Panel $panel -Label "Profile" -Value $d.Profile -ClickAction { Open-MyDeviceNetworkConnections } -ToolTip "Open Network Connections"
        Add-WmtNetworkLine -Panel $panel -Label "Connectivity" -Value $d.Connectivity
        Add-WmtNetworkLine -Panel $panel -Label "Link" -Value $d.LinkText

        $ipv4Copy = [string]$d.IPv4Copy
        Add-WmtNetworkLine -Panel $panel -Label "IPv4" -Value $d.IPv4Text -ClickAction ({ Copy-MyDeviceNetworkValue -Label "IPv4 address" -Value $ipv4Copy }.GetNewClosure()) -ToolTip "Copy IPv4 address"

        if (-not [string]::IsNullOrWhiteSpace($d.IPv6Text)) {
            $ipv6Copy = [string]$d.IPv6Copy
            Add-WmtNetworkLine -Panel $panel -Label "IPv6" -Value $d.IPv6Text -ClickAction ({ Copy-MyDeviceNetworkValue -Label "IPv6 address" -Value $ipv6Copy }.GetNewClosure()) -ToolTip "Copy IPv6 address"
        }

        $gatewayAddress = [string]$d.GatewayLink
        if (-not [string]::IsNullOrWhiteSpace($gatewayAddress)) {
            Add-WmtNetworkLine -Panel $panel -Label "Gateway" -Value $d.GatewayText -ClickAction ({ Open-MyDeviceGateway -Address $gatewayAddress }.GetNewClosure()) -ToolTip "Open gateway in browser"
        }
        else {
            Add-WmtNetworkLine -Panel $panel -Label "Gateway" -Value $d.GatewayText
        }

        $dnsAdapterName = [string]$d.Name
        Add-WmtNetworkLine -Panel $panel -Label "DNS" -Value $d.DnsText -ClickAction ({ Open-MyDeviceDnsSettings -AdapterName $dnsAdapterName }.GetNewClosure()) -ToolTip "Open this adapter's properties for DNS"

        Add-WmtNetworkLine -Panel $panel -Label "DHCP" -Value $d.DhcpText
        Add-WmtNetworkLine -Panel $panel -Label "Lease" -Value $d.LeaseText
        Add-WmtNetworkLine -Panel $panel -Label "DNS suffix" -Value $d.DnsSuffix

        $macCopy = [string]$d.MacAddress
        if (-not [string]::IsNullOrWhiteSpace($macCopy)) {
            Add-WmtNetworkLine -Panel $panel -Label "MAC" -Value $d.MacAddress -ClickAction ({ Copy-MyDeviceNetworkValue -Label "MAC address" -Value $macCopy }.GetNewClosure()) -ToolTip "Copy MAC address"
        }

        Add-WmtNetworkLine -Panel $panel -Label "Traffic" -Value $d.TrafficText
        if (-not [string]::IsNullOrWhiteSpace($d.WifiText)) {
            Add-WmtNetworkLine -Panel $panel -Label "Wi-Fi" -Value $d.WifiText -ClickAction { Open-MyDeviceWifiSettings } -ToolTip "Open Wi-Fi settings"
        }
        Add-WmtNetworkLine -Panel $panel -Label "Driver" -Value $d.DriverText

        if ($i -lt ($adapterList.Count - 1)) {
            $separator = New-Object System.Windows.Controls.Border
            $separator.Height = 1
            Set-WmtThemedBrush -Object $separator -Property ([System.Windows.Controls.Border]::BackgroundProperty) -ColorOrKey "BorderBrush"
            $separator.Margin = "0,10,0,0"
            [void]$panel.Children.Add($separator)
        }
    }
}

function Get-ActiveAdapters {
    Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notlike '*Virtual*' -and $_.Name -notlike '*vEthernet*' }
}

function Test-WmtDnsAddress {
    param([string]$Address)

    if ([string]::IsNullOrWhiteSpace($Address)) { return $false }
    $parsedAddress = [System.Net.IPAddress]::None
    return [System.Net.IPAddress]::TryParse($Address.Trim(), [ref]$parsedAddress)
}

function Get-WmtValidatedDnsAddresses {
    param([string[]]$Addresses)

    $valid = @()
    $invalid = @()
    $seen = @{}

    foreach ($address in @($Addresses)) {
        $candidate = ([string]$address).Trim()
        if ([string]::IsNullOrWhiteSpace($candidate) -or $seen.ContainsKey($candidate)) { continue }
        $seen[$candidate] = $true

        if (Test-WmtDnsAddress -Address $candidate) { $valid += $candidate }
        else { $invalid += $candidate }
    }

    [PSCustomObject]@{
        Valid   = $valid
        Invalid = $invalid
    }
}

function Clear-WmtDnsResolverCache {
    try {
        Clear-DnsClientCache -ErrorAction Stop
        return "DNS resolver cache cleared."
    }
    catch {
        $out = ipconfig /flushdns 2>&1
        $txt = ($out | Out-String).Trim()
        if ($txt) { return $txt }
        return "DNS resolver cache flush attempted."
    }
}

function Set-WmtDnsActionButtonsEnabled {
    param([bool]$Enabled)

    foreach ($buttonName in @(
            "btnDnsGoogle", "btnDnsCloudflare", "btnDnsQuad9", "btnDnsAdGuard",
            "btnDnsAuto", "btnDnsCustom", "btnDohAuto", "btnDohDisable"
        )) {
        try {
            $button = Get-Ctrl $buttonName
            if ($button) { $button.IsEnabled = $Enabled }
        }
        catch {}
    }
}

function Test-WmtDnsRunspaceBusy {
    return (($script:DnsRunspace -and $script:DnsAsyncResult -and -not $script:DnsAsyncResult.IsCompleted) -or
        ($script:DohRunspace -and $script:DohAsyncResult -and -not $script:DohAsyncResult.IsCompleted))
}

function Stop-WmtDnsRunspaces {
    if ($script:DnsTimer) {
        try { $script:DnsTimer.Stop() } catch {}
        $script:DnsTimer = $null
    }
    if ($script:DnsRunspace) {
        try { $script:DnsRunspace.Stop() } catch {}
        try { $script:DnsRunspace.Dispose() } catch {}
        $script:DnsRunspace = $null
        $script:DnsAsyncResult = $null
    }
    if ($script:DohTimer) {
        try { $script:DohTimer.Stop() } catch {}
        $script:DohTimer = $null
    }
    if ($script:DohRunspace) {
        try { $script:DohRunspace.Stop() } catch {}
        try { $script:DohRunspace.Dispose() } catch {}
        $script:DohRunspace = $null
        $script:DohAsyncResult = $null
    }
}

function Start-DnsAssignmentRunspace {
    param(
        [string[]]$Addresses = @(),
        [string]$Label = "Custom DNS",
        [switch]$Reset,
        [scriptblock]$OnComplete
    )

    if (Test-WmtDnsRunspaceBusy) {
        Write-GuiLog "A DNS or DoH operation is already running."
        return $false
    }

    $addrList = @($Addresses | Where-Object { -not [string]::IsNullOrWhiteSpace(([string]$_).Trim()) })
    if (-not $Reset -and (-not $addrList -or $addrList.Count -eq 0)) {
        Write-GuiLog "No valid DNS addresses provided."
        return $false
    }

    $labelText = $Label
    $isReset = [bool]$Reset
    $completion = $OnComplete
    $startMessage = if ($isReset) { "Resetting DNS..." } else { "Applying $labelText..." }

    Write-GuiLog $startMessage
    Set-WmtDnsActionButtonsEnabled $false

    $script:DnsRunspace = [PowerShell]::Create().AddScript({
            param($ServerAddresses, $OperationLabel, $ResetAddresses)

            $lines = New-Object System.Collections.Generic.List[string]
            $successCount = 0
            $adapterCount = 0

            function Add-DnsLine {
                param([string]$Text)
                if (-not [string]::IsNullOrWhiteSpace($Text)) { $lines.Add($Text) | Out-Null }
            }

            function Clear-DnsResolverCacheInRunspace {
                try {
                    Clear-DnsClientCache -ErrorAction Stop
                    return "DNS resolver cache cleared."
                }
                catch {
                    $out = ipconfig /flushdns 2>&1
                    $txt = ($out | Out-String).Trim()
                    if ($txt) { return $txt }
                    return "DNS resolver cache flush attempted."
                }
            }

            try {
                $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue |
                    Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notlike '*Virtual*' -and $_.Name -notlike '*vEthernet*' } |
                    Select-Object -ExpandProperty Name)

                $adapterCount = $adapters.Count
                if (-not $adapters -or $adapters.Count -eq 0) {
                    Add-DnsLine "No active adapters found."
                    return [PSCustomObject]@{
                        Success      = $false
                        SuccessCount = 0
                        AdapterCount = 0
                        Lines        = $lines.ToArray()
                        Error        = ""
                    }
                }

                foreach ($adapter in $adapters) {
                    try {
                        if ($ResetAddresses) {
                            Set-DnsClientServerAddress -InterfaceAlias $adapter -ResetServerAddresses -ErrorAction Stop
                            Add-DnsLine "[Auto DNS] Reset $adapter to automatic DNS."
                        }
                        else {
                            Set-DnsClientServerAddress -InterfaceAlias $adapter -ServerAddresses $ServerAddresses -ErrorAction Stop
                            Add-DnsLine "[$OperationLabel] Applied to $adapter : $($ServerAddresses -join ', ')"
                        }
                        $successCount++
                    }
                    catch {
                        if ($ResetAddresses) {
                            Add-DnsLine "[Auto DNS] Failed on $adapter : $($_.Exception.Message)"
                        }
                        else {
                            Add-DnsLine "[$OperationLabel] Failed on $adapter : $($_.Exception.Message)"
                        }
                    }
                }

                if ($successCount -gt 0) {
                    Add-DnsLine (Clear-DnsResolverCacheInRunspace)
                    if ($ResetAddresses) {
                        Add-DnsLine "[Auto DNS] Reset $successCount of $adapterCount active adapter(s)."
                    }
                    else {
                        Add-DnsLine "[$OperationLabel] Updated $successCount of $adapterCount active adapter(s)."
                    }
                }

                [PSCustomObject]@{
                    Success      = ($successCount -gt 0)
                    SuccessCount = $successCount
                    AdapterCount = $adapterCount
                    Lines        = $lines.ToArray()
                    Error        = ""
                }
            }
            catch {
                Add-DnsLine "ERROR: $($_.Exception.Message)"
                [PSCustomObject]@{
                    Success      = $false
                    SuccessCount = $successCount
                    AdapterCount = $adapterCount
                    Lines        = $lines.ToArray()
                    Error        = $_.Exception.Message
                }
            }
        }).AddArgument($addrList).AddArgument($labelText).AddArgument($isReset)

    try {
        $script:DnsAsyncResult = $script:DnsRunspace.BeginInvoke()
    }
    catch {
        Write-GuiLog "Failed to start DNS runspace: $($_.Exception.Message)"
        try { $script:DnsRunspace.Dispose() } catch {}
        $script:DnsRunspace = $null
        $script:DnsAsyncResult = $null
        Set-WmtDnsActionButtonsEnabled $true
        return $false
    }

    $dnsRunspace = $script:DnsRunspace
    $dnsAsync = $script:DnsAsyncResult
    $dnsTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:DnsTimer = $dnsTimer
    $dnsTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $dnsTimer.Add_Tick({
            if (-not $dnsAsync -or -not $dnsAsync.IsCompleted) { return }

            $dnsTimer.Stop()
            $result = $null
            try {
                $raw = $dnsRunspace.EndInvoke($dnsAsync)
                if ($raw -is [System.Collections.ObjectModel.Collection[PSObject]]) { $result = $raw | Select-Object -Last 1 }
                else { $result = $raw }

                if ($result -and $result.Lines) {
                    $text = ($result.Lines | Out-String).Trim()
                    if ($text) { Write-GuiLog $text }
                }
                elseif ($result -and $result.Success) {
                    Write-GuiLog "Done."
                }
                else {
                    Write-GuiLog "DNS operation finished with no output."
                }
            }
            catch {
                Write-GuiLog "DNS Error: $($_.Exception.Message)"
            }
            finally {
                try { $dnsRunspace.Dispose() } catch {}
                if ([object]::ReferenceEquals($script:DnsRunspace, $dnsRunspace)) { $script:DnsRunspace = $null }
                if ([object]::ReferenceEquals($script:DnsAsyncResult, $dnsAsync)) { $script:DnsAsyncResult = $null }
                if ([object]::ReferenceEquals($script:DnsTimer, $dnsTimer)) { $script:DnsTimer = $null }
                Set-WmtDnsActionButtonsEnabled $true
            }

            if ($completion) {
                try { & $completion $result }
                catch { Write-GuiLog "DNS completion action failed: $($_.Exception.Message)" }
            }
        }.GetNewClosure())

    $dnsTimer.Start()
    return $true
}

function Set-DnsAddresses {
    param(
        [string[]]$Addresses,
        [string]$Label = "Custom DNS",
        [scriptblock]$OnComplete
    )
    $validation = Get-WmtValidatedDnsAddresses -Addresses $Addresses
    if ($validation.Invalid.Count -gt 0) {
        Write-GuiLog "Invalid DNS skipped: $($validation.Invalid -join ', ')"
    }
    if (-not $validation.Valid -or $validation.Valid.Count -eq 0) {
        Write-GuiLog "No valid DNS addresses provided."
        return
    }

    $addrList = @($validation.Valid)
    Start-DnsAssignmentRunspace -Addresses $addrList -Label $Label -OnComplete $OnComplete | Out-Null
}

function Invoke-DnsPreset {
    param([string]$ProviderKey)

    if (-not $script:WmtDnsProviders.Contains($ProviderKey)) {
        Write-GuiLog "DNS provider not configured: $ProviderKey"
        return
    }

    $provider = $script:WmtDnsProviders[$ProviderKey]
    $addressText = $provider.Addresses -join " / "
    $msg = "Set DNS to $($provider.Name) ($addressText) on all active adapters?`n`nDNS cache will be flushed after changes."
    $res = [System.Windows.MessageBox]::Show($msg, "DNS Preset", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($res -ne "Yes") { return }

    Set-DnsAddresses -Addresses $provider.Addresses -Label $provider.Label
}

function Reset-DnsAddressesToAutomatic {
    $res = [System.Windows.MessageBox]::Show("Reset DNS server assignment to automatic (DHCP) on all active adapters?`n`nDNS cache will be flushed after changes.", "DNS Reset", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($res -ne "Yes") { return }

    Start-DnsAssignmentRunspace -Reset -Label "Auto DNS" -OnComplete {
        param($Result)
        if ($Result -and $Result.Success) {
            [System.Windows.MessageBox]::Show("DNS reset to automatic (DHCP).", "DNS Reset", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        }
    } | Out-Null
}

function Test-WmtDohTemplateUrl {
    param([string]$Url)

    $candidate = ([string]$Url).Trim()
    if ([string]::IsNullOrWhiteSpace($candidate)) { return $false }

    $uri = [System.Uri]$null
    if (-not [System.Uri]::TryCreate($candidate, [System.UriKind]::Absolute, [ref]$uri)) { return $false }

    return ($uri.Scheme -eq [System.Uri]::UriSchemeHttps -and -not [string]::IsNullOrWhiteSpace($uri.Host))
}

function New-WmtDohTargets {
    param(
        [string[]]$Addresses,
        [string]$Template = ""
    )

    $templateText = ([string]$Template).Trim()
    $targets = @()
    foreach ($address in @($Addresses)) {
        $server = ([string]$address).Trim()
        if ([string]::IsNullOrWhiteSpace($server)) { continue }
        $targets += [PSCustomObject]@{
            Server   = $server
            Template = $templateText
        }
    }
    return $targets
}

function Show-CustomDnsDialog {
    $settings = Get-WmtSettings

    [xml]$customDnsXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Custom DNS" Height="500" Width="560" WindowStartupLocation="CenterOwner"
        ResizeMode="NoResize" Background="{DynamicResource BgDark}" Foreground="{DynamicResource TextPrimary}">
    <Window.Resources>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="TextWrapping" Value="Wrap"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{DynamicResource BgPanel}"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Height" Value="32"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="Background" Value="{DynamicResource BgElevated}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,0"/>
        </Style>
    </Window.Resources>
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Text="Custom DNS" FontSize="18" FontWeight="SemiBold" Foreground="{DynamicResource Accent}"/>

        <TextBlock Grid.Row="1" Foreground="{DynamicResource TextSecondary}" Margin="0,12,0,0"
                   Text="Enter IPv4 and IPv6 DNS servers together. Use commas, spaces, semicolons, or new lines between addresses."/>

        <TextBlock Grid.Row="2" Text="DNS servers" Foreground="{DynamicResource TextSecondary}" Margin="0,16,0,6"/>
        <TextBox Name="txtDnsServers" Grid.Row="3" Height="78" AcceptsReturn="True"
                 TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>

        <TextBlock Grid.Row="4" Foreground="{DynamicResource TextSecondary}" Margin="0,6,0,0"
                   Text="Example: 1.1.1.1, 1.0.0.1, 2606:4700:4700::1111, 2606:4700:4700::1001"/>

        <CheckBox Name="chkRegisterDoh" Grid.Row="5" Content="Register DoH template" Margin="0,14,0,8"/>

        <TextBlock Grid.Row="6" Text="DoH template URL" Foreground="{DynamicResource TextSecondary}" Margin="0,0,0,6"/>
        <TextBox Name="txtDohTemplate" Grid.Row="7" Height="34"/>

        <TextBlock Grid.Row="8" Foreground="{DynamicResource TextSecondary}" Margin="0,6,0,0"
                   Text="Example: https://cloudflare-dns.com/dns-query. Use a DoH template from the same provider as the DNS servers."/>

        <TextBlock Name="lblError" Grid.Row="9" Foreground="{DynamicResource DangerHover}" Margin="0,10,0,0"/>

        <StackPanel Grid.Row="10" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0">
            <Button Name="btnRemoveDoh" Content="Remove DoH" Width="104" Background="{DynamicResource Danger}" Foreground="{DynamicResource DangerText}" Margin="0,0,8,0"/>
            <Button Name="btnApply" Content="Apply" Width="84" Background="{DynamicResource Success}" Foreground="{DynamicResource SuccessText}" Margin="0,0,8,0"/>
            <Button Name="btnCancel" Content="Cancel" Width="84"/>
        </StackPanel>
    </Grid>
</Window>
'@

    try {
        $dialog = New-WmtWindowFromFullXaml -Xaml $customDnsXaml
    }
    catch {
        Write-GuiLog "Failed to open custom DNS dialog: $($_.Exception.Message)"
        return $null
    }

    $txtDnsServers = $dialog.FindName("txtDnsServers")
    $chkRegisterDoh = $dialog.FindName("chkRegisterDoh")
    $txtDohTemplate = $dialog.FindName("txtDohTemplate")
    $lblError = $dialog.FindName("lblError")
    $btnApply = $dialog.FindName("btnApply")
    $btnCancel = $dialog.FindName("btnCancel")
    $btnRemoveDoh = $dialog.FindName("btnRemoveDoh")

    $savedServers = @($settings.CustomDnsServers | Where-Object { -not [string]::IsNullOrWhiteSpace(([string]$_).Trim()) })
    if ($savedServers.Count -eq 0) { $savedServers = @("1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001") }
    $txtDnsServers.Text = ($savedServers -join ", ")
    $txtDohTemplate.Text = if ($settings.CustomDohTemplate) { [string]$settings.CustomDohTemplate } else { "" }
    $chkRegisterDoh.IsChecked = [bool]$settings.CustomDohEnabled

    $setDohTemplateState = {
        $enabled = [bool]$chkRegisterDoh.IsChecked
        $txtDohTemplate.IsEnabled = $enabled
        $txtDohTemplate.Opacity = if ($enabled) { 1.0 } else { 0.55 }
    }.GetNewClosure()
    $chkRegisterDoh.Add_Checked($setDohTemplateState)
    $chkRegisterDoh.Add_Unchecked($setDohTemplateState)
    & $setDohTemplateState

    $dialog.Tag = $null

    $getValidatedCustomDns = {
        $lblError.Text = ""
        $addresses = $txtDnsServers.Text -split "[,;\s]+" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $validation = Get-WmtValidatedDnsAddresses -Addresses $addresses
        if (-not $validation.Valid -or $validation.Valid.Count -eq 0) {
            $lblError.Text = "Enter at least one valid DNS server IP address."
            $null
        }
        else {
            $registerDoh = [bool]$chkRegisterDoh.IsChecked
            $dohTemplate = ([string]$txtDohTemplate.Text).Trim()

            if ($registerDoh -and -not (Test-WmtDohTemplateUrl -Url $dohTemplate)) {
                $lblError.Text = "Enter a valid HTTPS DoH template URL."
                $null
            }
            else {
                [PSCustomObject]@{
                    Addresses   = @($validation.Valid)
                    Invalid     = @($validation.Invalid)
                    RegisterDoh = $registerDoh
                    DohTemplate = $dohTemplate
                    Action      = "Apply"
                }
            }
        }
    }.GetNewClosure()

    $btnApply.Add_Click({
            $candidate = & $getValidatedCustomDns
            if (-not $candidate) { return }

            $dialog.Tag = $candidate
            $dialog.DialogResult = $true
        }.GetNewClosure())

    $btnRemoveDoh.Add_Click({
            $lblError.Text = ""
            $addresses = $txtDnsServers.Text -split "[,;\s]+" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            $validation = Get-WmtValidatedDnsAddresses -Addresses $addresses
            if (-not $validation.Valid -or $validation.Valid.Count -eq 0) {
                $lblError.Text = "Enter at least one valid DNS server IP address."
                return
            }

            $dialog.Tag = [PSCustomObject]@{
                Addresses   = @($validation.Valid)
                Invalid     = @($validation.Invalid)
                RegisterDoh = $false
                DohTemplate = ([string]$txtDohTemplate.Text).Trim()
                Action      = "RemoveDoh"
            }
            $dialog.DialogResult = $true
        }.GetNewClosure())

    $btnCancel.Add_Click({ $dialog.DialogResult = $false }.GetNewClosure())

    if ($dialog.ShowDialog() -eq $true) { return $dialog.Tag }
    return $null
}

function Invoke-CustomDnsSettings {
    $customDns = Show-CustomDnsDialog
    if (-not $customDns) { return }

    if ($customDns.Invalid.Count -gt 0) {
        Write-GuiLog "Invalid DNS skipped: $($customDns.Invalid -join ', ')"
    }

    $settings = Get-WmtSettings
    $settings.CustomDnsServers = @($customDns.Addresses)
    $settings.CustomDohTemplate = [string]$customDns.DohTemplate
    $settings.CustomDohEnabled = [bool]$customDns.RegisterDoh
    Save-WmtSettings -Settings $settings

    $customDohTargets = New-WmtDohTargets -Addresses $customDns.Addresses -Template $customDns.DohTemplate
    if ($customDns.Action -eq "RemoveDoh") {
        Start-DohJob -List $customDohTargets -IsEnable $false
        return
    }

    if ($customDns.RegisterDoh) {
        Set-DnsAddresses -Addresses $customDns.Addresses -Label "Custom DNS" -OnComplete ({
                param($Result)
                if ($Result -and $Result.Success) {
                    Start-DohJob -List $customDohTargets -IsEnable $true
                }
                else {
                    Write-GuiLog "Skipped DoH registration because custom DNS assignment did not complete successfully."
                }
            }.GetNewClosure())
        return
    }

    Set-DnsAddresses -Addresses $customDns.Addresses -Label "Custom DNS"
}

function Start-DohJob {
    param($List, $IsEnable)

    $dnsList = @($List)
    if (-not $dnsList -or $dnsList.Count -eq 0) {
        Write-GuiLog "No DoH targets configured."
        return
    }

    if (Test-WmtDnsRunspaceBusy) {
        Write-GuiLog "A DNS or DoH operation is already running."
        return
    }

    if ($script:DohRunspace) {
        try { $script:DohRunspace.Dispose() } catch {}
        $script:DohRunspace = $null
        $script:DohAsyncResult = $null
    }

    $isEnableForTimer = [bool]$IsEnable
    $actionStr = if ($isEnableForTimer) { "Registering" } else { "Removing" }
    Write-GuiLog "$actionStr DoH templates..."
    Set-WmtDnsActionButtonsEnabled $false

    try {
        $script:DohRunspace = [PowerShell]::Create().AddScript({
                param($List, $IsEnable)

                $cnt = 0
                $failures = @()

                foreach ($dns in $List) {
                    $server = [string]$dns.Server
                    $template = [string]$dns.Template
                    if ([string]::IsNullOrWhiteSpace($server)) { continue }

                    if ($IsEnable) {
                        & netsh.exe dns delete encryption "server=$server" 2>&1 | Out-Null
                        & netsh.exe dns add encryption "server=$server" "dohtemplate=$template" autoupgrade=yes udpfallback=no 2>&1 | Out-Null
                        if ($LASTEXITCODE -eq 0) { $cnt++ }
                        else { $failures += $server }
                    }
                    else {
                        & netsh.exe dns delete encryption "server=$server" 2>&1 | Out-Null
                        # Treat missing entries as already disabled; the desired end state is still reached.
                        $cnt++
                    }
                }

                ipconfig /flushdns | Out-Null
                try { Restart-Service Dnscache -Force -ErrorAction SilentlyContinue } catch {}
                
                [PSCustomObject]@{
                    Count    = $cnt
                    Failed   = $failures.Count
                    Failures = $failures
                    Success  = ($failures.Count -eq 0)
                }
            }).AddArgument($dnsList).AddArgument($isEnableForTimer)

        $script:DohAsyncResult = $script:DohRunspace.BeginInvoke()
    }
    catch {
        Write-GuiLog "Failed to start DoH runspace: $($_.Exception.Message)"
        try { if ($script:DohRunspace) { $script:DohRunspace.Dispose() } } catch {}
        $script:DohRunspace = $null
        $script:DohAsyncResult = $null
        Set-WmtDnsActionButtonsEnabled $true
        return
    }

    $dohRunspace = $script:DohRunspace
    $dohAsync = $script:DohAsyncResult
    if (-not $dohRunspace -or -not $dohAsync) {
        Write-GuiLog "Failed to start DoH runspace."
        Set-WmtDnsActionButtonsEnabled $true
        return
    }

    if ($script:DohTimer) { $script:DohTimer.Stop() }
    $dohTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:DohTimer = $dohTimer
    $dohTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    
    $dohTimer.Add_Tick({
            if (-not $dohAsync -or -not $dohAsync.IsCompleted) { return }

            $dohTimer.Stop()
            try {
                $rawResults = $dohRunspace.EndInvoke($dohAsync)
                $res = $rawResults | Where-Object { $_ -is [PSCustomObject] -and $_.Psobject.Properties.Match('Count') } | Select-Object -Last 1

                if ($res -and $res.Success) {
                    $c = $res.Count
                    if ($isEnableForTimer) {
                        $finMsg = "Registered $c DoH templates."
                    }
                    else {
                        $finMsg = "Removed or verified $c DoH templates."
                    }

                    Write-GuiLog "Done. $finMsg"

                    if ($c -gt 0) {
                        [System.Windows.MessageBox]::Show($finMsg, "DoH Manager", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
                    }
                }
                else {
                    $failedText = if ($res -and $res.Failures) { " Failed: $($res.Failures -join ', ')" } else { "" }
                    Write-GuiLog "DoH operation failed or no changes were made.$failedText"
                }
            }
            catch {
                Write-GuiLog "DoH Error: $($_.Exception.Message)"
            }
            finally {
                try {
                    $dohRunspace.Dispose()
                }
                catch {}
                if ([object]::ReferenceEquals($script:DohRunspace, $dohRunspace)) { $script:DohRunspace = $null }
                if ([object]::ReferenceEquals($script:DohAsyncResult, $dohAsync)) { $script:DohAsyncResult = $null }
                if ([object]::ReferenceEquals($script:DohTimer, $dohTimer)) { $script:DohTimer = $null }
                Set-WmtDnsActionButtonsEnabled $true
            }
        }.GetNewClosure())
    
    $dohTimer.Start()
}

function Enable-AllDoh { Start-DohJob -List $script:DohTargets -IsEnable $true }

function Disable-AllDoh { Start-DohJob -List $script:DohTargets -IsEnable $false }

function Invoke-HostsUpdate {
    Invoke-UiCommand {
        # 1. Find PATHS
        $hostsPath = "$env:windir\System32\drivers\etc\hosts"
        $backupDir = Join-Path (Get-DataPath) "hosts_backups"
        if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

        # 2. DOWNLOAD HOSTS FILE
        $mirrors = @(
            "https://o0.pages.dev/Lite/hosts.win",
            "https://raw.githubusercontent.com/badmojr/1Hosts/master/Lite/hosts.win"
        )
        $adBlockContent = $null
        foreach ($mirror in $mirrors) {
            try {
                $wc = New-Object System.Net.WebClient
                # CRITICAL SPEED FIX: Bypasses auto-proxy detection delay (saves 1-5s)
                $wc.Proxy = $null 
                $wc.Encoding = [System.Text.Encoding]::UTF8
                
                Write-GuiLog "Downloading from $mirror..."
                $tempContent = $wc.DownloadString($mirror)
                
                # SAFETY CHECK: Ensure file is valid (> 1KB)
                if ($tempContent.Length -gt 1024) { 
                    $adBlockContent = $tempContent
                    Write-Output "Download complete ($([math]::Round($adBlockContent.Length / 1KB, 2)) KB)"
                    break 
                }
            }
            catch { 
                Write-Output "Mirror failed: $mirror" 
            }
            finally { 
                if ($wc) { $wc.Dispose() } 
            }
        }

        if (-not $adBlockContent) { 
            Write-GuiLog "ERROR: Download failed or file was empty. Aborting."
            return 
        }

        # 3. BACKUP EXISTING
        if (Test-Path $hostsPath) {
            $bkName = "hosts_$(Get-Date -F yyyyMMdd_HHmmss).bak"
            Copy-Item $hostsPath (Join-Path $backupDir $bkName) -Force
            Write-Output "Backup created: $bkName"
        }

        # 4. PRESERVE CUSTOM ENTRIES
        $customStart = "# === BEGIN USER CUSTOM ENTRIES ==="
        $customEnd = "# === END USER CUSTOM ENTRIES ==="
        $userEntries = "$customStart`r`n# Add custom entries here`r`n127.0.0.1 localhost`r`n::1 localhost`r`n$customEnd"

        if (Test-Path $hostsPath) {
            try {
                $raw = Get-Content $hostsPath -Raw
                if ($raw -match "(?s)$([regex]::Escape($customStart))(.*?)$([regex]::Escape($customEnd))") {
                    $userEntries = $matches[0]
                }
            }
            catch {}
        }

        # 5. CONSTRUCT & WRITE
        $finalContent = "$userEntries`r`n`r`n# UPDATED: $(Get-Date)`r`n$adBlockContent"
        
        try {
            # FIX: Write file as UTF-8 without Byte Order Mark (BOM)
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($hostsPath, $finalContent, $utf8NoBom)

            # FIX: Ensure Users have read access using Universal SID (Localization safe)
            try {
                $acl = Get-Acl -Path $hostsPath
                # Get Universal SID for Built-in "Users" group
                $usersSid = [System.Security.Principal.SecurityIdentifier]::new([System.Security.Principal.WellKnownSidType]::BuiltinUsersSid, $null)
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($usersSid, "ReadAndExecute", "Allow")
                $acl.SetAccessRule($rule)
                Set-Acl -Path $hostsPath -AclObject $acl
                Write-Output "Applied universal read permissions to hosts file."
            }
            catch {
                Write-Output "Warning: Could not strictly apply permissions: $($_.Exception.Message)"
            }
            
            # Validation
            if ((Get-Item $hostsPath).Length -lt 100) { throw "Write verification failed (File empty)." }
            
            ipconfig /flushdns | Out-Null
            Write-Output "Hosts file updated and DNS flushed successfully."
        }
        catch {
            Write-GuiLog "CRITICAL ERROR: $($_.Exception.Message)"
            # Restore backup if write failed
            $latestBackup = @(Get-WmtEnumeratedFiles -Path $backupDir | ForEach-Object { [System.IO.FileInfo]::new($_) } | Sort-Object CreationTime -Descending | Select-Object -First 1)
            if ($latestBackup) {
                Copy-Item $latestBackup.FullName $hostsPath -Force
                Write-GuiLog "Restored backup due to failure."
            }
        }
    } "Updating hosts file..."
}

function Show-HostsEditor {
    $hostsPath = "$env:windir\System32\drivers\etc\hosts"
    $content = ""

    if (Test-Path $hostsPath) {
        $diskSize = (Get-Item $hostsPath).Length
        $content = Get-Content $hostsPath -Raw -ErrorAction SilentlyContinue

        if ($diskSize -gt 0 -and [string]::IsNullOrWhiteSpace($content)) {
            Show-WmtMessageBox -Message "Could not read Hosts file. Aborting." -Title "Error" -Image Error | Out-Null
            return
        }
    }

    [xml]$hostsEditorXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Hosts File Editor" Width="920" Height="720" MinWidth="660" MinHeight="460"
        WindowStartupLocation="CenterOwner" Background="{DynamicResource BgDark}" Foreground="{DynamicResource TextPrimary}"
        FontFamily="Segoe UI Variable Display, Segoe UI, Arial" FontSize="13">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBox Name="txtHosts" Grid.Row="0" Margin="14" AcceptsReturn="True" AcceptsTab="True"
                 TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                 FontFamily="Consolas" FontSize="13" Background="{DynamicResource BgPanel}"/>

        <Border Grid.Row="1" Background="{DynamicResource BgPanel}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="0,1,0,0" Padding="14,10">
            <Grid>
                <TextBlock Text="Ctrl+S to Save" Foreground="{DynamicResource TextSecondary}" VerticalAlignment="Center"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                    <Button Name="btnSave" Content="Save" Width="100" Background="{DynamicResource Success}" Foreground="{DynamicResource SuccessText}" Margin="0,0,8,0"/>
                    <Button Name="btnClose" Content="Close" Width="94" IsCancel="True"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

    try {
        $dialog = New-WmtWindowFromFullXaml -Xaml $hostsEditorXaml
    }
    catch {
        Write-GuiLog "Failed to open Hosts editor: $($_.Exception.Message)"
        return
    }

    $txtHosts = $dialog.FindName("txtHosts")
    $btnSave = $dialog.FindName("btnSave")
    $btnClose = $dialog.FindName("btnClose")
    $state = @{ Dirty = $false }

    $txtHosts.Text = $content

    $SaveAction = {
        param($DialogObj, $TextBox, $FilePath)

        try {
            if ([string]::IsNullOrWhiteSpace($TextBox.Text)) {
                $check = Show-WmtMessageBox -Owner $DialogObj -Message "Save EMPTY file?" -Title "Warning" -Button YesNo -Image Warning
                if ($check -ne [System.Windows.MessageBoxResult]::Yes) { return $false }
            }

            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($FilePath, $TextBox.Text, $utf8NoBom)

            try {
                $acl = Get-Acl -Path $FilePath
                $usersSid = [System.Security.Principal.SecurityIdentifier]::new([System.Security.Principal.WellKnownSidType]::BuiltinUsersSid, $null)
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($usersSid, "ReadAndExecute", "Allow")
                $acl.SetAccessRule($rule)
                Set-Acl -Path $FilePath -AclObject $acl
            }
            catch {}

            ipconfig /flushdns | Out-Null

            if ((Get-Item $FilePath).Length -eq 0 -and $TextBox.Text.Length -gt 0) {
                throw "Write failed (0 bytes)."
            }

            $state.Dirty = $false
            if ($DialogObj) { $DialogObj.Title = "Hosts File Editor" }
            Show-WmtMessageBox -Owner $DialogObj -Message "Saved successfully and flushed DNS!" -Title "Success" -Image Information | Out-Null
            return $true
        }
        catch {
            Show-WmtMessageBox -Owner $DialogObj -Message "Error saving: $_" -Title "Error" -Image Error | Out-Null
            return $false
        }
    }

    $txtHosts.Add_TextChanged({
            $state.Dirty = $true
            if ($dialog.Title -notmatch "\*$") {
                $dialog.Title = "Hosts File Editor *"
            }
        }.GetNewClosure())

    $btnSave.Add_Click({
            $null = & $SaveAction -DialogObj $dialog -TextBox $txtHosts -FilePath $hostsPath
        }.GetNewClosure())

    $btnClose.Add_Click({ $dialog.Close() }.GetNewClosure())

    $dialog.Add_KeyDown({
            param($src, $e)
            if ($e.Key -eq [System.Windows.Input.Key]::S -and (([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -eq [System.Windows.Input.ModifierKeys]::Control)) {
                $e.Handled = $true
                $null = & $SaveAction -DialogObj $src -TextBox $txtHosts -FilePath $hostsPath
            }
        }.GetNewClosure())

    $dialog.Add_Closing({
            param($src, $e)

            if ($state.Dirty -eq $true) {
                $res = Show-WmtMessageBox -Owner $src -Message "You have unsaved changes. Save now?" -Title "Confirm" -Button YesNoCancel -Image Warning

                if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
                    $success = & $SaveAction -DialogObj $src -TextBox $txtHosts -FilePath $hostsPath
                    if (-not $success) {
                        $e.Cancel = $true
                    }
                }
                elseif ($res -eq [System.Windows.MessageBoxResult]::Cancel) {
                    $e.Cancel = $true
                }
            }
        }.GetNewClosure())

    $dialog.ShowDialog() | Out-Null
}

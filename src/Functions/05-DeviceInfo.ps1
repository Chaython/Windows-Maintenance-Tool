# Functional block generated from WMT-GUI.ps1.
# Dot-source this file; it intentionally shares WMT's script scope.

function New-WmtStorageTextBlock {
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

function Set-MyDeviceUiPlaceholders {
    (Get-Ctrl "txtDeviceOS").Text = "Gathering OS/security/account stats..."
    (Get-Ctrl "txtDeviceCPU").Text = "Gathering CPU stats..."
    (Get-Ctrl "txtDeviceRAM").Text = "Gathering RAM stats..."
    Set-MyDeviceGpuCardsPlaceholder "Gathering GPU stats..."
    (Get-Ctrl "txtDeviceMotherboard").Text = "Gathering motherboard/BIOS/TPM/chipset stats..."
    (Get-Ctrl "txtDeviceStorage").Text = "Gathering storage details..."
    (Get-Ctrl "txtDeviceNetwork").Text = "Gathering network details..."
    (Get-Ctrl "txtBatteryHealth").Text = "Health: Gathering..."
    (Get-Ctrl "txtBatteryCharge").Text = "Charge: Gathering..."
    (Get-Ctrl "txtBatteryStatus").Text = "Status: Gathering..."
    (Get-Ctrl "txtPowerPlan").Text = "Power: Gathering..."
    $batteryTimeCtrl = Get-Ctrl "txtBatteryTime"
    if ($batteryTimeCtrl) { $batteryTimeCtrl.Text = "Time Remaining: Gathering..."; $batteryTimeCtrl.Visibility = "Visible" }
    (Get-Ctrl "txtPowerDraw").Text = "Power Draw: Gathering..."
    (Get-Ctrl "txtPowerTotal").Text = "Total Power: Gathering..."
    (Get-Ctrl "txtPowerElectrical").Text = "Electrical: Gathering..."
    $storageList = Get-Ctrl "pnlDeviceStorageList"
    if ($storageList) { $storageList.Children.Clear() }
    $networkList = Get-Ctrl "pnlDeviceNetworkList"
    if ($networkList) { $networkList.Children.Clear() }
}

function Get-MyDeviceCacheEntry {
    param([string]$Section)
    if (-not $script:MyDeviceCache -or -not $script:MyDeviceCache.ContainsKey($Section)) { return $null }
    $entry = $script:MyDeviceCache[$Section]
    if (-not $entry -or -not $entry.Timestamp) { return $null }
    if (((Get-Date) - $entry.Timestamp).TotalSeconds -gt $script:MyDeviceCacheTtlSeconds) { return $null }
    return $entry.Data
}

function Set-MyDeviceCacheEntry {
    param([string]$Section, $Data)
    if (-not $script:MyDeviceCache) { $script:MyDeviceCache = @{} }
    $script:MyDeviceCache[$Section] = [pscustomobject]@{ Timestamp = Get-Date; Data = $Data }
}

function New-MyDeviceTextBlock {
    param(
        [string]$Text,
        [int]$FontSize = 13,
        [string]$Foreground = "TextSecondary",
        [string]$FontWeight = "Normal",
        [double]$MarginTop = 0
    )
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Text
    $tb.FontSize = $FontSize
    Set-WmtThemedBrush -Object $tb -Property ([System.Windows.Controls.TextBlock]::ForegroundProperty) -ColorOrKey $Foreground
    $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $tb.LineHeight = 18
    if ($FontWeight -ne "Normal") {
        switch ($FontWeight) {
            "SemiBold" { $tb.FontWeight = [System.Windows.FontWeights]::SemiBold }
            "Bold" { $tb.FontWeight = [System.Windows.FontWeights]::Bold }
            default { $tb.FontWeight = [System.Windows.FontWeights]::Normal }
        }
    }
    if ($MarginTop -gt 0) { $tb.Margin = [System.Windows.Thickness]::new(0, $MarginTop, 0, 0) }
    return $tb
}

function Get-GpuVendorFromTextBlock {
    param([string]$GpuText)
    if ($GpuText -match '(?im)^\s*Vendor:\s*(NVIDIA|AMD|Intel)\s*$') { return $matches[1] }
    if ($GpuText -match '(?i)nvidia|ven_10de') { return "NVIDIA" }
    if ($GpuText -match '(?i)amd|radeon|advanced micro devices|ven_1002') { return "AMD" }
    if ($GpuText -match '(?i)intel|iris|arc|uhd graphics|ven_8086') { return "Intel" }
    return "Unknown"
}

function Set-MyDeviceGpuCardsPlaceholder {
    param([string]$Text)
    $panel = Get-Ctrl "pnlDeviceGPUList"
    if (-not $panel) { return }
    $panel.Children.Clear()
    [void]$panel.Children.Add((New-MyDeviceTextBlock -Text $Text))
}

function Set-MyDeviceGpuCards {
    param([string]$GpuText)

    $panel = Get-Ctrl "pnlDeviceGPUList"
    if (-not $panel) { return }
    $panel.Children.Clear()

    if ([string]::IsNullOrWhiteSpace($GpuText)) {
        [void]$panel.Children.Add((New-MyDeviceTextBlock -Text "Unavailable"))
        return
    }

    $blocks = @($GpuText -split "(`r?`n){2,}" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($blocks.Count -eq 0) { $blocks = @($GpuText) }

    $index = 1
    foreach ($block in $blocks) {
        $vendor = Get-GpuVendorFromTextBlock -GpuText $block
        $lines = @($block -split "`r?`n" | Where-Object { $_ -ne $null })
        $title = if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[0])) { [string]$lines[0] } else { "GPU $index" }
        $details = if ($lines.Count -gt 1) { ($lines[1..($lines.Count - 1)] -join "`n") } else { "Vendor: $vendor" }

        $card = New-Object System.Windows.Controls.Border
        Set-WmtThemedBrush -Object $card -Property ([System.Windows.Controls.Border]::BackgroundProperty) -ColorOrKey "BgPanel"
        Set-WmtThemedBrush -Object $card -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -ColorOrKey "BorderBrush"
        $card.BorderThickness = [System.Windows.Thickness]::new(1)
        $card.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $card.Padding = [System.Windows.Thickness]::new(10)
        $card.Margin = if ($index -eq 1) { [System.Windows.Thickness]::new(0, 0, 0, 8) } else { [System.Windows.Thickness]::new(0, 4, 0, 8) }
        $card.Cursor = [System.Windows.Input.Cursors]::Hand
        $card.Tag = $vendor
        $card.ToolTip = if ($vendor -eq "Unknown") { "No known GPU vendor detected for this adapter." } else { "Open $vendor control panel for this GPU." }

        $stack = New-Object System.Windows.Controls.StackPanel
        [void]$stack.Children.Add((New-MyDeviceTextBlock -Text $title -FontSize 13 -Foreground "TextPrimary" -FontWeight "SemiBold"))
        [void]$stack.Children.Add((New-MyDeviceTextBlock -Text $details -FontSize 12 -Foreground "TextSecondary" -MarginTop 3))
        $card.Child = $stack

        $card.Add_MouseLeftButtonUp({
                param($s, $e)
                $selectedVendor = [string]$s.Tag
                if ([string]::IsNullOrWhiteSpace($selectedVendor) -or $selectedVendor -eq "Unknown") {
                    Write-GuiLog "No known GPU vendor detected for the clicked GPU entry."
                }
                else {
                    Open-GpuVendorControlPanel -Vendors @($selectedVendor)
                }
                $e.Handled = $true
            })

        [void]$panel.Children.Add($card)
        $index++
    }
}

function Set-MyDeviceSectionData {
    param($Data)
    if ($Data -is [System.Collections.ObjectModel.Collection[PSObject]]) { $Data = $Data[0] }
    if (-not $Data) { return }
    switch ([string]$Data.Section) {
        "Core" {
            if ($Data.OS) { (Get-Ctrl "txtDeviceOS").Text = $Data.OS }
            if ($Data.CPU) { (Get-Ctrl "txtDeviceCPU").Text = $Data.CPU }
            if ($Data.RAM) { (Get-Ctrl "txtDeviceRAM").Text = $Data.RAM }
            Start-MyDeviceBitLockerStatusUpdate
        }
        "GPU" { if ($Data.GPU) { Set-MyDeviceGpuCards -GpuText $Data.GPU } }
        "Motherboard" { if ($Data.MB) { (Get-Ctrl "txtDeviceMotherboard").Text = $Data.MB } }
        "Storage" {
            if ($Data.Storage) { (Get-Ctrl "txtDeviceStorage").Text = $Data.Storage }
            Set-MyDeviceStorageDetails -Devices $Data.StorageDevices
        }
        "Network" {
            if ($Data.Network) { (Get-Ctrl "txtDeviceNetwork").Text = $Data.Network }
            Set-MyDeviceNetworkDetails -Adapters $Data.NetworkAdapters
        }
        "Power" {
            (Get-Ctrl "txtBatteryHealth").Text = "Health: $($Data.BatteryHealth)"
            (Get-Ctrl "txtBatteryCharge").Text = "Charge: $($Data.BatteryCharge)"
            (Get-Ctrl "txtBatteryStatus").Text = "Status: $($Data.BatteryStatus)"
            (Get-Ctrl "txtPowerPlan").Text = "Power: $($Data.PowerPlan)"
            $batteryTimeText = [string]$Data.BatteryTime
            $batteryTimeCtrl = Get-Ctrl "txtBatteryTime"
            if ($batteryTimeCtrl) {
                if ([string]::IsNullOrWhiteSpace($batteryTimeText)) { $batteryTimeCtrl.Text = ""; $batteryTimeCtrl.Visibility = "Collapsed" }
                else { $batteryTimeCtrl.Text = "Time Remaining: $batteryTimeText"; $batteryTimeCtrl.Visibility = "Visible" }
            }
            (Get-Ctrl "txtPowerDraw").Text = "Power Draw: $($Data.PowerDraw)"
            (Get-Ctrl "txtPowerTotal").Text = "Total Power: $($Data.PowerTotal)"
            (Get-Ctrl "txtPowerElectrical").Text = "Electrical: $($Data.PowerElectrical)"
        }
    }
}

function Stop-MyDeviceSectionJobs {
    if ($script:StatsTimer) { try { $script:StatsTimer.Stop() } catch {} }
    if ($script:MyDevicePendingSections) {
        try { $script:MyDevicePendingSections.Clear() } catch {}
    }
    if ($script:MyDeviceSectionJobs) {
        foreach ($job in @($script:MyDeviceSectionJobs.Values)) {
            try { $job.PowerShell.Stop() } catch {}
            try { $job.PowerShell.Dispose() } catch {}
        }
        $script:MyDeviceSectionJobs.Clear()
    }
    if ($script:StatsRunspace) {
        try { $script:StatsRunspace.Stop() } catch {}
        try { $script:StatsRunspace.Dispose() } catch {}
        $script:StatsRunspace = $null
    }
}

function Start-MyDeviceQueuedSections {
    if (-not $script:MyDevicePendingSections -or $script:MyDevicePendingSections.Count -eq 0) { return }

    if (-not $script:MyDeviceStatsMaxConcurrent -or $script:MyDeviceStatsMaxConcurrent -lt 1) {
        $script:MyDeviceStatsMaxConcurrent = 6
    }

    while ($script:MyDeviceSectionJobs.Count -lt $script:MyDeviceStatsMaxConcurrent -and $script:MyDevicePendingSections.Count -gt 0) {
        $section = $script:MyDevicePendingSections[0]
        $script:MyDevicePendingSections.RemoveAt(0)
        Start-MyDeviceSectionJob -Name $section.Name -Body $section.Body
    }
}

function Start-MyDeviceSectionJob {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Body
    )
    $fullScript = $script:MyDeviceCommonHelpers + "`n" + $Body
    $ps = [PowerShell]::Create()
    [void]$ps.AddScript($fullScript)
    $async = $ps.BeginInvoke()
    $script:MyDeviceSectionJobs[$Name] = [pscustomobject]@{
        Name       = $Name
        PowerShell = $ps
        Async      = $async
        StartedAt  = Get-Date
    }
}

function Update-MyDeviceStats {
    param([switch]$ForceRefresh, [switch]$Preload)
    $script:MyDeviceStatsStarted = $true
    $script:StatsStartedAt = Get-Date
    $script:MyDeviceStatsPreloadMode = [bool]$Preload
    $script:MyDeviceStatsMaxConcurrent = 6
    Stop-MyDeviceSectionJobs
    $script:MyDevicePendingSections = [System.Collections.ArrayList]::new()
    Set-MyDeviceUiPlaceholders

    $sections = @(
        [pscustomobject]@{ Name = "Core"; Body = $script:MyDeviceCoreBody },
        [pscustomobject]@{ Name = "GPU"; Body = $script:MyDeviceGpuBody },
        [pscustomobject]@{ Name = "Motherboard"; Body = $script:MyDeviceMotherboardBody },
        [pscustomobject]@{ Name = "Storage"; Body = $script:MyDeviceStorageBody },
        [pscustomobject]@{ Name = "Network"; Body = $script:MyDeviceNetworkBody },
        [pscustomobject]@{ Name = "Power"; Body = $script:MyDevicePowerBody }
    )

    foreach ($section in $sections) {
        $cached = if (-not $ForceRefresh) { Get-MyDeviceCacheEntry -Section $section.Name } else { $null }
        if ($cached) {
            Set-MyDeviceSectionData -Data $cached
            if (-not $Preload) { Write-GuiLog "[My Device] Loaded $($section.Name) from RAM cache." }
        }
        else {
            [void]$script:MyDevicePendingSections.Add($section)
        }
    }

    Start-MyDeviceQueuedSections

    $hasPendingSections = ($script:MyDevicePendingSections -and $script:MyDevicePendingSections.Count -gt 0)
    if ($script:MyDeviceSectionJobs.Count -eq 0 -and -not $hasPendingSections) {
        if (-not $Preload) { Write-GuiLog "[My Device] All sections loaded from RAM cache." }
        $script:MyDeviceStatsPreloadMode = $false
        return
    }

    $script:StatsTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:StatsTimer.Interval = [TimeSpan]::FromMilliseconds(200)
    $script:StatsTimer.Add_Tick({
            if (-not $script:MyDeviceSectionJobs) { $script:MyDeviceSectionJobs = @{} }
            if ($script:MyDeviceSectionJobs.Count -eq 0) { Start-MyDeviceQueuedSections }

            foreach ($key in @($script:MyDeviceSectionJobs.Keys)) {
                $job = $script:MyDeviceSectionJobs[$key]
                if (-not $job -or -not $job.Async) { continue }
                if ($job.Async.IsCompleted) {
                    try {
                        $data = $job.PowerShell.EndInvoke($job.Async)
                        if ($data -is [System.Collections.ObjectModel.Collection[PSObject]]) { $data = $data[0] }
                        if ($data) {
                            Set-MyDeviceSectionData -Data $data
                            Set-MyDeviceCacheEntry -Section $key -Data $data
                            $elapsed = [math]::Round(((Get-Date) - $job.StartedAt).TotalSeconds, 1)
                            if (-not $script:MyDeviceStatsPreloadMode) { Write-GuiLog "[My Device] $key loaded in ${elapsed}s." }
                        }
                    }
                    catch {
                        Write-GuiLog "[My Device] $key load failed: $($_.Exception.Message)"
                    }
                    finally {
                        try { $job.PowerShell.Dispose() } catch {}
                        $script:MyDeviceSectionJobs.Remove($key)
                    }
                }
            }

            Start-MyDeviceQueuedSections

            $hasPendingSections = ($script:MyDevicePendingSections -and $script:MyDevicePendingSections.Count -gt 0)
            if ($script:MyDeviceSectionJobs.Count -eq 0 -and -not $hasPendingSections) {
                try { $script:StatsTimer.Stop() } catch {}
                if (-not $script:MyDeviceStatsPreloadMode -and $script:StatsStartedAt) {
                    $elapsed = [math]::Round(((Get-Date) - $script:StatsStartedAt).TotalSeconds, 1)
                    Write-GuiLog "[My Device] Progressive stats load finished in ${elapsed}s."
                }
                $script:MyDeviceStatsPreloadMode = $false
                return
            }
        })
    $script:StatsTimer.Start()
}

function Start-MyDeviceBitLockerStatusUpdate {
    $osText = Get-Ctrl "txtDeviceOS"
    if (-not $osText) { return }

    if ($script:BitLockerStatusTimer) {
        try { $script:BitLockerStatusTimer.Stop() } catch {}
    }
    if ($script:BitLockerStatusRunspace) {
        try { $script:BitLockerStatusRunspace.Stop() } catch {}
        try { $script:BitLockerStatusRunspace.Dispose() } catch {}
    }

    $script:BitLockerStatusRunspace = [PowerShell]::Create().AddScript({
            function Get-BitLockerStatusTextFast {
                $systemDrive = $env:SystemDrive
                if ([string]::IsNullOrWhiteSpace($systemDrive)) { return "Unavailable" }

                try {
                    if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
                        $volume = Get-BitLockerVolume -MountPoint $systemDrive -ErrorAction Stop | Select-Object -First 1
                        if ($volume) { return "$($volume.ProtectionStatus) ($($volume.VolumeStatus))" }
                    }
                }
                catch {}

                try {
                    $volume = Get-CimInstance -Namespace "root\cimv2\Security\MicrosoftVolumeEncryption" -ClassName Win32_EncryptableVolume -ErrorAction Stop |
                    Where-Object { $_.DriveLetter -eq $systemDrive } |
                    Select-Object -First 1

                    if ($volume) {
                        $protection = switch ([int]$volume.ProtectionStatus) {
                            0 { "Off" }
                            1 { "On" }
                            2 { "Unknown" }
                            default { "Unknown" }
                        }
                        $conversion = switch ([int]$volume.ConversionStatus) {
                            0 { "Fully Decrypted" }
                            1 { "Fully Encrypted" }
                            2 { "Encryption in Progress" }
                            3 { "Decryption in Progress" }
                            4 { "Encryption Paused" }
                            5 { "Decryption Paused" }
                            default { "Unknown" }
                        }
                        return "$protection ($conversion)"
                    }
                }
                catch {}

                return "Unavailable"
            }

            Get-BitLockerStatusTextFast
        })

    $script:BitLockerStatusAsyncResult = $script:BitLockerStatusRunspace.BeginInvoke()
    $script:BitLockerStatusStartedAt = Get-Date
    $script:BitLockerStatusTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:BitLockerStatusTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $script:BitLockerStatusTimer.Add_Tick({
            $timedOut = $script:BitLockerStatusStartedAt -and (((Get-Date) - $script:BitLockerStatusStartedAt).TotalSeconds -gt 20)
            if (($script:BitLockerStatusAsyncResult -and $script:BitLockerStatusAsyncResult.IsCompleted) -or $timedOut) {
                $script:BitLockerStatusTimer.Stop()
                try {
                    if ($timedOut) {
                        try { $script:BitLockerStatusRunspace.Stop() } catch {}
                        $status = "Timed out"
                    }
                    else {
                        $status = $script:BitLockerStatusRunspace.EndInvoke($script:BitLockerStatusAsyncResult)
                        if ($status -is [System.Collections.ObjectModel.Collection[PSObject]]) { $status = [string]$status[0] }
                    }
                    if ([string]::IsNullOrWhiteSpace([string]$status)) { $status = "Unavailable" }

                    $ctrl = Get-Ctrl "txtDeviceOS"
                    if ($ctrl) {
                        $replacement = "BitLocker: $status"
                        if ($ctrl.Text -match "(?m)^BitLocker:") {
                            $ctrl.Text = [regex]::Replace($ctrl.Text, "(?m)^BitLocker:.*$", $replacement)
                        }
                        else {
                            $ctrl.Text = "$($ctrl.Text)`n$replacement"
                        }
                    }
                }
                catch {}
                try { $script:BitLockerStatusRunspace.Dispose() } catch {}
                $script:BitLockerStatusRunspace = $null
                $script:BitLockerStatusAsyncResult = $null
                $script:BitLockerStatusStartedAt = $null
            }
        })
    $script:BitLockerStatusTimer.Start()
}

function Set-MyDeviceStorageDetails {
    param($Devices)

    $panel = Get-Ctrl "pnlDeviceStorageList"
    $summary = Get-Ctrl "txtDeviceStorage"
    if (-not $panel) { return }

    $panel.Children.Clear()
    $deviceList = @($Devices)

    if (-not $deviceList -or $deviceList.Count -eq 0) {
        if ($summary) { $summary.Text = "No fixed storage volumes found." }
        return
    }

    if ($summary) { $summary.Text = "Fixed volumes detected: $($deviceList.Count)" }

    for ($i = 0; $i -lt $deviceList.Count; $i++) {
        $d = $deviceList[$i]

        $header = New-Object System.Windows.Controls.Grid
        $header.Margin = if ($i -eq 0) { "0,8,0,0" } else { "0,12,0,0" }
        $colMain = New-Object System.Windows.Controls.ColumnDefinition
        $colMain.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $colHealth = New-Object System.Windows.Controls.ColumnDefinition
        $colHealth.Width = [System.Windows.GridLength]::Auto
        [void]$header.ColumnDefinitions.Add($colMain)
        [void]$header.ColumnDefinitions.Add($colHealth)

        $driveRoot = if ([string]$d.Drive -match "\\$") { [string]$d.Drive } else { "$($d.Drive)\" }
        $header.Cursor = [System.Windows.Input.Cursors]::Hand
        $header.ToolTip = "Open $driveRoot"
        $header.Add_MouseLeftButtonUp({ Open-MyDeviceDriveRoot -Drive $driveRoot }.GetNewClosure())

        $driveTitle = New-WmtStorageTextBlock -Text ("{0}  {1}" -f $d.Drive, $d.Label) -Color "Accent" -FontSize 13 -FontWeight "SemiBold"
        [void]$header.Children.Add($driveTitle)

        $healthText = New-WmtStorageTextBlock -Text $d.Health -Color $d.HealthBrush -FontSize 12 -FontWeight "SemiBold" -Margin "8,0,0,0"
        [System.Windows.Controls.Grid]::SetColumn($healthText, 1)
        [void]$header.Children.Add($healthText)
        [void]$panel.Children.Add($header)

        [void]$panel.Children.Add((New-WmtStorageTextBlock -Text $d.Hardware -Color "TextPrimary" -FontSize 12 -Margin "0,4,0,0"))
        [void]$panel.Children.Add((New-WmtStorageTextBlock -Text $d.Meta -Color "TextSecondary" -FontSize 11 -Margin "0,2,0,0"))
        [void]$panel.Children.Add((New-WmtStorageTextBlock -Text $d.Operational -Color "TextMuted" -FontSize 11 -Margin "0,2,0,0"))

        $bar = New-Object System.Windows.Controls.ProgressBar
        $bar.Minimum = 0
        $bar.Maximum = 100
        $bar.Value = [double]$d.FreePercent
        $bar.Height = 7
        $bar.Margin = "0,7,0,2"
        Set-WmtThemedBrush -Object $bar -Property ([System.Windows.Controls.Control]::ForegroundProperty) -ColorOrKey $d.FreeBrush -FallbackKey "Accent"
        Set-WmtThemedBrush -Object $bar -Property ([System.Windows.Controls.Control]::BackgroundProperty) -ColorOrKey "BorderBrush"
        [void]$panel.Children.Add($bar)

        [void]$panel.Children.Add((New-WmtStorageTextBlock -Text $d.FreeText -Color $d.FreeBrush -FontSize 12 -FontWeight "SemiBold" -Margin "0,2,0,0"))

        if ($i -lt ($deviceList.Count - 1)) {
            $separator = New-Object System.Windows.Controls.Border
            $separator.Height = 1
            Set-WmtThemedBrush -Object $separator -Property ([System.Windows.Controls.Border]::BackgroundProperty) -ColorOrKey "BorderBrush"
            $separator.Margin = "0,10,0,0"
            [void]$panel.Children.Add($separator)
        }
    }
}

function Open-MyDeviceGateway {
    param([string]$Address)

    if ([string]::IsNullOrWhiteSpace($Address)) { return }
    $target = $Address.Trim()
    if ($target -match "^\d{1,3}(\.\d{1,3}){3}$") {
        $url = "http://$target/"
    }
    elseif ($target -match ":") {
        $url = "http://[$($target -replace '%', '%25')]/"
    }
    else {
        Write-GuiLog "[Network] Unsupported gateway address: $target"
        return
    }

    try {
        Start-Process -FilePath $url
        Write-GuiLog "[Network] Opened gateway $target"
    }
    catch {
        Write-GuiLog "[Network] Failed to open gateway $target`: $($_.Exception.Message)"
    }
}

function Open-MyDeviceWifiSettings {
    try {
        Start-Process -FilePath "ms-settings:network-wifi"
        Write-GuiLog "[Network] Opened Wi-Fi settings."
    }
    catch {
        Write-GuiLog "[Network] Failed to open Wi-Fi settings: $($_.Exception.Message)"
    }
}

function Update-MyDeviceResponsiveLayout {
    $cards = Get-Ctrl "pnlMyDeviceCards"
    $scroll = Get-Ctrl "pnlMyDevice"
    if (-not $cards -or -not $scroll) { return }

    $available = [double]$scroll.ViewportWidth
    if ([double]::IsNaN($available) -or $available -le 0) { $available = [double]$scroll.ActualWidth }
    if ([double]::IsNaN($available) -or $available -le 0) { $available = [double]$window.ActualWidth }
    if ([double]::IsNaN($available) -or $available -le 0) { return }

    $marginWidth = 40.0
    $contentWidth = [math]::Max(320.0, $available - $marginWidth)
    $minCardWidth = 330.0
    $targetCardWidth = 410.0
    $columns = [math]::Floor($contentWidth / $targetCardWidth)
    if ($columns -lt 1) { $columns = 1 }
    if ($columns -gt 4) { $columns = 4 }

    while ($columns -gt 1 -and ($contentWidth / $columns) -lt $minCardWidth) {
        $columns--
    }

    $itemWidth = [math]::Floor($contentWidth / $columns)
    $newItemWidth = [math]::Max($minCardWidth, $itemWidth)
    $currentItemWidth = [double]$cards.ItemWidth
    if ([double]::IsNaN($currentItemWidth) -or [math]::Abs($currentItemWidth - $newItemWidth) -ge 1) {
        $cards.ItemWidth = $newItemWidth
    }
}

function Get-MyDeviceExportTextLines {
    param($Control)

    $lines = New-Object System.Collections.Generic.List[string]
    if (-not $Control) { return @() }

    if ($Control -is [System.Windows.Controls.TextBlock]) {
        $text = ([string]$Control.Text).Trim()
        if (-not [string]::IsNullOrWhiteSpace($text)) { [void]$lines.Add($text) }
    }
    elseif ($Control -is [System.Windows.Controls.TextBox]) {
        $text = ([string]$Control.Text).Trim()
        if (-not [string]::IsNullOrWhiteSpace($text)) { [void]$lines.Add($text) }
    }
    elseif ($Control -is [System.Windows.Controls.ContentControl]) {
        if ($Control.Content -is [string]) {
            $text = ([string]$Control.Content).Trim()
            if (-not [string]::IsNullOrWhiteSpace($text)) { [void]$lines.Add($text) }
        }
        elseif ($Control.Content -is [System.Windows.DependencyObject]) {
            foreach ($line in (Get-MyDeviceExportTextLines -Control $Control.Content)) { [void]$lines.Add($line) }
        }
    }

    if ($Control -is [System.Windows.Controls.Panel]) {
        foreach ($child in $Control.Children) {
            foreach ($line in (Get-MyDeviceExportTextLines -Control $child)) { [void]$lines.Add($line) }
        }
    }
    elseif ($Control -is [System.Windows.Controls.Decorator] -and $Control.Child) {
        foreach ($line in (Get-MyDeviceExportTextLines -Control $Control.Child)) { [void]$lines.Add($line) }
    }

    return $lines.ToArray()
}

function Add-MyDeviceExportSection {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Title,
        [string[]]$TextControlNames = @(),
        [string[]]$PanelControlNames = @()
    )

    $sectionLines = New-Object System.Collections.Generic.List[string]

    foreach ($name in $TextControlNames) {
        $ctrl = Get-Ctrl $name
        if ($ctrl -and $ctrl.Text) {
            $text = ([string]$ctrl.Text).Trim()
            if (-not [string]::IsNullOrWhiteSpace($text)) { [void]$sectionLines.Add($text) }
        }
    }

    foreach ($name in $PanelControlNames) {
        foreach ($line in (Get-MyDeviceExportTextLines -Control (Get-Ctrl $name))) {
            $text = ([string]$line).Trim()
            if (-not [string]::IsNullOrWhiteSpace($text)) { [void]$sectionLines.Add($text) }
        }
    }

    if ($sectionLines.Count -eq 0) { return }

    if ($Lines.Count -gt 0) { [void]$Lines.Add("") }
    [void]$Lines.Add($Title)
    [void]$Lines.Add(("-" * $Title.Length))

    $previous = $null
    foreach ($line in $sectionLines) {
        if ($line -ne $previous) { [void]$Lines.Add($line) }
        $previous = $line
    }
}

function Invoke-MyDeviceExport {
    try {
        $lines = New-Object System.Collections.Generic.List[string]
        [void]$lines.Add("Windows Maintenance Tool - My Device Export")
        [void]$lines.Add("Generated: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))")
        [void]$lines.Add("Computer: $env:COMPUTERNAME")

        Add-MyDeviceExportSection -Lines $lines -Title "Operating System" -TextControlNames @("txtDeviceOS")
        Add-MyDeviceExportSection -Lines $lines -Title "Network Info" -TextControlNames @("txtDeviceNetwork") -PanelControlNames @("pnlDeviceNetworkList")
        Add-MyDeviceExportSection -Lines $lines -Title "Processor (CPU)" -TextControlNames @("txtDeviceCPU")
        Add-MyDeviceExportSection -Lines $lines -Title "Battery / Power" -TextControlNames @("txtBatteryHealth", "txtBatteryCharge", "txtBatteryStatus", "txtPowerPlan", "txtBatteryTime", "txtPowerDraw", "txtPowerTotal", "txtPowerElectrical")
        Add-MyDeviceExportSection -Lines $lines -Title "Memory (RAM)" -TextControlNames @("txtDeviceRAM")
        Add-MyDeviceExportSection -Lines $lines -Title "Graphics (GPU)" -PanelControlNames @("pnlDeviceGPUList")
        Add-MyDeviceExportSection -Lines $lines -Title "Motherboard" -TextControlNames @("txtDeviceMotherboard")
        Add-MyDeviceExportSection -Lines $lines -Title "Storage Drives" -TextControlNames @("txtDeviceStorage") -PanelControlNames @("pnlDeviceStorageList")

        $outFile = Join-Path (Get-DataPath) ("MyDevice_{0}.txt" -f (Get-Date -Format "yyyy-MM-dd_HHmmss"))
        Set-Content -Path $outFile -Value $lines.ToArray() -Encoding UTF8

        Write-GuiLog "[My Device] Exported device summary to $outFile"
        [System.Windows.MessageBox]::Show("My Device export saved to:`n$outFile", "Export Complete", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
    }
    catch {
        Write-GuiLog "[My Device] Export failed: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("Failed to export My Device details:`n$($_.Exception.Message)", "Export Failed", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
    }
}

function Get-MyDeviceGpuVendors {
    try {
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
        $vendors = New-Object System.Collections.Generic.List[string]
        foreach ($gpu in $gpus) {
            $probe = "$($gpu.Name) $($gpu.AdapterCompatibility) $($gpu.PNPDeviceID)"
            if ($probe -match "(?i)nvidia|ven_10de" -and -not $vendors.Contains("NVIDIA")) { $vendors.Add("NVIDIA") }
            elseif ($probe -match "(?i)amd|radeon|advanced micro devices|ven_1002" -and -not $vendors.Contains("AMD")) { $vendors.Add("AMD") }
            elseif ($probe -match "(?i)intel|iris|arc|uhd graphics|ven_8086" -and -not $vendors.Contains("Intel")) { $vendors.Add("Intel") }
        }
        return @($vendors)
    }
    catch { return @() }
}

function Open-GpuVendorControlPanel {
    param([string[]]$Vendors)

    if (-not $Vendors -or $Vendors.Count -eq 0) { $Vendors = Get-MyDeviceGpuVendors }
    $Vendors = @($Vendors | Where-Object { $_ } | Select-Object -Unique)

    if (-not $Vendors -or $Vendors.Count -eq 0) {
        Write-GuiLog "No known GPU vendor detected for control panel launch."
        return
    }

    # Important: only try the detected/selected vendor. Do not fall through to another
    # vendor's panel if the matching panel is not installed or cannot be launched.
    $vendor = [string]$Vendors[0]
    if ($Vendors.Count -gt 1) {
        Write-GuiLog "Multiple GPU vendors detected ($($Vendors -join ', ')); trying $vendor control panel only."
    }

    $opened = $false
    switch ($vendor) {
        "NVIDIA" {
            $opened = Start-ExistingExecutable @(
                "$env:ProgramFiles\NVIDIA Corporation\Control Panel Client\nvcplui.exe",
                "${env:ProgramFiles(x86)}\NVIDIA Corporation\Control Panel Client\nvcplui.exe"
            )
            if (-not $opened) { $opened = Start-AppByStartMenuName @("(?i)^NVIDIA Control Panel$", "(?i)NVIDIA.*Control") }
            if (-not $opened) {
                try { Start-Process "nvcplui.exe"; $opened = $true } catch {}
            }
        }
        "AMD" {
            $opened = Start-ExistingExecutable @(
                "$env:ProgramFiles\AMD\CNext\CNext\RadeonSoftware.exe",
                "$env:ProgramFiles\AMD\CNext\CNext\AMDRSServ.exe",
                "$env:ProgramFiles\AMD\CNext\CCCSlim\CLIStart.exe",
                "${env:ProgramFiles(x86)}\AMD\CNext\CNext\RadeonSoftware.exe"
            )
            if (-not $opened) { $opened = Start-AppByStartMenuName @("(?i)^AMD Software", "(?i)Radeon.*Software", "(?i)AMD.*Adrenalin") }
        }
        "Intel" {
            $opened = Start-AppByStartMenuName @("(?i)Intel.*Graphics.*Command", "(?i)Intel.*Arc.*Control", "(?i)Intel.*Graphics.*Control")
            if (-not $opened) {
                $opened = Start-ExistingExecutable @(
                    "$env:ProgramFiles\WindowsApps\*\GfxUIEx.exe",
                    "$env:ProgramFiles\Intel\Intel Graphics Command Center\IGCC.exe",
                    "$env:ProgramFiles\Intel\Intel(R) Graphics Control Panel\GfxUIEx.exe",
                    "$env:SystemRoot\System32\GfxUIEx.exe"
                )
            }
        }
        default {
            Write-GuiLog "No GPU control panel launch targets are defined for vendor '$vendor'."
            return
        }
    }

    if ($opened) { Write-GuiLog "Opened $vendor GPU control panel." }
    else { Write-GuiLog "$vendor GPU control panel was not found. Use Check Drivers to open the vendor driver page." }
}

function Connect-WmtMyDeviceShortcut {
    param(
        [string]$ShortcutButtonName,
        [string]$TargetButtonName
    )

    $shortcutButton = Get-Ctrl $ShortcutButtonName
    $targetButton = Get-Ctrl $TargetButtonName
    if (-not $shortcutButton -or -not $targetButton) { return }

    try {
        $enabledBinding = [System.Windows.Data.Binding]::new("IsEnabled")
        $enabledBinding.Source = $targetButton
        [void][System.Windows.Data.BindingOperations]::SetBinding($shortcutButton, [System.Windows.Controls.Button]::IsEnabledProperty, $enabledBinding)
    }
    catch {}

    $shortcutButton.Add_Click({
            if (-not $targetButton.IsEnabled) { return }
            $targetButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        }.GetNewClosure())
}

function Open-MyDeviceDriveRoot {
    param([string]$Drive)

    if ([string]::IsNullOrWhiteSpace($Drive)) { return }
    $driveRoot = if ($Drive.EndsWith("\")) { $Drive } elseif ($Drive.EndsWith(":")) { "$Drive\" } else { "$Drive\" }

    if (-not (Test-Path -LiteralPath $driveRoot)) {
        Write-GuiLog "[Storage] Drive root not found: $driveRoot"
        return
    }

    try {
        Start-Process -FilePath "explorer.exe" -ArgumentList "`"$driveRoot`""
        Write-GuiLog "[Storage] Opened $driveRoot"
    }
    catch {
        Write-GuiLog "[Storage] Failed to open $driveRoot`: $($_.Exception.Message)"
    }
}

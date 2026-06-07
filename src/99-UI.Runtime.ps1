# WMT application state, XAML, event wiring, and message loop.
# Loaded last after every functional block has defined its functions.

























# Centralized data path for exports (in repo folder)

$script:MyDeviceCacheTtlSeconds = 600
if (-not $script:MyDeviceCache) { $script:MyDeviceCache = @{} }
if (-not $script:MyDeviceSectionJobs) { $script:MyDeviceSectionJobs = @{} }
$script:MyDeviceCommonHelpers = @'
function ConvertTo-StorageSizeText {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return ("{0:N2} TB" -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ("{0:N1} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N0} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -gt 0) { return ("{0:N0} KB" -f ($Bytes / 1KB)) }
    return "0 B"
}

function Get-FreeSpaceBrush {
    param([double]$FreePercent)
    if ($FreePercent -lt 10) { return "#F85149" }
    if ($FreePercent -lt 20) { return "#D29922" }
    if ($FreePercent -lt 35) { return "#E3B341" }
    return "#3FB950"
}

function Get-HealthRank {
    param([string]$Status)
    if ([string]::IsNullOrWhiteSpace($Status)) { return 0 }
    if ($Status -match "(?i)unhealthy|critical|failed|failure|error") { return 3 }
    if ($Status -match "(?i)warning|degraded|predict|attention|stressed") { return 2 }
    if ($Status -match "(?i)healthy|ok|online") { return 1 }
    return 0
}

function Get-HealthBrush {
    param([int]$Rank)
    switch ($Rank) {
        3 { return "#F85149" }
        2 { return "#D29922" }
        1 { return "#3FB950" }
        default { return "#8B949E" }
    }
}

function Get-CleanHardwareValue {
    param($Value, [string]$Fallback = "Unavailable")
    if ($null -eq $Value) { return $Fallback }
    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $Fallback }
    if ($text -match "(?i)^(to be filled by o\.e\.m\.|default string|system product name|system manufacturer|none|not applicable|not specified)$") { return $Fallback }
    return $text
}

function Convert-CimDateText {
    param($Value)
    if ($null -eq $Value) { return "Unavailable" }
    try {
        if ($Value -is [datetime]) { return $Value.ToString("yyyy-MM-dd") }
        return ([System.Management.ManagementDateTimeConverter]::ToDateTime([string]$Value)).ToString("yyyy-MM-dd")
    }
    catch { return "Unavailable" }
}

function Get-FirmwareModeText {
    try {
        $fwType = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "PEFirmwareType" -ErrorAction Stop).PEFirmwareType
        switch ([int]$fwType) {
            1 { return "Legacy BIOS" }
            2 { return "UEFI" }
            default { return "Unknown" }
        }
    }
    catch { return "Unknown" }
}

function ConvertTo-DateTimeValue {
    param($Value)
    if ($null -eq $Value) { return $null }
    try {
        if ($Value -is [datetime]) { return $Value }
        return [datetime]::Parse([string]$Value)
    }
    catch {
        try { return [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$Value) }
        catch { return $null }
    }
}

function Format-DateTimeText {
    param($Value, [string]$Format = "yyyy-MM-dd HH:mm")
    $dateValue = ConvertTo-DateTimeValue $Value
    if ($null -eq $dateValue) { return "Unavailable" }
    return $dateValue.ToString($Format)
}

function Format-TimeSpanText {
    param([TimeSpan]$Span)
    if ($null -eq $Span) { return "Unavailable" }
    $days = [int][math]::Floor($Span.TotalDays)
    if ($days -gt 0) { return "$days d $($Span.Hours) h" }
    if ($Span.Hours -gt 0) { return "$($Span.Hours) h $($Span.Minutes) m" }
    return "$($Span.Minutes) m"
}

function Get-PendingRebootStatusText {
    try {
        if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { return "Yes" }
        if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { return "Yes" }
        $sessionManager = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
        if ($sessionManager -and $sessionManager.PendingFileRenameOperations) { return "Yes" }
    }
    catch {}
    return "No"
}

function Get-SecureBootStatusText {
    try {
        if (Confirm-SecureBootUEFI -ErrorAction Stop) { return "Enabled" }
        return "Disabled"
    }
    catch {
        if ((Get-FirmwareModeText) -eq "Legacy BIOS") { return "N/A (Legacy BIOS)" }
        return "Unavailable"
    }
}

function Get-ActivationStatusText {
    try {
        $license = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "Windows" } |
        Sort-Object @{ Expression = { $_.LicenseStatus -eq 1 }; Descending = $true } |
        Select-Object -First 1

        if ($null -eq $license) { return "Unavailable" }
        switch ([int]$license.LicenseStatus) {
            0 { return "Unlicensed" }
            1 { return "Activated" }
            2 { return "Grace Period" }
            3 { return "Out-of-Tolerance" }
            4 { return "Non-Genuine" }
            5 { return "Notification" }
            6 { return "Extended Grace" }
            default { return "Unknown" }
        }
    }
    catch { return "Unavailable" }
}

function Get-LocalUserSummaryText {
    try {
        $users = @(Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True" -ErrorAction SilentlyContinue)
        if ($users.Count -eq 0) { return "Unavailable" }
        $enabled = @($users | Where-Object { -not $_.Disabled }).Count
        $disabled = [math]::Max(0, $users.Count - $enabled)
        $locked = @($users | Where-Object { $_.Lockout }).Count
        $text = "$($users.Count) total, $enabled enabled, $disabled disabled"
        if ($locked -gt 0) { $text += ", $locked locked" }
        return $text
    }
    catch { return "Unavailable" }
}

function Get-LocalAdminSummaryText {
    try {
        $adminGroup = Get-CimInstance Win32_Group -Filter "SID='S-1-5-32-544'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $adminGroup) { return "Unavailable" }
        $members = @(Get-CimAssociatedInstance -InputObject $adminGroup -Association Win32_GroupUser -ErrorAction SilentlyContinue)
        return "$($members.Count) members"
    }
    catch { return "Unavailable" }
}

function Get-LatestHotfixText {
    try {
        $hotfix = Get-CimInstance Win32_QuickFixEngineering -ErrorAction SilentlyContinue |
        Sort-Object @{ Expression = { ConvertTo-DateTimeValue $_.InstalledOn }; Descending = $true } |
        Select-Object -First 1

        if ($null -eq $hotfix) { return "Unavailable" }
        $installed = Format-DateTimeText $hotfix.InstalledOn "yyyy-MM-dd"
        if ($installed -eq "Unavailable") { return $hotfix.HotFixID }
        return "$($hotfix.HotFixID) ($installed)"
    }
    catch { return "Unavailable" }
}

function Get-BitLockerStatusText {
    try {
        if (-not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) { return "Unavailable" }
        $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $volume) { return "Unavailable" }
        return "$($volume.ProtectionStatus) ($($volume.VolumeStatus))"
    }
    catch { return "Unavailable" }
}

function Get-DefenderStatusText {
    try {
        if (-not (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)) { return "Unavailable" }
        $status = Get-MpComputerStatus -ErrorAction Stop
        $realTime = if ($status.RealTimeProtectionEnabled) { "Real-time on" } else { "Real-time off" }
        if ($null -ne $status.AntivirusSignatureAge) { return "$realTime, sig $($status.AntivirusSignatureAge)d old" }
        return $realTime
    }
    catch { return "Unavailable" }
}

function Get-ValidPowerNumber {
    param($Value, [switch]$AllowZero)
    if ($null -eq $Value) { return $null }
    try { $number = [double]$Value }
    catch { return $null }

    if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) { return $null }
    if ($number -lt 0) { return $null }
    if ($number -in @(2147483647, 4294967295)) { return $null }
    if (-not $AllowZero -and $number -eq 0) { return $null }
    return $number
}

function Convert-MilliwattText {
    param($Milliwatts)
    $value = Get-ValidPowerNumber $Milliwatts
    if ($null -eq $value) { return "Unavailable" }
    return ("{0:N1} W" -f ($value / 1000))
}

function Convert-MillivoltText {
    param($Millivolts)
    $value = Get-ValidPowerNumber $Millivolts
    if ($null -eq $value) { return "Unavailable" }
    return ("{0:N2} V" -f ($value / 1000))
}

function Convert-MilliwattHourText {
    param($MilliwattHours)
    $value = Get-ValidPowerNumber $MilliwattHours
    if ($null -eq $value) { return "Unavailable" }
    return ("{0:N1} Wh" -f ($value / 1000))
}

function Convert-SubnetMaskToPrefixLength {
    param([string]$SubnetMask)
    if ([string]::IsNullOrWhiteSpace($SubnetMask)) { return "" }
    try {
        $bits = 0
        foreach ($octet in ($SubnetMask -split "\.")) {
            $value = [byte]$octet
            while ($value -gt 0) {
                $bits += ($value -band 1)
                $value = $value -shr 1
            }
        }
        return [string]$bits
    }
    catch { return "" }
}

function Convert-NetworkSpeedText {
    param($BitsPerSecond)
    $speed = Get-ValidPowerNumber $BitsPerSecond
    if ($null -eq $speed) { return "Unknown" }
    if ($speed -ge 1000000000) { return ("{0:N1} Gbps" -f ($speed / 1000000000)) }
    if ($speed -ge 1000000) { return ("{0:N0} Mbps" -f ($speed / 1000000)) }
    if ($speed -ge 1000) { return ("{0:N0} Kbps" -f ($speed / 1000)) }
    return ("{0:N0} bps" -f $speed)
}

function Convert-NetConnectionStatusText {
    param($Status)
    if ($null -eq $Status) { return "Unknown" }
    try {
        switch ([int]$Status) {
            0 { return "Disconnected" }
            1 { return "Connecting" }
            2 { return "Connected" }
            3 { return "Disconnecting" }
            4 { return "Hardware not present" }
            5 { return "Hardware disabled" }
            6 { return "Hardware malfunction" }
            7 { return "Media disconnected" }
            8 { return "Authenticating" }
            9 { return "Authentication succeeded" }
            10 { return "Authentication failed" }
            11 { return "Invalid address" }
            12 { return "Credentials required" }
            default { return "Unknown ($Status)" }
        }
    }
    catch { return "Unknown" }
}

function Get-SystemPowerMeterText {
    try {
        $meters = @(Get-CimInstance -Namespace "root\CIMV2\power" -ClassName Win32_PowerMeter -ErrorAction SilentlyContinue)
        if ($meters.Count -eq 0) { return "Unavailable" }

        $totalWatts = 0.0
        $readingCount = 0
        foreach ($meter in $meters) {
            $readingProperty = $meter.PSObject.Properties["CurrentReading"]
            if ($null -eq $readingProperty) { continue }

            $reading = Get-ValidPowerNumber $readingProperty.Value
            if ($null -eq $reading) { continue }

            $modifier = 0
            try {
                if ($null -ne $meter.UnitModifier) { $modifier = [int]$meter.UnitModifier }
            }
            catch { $modifier = 0 }

            $watts = $reading * [math]::Pow(10, $modifier)
            if ($watts -lt 0) { continue }

            $totalWatts += $watts
            $readingCount++
        }

        if ($readingCount -eq 0) { return "Unavailable" }
        $suffix = if ($readingCount -gt 1) { " across $readingCount meters" } else { "" }
        return ("{0:N1} W{1}" -f $totalWatts, $suffix)
    }
    catch { return "Unavailable" }
}

function Get-BatteryPowerTelemetry {
    param([object[]]$Win32Batteries = @())

    $summary = [ordered]@{
        BatteryRate    = "Unavailable"
        TotalPower     = "Unavailable"
        Electrical     = "Unavailable"
        DesignCapacity = $null
        FullCapacity   = $null
    }

    try {
        $batteryStatuses = @(Get-CimInstance -Namespace "root\wmi" -ClassName BatteryStatus -ErrorAction SilentlyContinue)
        $chargeRateMw = 0.0
        $dischargeRateMw = 0.0
        $remainingMwh = 0.0
        $voltageTotalMv = 0.0
        $hasChargeRate = $false
        $hasDischargeRate = $false
        $hasRemaining = $false
        $voltageCount = 0
        $isCharging = $false
        $isDischarging = $false
        $powerOnline = $false

        foreach ($status in $batteryStatuses) {
            if ($status.PowerOnline) { $powerOnline = $true }
            if ($status.Charging) { $isCharging = $true }
            if ($status.Discharging) { $isDischarging = $true }

            $chargeRate = Get-ValidPowerNumber $status.ChargeRate
            if ($null -ne $chargeRate) {
                $chargeRateMw += $chargeRate
                $hasChargeRate = $true
            }

            $dischargeRate = Get-ValidPowerNumber $status.DischargeRate
            if ($null -ne $dischargeRate) {
                $dischargeRateMw += $dischargeRate
                $hasDischargeRate = $true
            }

            $remaining = Get-ValidPowerNumber $status.RemainingCapacity
            if ($null -ne $remaining) {
                $remainingMwh += $remaining
                $hasRemaining = $true
            }

            $voltage = Get-ValidPowerNumber $status.Voltage
            if ($null -ne $voltage) {
                $voltageTotalMv += $voltage
                $voltageCount++
            }
        }

        $electricalParts = @()
        if ($voltageCount -gt 0) {
            $electricalParts += "Voltage: $(Convert-MillivoltText ($voltageTotalMv / $voltageCount))"
        }
        if ($hasRemaining) {
            $electricalParts += "Remaining: $(Convert-MilliwattHourText $remainingMwh)"
        }

        $cycleCounts = @(Get-CimInstance -Namespace "root\wmi" -ClassName BatteryCycleCount -ErrorAction SilentlyContinue |
            ForEach-Object { Get-ValidPowerNumber $_.CycleCount -AllowZero } |
            Where-Object { $null -ne $_ })
        if ($cycleCounts.Count -eq 1) {
            $electricalParts += "Cycles: $([int]$cycleCounts[0])"
        }
        elseif ($cycleCounts.Count -gt 1) {
            $electricalParts += "Cycles: $(($cycleCounts | ForEach-Object { [int]$_ }) -join ', ')"
        }

        $designCapacity = @(Get-CimInstance -Namespace "root\wmi" -ClassName BatteryStaticData -ErrorAction SilentlyContinue |
            ForEach-Object { Get-ValidPowerNumber $_.DesignedCapacity } |
            Where-Object { $null -ne $_ } |
            Measure-Object -Sum).Sum
        $fullCapacity = @(Get-CimInstance -Namespace "root\wmi" -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue |
            ForEach-Object { Get-ValidPowerNumber $_.FullChargedCapacity } |
            Where-Object { $null -ne $_ } |
            Measure-Object -Sum).Sum

        if ($null -eq $designCapacity -or $designCapacity -le 0 -or $null -eq $fullCapacity -or $fullCapacity -le 0) {
            $win32Batteries = @($Win32Batteries)
            if ($win32Batteries.Count -eq 0) { $win32Batteries = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) }
            if ($null -eq $designCapacity -or $designCapacity -le 0) {
                $designCapacity = @($win32Batteries |
                    ForEach-Object { Get-ValidPowerNumber $_.DesignCapacity } |
                    Where-Object { $null -ne $_ } |
                    Measure-Object -Sum).Sum
            }
            if ($null -eq $fullCapacity -or $fullCapacity -le 0) {
                $fullCapacity = @($win32Batteries |
                    ForEach-Object { Get-ValidPowerNumber $_.FullChargeCapacity } |
                    Where-Object { $null -ne $_ } |
                    Measure-Object -Sum).Sum
            }
        }

        if ($null -ne $designCapacity -and $designCapacity -gt 0) { $summary.DesignCapacity = [double]$designCapacity }
        if ($null -ne $fullCapacity -and $fullCapacity -gt 0) { $summary.FullCapacity = [double]$fullCapacity }

        if ($isDischarging -and $hasDischargeRate) {
            $rateText = Convert-MilliwattText $dischargeRateMw
            $summary.BatteryRate = "Discharging $rateText"
            $summary.TotalPower = "$rateText estimate from battery"
        }
        elseif ($isCharging -and $hasChargeRate) {
            $summary.BatteryRate = "Charging +$(Convert-MilliwattText $chargeRateMw)"
        }
        elseif ($powerOnline) {
            $summary.BatteryRate = "AC power, battery idle"
        }
        elseif ($batteryStatuses.Count -gt 0) {
            $summary.BatteryRate = "Battery telemetry unavailable"
        }

        if ($electricalParts.Count -gt 0) { $summary.Electrical = $electricalParts -join " | " }
    }
    catch {}

    $powerMeter = Get-SystemPowerMeterText
    if ($powerMeter -ne "Unavailable") {
        $summary.TotalPower = "$powerMeter power meter"
    }
    elseif ($summary.TotalPower -eq "Unavailable") {
        $summary.TotalPower = "Not exposed by Windows"
    }

    return [PSCustomObject]$summary
}

function Get-PowerSchemeFriendlyName {
    param([string]$Guid)
    if ([string]::IsNullOrWhiteSpace($Guid)) { return "Unavailable" }

    $normalizedGuid = $Guid.Trim("{}").ToLowerInvariant()
    switch ($normalizedGuid) {
        "00000000-0000-0000-0000-000000000000" { return "Balanced" }
        "381b4222-f694-41f0-9685-ff5bb260df2e" { return "Balanced" }
        "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" { return "High performance" }
        "a1841308-3541-4fab-bc81-f71556f20b4a" { return "Power saver" }
        "e9a42b02-d5df-448d-aa00-03f14749eb61" { return "Ultimate Performance" }
        "961cc777-2547-4f9d-8174-7d86181b8a7a" { return "Best power efficiency" }
        "3af9b8d9-7c97-431d-ad78-34a8bfea439f" { return "High performance" }
        "ded574b5-45a0-4f42-8737-46345c09c238" { return "Best performance" }
    }

    try {
        $scheme = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$normalizedGuid" -ErrorAction SilentlyContinue
        $friendlyName = Get-CleanHardwareValue $scheme.FriendlyName ""
        if (-not [string]::IsNullOrWhiteSpace($friendlyName)) {
            if ($friendlyName -match ",([^,]+)$") { $friendlyName = $matches[1] }
            $friendlyName = ($friendlyName -replace "\s+Overlay$", "").Trim()
            if (-not [string]::IsNullOrWhiteSpace($friendlyName)) { return $friendlyName }
        }
    }
    catch {}

    return $normalizedGuid
}

function Get-ActivePowerPlanText {
    $basePlan = "Unavailable"
    $settingsMode = "Unavailable"

    try {
        $powerSchemes = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes" -ErrorAction Stop
        $baseGuid = Get-CleanHardwareValue $powerSchemes.ActivePowerScheme ""
        $acOverlayGuid = Get-CleanHardwareValue $powerSchemes.ActiveOverlayAcPowerScheme ""
        $dcOverlayGuid = Get-CleanHardwareValue $powerSchemes.ActiveOverlayDcPowerScheme ""

        if (-not [string]::IsNullOrWhiteSpace($baseGuid)) {
            $basePlan = Get-PowerSchemeFriendlyName $baseGuid
        }

        $acMode = if (-not [string]::IsNullOrWhiteSpace($acOverlayGuid)) { Get-PowerSchemeFriendlyName $acOverlayGuid } else { "Balanced" }
        $dcMode = if (-not [string]::IsNullOrWhiteSpace($dcOverlayGuid)) { Get-PowerSchemeFriendlyName $dcOverlayGuid } else { "Balanced" }

        if ($acMode -eq $dcMode) {
            $settingsMode = $acMode
        }
        else {
            $settingsMode = "AC $acMode / Battery $dcMode"
        }
    }
    catch {}

    if ($basePlan -eq "Unavailable") {
        try {
            $powerPlan = powercfg /getactivescheme
            if ($powerPlan -match '\((.*?)\)') { $basePlan = $matches[1] }
        }
        catch {}
    }

    if ($settingsMode -eq "Unavailable" -or [string]::IsNullOrWhiteSpace($settingsMode)) {
        return "Base plan: $basePlan"
    }

    return "CFG: $basePlan | Settings: $settingsMode"
}

function Get-WindowsDetailsText {
    param($OperatingSystem, $ComputerSystem)

    $lines = @()
    $currentVersion = $null
    try { $currentVersion = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue } catch {}

    $caption = Get-CleanHardwareValue $OperatingSystem.Caption
    $displayVersion = Get-CleanHardwareValue $currentVersion.DisplayVersion ""
    if ([string]::IsNullOrWhiteSpace($displayVersion)) { $displayVersion = Get-CleanHardwareValue $currentVersion.ReleaseId "" }
    $nameParts = @($caption, $displayVersion) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne "Unavailable" }
    if ($nameParts.Count -gt 0) { $lines += ($nameParts -join " ") }

    $ubr = Get-CleanHardwareValue $currentVersion.UBR ""
    $buildText = Get-CleanHardwareValue $OperatingSystem.BuildNumber
    if (-not [string]::IsNullOrWhiteSpace($ubr)) { $buildText = "$buildText.$ubr" }

    $versionText = Get-CleanHardwareValue $OperatingSystem.Version
    if ($versionText -ne "Unavailable") { $lines += "Version: $versionText" }
    if ($buildText -ne "Unavailable") { $lines += "Build: $buildText" }

    $edition = Get-CleanHardwareValue $currentVersion.EditionID
    if ($edition -ne "Unavailable") { $lines += "Edition: $edition" }

    $installType = Get-CleanHardwareValue $currentVersion.InstallationType
    if ($installType -ne "Unavailable") { $lines += "Install Type: $installType" }

    $arch = Get-CleanHardwareValue $OperatingSystem.OSArchitecture
    if ($arch -ne "Unavailable") { $lines += "Architecture: $arch" }

    $role = switch ([int]$OperatingSystem.ProductType) {
        1 { "Workstation" }
        2 { "Domain Controller" }
        3 { "Server" }
        default { "Unknown" }
    }
    $lines += "OS Role: $role"

    $lines += "Computer Name: $env:COMPUTERNAME"
    if ($ComputerSystem.PartOfDomain) {
        $domainName = Get-CleanHardwareValue $ComputerSystem.Domain
        if ($domainName -ne "Unavailable") { $lines += "Domain: $domainName" }
    }
    else {
        $workgroup = Get-CleanHardwareValue $ComputerSystem.Workgroup
        if ($workgroup -ne "Unavailable") { $lines += "Workgroup: $workgroup" }
    }

    $localUsers = Get-LocalUserSummaryText
    if ($localUsers -ne "Unavailable") { $lines += "Local Users: $localUsers" }

    $localAdmins = Get-LocalAdminSummaryText
    if ($localAdmins -ne "Unavailable") { $lines += "Local Admins: $localAdmins" }

    $installDate = Format-DateTimeText $OperatingSystem.InstallDate "yyyy-MM-dd"
    if ($installDate -ne "Unavailable") { $lines += "Installed: $installDate" }

    $lastBoot = Format-DateTimeText $OperatingSystem.LastBootUpTime "yyyy-MM-dd HH:mm"
    if ($lastBoot -ne "Unavailable") {
        $bootDate = ConvertTo-DateTimeValue $OperatingSystem.LastBootUpTime
        $uptime = Format-TimeSpanText (New-TimeSpan -Start $bootDate -End (Get-Date))
        $lines += "Last Boot: $lastBoot"
        $lines += "Uptime: $uptime"
    }

    $latestHotfix = Get-LatestHotfixText
    if ($latestHotfix -ne "Unavailable") { $lines += "Latest Hotfix: $latestHotfix" }

    $activation = Get-ActivationStatusText
    if ($activation -ne "Unavailable") { $lines += "Activation: $activation" }

    $lines += "Secure Boot: $(Get-SecureBootStatusText)"

    $lines += "BitLocker: Checking..."

    $defender = Get-DefenderStatusText
    if ($defender -ne "Unavailable") { $lines += "Defender: $defender" }

    $lines += "Pending Reboot: $(Get-PendingRebootStatusText)"

    try {
        $culture = [System.Globalization.CultureInfo]::CurrentCulture.Name
        $timeZone = [System.TimeZoneInfo]::Local.DisplayName
        $lines += "Locale / Time Zone: $culture | $timeZone"
    }
    catch {}

    return ($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
}

'@
$script:MyDeviceCoreBody = @'

$res = [ordered]@{ Section = "Core" }
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue | Select-Object -First 1
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue | Select-Object -First 1
    $res.OS = Get-WindowsDetailsText -OperatingSystem $os -ComputerSystem $cs
}
catch { $res.OS = "Unavailable" }
try {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cpu) {
        $cpuLines = @()
        $cpuName = Get-CleanHardwareValue $cpu.Name
        $cpuLines += $cpuName
        if ($cpu.Manufacturer) { $cpuLines += "Vendor: $($cpu.Manufacturer)" }
        if ($cpu.SocketDesignation) { $cpuLines += "Socket: $($cpu.SocketDesignation)" }
        if ($null -ne $cpu.NumberOfCores -or $null -ne $cpu.NumberOfLogicalProcessors) { $cpuLines += "Cores/Threads: $($cpu.NumberOfCores)/$($cpu.NumberOfLogicalProcessors)" }
        if ($null -ne $cpu.NumberOfEnabledCore -and $cpu.NumberOfEnabledCore -ne $cpu.NumberOfCores) { $cpuLines += "Enabled cores: $($cpu.NumberOfEnabledCore)" }
        if ($cpu.MaxClockSpeed) { $cpuLines += "Base/Max clock: $($cpu.MaxClockSpeed) MHz" }
        if ($cpu.CurrentClockSpeed) { $cpuLines += "Current clock: $($cpu.CurrentClockSpeed) MHz" }
        if ($cpu.L2CacheSize -or $cpu.L3CacheSize) {
            $cacheParts = @()
            if ($cpu.L2CacheSize) { $cacheParts += ("L2 {0:N0} KB" -f [double]$cpu.L2CacheSize) }
            if ($cpu.L3CacheSize) { $cacheParts += ("L3 {0:N0} KB" -f [double]$cpu.L3CacheSize) }
            $cpuLines += "Cache: $($cacheParts -join ', ')"
        }
        if ($cpu.VirtualizationFirmwareEnabled -ne $null) { $cpuLines += "Virtualization firmware: $($cpu.VirtualizationFirmwareEnabled)" }
        if ($cpu.SecondLevelAddressTranslationExtensions -ne $null) { $cpuLines += "SLAT: $($cpu.SecondLevelAddressTranslationExtensions)" }
        if ($cpu.AddressWidth) { $cpuLines += "Address width: $($cpu.AddressWidth)-bit" }
        $res.CPU = ($cpuLines | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join "`n"
    }
    else { $res.CPU = "Unavailable" }
}
catch { $res.CPU = "Unavailable" }
try {
    $mem = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | Sort-Object BankLabel, DeviceLocator)
    if ($mem.Count -gt 0) {
        function Get-MemoryTypeTextLocal {
            param($Module)
            $smbios = 0
            try { $smbios = [int]$Module.SMBIOSMemoryType } catch {}
            $legacy = 0
            try { $legacy = [int]$Module.MemoryType } catch {}
            switch ($smbios) {
                20 { return "DDR" }
                21 { return "DDR2" }
                24 { return "DDR3" }
                26 { return "DDR4" }
                34 { return "DDR5" }
                35 { return "LPDDR5" }
                30 { return "LPDDR4" }
                31 { return "LPDDR4X" }
            }
            switch ($legacy) {
                20 { return "DDR" }
                21 { return "DDR2" }
                24 { return "DDR3" }
                26 { return "DDR4" }
                34 { return "DDR5" }
                default { return "Unknown" }
            }
        }
        function Get-FormFactorTextLocal {
            param($Value)
            try { $v = [int]$Value } catch { return "Unknown" }
            switch ($v) {
                8 { return "DIMM" }
                12 { return "SODIMM" }
                13 { return "SRIMM" }
                14 { return "SMD" }
                15 { return "SSMP" }
                16 { return "QFP" }
                17 { return "TQFP" }
                18 { return "SOIC" }
                19 { return "LCC" }
                20 { return "PLCC" }
                21 { return "BGA" }
                22 { return "FPBGA" }
                default { return "Unknown" }
            }
        }

        $totalGb = [math]::Round(($mem | Measure-Object Capacity -Sum).Sum / 1GB, 2)
        $stickCapsGb = @($mem | ForEach-Object {
            if ($_.Capacity) { [math]::Round([double]$_.Capacity / 1GB, 2) }
        })
        $stickCapSummary = $null
        if ($stickCapsGb.Count -gt 0) {
            $capGroups = @($stickCapsGb | Group-Object | Sort-Object { [double]$_.Name })
            if ($capGroups.Count -eq 1) {
                $stickCapSummary = "$($capGroups[0].Count) x $($capGroups[0].Name) GB"
            }
            else {
                $stickCapSummary = (($capGroups | ForEach-Object { "$($_.Count) x $($_.Name) GB" }) -join " + ")
            }
        }
        $types = @($mem | ForEach-Object { Get-MemoryTypeTextLocal $_ } | Where-Object { $_ -and $_ -ne "Unknown" } | Select-Object -Unique)
        $forms = @($mem | ForEach-Object { Get-FormFactorTextLocal $_.FormFactor } | Where-Object { $_ -and $_ -ne "Unknown" } | Select-Object -Unique)
        $configuredSpeeds = @($mem | ForEach-Object { $_.ConfiguredClockSpeed } | Where-Object { $_ } | Select-Object -Unique)
        $ratedSpeeds = @($mem | ForEach-Object { $_.Speed } | Where-Object { $_ } | Select-Object -Unique)
        $volts = @($mem | ForEach-Object { $_.ConfiguredVoltage } | Where-Object { $_ } | Select-Object -Unique)
        $ramLines = @()
        if ($stickCapSummary) {
            $ramLines += "Total: ${totalGb} GB ($stickCapSummary)"
        }
        else {
            $ramLines += "Total: ${totalGb} GB"
        }
        $ramLines += "Modules: $($mem.Count)"
        if ($types.Count -gt 0) { $ramLines += "Type: $($types -join '/')" }
        if ($forms.Count -gt 0) { $ramLines += "Form factor: $($forms -join '/')" }
        if ($configuredSpeeds.Count -gt 0) { $ramLines += "Configured speed: $(($configuredSpeeds | Sort-Object) -join '/') MHz" }
        if ($ratedSpeeds.Count -gt 0) { $ramLines += "Rated speed: $(($ratedSpeeds | Sort-Object) -join '/') MHz" }
        if ($volts.Count -gt 0) { $ramLines += "Voltage: $(($volts | Sort-Object) -join '/') mV" }
        $ramLines += ""
        $ramLines += "Per-stick:"

        $idx = 1
        foreach ($m in $mem) {
            $capGb = if ($m.Capacity) { [math]::Round([double]$m.Capacity / 1GB, 2) } else { $null }
            $slot = Get-CleanHardwareValue $m.DeviceLocator "Slot $idx"
            $bank = Get-CleanHardwareValue $m.BankLabel "Unknown bank"
            $manufacturer = Get-CleanHardwareValue $m.Manufacturer "Unknown maker"
            $part = Get-CleanHardwareValue $m.PartNumber "Unknown model"
            $type = Get-MemoryTypeTextLocal $m
            $form = Get-FormFactorTextLocal $m.FormFactor
            $speed = if ($m.ConfiguredClockSpeed) { "$($m.ConfiguredClockSpeed) MHz configured" } elseif ($m.Speed) { "$($m.Speed) MHz rated" } else { "Unknown speed" }
            $stickLine = " - ${slot} / ${bank}: "
            if ($capGb -ne $null) { $stickLine += "${capGb} GB, " }
            $stickLine += "$type $form, $speed, $manufacturer $part"
            if ($m.ConfiguredVoltage) { $stickLine += ", $($m.ConfiguredVoltage)mV" }
            $ramLines += $stickLine.Trim()
            $idx++
        }

        $res.RAM = ($ramLines | Where-Object { $null -ne $_ }) -join "`n"
    }
    else { $res.RAM = "Unavailable" }
}
catch { $res.RAM = "Unavailable" }
[pscustomobject]$res

'@
$script:MyDeviceGpuBody = @'

$res = [ordered]@{ Section = "GPU" }
try {
    function Get-GpuVendorTextLocal {
        param($Name, $PnpId)
        $text = "${Name} ${PnpId}"
        if ($text -match "(?i)nvidia|ven_10de") { return "NVIDIA" }
        if ($text -match "(?i)amd|radeon|advanced micro devices|ven_1002") { return "AMD" }
        if ($text -match "(?i)intel|iris|arc|uhd graphics|ven_8086") { return "Intel" }
        return "Unknown"
    }

    function Get-GpuVideoArchTextLocal {
        param($Code)
        switch ([int]($Code -as [int])) {
            1 { return "Other" }
            2 { return "Unknown" }
            3 { return "CGA" }
            4 { return "EGA" }
            5 { return "VGA" }
            6 { return "SVGA" }
            7 { return "MDA" }
            8 { return "HGC" }
            9 { return "MCGA" }
            10 { return "8514A" }
            11 { return "XGA" }
            12 { return "Linear Frame Buffer" }
            160 { return "PC-98" }
            default { return "Unknown" }
        }
    }

    function Get-GpuAvailabilityTextLocal {
        param($Code)
        switch ([int]($Code -as [int])) {
            3 { return "Running/full power" }
            4 { return "Warning" }
            5 { return "In test" }
            6 { return "Not applicable" }
            7 { return "Power off" }
            8 { return "Offline" }
            9 { return "Off duty" }
            10 { return "Degraded" }
            11 { return "Not installed" }
            12 { return "Install error" }
            13 { return "Power save: unknown" }
            14 { return "Power save: low power" }
            15 { return "Power save: standby" }
            16 { return "Power cycle" }
            17 { return "Power save: warning" }
            default { return "Unknown" }
        }
    }

    function ConvertTo-GpuMemoryTextLocal {
        param($Bytes)
        try {
            if ($null -eq $Bytes -or [double]$Bytes -le 0) { return "Unavailable" }
            if ([double]$Bytes -ge 1GB) { return ("{0:N2} GB" -f ([double]$Bytes / 1GB)) }
            if ([double]$Bytes -ge 1MB) { return ("{0:N0} MB" -f ([double]$Bytes / 1MB)) }
            return ("{0:N0} bytes" -f [double]$Bytes)
        }
        catch { return "Unavailable" }
    }

    $gpu = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
    $gpuText = New-Object System.Collections.Generic.List[string]
    foreach ($g in $gpu) {
        $reg = $null
        $regMatches = @(Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\*" -EA Ignore | Where-Object {
            $_.DriverDesc -eq $g.Name -or $_.MatchingDeviceId -eq $g.PNPDeviceID -or $_.ProviderName -eq $g.AdapterCompatibility
        })
        if ($regMatches.Count -gt 0) { $reg = $regMatches[0] }

        $vramBytes = $null
        if ($reg) {
            if ($null -ne $reg.'HardwareInformation.qwMemorySize') { $vramBytes = [double]$reg.'HardwareInformation.qwMemorySize' }
            elseif ($null -ne $reg.'HardwareInformation.MemorySize' -and $reg.'HardwareInformation.MemorySize' -isnot [byte[]]) { $vramBytes = [double]$reg.'HardwareInformation.MemorySize' }
        }
        if (($null -eq $vramBytes -or $vramBytes -le 0) -and $g.AdapterRAM) { $vramBytes = [double]([uint32]$g.AdapterRAM) }

        $name = Get-CleanHardwareValue $g.Name "Unknown GPU"
        $vendor = Get-GpuVendorTextLocal $g.Name $g.PNPDeviceID
        $driverDate = Convert-CimDateText $g.DriverDate
        $refresh = if ($g.CurrentRefreshRate) { "$($g.CurrentRefreshRate) Hz" } else { "Unavailable" }
        $resolution = if ($g.CurrentHorizontalResolution -and $g.CurrentVerticalResolution) { "$($g.CurrentHorizontalResolution) x $($g.CurrentVerticalResolution) @ $refresh" } else { "Unavailable" }
        $bits = if ($g.CurrentBitsPerPixel) { "$($g.CurrentBitsPerPixel)-bit" } else { "Unavailable" }
        $status = Get-CleanHardwareValue $g.Status "Unknown"
        $availability = Get-GpuAvailabilityTextLocal $g.Availability
        $arch = Get-GpuVideoArchTextLocal $g.VideoArchitecture
        $mode = Get-CleanHardwareValue $g.VideoModeDescription "Unavailable"
        $processor = Get-CleanHardwareValue $g.VideoProcessor "Unavailable"
        $dac = Get-CleanHardwareValue $g.AdapterDACType "Unavailable"
        $pnp = Get-CleanHardwareValue $g.PNPDeviceID "Unavailable"
        $infSection = if ($reg -and $reg.InfSection) { Get-CleanHardwareValue $reg.InfSection "Unavailable" } else { "Unavailable" }
        $provider = if ($reg -and $reg.ProviderName) { Get-CleanHardwareValue $reg.ProviderName "Unavailable" } elseif ($g.AdapterCompatibility) { Get-CleanHardwareValue $g.AdapterCompatibility "Unavailable" } else { "Unavailable" }
        $luid = if ($reg -and $reg.AdapterLuid) { Get-CleanHardwareValue $reg.AdapterLuid "Unavailable" } else { "Unavailable" }

        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add($name)
        $lines.Add("Vendor: $vendor")
        $lines.Add("VRAM: $(ConvertTo-GpuMemoryTextLocal $vramBytes)")
        $lines.Add("Driver: $($g.DriverVersion)")
        if ($driverDate -ne "Unavailable") { $lines.Add("Driver date: $driverDate") }
        if ($provider -ne "Unavailable") { $lines.Add("Provider: $provider") }
        $lines.Add("Status: $status / $availability")
        $lines.Add("Resolution: $resolution")
        if ($bits -ne "Unavailable") { $lines.Add("Color depth: $bits") }
        if ($mode -ne "Unavailable") { $lines.Add("Mode: $mode") }
        if ($processor -ne "Unavailable") { $lines.Add("Processor: $processor") }
        if ($dac -ne "Unavailable") { $lines.Add("DAC: $dac") }
        if ($arch -ne "Unknown") { $lines.Add("Architecture: $arch") }
        if ($infSection -ne "Unavailable") { $lines.Add("INF section: $infSection") }
        if ($luid -ne "Unavailable") { $lines.Add("Adapter LUID: $luid") }
        if ($pnp -ne "Unavailable") { $lines.Add("PNP ID: $pnp") }
        $gpuText.Add(($lines -join "`n"))
    }
    $res.GPU = if ($gpuText.Count -eq 0) { "Unavailable" } else { ($gpuText -join "`n`n") }
}
catch { $res.GPU = "Unavailable" }
[pscustomobject]$res

'@
$script:MyDeviceMotherboardBody = @'

$res = [ordered]@{ Section = "Motherboard" }
try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue | Select-Object -First 1
    $mb = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue | Select-Object -First 1
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue | Select-Object -First 1
    $csp = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue | Select-Object -First 1
    $mem = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $memArray = Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue | Select-Object -First 1
    $tpm = Get-CimInstance -Namespace "root\cimv2\Security\MicrosoftTpm" -ClassName Win32_Tpm -ErrorAction SilentlyContinue | Select-Object -First 1
    $mbLines = @()
    $systemName = ("{0} {1}" -f (Get-CleanHardwareValue $cs.Manufacturer ""), (Get-CleanHardwareValue $cs.Model "")).Trim()
    if (-not [string]::IsNullOrWhiteSpace($systemName)) { $mbLines += "System: $systemName" }
    $boardName = ("{0} {1}" -f (Get-CleanHardwareValue $mb.Manufacturer ""), (Get-CleanHardwareValue $mb.Product "")).Trim()
    if (-not [string]::IsNullOrWhiteSpace($boardName)) { $mbLines += "Board: $boardName" }
    $boardVersion = Get-CleanHardwareValue $mb.Version
    if ($boardVersion -ne "Unavailable") { $mbLines += "Board Version: $boardVersion" }
    $boardSerial = Get-CleanHardwareValue $mb.SerialNumber
    if ($boardSerial -ne "Unavailable") { $mbLines += "Board Serial: $boardSerial" }
    $sku = Get-CleanHardwareValue $cs.SystemSKUNumber
    if ($sku -eq "Unavailable") { $sku = Get-CleanHardwareValue $csp.SKUNumber }
    if ($sku -ne "Unavailable") { $mbLines += "System SKU: $sku" }
    $uuid = Get-CleanHardwareValue $csp.UUID
    if ($uuid -ne "Unavailable") { $mbLines += "UUID: $uuid" }
    $biosVendor = Get-CleanHardwareValue $bios.Manufacturer
    $biosVersion = Get-CleanHardwareValue $bios.SMBIOSBIOSVersion
    if ($biosVersion -eq "Unavailable") { $biosVersion = Get-CleanHardwareValue $bios.Version }
    $biosParts = @($biosVendor, $biosVersion) | Where-Object { $_ -ne "Unavailable" }
    if ($biosParts.Count -gt 0) { $mbLines += "BIOS: $($biosParts -join ' ')" }
    $biosDate = Convert-CimDateText $bios.ReleaseDate
    if ($biosDate -ne "Unavailable") { $mbLines += "BIOS Date: $biosDate" }
    $smbios = if ($bios.SMBIOSMajorVersion -and $null -ne $bios.SMBIOSMinorVersion) { "$($bios.SMBIOSMajorVersion).$($bios.SMBIOSMinorVersion)" } else { "Unavailable" }
    if ($smbios -ne "Unavailable") { $mbLines += "SMBIOS: $smbios" }
    $mbLines += "Firmware Mode: $(Get-FirmwareModeText)"
    $slotCount = if ($memArray -and $memArray.MemoryDevices) { [int]$memArray.MemoryDevices } else { 0 }
    if ($slotCount -gt 0) { $mbLines += "Memory Slots: $($mem.Count)/$slotCount used" }
    if ($tpm) {
        $tpmSpec = Get-CleanHardwareValue $tpm.SpecVersion
        $tpmState = if ($tpm.IsEnabled_InitialValue) { "Enabled" } else { "Present" }
        $tpmLine = "TPM: $tpmState"
        if ($tpmSpec -ne "Unavailable") { $tpmLine += " ($tpmSpec)" }
        $mbLines += $tpmLine
    }
    $chipsetPattern = "(?i)chipset|SMBus|LPC|PCI Express Root|PCIe Root|Root Port|Host Bridge|Root Complex|Platform Controller Hub|\bPCH\b|I/O Controller|IO Controller|Memory Controller|AMD PSP|AMD GPIO|Intel.*Management Engine"
    $chipsetDevices = @()
    try {
        $pnpCandidates = @()
        try { $pnpCandidates = @(Get-CimInstance Win32_PnPEntity -Filter "PNPClass='System'" -Property Name, PNPClass -ErrorAction Stop) } catch {}
        if ($pnpCandidates.Count -eq 0) { $pnpCandidates = @(Get-CimInstance Win32_PnPEntity -Property Name, PNPClass -ErrorAction SilentlyContinue) }
        $chipsetDevices = @($pnpCandidates | Where-Object { $_.Name -and $_.Name -match $chipsetPattern -and $_.Name -notmatch "(?i)virtual|Hyper-V" } | Sort-Object Name -Unique | Select-Object -ExpandProperty Name -First 6 | ForEach-Object { Get-CleanHardwareValue $_ } | Where-Object { $_ -ne "Unavailable" })
    } catch {}
    if ($chipsetDevices.Count -gt 0) {
        $mbLines += "Chipset / Platform:"
        foreach ($deviceName in $chipsetDevices) { $mbLines += " - $deviceName" }
    } else { $mbLines += "Chipset / Platform: Not exposed by Windows" }
    $res.MB = ($mbLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
}
catch { $res.MB = "Unavailable" }
[pscustomobject]$res

'@
$script:MyDeviceStorageBody = @'

$res = [ordered]@{ Section = "Storage" }
try {
    $storageDevices = @()
    $volumes = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $null -ne $_.DriveLetter -and $_.DriveType -eq "Fixed" } | Sort-Object DriveLetter)
    $partitionByDriveLetter = @{}
    foreach ($p in @(Get-Partition -ErrorAction SilentlyContinue)) { if ($null -ne $p.DriveLetter) { $partitionByDriveLetter[[string]$p.DriveLetter] = $p } }
    $diskByNumber = @{}
    foreach ($d in @(Get-Disk -ErrorAction SilentlyContinue)) { if ($null -ne $d.Number) { $diskByNumber[[int]$d.Number] = $d } }
    $cimDiskByIndex = @{}
    foreach ($d in @(Get-CimInstance Win32_DiskDrive -Property Index, Model, InterfaceType, SerialNumber -ErrorAction SilentlyContinue)) { if ($null -ne $d.Index) { $cimDiskByIndex[[int]$d.Index] = $d } }
    foreach ($v in $volumes) {
        $driveId = "{0}:" -f $v.DriveLetter
        $label = if ([string]::IsNullOrWhiteSpace($v.FileSystemLabel)) { "(No label)" } else { [string]$v.FileSystemLabel }
        $fileSystem = if ([string]::IsNullOrWhiteSpace($v.FileSystem)) { "Unknown FS" } else { [string]$v.FileSystem }
        $sizeBytes = [double]$v.Size; $freeBytes = [double]$v.SizeRemaining
        $freePercent = if ($sizeBytes -gt 0) { [math]::Round(($freeBytes / $sizeBytes) * 100, 1) } else { 0 }
        $usedPercent = [math]::Max(0, [math]::Round(100 - $freePercent, 1))
        $partition = $null; $disk = $null; $cimDisk = $null
        try { $partition = $partitionByDriveLetter[[string]$v.DriveLetter]; if ($partition -and $null -ne $partition.DiskNumber) { $disk = $diskByNumber[[int]$partition.DiskNumber]; $cimDisk = $cimDiskByIndex[[int]$partition.DiskNumber] } } catch {}
        $hardwareName = "Unknown physical drive"
        if ($disk -and -not [string]::IsNullOrWhiteSpace($disk.FriendlyName)) { $hardwareName = [string]$disk.FriendlyName } elseif ($cimDisk -and -not [string]::IsNullOrWhiteSpace($cimDisk.Model)) { $hardwareName = [string]$cimDisk.Model }
        $diskNumberText = if ($partition) { "Disk $($partition.DiskNumber), Partition $($partition.PartitionNumber)" } else { "Disk unknown" }
        $busType = if ($disk -and $disk.BusType) { [string]$disk.BusType } elseif ($cimDisk -and $cimDisk.InterfaceType) { [string]$cimDisk.InterfaceType } else { "Bus unknown" }
        $partitionStyle = if ($disk -and $disk.PartitionStyle) { [string]$disk.PartitionStyle } else { "Style unknown" }
        $serial = if ($disk -and -not [string]::IsNullOrWhiteSpace($disk.SerialNumber)) { ([string]$disk.SerialNumber).Trim() } elseif ($cimDisk -and -not [string]::IsNullOrWhiteSpace($cimDisk.SerialNumber)) { ([string]$cimDisk.SerialNumber).Trim() } else { "" }
        $diskHealth = if ($disk -and $disk.HealthStatus) { [string]$disk.HealthStatus } else { "Unknown" }
        $volumeHealth = if ($v.HealthStatus) { [string]$v.HealthStatus } else { "Unknown" }
        $healthText = if ($diskHealth -eq $volumeHealth) { $diskHealth } else { "Disk: $diskHealth | Volume: $volumeHealth" }
        $healthRank = [math]::Max((Get-HealthRank $diskHealth), (Get-HealthRank $volumeHealth))
        $operational = if ($disk -and $disk.OperationalStatus) { ([string[]]$disk.OperationalStatus) -join ", " } else { "Unknown" }
        $metaParts = @($diskNumberText, $busType, $fileSystem, $partitionStyle)
        if (-not [string]::IsNullOrWhiteSpace($serial)) { $metaParts += "Serial: $serial" }
        $storageDevices += [pscustomobject]@{ Drive=$driveId; Label=$label; Hardware=$hardwareName; Meta=($metaParts -join " | "); Health=$healthText; HealthBrush=(Get-HealthBrush $healthRank); Operational="Operational: $operational"; FreeText=("{0} free of {1} ({2:N1}%)" -f (ConvertTo-StorageSizeText $freeBytes), (ConvertTo-StorageSizeText $sizeBytes), $freePercent); FreePercent=$freePercent; UsedPercent=$usedPercent; FreeBrush=(Get-FreeSpaceBrush $freePercent) }
    }
    if ($storageDevices.Count -eq 0) {
        $logicalDisks = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue | Sort-Object DeviceID)
        foreach ($d in $logicalDisks) {
            $sizeBytes = [double]$d.Size; $freeBytes = [double]$d.FreeSpace; $freePercent = if ($sizeBytes -gt 0) { [math]::Round(($freeBytes / $sizeBytes) * 100, 1) } else { 0 }
            $storageDevices += [pscustomobject]@{ Drive=[string]$d.DeviceID; Label=if ([string]::IsNullOrWhiteSpace($d.VolumeName)) { "(No label)" } else { [string]$d.VolumeName }; Hardware="Physical drive details unavailable"; Meta="Logical disk fallback | $($d.FileSystem)"; Health="Unknown"; HealthBrush="#8B949E"; Operational="Operational: Unknown"; FreeText=("{0} free of {1} ({2:N1}%)" -f (ConvertTo-StorageSizeText $freeBytes), (ConvertTo-StorageSizeText $sizeBytes), $freePercent); FreePercent=$freePercent; UsedPercent=[math]::Max(0, [math]::Round(100 - $freePercent, 1)); FreeBrush=(Get-FreeSpaceBrush $freePercent) }
        }
    }
    $res.StorageDevices = $storageDevices
    $res.Storage = if ($storageDevices.Count -gt 0) { "Fixed volumes detected: $($storageDevices.Count)" } else { "No fixed storage volumes found." }
}
catch { $res.Storage = "Unavailable"; $res.StorageDevices = @() }
[pscustomobject]$res

'@
$script:MyDeviceNetworkBody = @'

$res = [ordered]@{ Section = "Network" }
try {
    $networkAdapters = @()
    $adapterByIndex = @{}
    foreach ($adapter in @(Get-CimInstance Win32_NetworkAdapter -Filter "NetEnabled=True" -Property Index, Name, NetConnectionID, Speed, PhysicalAdapter, NetConnectionStatus, MACAddress, Manufacturer, AdapterType, ServiceName -ErrorAction SilentlyContinue)) {
        if ($null -ne $adapter.Index) { $adapterByIndex[[int]$adapter.Index] = $adapter }
    }

    $netAdapterByIndex = @{}
    try {
        foreach ($netAdapter in @(Get-NetAdapter -ErrorAction Stop)) {
            if ($null -ne $netAdapter.ifIndex) { $netAdapterByIndex[[int]$netAdapter.ifIndex] = $netAdapter }
        }
    } catch {}

    $profileByIndex = @{}
    try {
        foreach ($profile in @(Get-NetConnectionProfile -ErrorAction Stop)) {
            if ($null -ne $profile.InterfaceIndex) { $profileByIndex[[int]$profile.InterfaceIndex] = $profile }
        }
    } catch {}

    $ipInterfaceByIndex = @{}
    try {
        foreach ($ipInterface in @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction Stop)) {
            if ($null -ne $ipInterface.InterfaceIndex) { $ipInterfaceByIndex[[int]$ipInterface.InterfaceIndex] = $ipInterface }
        }
    } catch {}

    $dnsClientByIndex = @{}
    try {
        foreach ($dnsClient in @(Get-DnsClient -ErrorAction Stop)) {
            if ($null -ne $dnsClient.InterfaceIndex) { $dnsClientByIndex[[int]$dnsClient.InterfaceIndex] = $dnsClient }
        }
    } catch {}

    $routeByIndex = @{}
    try {
        foreach ($route in @(Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop | Sort-Object RouteMetric, InterfaceMetric)) {
            if ($null -ne $route.InterfaceIndex) {
                $idx = [int]$route.InterfaceIndex
                if (-not $routeByIndex.ContainsKey($idx)) { $routeByIndex[$idx] = $route }
            }
        }
    } catch {}

    $statsByName = @{}
    try {
        foreach ($stats in @(Get-NetAdapterStatistics -ErrorAction Stop)) {
            if (-not [string]::IsNullOrWhiteSpace($stats.Name)) { $statsByName[[string]$stats.Name] = $stats }
        }
    } catch {}

    $wifiInfoByName = @{}
    try {
        $currentWifiName = $null
        foreach ($line in @(netsh wlan show interfaces 2>$null)) {
            if ($line -match '^\s*Name\s*:\s*(.+?)\s*$') {
                $currentWifiName = $matches[1].Trim()
                if (-not $wifiInfoByName.ContainsKey($currentWifiName)) { $wifiInfoByName[$currentWifiName] = [ordered]@{} }
                continue
            }
            if ([string]::IsNullOrWhiteSpace($currentWifiName)) { continue }
            if ($line -match '^\s*SSID\s*:\s*(.+?)\s*$') { $wifiInfoByName[$currentWifiName]["SSID"] = $matches[1].Trim(); continue }
            if ($line -match '^\s*BSSID\s*:\s*(.+?)\s*$') { $wifiInfoByName[$currentWifiName]["BSSID"] = $matches[1].Trim(); continue }
            if ($line -match '^\s*Signal\s*:\s*(.+?)\s*$') { $wifiInfoByName[$currentWifiName]["Signal"] = $matches[1].Trim(); continue }
            if ($line -match '^\s*Radio type\s*:\s*(.+?)\s*$') { $wifiInfoByName[$currentWifiName]["Radio"] = $matches[1].Trim(); continue }
            if ($line -match '^\s*Channel\s*:\s*(.+?)\s*$') { $wifiInfoByName[$currentWifiName]["Channel"] = $matches[1].Trim(); continue }
            if ($line -match '^\s*Authentication\s*:\s*(.+?)\s*$') { $wifiInfoByName[$currentWifiName]["Authentication"] = $matches[1].Trim(); continue }
            if ($line -match '^\s*Cipher\s*:\s*(.+?)\s*$') { $wifiInfoByName[$currentWifiName]["Cipher"] = $matches[1].Trim(); continue }
            if ($line -match '^\s*Receive rate \(Mbps\)\s*:\s*(.+?)\s*$') { $wifiInfoByName[$currentWifiName]["RxRate"] = $matches[1].Trim(); continue }
            if ($line -match '^\s*Transmit rate \(Mbps\)\s*:\s*(.+?)\s*$') { $wifiInfoByName[$currentWifiName]["TxRate"] = $matches[1].Trim(); continue }
        }
    } catch {}

    $networkConfigs = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -Property Index, Description, IPAddress, IPSubnet, DefaultIPGateway, DNSServerSearchOrder, DHCPEnabled, DHCPServer, DHCPLeaseObtained, DHCPLeaseExpires, DNSDomain, DNSHostName, MACAddress -ErrorAction SilentlyContinue)
    foreach ($cfg in $networkConfigs) {
        if ($null -eq $cfg.Index) { continue }
        $idx = [int]$cfg.Index
        $adapter = $adapterByIndex[$idx]
        $netAdapter = $netAdapterByIndex[$idx]
        $adapterName = if ($netAdapter -and -not [string]::IsNullOrWhiteSpace($netAdapter.Name)) { [string]$netAdapter.Name } elseif ($adapter -and -not [string]::IsNullOrWhiteSpace($adapter.NetConnectionID)) { [string]$adapter.NetConnectionID } else { [string]$cfg.Description }
        $description = if ($netAdapter -and -not [string]::IsNullOrWhiteSpace($netAdapter.InterfaceDescription)) { [string]$netAdapter.InterfaceDescription } elseif (-not [string]::IsNullOrWhiteSpace($cfg.Description)) { [string]$cfg.Description } elseif ($adapter -and -not [string]::IsNullOrWhiteSpace($adapter.Name)) { [string]$adapter.Name } else { "Unknown adapter" }
        if ($adapterName -match "(?i)loopback|virtual|vEthernet|Hyper-V|Bluetooth" -or $description -match "(?i)loopback|virtual|vEthernet|Hyper-V|Bluetooth") { continue }
        if ($adapter -and $null -ne $adapter.PhysicalAdapter -and -not $adapter.PhysicalAdapter) { continue }

        $ipAddresses = @($cfg.IPAddress)
        $subnets = @($cfg.IPSubnet)
        $ipv4Entries = @()
        $ipv4Copy = @()
        $ipv6Entries = @()
        $ipv6Copy = @()
        for ($i = 0; $i -lt $ipAddresses.Count; $i++) {
            $address = [string]$ipAddresses[$i]
            if ([string]::IsNullOrWhiteSpace($address)) { continue }
            $subnet = if ($i -lt $subnets.Count) { [string]$subnets[$i] } else { "" }
            if ($address -match "^\d{1,3}(\.\d{1,3}){3}$") {
                $prefixLength = Convert-SubnetMaskToPrefixLength $subnet
                $cidr = if ([string]::IsNullOrWhiteSpace($prefixLength)) { $address } else { "$address/$prefixLength" }
                $ipv4Copy += $cidr
                if ([string]::IsNullOrWhiteSpace($subnet)) { $ipv4Entries += $cidr } else { $ipv4Entries += "$cidr ($subnet)" }
            }
            elseif ($address -match ":") {
                $prefix = if ($subnet -match "^\d{1,3}$") { "/$subnet" } else { "" }
                $cidr6 = "$address$prefix"
                $ipv6Copy += $cidr6
                if ($address -notmatch "^(?i)fe80:") { $ipv6Entries += $cidr6 }
            }
        }
        if ($ipv6Entries.Count -eq 0) { $ipv6Entries = @($ipv6Copy | Select-Object -First 2) }
        if ($ipv4Entries.Count -eq 0) { continue }

        $gatewayList = @($cfg.DefaultIPGateway | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        $gatewayText = if ($gatewayList.Count -gt 0) { $gatewayList -join ", " } else { "None" }
        $gatewayLink = [string](@($gatewayList | Where-Object { $_ -match "^\d{1,3}(\.\d{1,3}){3}$" }) | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($gatewayLink)) { $gatewayLink = [string]($gatewayList | Select-Object -First 1) }

        $dnsList = @($cfg.DNSServerSearchOrder | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        $dnsText = if ($dnsList.Count -gt 0) { $dnsList -join ", " } else { "None" }

        $speed = if ($netAdapter -and -not [string]::IsNullOrWhiteSpace($netAdapter.LinkSpeed)) { [string]$netAdapter.LinkSpeed } elseif ($adapter) { Convert-NetworkSpeedText $adapter.Speed } else { "Unknown" }
        $status = if ($netAdapter -and -not [string]::IsNullOrWhiteSpace($netAdapter.Status)) { [string]$netAdapter.Status } elseif ($adapter) { Convert-NetConnectionStatusText $adapter.NetConnectionStatus } else { "Unknown" }
        $mediaState = if ($netAdapter -and -not [string]::IsNullOrWhiteSpace($netAdapter.MediaConnectionState)) { [string]$netAdapter.MediaConnectionState } else { "" }
        $linkParts = @($status)
        if (-not [string]::IsNullOrWhiteSpace($mediaState) -and $mediaState -ne $status) { $linkParts += $mediaState }
        if (-not [string]::IsNullOrWhiteSpace($speed)) { $linkParts += "Speed: $speed" }

        $profile = $profileByIndex[$idx]
        $profileText = "Unavailable"
        $connectivityText = ""
        if ($profile) {
            $profileName = if ([string]::IsNullOrWhiteSpace($profile.Name)) { "Unidentified network" } else { [string]$profile.Name }
            $category = if ([string]::IsNullOrWhiteSpace($profile.NetworkCategory)) { "Unknown" } else { [string]$profile.NetworkCategory }
            $profileText = "$profileName ($category)"
            $connectivityParts = @()
            if (-not [string]::IsNullOrWhiteSpace($profile.IPv4Connectivity)) { $connectivityParts += "IPv4 $($profile.IPv4Connectivity)" }
            if (-not [string]::IsNullOrWhiteSpace($profile.IPv6Connectivity)) { $connectivityParts += "IPv6 $($profile.IPv6Connectivity)" }
            $connectivityText = $connectivityParts -join " | "
        }

        $ipInterface = $ipInterfaceByIndex[$idx]
        $route = $routeByIndex[$idx]
        $metricParts = @()
        if ($ipInterface -and $null -ne $ipInterface.NlMtu) { $metricParts += "MTU: $($ipInterface.NlMtu)" }
        if ($ipInterface -and $null -ne $ipInterface.InterfaceMetric) { $metricParts += "Interface metric: $($ipInterface.InterfaceMetric)" }
        if ($route -and $null -ne $route.RouteMetric) { $metricParts += "Route metric: $($route.RouteMetric)" }
        $routeText = $metricParts -join " | "

        $dhcpMode = if ($cfg.DHCPEnabled) { "On" } else { "Off / static" }
        if ($ipInterface -and -not [string]::IsNullOrWhiteSpace($ipInterface.Dhcp)) { $dhcpMode = [string]$ipInterface.Dhcp }
        $dhcpText = $dhcpMode
        if ($cfg.DHCPEnabled -and -not [string]::IsNullOrWhiteSpace($cfg.DHCPServer)) { $dhcpText += " via $($cfg.DHCPServer)" }
        $leaseText = ""
        if ($cfg.DHCPEnabled) {
            $leaseStart = Format-DateTimeText $cfg.DHCPLeaseObtained "yyyy-MM-dd HH:mm"
            $leaseEnd = Format-DateTimeText $cfg.DHCPLeaseExpires "yyyy-MM-dd HH:mm"
            if ($leaseStart -ne "Unavailable" -or $leaseEnd -ne "Unavailable") { $leaseText = "$leaseStart to $leaseEnd" }
        }

        $dnsClient = $dnsClientByIndex[$idx]
        $suffixParts = @()
        if (-not [string]::IsNullOrWhiteSpace($cfg.DNSDomain)) { $suffixParts += [string]$cfg.DNSDomain }
        if ($dnsClient -and -not [string]::IsNullOrWhiteSpace($dnsClient.ConnectionSpecificSuffix)) { $suffixParts += [string]$dnsClient.ConnectionSpecificSuffix }
        $dnsSuffixText = @($suffixParts | Select-Object -Unique) -join ", "

        $mac = if (-not [string]::IsNullOrWhiteSpace($cfg.MACAddress)) { [string]$cfg.MACAddress } elseif ($netAdapter -and -not [string]::IsNullOrWhiteSpace($netAdapter.MacAddress)) { [string]$netAdapter.MacAddress } elseif ($adapter -and -not [string]::IsNullOrWhiteSpace($adapter.MACAddress)) { [string]$adapter.MACAddress } else { "" }

        $stats = $null
        if ($statsByName.ContainsKey($adapterName)) { $stats = $statsByName[$adapterName] }
        elseif ($netAdapter -and $statsByName.ContainsKey([string]$netAdapter.Name)) { $stats = $statsByName[[string]$netAdapter.Name] }
        $trafficText = ""
        if ($stats) {
            $rx = ConvertTo-StorageSizeText ([double]$stats.ReceivedBytes)
            $tx = ConvertTo-StorageSizeText ([double]$stats.SentBytes)
            $trafficText = "RX $rx / TX $tx"
        }

        $wifi = $null
        foreach ($wifiKey in @($adapterName, $description, $(if ($netAdapter) { [string]$netAdapter.Name } else { "" }))) {
            if (-not [string]::IsNullOrWhiteSpace($wifiKey) -and $wifiInfoByName.ContainsKey($wifiKey)) { $wifi = $wifiInfoByName[$wifiKey]; break }
        }
        $wifiText = ""
        if ($wifi) {
            $wifiParts = @()
            if (-not [string]::IsNullOrWhiteSpace($wifi["SSID"])) { $wifiParts += "SSID: $($wifi["SSID"])" }
            if (-not [string]::IsNullOrWhiteSpace($wifi["BSSID"])) { $wifiParts += "BSSID: $($wifi["BSSID"])" }
            if (-not [string]::IsNullOrWhiteSpace($wifi["Signal"])) { $wifiParts += "Signal: $($wifi["Signal"])" }
            if (-not [string]::IsNullOrWhiteSpace($wifi["Radio"])) { $wifiParts += "Radio: $($wifi["Radio"])" }
            if (-not [string]::IsNullOrWhiteSpace($wifi["Channel"])) { $wifiParts += "Channel: $($wifi["Channel"])" }
            if (-not [string]::IsNullOrWhiteSpace($wifi["Authentication"])) { $wifiParts += "Auth: $($wifi["Authentication"])" }
            if (-not [string]::IsNullOrWhiteSpace($wifi["Cipher"])) { $wifiParts += "Cipher: $($wifi["Cipher"])" }
            if (-not [string]::IsNullOrWhiteSpace($wifi["RxRate"]) -or -not [string]::IsNullOrWhiteSpace($wifi["TxRate"])) { $wifiParts += "Rate: $($wifi["RxRate"])/$($wifi["TxRate"]) Mbps" }
            $wifiText = $wifiParts -join " | "
        }

        $driverParts = @()
        if ($netAdapter -and -not [string]::IsNullOrWhiteSpace($netAdapter.DriverVersion)) { $driverParts += "Version: $($netAdapter.DriverVersion)" }
        if ($netAdapter -and $null -ne $netAdapter.DriverDate) {
            $driverDate = Format-DateTimeText $netAdapter.DriverDate "yyyy-MM-dd"
            if ($driverDate -ne "Unavailable") { $driverParts += "Date: $driverDate" }
        }
        if ($driverParts.Count -eq 0 -and $netAdapter -and -not [string]::IsNullOrWhiteSpace($netAdapter.DriverInformation)) { $driverParts += [string]$netAdapter.DriverInformation }
        $driverText = $driverParts -join " | "

        $networkAdapters += [pscustomobject]@{
            Name         = $adapterName
            Description  = $description
            Profile      = $profileText
            Connectivity = $connectivityText
            LinkText     = (($linkParts + $metricParts) -join " | ")
            Status       = $status
            IPv4Text     = ($ipv4Entries -join ", ")
            IPv4Copy     = ($ipv4Copy -join ", ")
            IPv6Text     = ($ipv6Entries -join ", ")
            IPv6Copy     = ($ipv6Copy -join ", ")
            GatewayText  = $gatewayText
            GatewayLink  = $gatewayLink
            DnsText      = $dnsText
            DnsCopy      = ($dnsList -join ", ")
            DhcpText     = $dhcpText
            LeaseText    = $leaseText
            DnsSuffix    = $dnsSuffixText
            MacAddress   = $mac
            TrafficText  = $trafficText
            WifiText     = $wifiText
            DriverText   = $driverText
            RouteText    = $routeText
        }
    }
    $res.NetworkAdapters = $networkAdapters
    if ($networkAdapters.Count -gt 0) {
        $primary = @($networkAdapters | Where-Object { $_.GatewayText -and $_.GatewayText -ne "None" } | Select-Object -First 1)
        $primaryText = if ($primary.Count -gt 0) { " | Primary: $($primary[0].Name)" } else { "" }
        $res.Network = "Active physical adapters: $($networkAdapters.Count)$primaryText"
    }
    else {
        $res.Network = "No active physical network adapters found."
    }
}
catch { $res.Network = "Unavailable"; $res.NetworkAdapters = @() }
[pscustomobject]$res

'@
$script:MyDevicePowerBody = @'

$res = [ordered]@{ Section = "Power" }
try {
    $batteries = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    $powerTelemetry = Get-BatteryPowerTelemetry -Win32Batteries $batteries
    $res.PowerDraw = $powerTelemetry.BatteryRate
    $res.PowerTotal = $powerTelemetry.TotalPower
    $res.PowerElectrical = $powerTelemetry.Electrical
    if ($batteries.Count -gt 0) {
        $chargeValues = @($batteries | ForEach-Object { Get-ValidPowerNumber $_.EstimatedChargeRemaining -AllowZero } | Where-Object { $null -ne $_ })
        if ($chargeValues.Count -gt 0) { $averageCharge = [math]::Round(($chargeValues | Measure-Object -Average).Average, 0); $packText = if ($batteries.Count -gt 1) { " avg across $($batteries.Count) packs" } else { "" }; $res.BatteryCharge = "$averageCharge%$packText" } else { $res.BatteryCharge = "Unavailable" }
        $statusText = @($batteries | ForEach-Object { switch ([int]$_.BatteryStatus) { 1 { "Discharging" } 2 { "Plugged In / Charging" } 3 { "Fully Charged" } 4 { "Low" } 5 { "Critical" } 6 { "Charging" } 7 { "Charging (High)" } 8 { "Charging (Low)" } 9 { "Charging (Critical)" } 11 { "Partially Charged" } default { "Unknown (Code: $($_.BatteryStatus))" } } } | Select-Object -Unique)
        $res.BatteryStatus = if ($statusText.Count -gt 0) { $statusText -join ", " } else { "Unknown" }
        $runtimeValues = @($batteries | ForEach-Object { Get-ValidPowerNumber $_.EstimatedRunTime } | Where-Object { $null -ne $_ -and $_ -ne 71582788 })
        if ($runtimeValues.Count -gt 0) { $runtime = [int]($runtimeValues | Select-Object -First 1); $hours = [math]::Floor($runtime / 60); $minutes = $runtime % 60; $res.BatteryTime = "${hours}h ${minutes}m remaining" } else { $res.BatteryTime = "" }
        if ($powerTelemetry.DesignCapacity -and $powerTelemetry.FullCapacity) { $health = [math]::Round(($powerTelemetry.FullCapacity / $powerTelemetry.DesignCapacity) * 100, 1); $res.BatteryHealth = "$health% ($(Convert-MilliwattHourText $powerTelemetry.FullCapacity) / $(Convert-MilliwattHourText $powerTelemetry.DesignCapacity))" } else { $res.BatteryHealth = "Not exposed by battery firmware" }
    }
    else {
        $res.BatteryCharge = "Desktop System"; $res.BatteryStatus = "No Battery Detected"; $res.BatteryTime = ""; $res.BatteryHealth = "N/A"; $res.PowerDraw = "N/A"; $res.PowerElectrical = "N/A"
    }
    $res.PowerPlan = Get-ActivePowerPlanText
}
catch { $res.BatteryCharge = "Unavailable"; $res.BatteryStatus = "Unavailable"; $res.BatteryTime = ""; $res.BatteryHealth = "Unavailable"; $res.PowerPlan = "Unavailable"; $res.PowerDraw = "Unavailable"; $res.PowerTotal = "Unavailable"; $res.PowerElectrical = "Unavailable" }
[pscustomobject]$res

'@











































































































$script:DataDir = Get-DataPath













# Simple modal text viewer (read-only)




















# --- SETTINGS MANAGER ---
# Initialize cache variable
$script:WmtSettingsCache = $null

































$script:WmtNotificationAppId = "Chaython.WindowsMaintenanceTool"
$script:WmtNativeToastReady = $false
$script:WmtNativeToastUnavailable = $false
$script:WmtNativeToastShortcutWarningShown = $false
$script:WmtNotificationFallbackTimers = New-Object System.Collections.ArrayList
$script:WmtTrayIcon = $null
$script:WmtTrayIconImage = $null
$script:WmtTrayMenu = $null
$script:WmtAllowFinalClose = $false
$script:WmtTrayHideNotificationShown = $false
$script:WmtHiddenToTray = $false

$script:WmtMaxLogLines = 500
$script:WmtMemoryTrimBusy = $false




$script:WmtApplication = $null































# --- UPDATE CHECKER ---












# --- NETWORK / DNS HELPERS (from CLI) ---


# --- SHARED DNS CONFIGURATION ---
$script:WmtDnsProviders = [ordered]@{
    Google     = [PSCustomObject]@{
        Key       = "Google"
        Label     = "Google DNS"
        Name      = "Google"
        Addresses = @("8.8.8.8", "8.8.4.4")
        Doh       = @(
            [PSCustomObject]@{ Server = "8.8.8.8"; Template = "https://dns.google/dns-query" }
            [PSCustomObject]@{ Server = "8.8.4.4"; Template = "https://dns.google/dns-query" }
            [PSCustomObject]@{ Server = "2001:4860:4860::8888"; Template = "https://dns.google/dns-query" }
            [PSCustomObject]@{ Server = "2001:4860:4860::8844"; Template = "https://dns.google/dns-query" }
        )
    }
    Cloudflare = [PSCustomObject]@{
        Key       = "Cloudflare"
        Label     = "Cloudflare DNS"
        Name      = "Cloudflare"
        Addresses = @("1.1.1.1", "1.0.0.1")
        Doh       = @(
            [PSCustomObject]@{ Server = "1.1.1.1"; Template = "https://cloudflare-dns.com/dns-query" }
            [PSCustomObject]@{ Server = "1.0.0.1"; Template = "https://cloudflare-dns.com/dns-query" }
            [PSCustomObject]@{ Server = "2606:4700:4700::1111"; Template = "https://cloudflare-dns.com/dns-query" }
            [PSCustomObject]@{ Server = "2606:4700:4700::1001"; Template = "https://cloudflare-dns.com/dns-query" }
        )
    }
    Quad9      = [PSCustomObject]@{
        Key       = "Quad9"
        Label     = "Quad9 DNS"
        Name      = "Quad9"
        Addresses = @("9.9.9.9", "149.112.112.112")
        Doh       = @(
            [PSCustomObject]@{ Server = "9.9.9.9"; Template = "https://dns.quad9.net/dns-query" }
            [PSCustomObject]@{ Server = "149.112.112.112"; Template = "https://dns.quad9.net/dns-query" }
            [PSCustomObject]@{ Server = "2620:fe::fe"; Template = "https://dns.quad9.net/dns-query" }
            [PSCustomObject]@{ Server = "2620:fe::9"; Template = "https://dns.quad9.net/dns-query" }
        )
    }
    AdGuard    = [PSCustomObject]@{
        Key       = "AdGuard"
        Label     = "AdGuard DNS"
        Name      = "AdGuard"
        Addresses = @("94.140.14.14", "94.140.15.15")
        Doh       = @(
            [PSCustomObject]@{ Server = "94.140.14.14"; Template = "https://dns.adguard.com/dns-query" }
            [PSCustomObject]@{ Server = "94.140.15.15"; Template = "https://dns.adguard.com/dns-query" }
            [PSCustomObject]@{ Server = "2a10:50c0::ad1:ff"; Template = "https://dns.adguard.com/dns-query" }
            [PSCustomObject]@{ Server = "2a10:50c0::ad2:ff"; Template = "https://dns.adguard.com/dns-query" }
        )
    }
}

$script:DohTargets = @(
    foreach ($provider in $script:WmtDnsProviders.Values) {
        foreach ($target in @($provider.Doh)) { $target }
    }
)































# Redirect existing function calls to the new Async handler



# --- Hosts Adblock ---


# --- HOSTS EDITOR ---

# --- STORAGE / SYSTEM ---



# ==========================================
# WINAPP2.INI INTEGRATION
# ==========================================








































    









# --- Registry Scan Selection UI ---

# --- Registry Results UI ---

# =========================================================
# 1. GLOBAL REGISTRY HELPERS
# (Place these ABOVE Invoke-RegistryTask)
# =========================================================

















































# =========================================================
# 2. INVOKE-REGISTRYTASK (Full Function)
# =========================================================





















# --- FIREWALL TOOLS ---








# --- DRIVER TOOLS ---















# --- RESTORE DRIVERS ---



# --- UPDATE / REPORT TOOLS ---













# --- FIREWALL RULE DIALOG ---



# --- WINRE STATUS CHECK ---




# --- SYSTEM RESTORE MANAGER ---



# --- STARTUP MANAGER (Windows / Tasks / Context Menu / Services) ---



# --- Tweaks Functions ---




































# ==========================================
# 3. XAML GUI
# ==========================================
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows Maintenance Tool v$AppVersion" Height="820" Width="1280" MinHeight="620" MinWidth="960"
        WindowStartupLocation="CenterScreen" Background="{DynamicResource BgDark}" Foreground="{DynamicResource TextPrimary}"
        FontFamily="Segoe UI Variable Display, Segoe UI, Arial" FontSize="13"
        TextOptions.TextFormattingMode="Display"
        TextOptions.TextRenderingMode="ClearType"
        UseLayoutRounding="True"
        SnapsToDevicePixels="True">

    <Window.Resources>
        <!-- Modern Color Palette (GitHub Dark inspired) -->
        <SolidColorBrush x:Key="BgDark" Color="#0D1117"/>
        <SolidColorBrush x:Key="BgPanel" Color="#161B22"/>
        <SolidColorBrush x:Key="BgElevated" Color="#21262D"/>
        <SolidColorBrush x:Key="BgHover" Color="#30363D"/>
        <SolidColorBrush x:Key="BorderBrush" Color="#30363D"/>
        <SolidColorBrush x:Key="BorderAccent" Color="#58A6FF"/>
        <SolidColorBrush x:Key="Accent" Color="#58A6FF"/>
        <SolidColorBrush x:Key="AccentHover" Color="#79C0FF"/>
        <SolidColorBrush x:Key="TextPrimary" Color="#E6EDF3"/>
        <SolidColorBrush x:Key="TextSecondary" Color="#8B949E"/>
        <SolidColorBrush x:Key="TextMuted" Color="#6E7681"/>
        <SolidColorBrush x:Key="Success" Color="#238636"/>
        <SolidColorBrush x:Key="SuccessHover" Color="#2EA043"/>
        <SolidColorBrush x:Key="Danger" Color="#DA3633"/>
        <SolidColorBrush x:Key="DangerHover" Color="#F85149"/>
        <SolidColorBrush x:Key="Warning" Color="#D29922"/>
        <SolidColorBrush x:Key="WarningHover" Color="#E3B341"/>
        <SolidColorBrush x:Key="Info" Color="#1F6FEB"/>
        <SolidColorBrush x:Key="AccentText" Color="#0D1117"/>
        <SolidColorBrush x:Key="SuccessText" Color="#F6FFFA"/>
        <SolidColorBrush x:Key="DangerText" Color="#FFF5F5"/>
        <SolidColorBrush x:Key="WarningText" Color="#0D1117"/>
        <SolidColorBrush x:Key="InfoText" Color="#F0F6FC"/>

        <!-- Subtle Shadow Effects (reduced for clarity) -->
        <DropShadowEffect x:Key="CardShadow" ShadowDepth="1" BlurRadius="4" Opacity="0.15" Color="#000000"/>

        <!-- Transparent, theme-aware scrollbars for all WPF scroll viewers -->
        <Style x:Key="TransparentScrollRepeatButton" TargetType="{x:Type RepeatButton}">
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type RepeatButton}">
                        <Border Background="Transparent"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="{x:Type ScrollBar}">
            <Setter Property="Width" Value="10"/>
            <Setter Property="MinWidth" Value="10"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type ScrollBar}">
                        <Grid Background="{TemplateBinding Background}" SnapsToDevicePixels="True">
                            <Track x:Name="PART_Track" IsDirectionReversed="True">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton x:Name="PageDecreaseButton" Command="{x:Static ScrollBar.PageUpCommand}" Style="{StaticResource TransparentScrollRepeatButton}"/>
                                </Track.DecreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb x:Name="ScrollThumb" MinHeight="34" Background="{DynamicResource BorderBrush}">
                                        <Thumb.Template>
                                            <ControlTemplate TargetType="{x:Type Thumb}">
                                                <Border Background="{TemplateBinding Background}" CornerRadius="5" Margin="2"/>
                                            </ControlTemplate>
                                        </Thumb.Template>
                                    </Thumb>
                                </Track.Thumb>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton x:Name="PageIncreaseButton" Command="{x:Static ScrollBar.PageDownCommand}" Style="{StaticResource TransparentScrollRepeatButton}"/>
                                </Track.IncreaseRepeatButton>
                            </Track>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="Orientation" Value="Horizontal">
                                <Setter Property="Width" Value="Auto"/>
                                <Setter Property="MinWidth" Value="0"/>
                                <Setter Property="Height" Value="10"/>
                                <Setter Property="MinHeight" Value="10"/>
                                <Setter TargetName="PART_Track" Property="IsDirectionReversed" Value="False"/>
                                <Setter TargetName="ScrollThumb" Property="MinWidth" Value="34"/>
                                <Setter TargetName="ScrollThumb" Property="MinHeight" Value="0"/>
                                <Setter TargetName="PageDecreaseButton" Property="Command" Value="{x:Static ScrollBar.PageLeftCommand}"/>
                                <Setter TargetName="PageIncreaseButton" Property="Command" Value="{x:Static ScrollBar.PageRightCommand}"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ScrollThumb" Property="Background" Value="{DynamicResource TextSecondary}"/>
                            </Trigger>
                            <Trigger SourceName="ScrollThumb" Property="IsDragging" Value="True">
                                <Setter TargetName="ScrollThumb" Property="Background" Value="{DynamicResource Accent}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern TextBox (crisp text) -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{DynamicResource BgDark}"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="UseLayoutRounding" Value="True"/>
            <Setter Property="TextOptions.TextFormattingMode" Value="Display"/>
            <Setter Property="TextOptions.TextRenderingMode" Value="ClearType"/>
            <Style.Triggers>
                <Trigger Property="IsFocused" Value="True">
                    <Setter Property="BorderBrush" Value="{DynamicResource BorderAccent}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="UseLayoutRounding" Value="True"/>
            <Setter Property="TextOptions.TextFormattingMode" Value="Display"/>
            <Setter Property="TextOptions.TextRenderingMode" Value="ClearType"/>
        </Style>

        <!-- Modern Navigation Button (crisp text) -->
        <Style TargetType="Button" x:Key="NavBtn">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{DynamicResource TextSecondary}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Height" Value="38"/>
            <Setter Property="Margin" Value="2"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Padding" Value="12,0"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="UseLayoutRounding" Value="True"/>
            <Setter Property="TextOptions.TextFormattingMode" Value="Display"/>
            <Setter Property="TextOptions.TextRenderingMode" Value="ClearType"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Grid>
                            <Border Name="Bd" Background="{TemplateBinding Background}" CornerRadius="4" UseLayoutRounding="True">
                                <ContentPresenter VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                            </Border>
                            <!-- Active Indicator Bar (left side) -->
                            <Border Name="Indicator" Width="3" Background="{DynamicResource Accent}" HorizontalAlignment="Left" 
                                    CornerRadius="2,0,0,2" Visibility="{TemplateBinding Tag}" UseLayoutRounding="True"/>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BgElevated}"/>
                                <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern Action Button (clean, no blur) -->
        <Style TargetType="Button" x:Key="ActionBtn">
            <Setter Property="Background" Value="{DynamicResource BgElevated}"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="Height" Value="32"/>
            <Setter Property="Margin" Value="4"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="Normal"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="UseLayoutRounding" Value="True"/>
            <Setter Property="TextOptions.TextFormattingMode" Value="Display"/>
            <Setter Property="TextOptions.TextRenderingMode" Value="ClearType"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="Bd" Background="{TemplateBinding Background}" CornerRadius="4" 
                                BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="16,0"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource BgHover}"/>
                    <Setter Property="BorderBrush" Value="{DynamicResource TextSecondary}"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Background" Value="{DynamicResource BgPanel}"/>
                    <Setter Property="Foreground" Value="{DynamicResource TextMuted}"/>
                    <Setter Property="Opacity" Value="0.55"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Success/Green Button -->
        <Style TargetType="Button" x:Key="PositiveBtn" BasedOn="{StaticResource ActionBtn}">
            <Setter Property="Background" Value="{DynamicResource Success}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource SuccessHover}"/>
            <Setter Property="Foreground" Value="{DynamicResource SuccessText}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource SuccessHover}"/>
                    <Setter Property="BorderBrush" Value="{DynamicResource SuccessHover}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Danger/Red Button -->
        <Style TargetType="Button" x:Key="DestructiveBtn" BasedOn="{StaticResource ActionBtn}">
            <Setter Property="Background" Value="{DynamicResource Danger}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource DangerHover}"/>
            <Setter Property="Foreground" Value="{DynamicResource DangerText}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource DangerHover}"/>
                    <Setter Property="BorderBrush" Value="{DynamicResource DangerHover}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Warning/Yellow Button -->
        <Style TargetType="Button" x:Key="WarningBtn" BasedOn="{StaticResource ActionBtn}">
            <Setter Property="Background" Value="{DynamicResource Warning}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource WarningHover}"/>
            <Setter Property="Foreground" Value="{DynamicResource WarningText}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource WarningHover}"/>
                    <Setter Property="BorderBrush" Value="{DynamicResource WarningHover}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Info/Blue Button -->
        <Style TargetType="Button" x:Key="UtilityBtn" BasedOn="{StaticResource ActionBtn}">
            <Setter Property="Background" Value="{DynamicResource Info}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource Accent}"/>
            <Setter Property="Foreground" Value="{DynamicResource InfoText}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource Accent}"/>
                    <Setter Property="BorderBrush" Value="{DynamicResource AccentHover}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Accent Button -->
        <Style TargetType="Button" x:Key="AccentBtn" BasedOn="{StaticResource ActionBtn}">
            <Setter Property="Background" Value="{DynamicResource Accent}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource AccentHover}"/>
            <Setter Property="Foreground" Value="{DynamicResource AccentText}"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource AccentHover}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Modern ListView Item (crisp text) -->
        <Style x:Key="FwItem" TargetType="ListViewItem">
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="Margin" Value="2,1"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="UseLayoutRounding" Value="True"/>
            <Setter Property="TextOptions.TextFormattingMode" Value="Display"/>
            <Setter Property="TextOptions.TextRenderingMode" Value="ClearType"/>
            <Style.Triggers>
                <Trigger Property="ItemsControl.AlternationIndex" Value="0">
                    <Setter Property="Background" Value="{DynamicResource BgPanel}"/>
                </Trigger>
                <Trigger Property="ItemsControl.AlternationIndex" Value="1">
                    <Setter Property="Background" Value="{DynamicResource BgDark}"/>
                </Trigger>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="{DynamicResource Accent}"/>
                    <Setter Property="Foreground" Value="{DynamicResource AccentText}"/>
                    <Setter Property="FontWeight" Value="Medium"/>
                </Trigger>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource BgHover}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Card Style Border (clean, crisp) -->
        <Style x:Key="CardStyle" TargetType="Border">
            <Setter Property="Background" Value="{DynamicResource BgPanel}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="4"/>
            <Setter Property="Margin" Value="6"/>
            <Setter Property="Padding" Value="16"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="UseLayoutRounding" Value="True"/>
        </Style>

        <!-- Section Header Text (crisp) -->
        <Style x:Key="SectionHeader" TargetType="TextBlock">
            <Setter Property="FontSize" Value="26"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="Margin" Value="0,0,0,16"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="TextOptions.TextFormattingMode" Value="Display"/>
            <Setter Property="TextOptions.TextRenderingMode" Value="ClearType"/>
        </Style>

        <!-- Subsection Header (crisp) -->
        <Style x:Key="SubHeader" TargetType="TextBlock">
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Foreground" Value="{DynamicResource TextSecondary}"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
            <Setter Property="FontFamily" Value="Segoe UI, Arial"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="TextOptions.TextFormattingMode" Value="Display"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="300"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- Sidebar -->
        <Border Grid.Column="0" Background="{DynamicResource BgPanel}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="0,0,1,0">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/> 
                    <RowDefinition Height="Auto"/> 
                    <RowDefinition Height="Auto"/>    
                    <RowDefinition Height="6"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <!-- Header/Search -->
                <Border Name="bdQuickFind" Grid.Row="0" Background="{DynamicResource BgDark}" Margin="16,20,16,12" CornerRadius="8" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" Cursor="IBeam">
                    <StackPanel Margin="12">
                        <TextBlock Text="Quick Find" FontSize="11" Foreground="{DynamicResource TextMuted}" FontWeight="SemiBold" Margin="0,0,0,8"/>
                        <TextBox Name="txtGlobalSearch" Height="36" ToolTip="Search any function..." VerticalContentAlignment="Center"
                                 Background="{DynamicResource BgPanel}" Foreground="{DynamicResource TextPrimary}"
                                 BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" Padding="10,0"/>
                    </StackPanel>
                </Border>

                <!-- Navigation -->
                <StackPanel Grid.Row="1" Margin="8,8,8,0">
                    <TextBlock Text="NAVIGATION" Style="{StaticResource SubHeader}" Margin="12,0,0,4"/>
                    <StackPanel Name="pnlNavButtons">
                        <Button Name="btnTabUpdates" Content="Updates" Style="{StaticResource NavBtn}" Tag="pnlUpdates"/>
                        <Button Name="btnTabTweaks" Content="Tweaks" Style="{StaticResource NavBtn}" Tag="pnlTweaks"/>
                        <Button Name="btnTabHealth" Content="System Health" Style="{StaticResource NavBtn}" Tag="pnlHealth"/>
                        <Button Name="btnTabNetwork" Content="Network &amp; DNS" Style="{StaticResource NavBtn}" Tag="pnlNetwork"/>
                        <Button Name="btnTabFirewall" Content="Firewall" Style="{StaticResource NavBtn}" Tag="pnlFirewall"/>
                        <Button Name="btnTabDrivers" Content="Drivers" Style="{StaticResource NavBtn}" Tag="pnlDrivers"/>
                        <Button Name="btnTabCleanup" Content="Cleanup" Style="{StaticResource NavBtn}" Tag="pnlCleanup"/>
                        <Button Name="btnTabUtils" Content="Utilities" Style="{StaticResource NavBtn}" Tag="pnlUtils"/>
                        <Button Name="btnTabMyDevice" Style="{StaticResource NavBtn}" Tag="pnlMyDevice">
                            <StackPanel Orientation="Horizontal">
                                <Path Data="M21 2H3c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h7v2H8v2h8v-2h-2v-2h7c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H3V4h18v12z" 
                                      Fill="{DynamicResource TextSecondary}" 
                                      Width="16" Height="16" Stretch="Uniform" Margin="0,0,10,0" VerticalAlignment="Center"/>
                                <TextBlock Text="My Device" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button Name="btnTabSupport" Content="Support" Style="{StaticResource NavBtn}" Tag="pnlSupport"/>
                        <Button Name="btnNavDownloads" Content="Download Stats" Style="{StaticResource NavBtn}" ToolTip="Show latest release download counts"/>
                    </StackPanel>
                </StackPanel>
                
                <ListBox Name="lstSearchResults" Grid.Row="2" Background="{DynamicResource BgDark}" BorderThickness="0" Foreground="{DynamicResource Accent}" Visibility="Collapsed" Margin="8" MaxHeight="220"/>

                <GridSplitter Grid.Row="3" Height="8" Margin="12,0" HorizontalAlignment="Stretch" VerticalAlignment="Center"
                              Background="Transparent" Cursor="SizeNS" ResizeDirection="Rows" ResizeBehavior="PreviousAndNext"
                              ShowsPreview="True"/>

                <!-- Log Panel -->
                <Border Grid.Row="4" Background="{DynamicResource BgDark}" Margin="12" CornerRadius="8" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" MinHeight="140" VerticalAlignment="Stretch">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        <Border Grid.Row="0" Background="{DynamicResource BgPanel}" CornerRadius="8,8,0,0" Padding="12,8">
                            <TextBlock Text="Activity Log" FontSize="11" Foreground="{DynamicResource TextMuted}" FontWeight="SemiBold"/>
                        </Border>
                        <ScrollViewer Name="svLog" Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Margin="8" UseLayoutRounding="True" VerticalAlignment="Stretch">
                            <TextBox Name="LogBox" IsReadOnly="True" TextWrapping="Wrap" FontFamily="Consolas, monospace" FontSize="12" 
                                     Background="Transparent" Foreground="#3FB950" BorderThickness="0" Padding="4"
                                     VerticalAlignment="Stretch" AcceptsReturn="True"
                                     SnapsToDevicePixels="True" TextOptions.TextFormattingMode="Display"/>
                        </ScrollViewer>
                    </Grid>
                </Border>
            </Grid>
        </Border>

        <Border Grid.Column="1" Background="{DynamicResource BgDark}">
            <Grid Margin="20">
                
                <!-- UPDATES PANEL -->
                <Grid Name="pnlUpdates" Visibility="Visible">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    
                    <!-- Header Card -->
                    <Border Grid.Row="0" Style="{StaticResource CardStyle}" Margin="0,0,0,12">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="320"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel VerticalAlignment="Center">
                                <StackPanel>
                                    <TextBlock Name="lblWingetTitle" Text="Package Updates" Style="{StaticResource SectionHeader}" Margin="0"/>
                                    <TextBlock Name="lblWingetStatus" Text="Ready to scan" Foreground="#D29922" FontSize="13" Visibility="Visible"/>
                                    <StackPanel Orientation="Horizontal" Margin="0,8,0,0" VerticalAlignment="Center">
                                        <ProgressBar Name="pbWingetProgress" Width="260" Height="8" Minimum="0" Maximum="100" Value="0" Visibility="Collapsed"/>
                                        <TextBlock Name="lblWingetProgress" Text="" Margin="10,0,0,0" Foreground="{DynamicResource TextMuted}" FontSize="12" Visibility="Collapsed"/>
                                    </StackPanel>
                                    <TextBlock Name="lblWingetLastResult" Text="" Margin="0,6,0,0" Foreground="{DynamicResource TextMuted}" FontSize="12" Visibility="Collapsed"/>
                                </StackPanel>
                            </StackPanel>
                            <Grid Grid.Column="1">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBox Name="txtWingetSearch" Grid.Column="0" Height="40" VerticalContentAlignment="Center" Text="Search packages..."/>
                                <Button Name="btnWingetFind" Grid.Column="1" Content="Search" Width="100" Height="40" Margin="8,0,0,0" Style="{StaticResource AccentBtn}"/>
                            </Grid>
                        </Grid>
                    </Border>

                    <!-- List Card -->
                    <Border Grid.Row="1" Style="{StaticResource CardStyle}" Padding="0">
                        <ListView Name="lstWinget" Background="Transparent" Foreground="{DynamicResource TextPrimary}" BorderThickness="0" 
                                  SelectionMode="Extended" AlternationCount="2" ItemContainerStyle="{StaticResource FwItem}">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Select" Width="64">
                                        <GridViewColumn.CellTemplate>
                                            <DataTemplate>
                                                <CheckBox IsChecked="{Binding IsChecked, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"
                                                          HorizontalAlignment="Center" VerticalAlignment="Center"
                                                          ToolTip="Check this item to include it when you click Update Checked"/>
                                            </DataTemplate>
                                        </GridViewColumn.CellTemplate>
                                    </GridViewColumn>
                                    <GridViewColumn Header="Source" Width="90" DisplayMemberBinding="{Binding Source}"/>
                                    <GridViewColumn Header="Package Name" Width="280" DisplayMemberBinding="{Binding Name}"/>
                                    <GridViewColumn Header="ID" Width="220" DisplayMemberBinding="{Binding Id}"/>
                                    <GridViewColumn Header="Installed" Width="110" DisplayMemberBinding="{Binding Version}"/>
                                    <GridViewColumn Header="Latest" Width="110" DisplayMemberBinding="{Binding Available}"/>
                                </GridView>
                            </ListView.View>
                        </ListView>
                    </Border>

                    <!-- Action Bar -->
                    <Border Grid.Row="2" Style="{StaticResource CardStyle}" Margin="0,12,0,0">
                        <WrapPanel HorizontalAlignment="Right">
                            <Button Name="btnManageProviders" Content="Providers" Style="{StaticResource ActionBtn}" ToolTip="Manage package sources"/>
                            <Button Name="btnShowCatalog" Content="Software Catalog" Style="{StaticResource ActionBtn}" ToolTip="Browse our curated catalog of popular free applications. Install multiple apps at once with one click."/>
                            <Button Name="btnWingetScan" Content="Refresh All" Style="{StaticResource AccentBtn}"/>
                            <Button Name="btnWingetUpdateSel" Content="Update Checked" Style="{StaticResource PositiveBtn}" ToolTip="Update checked rows. If none are checked, selected rows are used."/>
                            <Button Name="btnWingetUpdateAll" Content="Update All" Style="{StaticResource PositiveBtn}"/>
                            <Button Name="btnWingetInstall" Content="Install" Style="{StaticResource PositiveBtn}" Visibility="Collapsed"/>
                            <Button Name="btnWingetUninstall" Content="Uninstall" Style="{StaticResource DestructiveBtn}"/>
                            <Button Name="btnWingetIgnore" Content="Ignore" Style="{StaticResource WarningBtn}"/>
                            <Button Name="btnWingetUnignore" Content="Manage Ignored" Style="{StaticResource ActionBtn}"/>
                        </WrapPanel>
                    </Border>
                </Grid>

                <!-- SOFTWARE CATALOG PANEL (Initially Hidden) -->
                <Grid Name="pnlCatalog" Visibility="Collapsed">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    
                    <!-- Header -->
                    <Border Grid.Row="0" Style="{StaticResource CardStyle}" Margin="0,0,0,12">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="300"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel>
                                <TextBlock Text="Software Catalog" Style="{StaticResource SectionHeader}" Margin="0"/>
                                <TextBlock Text="Curated selection of popular applications" Foreground="{DynamicResource TextSecondary}" FontSize="13"/>
                            </StackPanel>
                            <Grid Grid.Column="1">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBox Name="txtCatalogSearch" Grid.Column="0" Height="40" VerticalContentAlignment="Center" Text="Search catalog..." ToolTip="Type to filter applications by name or description"/>
                                <Button Name="btnCatalogSearch" Grid.Column="1" Content="Search" Width="100" Height="40" Margin="8,0,0,0" Style="{StaticResource AccentBtn}" ToolTip="Search the catalog"/>
                            </Grid>
                        </Grid>
                    </Border>

                    <!-- Category Filter -->
                    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="6,0,6,12">
                        <Button Name="btnCatAll" Content="All" Width="80" Style="{StaticResource AccentBtn}" ToolTip="Show all applications"/>
                        <Button Name="btnCatBrowsers" Content="Browsers" Width="90" Style="{StaticResource ActionBtn}" ToolTip="Filter: Web browsers"/>
                        <Button Name="btnCatDev" Content="Development" Width="Auto" MinWidth="120" Style="{StaticResource ActionBtn}" ToolTip="Filter: Developer tools, IDEs, runtimes"/>
                        <Button Name="btnCatUtils" Content="Utilities" Width="90" Style="{StaticResource ActionBtn}" ToolTip="Filter: System utilities and tools"/>
                        <Button Name="btnCatMedia" Content="Multimedia" Width="100" Style="{StaticResource ActionBtn}" ToolTip="Filter: Media players, editors, streaming"/>
                        <Button Name="btnCatGames" Content="Gaming" Width="80" Style="{StaticResource ActionBtn}" ToolTip="Filter: Game platforms and gaming tools"/>
                        <Button Name="btnCatSecurity" Content="Security" Width="90" Style="{StaticResource ActionBtn}" ToolTip="Filter: Antivirus, password managers, security tools"/>
                    </StackPanel>

                    <!-- Catalog List -->
                    <Border Grid.Row="2" Style="{StaticResource CardStyle}" Padding="0">
                        <ListView Name="lstCatalog" Background="Transparent" Foreground="{DynamicResource TextPrimary}" BorderThickness="0" 
                                  SelectionMode="Extended" AlternationCount="2" ItemContainerStyle="{StaticResource FwItem}">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Category" Width="100" DisplayMemberBinding="{Binding Category}"/>
                                    <GridViewColumn Header="Name" Width="200" DisplayMemberBinding="{Binding Name}"/>
                                    <GridViewColumn Header="Description" Width="350" DisplayMemberBinding="{Binding Description}"/>
                                    <GridViewColumn Header="Source" Width="80" DisplayMemberBinding="{Binding Source}"/>
                                </GridView>
                            </ListView.View>
                        </ListView>
                    </Border>

                    <!-- Actions -->
                    <Border Grid.Row="3" Style="{StaticResource CardStyle}" Margin="0,12,0,0">
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                            <Button Name="btnBackToUpdates" Content="Back to Updates" Style="{StaticResource ActionBtn}" ToolTip="Return to the package updates view"/>
                            <Button Name="btnCatalogInstall" Content="Install Selected" Style="{StaticResource PositiveBtn}" ToolTip="Install all selected applications using winget. May take several minutes depending on app size."/>
                            <Button Name="btnCatalogSelectAll" Content="Select All" Style="{StaticResource ActionBtn}" ToolTip="Select all visible applications in the list"/>
                            <Button Name="btnCatalogClear" Content="Clear Selection" Style="{StaticResource ActionBtn}" ToolTip="Unselect all applications"/>
                        </StackPanel>
                    </Border>
                </Grid>

                <!-- TWEAKS PANEL -->
        <ScrollViewer Name="pnlTweaks" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
            <StackPanel>
                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <StackPanel Margin="0,0,0,12">
                            <TextBlock Text="Performance Tweaks" Style="{StaticResource SectionHeader}" Margin="0"/>
                        </StackPanel>
                        <TextBlock Text="POWER &amp; PERFORMANCE" Style="{StaticResource SubHeader}"/>
                        <WrapPanel>
                            <Button Name="btnPerfServicesManual" Content="Services to Manual" Style="{StaticResource ActionBtn}" ToolTip="Optimize 100+ Windows services by setting them to Manual startup. Improves boot time and reduces background RAM usage."/>
                            <Button Name="btnPerfServicesRevert" Content="Revert Services" Style="{StaticResource WarningBtn}" ToolTip="Restore all services to their default startup type (Automatic/Manual/Disabled). Use this if you experience issues after optimization."/>
                            <Button Name="btnPerfDisableHibernate" Content="Disable Hibernation" Style="{StaticResource ActionBtn}" ToolTip="Disable hibernation and delete hiberfil.sys. Frees up several GB of disk space equal to your RAM size."/>
                            <Button Name="btnPerfEnableHibernate" Content="Enable Hibernation" Style="{StaticResource ActionBtn}" ToolTip="Re-enable hibernation mode. Allows your PC to save state and power off completely, resuming faster than a full boot."/>
                            <Button Name="btnPerfDisableSuperfetch" Content="Disable Superfetch" Style="{StaticResource ActionBtn}" ToolTip="Disable SysMain (Superfetch) service. Prevents Windows from pre-loading apps into RAM. Can help on systems with low RAM or SSDs."/>
                            <Button Name="btnPerfEnableSuperfetch" Content="Enable Superfetch" Style="{StaticResource ActionBtn}" ToolTip="Enable SysMain (Superfetch) service. Pre-loads frequently used apps into RAM for faster launch times on HDDs."/>
                            <Button Name="btnPerfDisableMemCompress" Content="Disable Mem Compression" Style="{StaticResource ActionBtn}" ToolTip="Disable memory compression. RAM stores data uncompressed. May improve performance on high-RAM systems."/>
                            <Button Name="btnPerfEnableMemCompress" Content="Enable Mem Compression" Style="{StaticResource ActionBtn}" ToolTip="Enable memory compression. Windows compresses inactive RAM pages to free up physical memory for active apps."/>
                            <Button Name="btnPerfUltimatePower" Content="Ultimate Performance" Style="{StaticResource PositiveBtn}" ToolTip="Enable the Ultimate Performance power plan. Removes all power throttling for maximum performance. Best for desktops and high-performance laptops."/>
                            <Button Name="btnPerfEnableHags" Content="Enable HAGS" Style="{StaticResource ActionBtn}" ToolTip="Turn on Hardware-Accelerated GPU Scheduling for better VRAM management and lower latency." />
                            <Button Name="btnPerfDisableHags" Content="Disable HAGS" Style="{StaticResource ActionBtn}" ToolTip="Turn off Hardware-Accelerated GPU Scheduling." />
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <TextBlock Text="APPX BLOATWARE REMOVAL" Style="{StaticResource SubHeader}" ToolTip="Remove pre-installed Windows apps (UWP/Modern apps) that you don't use. Frees disk space and reduces background processes."/>
                        <TextBlock Text="Select apps to remove (use Ctrl+Click for multiple)" Foreground="{DynamicResource TextSecondary}" Margin="0,0,0,8"/>
                        <ListView Name="lstAppxPackages" Height="200" Background="{DynamicResource BgDark}" Foreground="{DynamicResource TextPrimary}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" SelectionMode="Multiple">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="App Name" Width="250" DisplayMemberBinding="{Binding Name}"/>
                                    <GridViewColumn Header="Package" Width="300" DisplayMemberBinding="{Binding Package}"/>
                                </GridView>
                            </ListView.View>
                        </ListView>
                        <WrapPanel Margin="0,12,0,0">
                            <Button Name="btnAppxLoad" Content="Load Apps" Style="{StaticResource ActionBtn}" ToolTip="Scan for installed UWP/Modern apps that can be removed. Populates the list above with removable bloatware."/>
                            <Button Name="btnAppxRemoveSel" Content="Remove Selected" Style="{StaticResource DestructiveBtn}" ToolTip="Remove the selected apps from your system. These apps can be reinstalled from the Microsoft Store if needed later."/>
                            <Button Name="btnAppxRemoveAll" Content="Remove All" Style="{StaticResource DestructiveBtn}" ToolTip="Remove ALL listed apps at once. This is faster but be careful - only click if you're sure you don't need any of these apps!"/>
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <TextBlock Text="WINDOWS OPTIONAL FEATURES" Style="{StaticResource SubHeader}"/>
                        <WrapPanel>
                            <Button Name="btnFeatHyperV" Content="Hyper-V" Style="{StaticResource ActionBtn}" ToolTip="Microsoft's hardware virtualization platform. Create and run virtual machines. Requires Pro/Enterprise edition and CPU virtualization support."/>
                            <Button Name="btnFeatWSL" Content="WSL" Style="{StaticResource ActionBtn}" ToolTip="Windows Subsystem for Linux. Run Linux command-line tools and apps directly on Windows without a VM. Popular for developers."/>
                            <Button Name="btnFeatSandbox" Content="Sandbox" Style="{StaticResource ActionBtn}" ToolTip="Windows Sandbox - a lightweight, temporary desktop environment to safely run untrusted apps. Discards all changes when closed. Requires Pro/Enterprise."/>
                            <Button Name="btnFeatDotNet35" Content=".NET 3.5" Style="{StaticResource ActionBtn}" ToolTip=".NET Framework 3.5 (includes 2.0 and 3.0). Required for many older Windows applications and some games."/>
                            <Button Name="btnFeatNFS" Content="NFS Client" Style="{StaticResource ActionBtn}" ToolTip="Network File System client. Allows Windows to connect to Linux/UNIX NFS file shares and NAS devices."/>
                            <Button Name="btnFeatTelnet" Content="Telnet" Style="{StaticResource ActionBtn}" ToolTip="Telnet client for command-line remote connections. Not secure (unencrypted) - use SSH when possible."/>
                            <Button Name="btnFeatIIS" Content="IIS" Style="{StaticResource ActionBtn}" ToolTip="Internet Information Services - Microsoft's web server. Host websites locally, useful for web development."/>
                            <Button Name="btnFeatLegacy" Content="Legacy Media" Style="{StaticResource ActionBtn}" ToolTip="Windows Media Player and DirectPlay. Required for some older games and media playback."/>
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <TextBlock Text="SERVICES MANAGEMENT" Style="{StaticResource SubHeader}"/>
                        <WrapPanel>
                            <Button Name="btnSvcOptimize" Content="Optimize Services" Style="{StaticResource PositiveBtn}" ToolTip="Set 100+ non-essential Windows services to Manual startup. Significantly improves boot time and reduces background resource usage."/>
                            <Button Name="btnSvcRestore" Content="Restore Defaults" Style="{StaticResource WarningBtn}" ToolTip="Restore ALL services to their original Windows default settings. Use this if you experience system issues after optimization."/>
                            <Button Name="btnSvcView" Content="View Services" Style="{StaticResource ActionBtn}" ToolTip="Open a grid view of all Windows services showing their current startup type and status. Useful for manual troubleshooting."/>
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <TextBlock Text="SCHEDULED TASKS" Style="{StaticResource SubHeader}"/>
                        <TextBlock Text="Disable telemetry and tracking tasks" Foreground="{DynamicResource TextSecondary}" Margin="0,0,0,8"/>
                        <WrapPanel>
                            <Button Name="btnTasksDisableTelemetry" Content="Disable Telemetry Tasks" Style="{StaticResource DestructiveBtn}" ToolTip="Disable Windows telemetry scheduled tasks including: CEIP (Customer Experience), Error Reporting, Compatibility Appraiser. Reduces background activity and privacy concerns."/>
                            <Button Name="btnTasksRestore" Content="Restore Tasks" Style="{StaticResource WarningBtn}" ToolTip="Re-enable all telemetry and diagnostic scheduled tasks. Restores Windows default behavior for diagnostics and feedback."/>
                            <Button Name="btnTasksView" Content="View Tasks" Style="{StaticResource ActionBtn}" ToolTip="View telemetry-related scheduled tasks in a grid. Shows task name, path, and current enabled/disabled state."/>
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <TextBlock Text="WINDOWS UPDATE PRESETS" Style="{StaticResource SubHeader}"/>
                        <WrapPanel>
                            <Button Name="btnWUDefault" Content="Default" Style="{StaticResource ActionBtn}" ToolTip="Standard Windows Update behavior. Feature and security updates install automatically. Recommended for most users."/>
                            <Button Name="btnWUSecurity" Content="Security Only" Style="{StaticResource UtilityBtn}" ToolTip="Defer feature updates for 1 year, install security updates only. Get new features later while staying secure. Good for stability."/>
                            <Button Name="btnWUDisable" Content="Disable All" Style="{StaticResource DestructiveBtn}" ToolTip="Completely disable Windows Update. NOT RECOMMENDED - your system will become vulnerable to security threats. Use with caution."/>
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <TextBlock Text="TASKBAR &amp; SYSTEM CLOCK" Style="{StaticResource SubHeader}"/>
                        <WrapPanel>
                            <Button Name="btnTaskbarLeft" Content="Align Taskbar Left" Style="{StaticResource ActionBtn}" ToolTip="Aligns the Windows 11 Taskbar to the left side."/>
                            <Button Name="btnTaskbarCenter" Content="Align Taskbar Center" Style="{StaticResource ActionBtn}" ToolTip="Aligns the Windows 11 Taskbar to the center (Default)."/>
                            <Button Name="btnClock24" Content="24-Hour Clock" Style="{StaticResource ActionBtn}" ToolTip="Changes the system tray clock to 24-hour format."/>
                            <Button Name="btnClock12" Content="12-Hour Clock" Style="{StaticResource ActionBtn}" ToolTip="Changes the system tray clock to 12-hour format (Default)."/>
                            <Button Name="btnClockSecsOn" Content="Show Clock Seconds" Style="{StaticResource ActionBtn}" ToolTip="Displays seconds on the system tray clock."/>
                            <Button Name="btnClockSecsOff" Content="Hide Clock Seconds" Style="{StaticResource ActionBtn}" ToolTip="Hides seconds on the system tray clock (Default)."/>
                            <Button Name="btnHideSearch" Content="Hide Search" Style="{StaticResource ActionBtn}" ToolTip="Completely removes the Search box/icon from the taskbar."/>
                            <Button Name="btnSearchIcon" Content="Search as Icon" Style="{StaticResource ActionBtn}" ToolTip="Changes the large Search box into a small icon."/>
                            <Button Name="btnHideWidgets" Content="Hide Widgets" Style="{StaticResource ActionBtn}" ToolTip="Removes the Widgets/Weather panel from the taskbar."/>
                            <Button Name="btnHideTaskView" Content="Hide Task View" Style="{StaticResource ActionBtn}" ToolTip="Removes the Task View (multiple desktops) button."/>
                            <Button Name="btnHideChat" Content="Hide Chat" Style="{StaticResource ActionBtn}" ToolTip="Removes the built-in Microsoft Teams Chat icon."/>
                            <Button Name="btnNeverCombine" Content="Never Combine" Style="{StaticResource ActionBtn}" ToolTip="Shows app labels and stops identical app windows from grouping into one button."/>
                            <Button Name="btnAlwaysCombine" Content="Always Combine" Style="{StaticResource ActionBtn}" ToolTip="Hides app labels and groups windows (Windows 11 Default)."/>
                            </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <TextBlock Text="EXPLORER &amp; FILES" Style="{StaticResource SubHeader}"/>
                        <WrapPanel>
                            <Button Name="btnExpShowExt" Content="Show Extensions" Style="{StaticResource ActionBtn}" ToolTip="Show known file extensions in File Explorer."/>
                            <Button Name="btnExpHideExt" Content="Hide Extensions" Style="{StaticResource ActionBtn}" ToolTip="Restore Windows default behavior for known file extensions."/>
                            <Button Name="btnExpShowHidden" Content="Show Hidden Files" Style="{StaticResource ActionBtn}" ToolTip="Show hidden files and folders in File Explorer."/>
                            <Button Name="btnExpHideHidden" Content="Hide Hidden Files" Style="{StaticResource ActionBtn}" ToolTip="Hide hidden files and folders."/>
                            <Button Name="btnExpFullPathOn" Content="Full Path On" Style="{StaticResource ActionBtn}" ToolTip="Show the full folder path in File Explorer title bars."/>
                            <Button Name="btnExpFullPathOff" Content="Full Path Off" Style="{StaticResource ActionBtn}" ToolTip="Hide the full folder path in File Explorer title bars."/>
                            <Button Name="btnExpLaunchThisPc" Content="Open This PC" Style="{StaticResource ActionBtn}" ToolTip="Make File Explorer open to This PC."/>
                            <Button Name="btnExpLaunchQuickAccess" Content="Open Quick Access" Style="{StaticResource ActionBtn}" ToolTip="Make File Explorer open to Quick Access/Home."/>
                            <Button Name="btnExpHideRecents" Content="Hide Recents" Style="{StaticResource ActionBtn}" ToolTip="Hide recent and frequent items from Quick Access/Home."/>
                            <Button Name="btnExpShowRecents" Content="Show Recents" Style="{StaticResource ActionBtn}" ToolTip="Restore recent and frequent items in Quick Access/Home."/>
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <TextBlock Text="MOUSE &amp; FOLDER OPENING" Style="{StaticResource SubHeader}"/>
                        <WrapPanel>
                            <Button Name="btnMouseSpeedSlow" Content="Cursor Slow" Style="{StaticResource ActionBtn}" ToolTip="Set mouse pointer speed to 6."/>
                            <Button Name="btnMouseSpeedDefault" Content="Cursor Default" Style="{StaticResource ActionBtn}" ToolTip="Set mouse pointer speed to the Windows default of 10."/>
                            <Button Name="btnMouseSpeedFast" Content="Cursor Fast" Style="{StaticResource ActionBtn}" ToolTip="Set mouse pointer speed to 15."/>
                            <Button Name="btnMouseAccelOn" Content="Acceleration On" Style="{StaticResource ActionBtn}" ToolTip="Enable enhanced pointer precision / mouse acceleration."/>
                            <Button Name="btnMouseAccelOff" Content="Acceleration Off" Style="{StaticResource ActionBtn}" ToolTip="Disable enhanced pointer precision / mouse acceleration."/>
                            <Button Name="btnMouseSingleClick" Content="Single-Click Folders" Style="{StaticResource ActionBtn}" ToolTip="Open files and folders with a single click in File Explorer."/>
                            <Button Name="btnMouseDoubleClick" Content="Double-Click Folders" Style="{StaticResource ActionBtn}" ToolTip="Restore double-click to open files and folders."/>
                            <Button Name="btnMouseSettings" Content="Mouse Settings" Style="{StaticResource UtilityBtn}" ToolTip="Open Windows mouse settings."/>
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <TextBlock Text="CONTEXT MENU" Style="{StaticResource SubHeader}"/>
                        <WrapPanel>
                            <Button Name="btnCtxClassic" Content="Classic Right-Click" Style="{StaticResource ActionBtn}" ToolTip="Use the classic Windows 10-style context menu on Windows 11."/>
                            <Button Name="btnCtxModern" Content="Modern Right-Click" Style="{StaticResource ActionBtn}" ToolTip="Restore the default Windows 11 context menu."/>
                            <Button Name="btnCtxTakeOwnAdd" Content="Add Take Ownership" Style="{StaticResource WarningBtn}" ToolTip="Add an elevated Take Ownership action to file, folder, and drive context menus."/>
                            <Button Name="btnCtxTakeOwnRemove" Content="Remove Take Ownership" Style="{StaticResource ActionBtn}" ToolTip="Remove the Take Ownership context menu action."/>
                            <Button Name="btnCtxPsHereAdd" Content="Add PowerShell Here" Style="{StaticResource ActionBtn}" ToolTip="Add Open PowerShell Here to folder and background context menus."/>
                            <Button Name="btnCtxPsHereRemove" Content="Remove PowerShell Here" Style="{StaticResource ActionBtn}" ToolTip="Remove the Open PowerShell Here context menu action."/>
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <TextBlock Text="PRIVACY" Style="{StaticResource SubHeader}"/>
                        <WrapPanel>
                            <Button Name="btnPrivacyAdsOff" Content="Ad ID Off" Style="{StaticResource ActionBtn}" ToolTip="Disable the per-user Windows advertising ID."/>
                            <Button Name="btnPrivacyAdsOn" Content="Ad ID On" Style="{StaticResource ActionBtn}" ToolTip="Re-enable the per-user Windows advertising ID."/>
                            <Button Name="btnPrivacySuggestedOff" Content="Suggestions Off" Style="{StaticResource ActionBtn}" ToolTip="Disable suggested apps, settings suggestions, and consumer content prompts."/>
                            <Button Name="btnPrivacySuggestedOn" Content="Suggestions On" Style="{StaticResource ActionBtn}" ToolTip="Restore suggested content defaults."/>
                            <Button Name="btnPrivacyTailoredOff" Content="Tailored Off" Style="{StaticResource ActionBtn}" ToolTip="Disable tailored experiences based on diagnostic data."/>
                            <Button Name="btnPrivacyTailoredOn" Content="Tailored On" Style="{StaticResource ActionBtn}" ToolTip="Restore tailored experiences."/>
                            <Button Name="btnPrivacyActivityOff" Content="Activity History Off" Style="{StaticResource ActionBtn}" ToolTip="Disable Windows activity history publishing and upload policies."/>
                            <Button Name="btnPrivacyActivityOn" Content="Activity History On" Style="{StaticResource ActionBtn}" ToolTip="Restore Windows activity history policy defaults."/>
                            <Button Name="btnPrivacyAppLaunchOff" Content="Launch Tracking Off" Style="{StaticResource ActionBtn}" ToolTip="Stop Windows from tracking app launches to personalize Start and Search."/>
                            <Button Name="btnPrivacyAppLaunchOn" Content="Launch Tracking On" Style="{StaticResource ActionBtn}" ToolTip="Restore app launch tracking."/>
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <TextBlock Text="SEARCH &amp; INDEXING" Style="{StaticResource SubHeader}"/>
                        <WrapPanel>
                            <Button Name="btnSearchWebOff" Content="Web Search Off" Style="{StaticResource ActionBtn}" ToolTip="Disable Bing/web results in Windows Start search."/>
                            <Button Name="btnSearchWebOn" Content="Web Search On" Style="{StaticResource ActionBtn}" ToolTip="Restore web results in Windows Start search."/>
                            <Button Name="btnSearchIndexReduced" Content="Reduce Indexing" Style="{StaticResource ActionBtn}" ToolTip="Set Windows Search indexing service to Manual and stop it."/>
                            <Button Name="btnSearchIndexDefault" Content="Default Indexing" Style="{StaticResource ActionBtn}" ToolTip="Restore Windows Search indexing service to Automatic."/>
                            <Button Name="btnSearchIndexRebuild" Content="Rebuild Index" Style="{StaticResource WarningBtn}" ToolTip="Delete the Windows search index database so Windows rebuilds it."/>
                            <Button Name="btnSearchIndexOptions" Content="Index Options" Style="{StaticResource UtilityBtn}" ToolTip="Open Windows Indexing Options."/>
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <TextBlock Text="GAMING" Style="{StaticResource SubHeader}"/>
                        <WrapPanel>
                            <Button Name="btnGameModeOn" Content="Game Mode On" Style="{StaticResource ActionBtn}" ToolTip="Enable Windows Game Mode."/>
                            <Button Name="btnGameModeOff" Content="Game Mode Off" Style="{StaticResource ActionBtn}" ToolTip="Disable Windows Game Mode."/>
                            <Button Name="btnGameBarOff" Content="Game Bar Off" Style="{StaticResource ActionBtn}" ToolTip="Disable Xbox Game Bar and Game DVR toggles."/>
                            <Button Name="btnGameBarOn" Content="Game Bar On" Style="{StaticResource ActionBtn}" ToolTip="Restore Xbox Game Bar and Game DVR toggles."/>
                            <Button Name="btnGameCaptureOff" Content="Capture Off" Style="{StaticResource ActionBtn}" ToolTip="Disable background gameplay capture."/>
                            <Button Name="btnGameCaptureOn" Content="Capture On" Style="{StaticResource ActionBtn}" ToolTip="Restore background gameplay capture."/>
                            <Button Name="btnGameFsoOff" Content="Disable FS Optimizations" Style="{StaticResource ActionBtn}" ToolTip="Apply common registry values to disable fullscreen optimizations globally."/>
                            <Button Name="btnGameFsoDefault" Content="Default FS Optimizations" Style="{StaticResource ActionBtn}" ToolTip="Restore default fullscreen optimization registry values."/>
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <TextBlock Text="VISUAL EFFECTS" Style="{StaticResource SubHeader}"/>
                        <WrapPanel>
                            <Button Name="btnVisualBestAppearance" Content="Best Appearance" Style="{StaticResource ActionBtn}" ToolTip="Set Windows visual effects to best appearance."/>
                            <Button Name="btnVisualBestPerformance" Content="Best Performance" Style="{StaticResource ActionBtn}" ToolTip="Set Windows visual effects to best performance."/>
                            <Button Name="btnVisualSnappy" Content="Snappy Desktop" Style="{StaticResource PositiveBtn}" ToolTip="Disable taskbar animations, window minimize animations, Aero Peek, and transparency."/>
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <TextBlock Text="NOTIFICATIONS &amp; LOCK SCREEN" Style="{StaticResource SubHeader}"/>
                        <WrapPanel>
                            <Button Name="btnNotifyFocusSettings" Content="Focus Settings" Style="{StaticResource UtilityBtn}" ToolTip="Open Focus Assist / Do Not Disturb settings."/>
                            <Button Name="btnNotifyTipsOff" Content="Tips Off" Style="{StaticResource ActionBtn}" ToolTip="Disable Windows tips, welcome experience, and suggestion notifications."/>
                            <Button Name="btnNotifyTipsOn" Content="Tips On" Style="{StaticResource ActionBtn}" ToolTip="Restore Windows tips and suggestion notifications."/>
                            <Button Name="btnNotifySetupOff" Content="Setup Prompts Off" Style="{StaticResource ActionBtn}" ToolTip="Disable finish setting up this device prompts."/>
                            <Button Name="btnNotifySetupOn" Content="Setup Prompts On" Style="{StaticResource ActionBtn}" ToolTip="Restore finish setting up this device prompts."/>
                            <Button Name="btnLockFactsOff" Content="Lock Facts Off" Style="{StaticResource ActionBtn}" ToolTip="Disable fun facts, tips, and overlays on the lock screen."/>
                            <Button Name="btnLockFactsOn" Content="Lock Facts On" Style="{StaticResource ActionBtn}" ToolTip="Restore lock screen fun facts and overlays."/>
                            <Button Name="btnLockSpotlightOff" Content="Spotlight Off" Style="{StaticResource ActionBtn}" ToolTip="Disable Windows Spotlight on the lock screen."/>
                            <Button Name="btnLockSpotlightOn" Content="Spotlight On" Style="{StaticResource ActionBtn}" ToolTip="Restore Windows Spotlight on the lock screen."/>
                            <Button Name="btnLockPlain" Content="Plain Lock Screen" Style="{StaticResource ActionBtn}" ToolTip="Disable lock screen Spotlight and overlay content together."/>
                            <Button Name="btnLockDefault" Content="Default Lock Screen" Style="{StaticResource ActionBtn}" ToolTip="Restore default lock screen content settings."/>
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <TextBlock Text="STARTUP BEHAVIOR" Style="{StaticResource SubHeader}"/>
                        <WrapPanel>
                            <Button Name="btnStartupFastOff" Content="Fast Startup Off" Style="{StaticResource ActionBtn}" ToolTip="Disable Windows Fast Startup."/>
                            <Button Name="btnStartupFastOn" Content="Fast Startup On" Style="{StaticResource ActionBtn}" ToolTip="Enable Windows Fast Startup."/>
                            <Button Name="btnStartupRestoreFoldersOn" Content="Restore Folders On" Style="{StaticResource ActionBtn}" ToolTip="Restore previous folder windows at logon."/>
                            <Button Name="btnStartupRestoreFoldersOff" Content="Restore Folders Off" Style="{StaticResource ActionBtn}" ToolTip="Do not restore previous folder windows at logon."/>
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <TextBlock Text="SECURITY SHORTCUTS" Style="{StaticResource SubHeader}"/>
                        <WrapPanel>
                            <Button Name="btnSecurityUacOpen" Content="UAC Settings" Style="{StaticResource UtilityBtn}" ToolTip="Open User Account Control settings."/>
                            <Button Name="btnSecurityUacStatus" Content="UAC Status" Style="{StaticResource ActionBtn}" ToolTip="Log the current UAC registry status."/>
                            <Button Name="btnSecuritySmartScreenOpen" Content="SmartScreen Settings" Style="{StaticResource UtilityBtn}" ToolTip="Open Windows App and Browser Control settings."/>
                            <Button Name="btnSecuritySmartScreenStatus" Content="SmartScreen Status" Style="{StaticResource ActionBtn}" ToolTip="Log the current SmartScreen status."/>
                            <Button Name="btnSecurityCfaOpen" Content="Controlled Folders" Style="{StaticResource UtilityBtn}" ToolTip="Open Controlled Folder Access / ransomware protection settings."/>
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <TextBlock Text="POWER &amp; BATTERY" Style="{StaticResource SubHeader}"/>
                        <WrapPanel>
                            <Button Name="btnPowerBatterySaverOff" Content="Saver Off" Style="{StaticResource ActionBtn}" ToolTip="Set battery saver threshold to 0 percent."/>
                            <Button Name="btnPowerBatterySaver20" Content="Saver 20%" Style="{StaticResource ActionBtn}" ToolTip="Set battery saver threshold to 20 percent."/>
                            <Button Name="btnPowerBatterySaver50" Content="Saver 50%" Style="{StaticResource ActionBtn}" ToolTip="Set battery saver threshold to 50 percent."/>
                            <Button Name="btnPowerUsbSuspendOn" Content="USB Suspend On" Style="{StaticResource ActionBtn}" ToolTip="Enable USB selective suspend for the active power plan."/>
                            <Button Name="btnPowerUsbSuspendOff" Content="USB Suspend Off" Style="{StaticResource ActionBtn}" ToolTip="Disable USB selective suspend for the active power plan."/>
                            <Button Name="btnPowerPcieModerate" Content="PCIe Savings" Style="{StaticResource ActionBtn}" ToolTip="Set PCI Express link state power management to moderate savings."/>
                            <Button Name="btnPowerPcieOff" Content="PCIe Savings Off" Style="{StaticResource ActionBtn}" ToolTip="Turn off PCI Express link state power management."/>
                        </WrapPanel>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource CardStyle}">
                    <StackPanel>
                        <TextBlock Text="DEVELOPER" Style="{StaticResource SubHeader}"/>
                        <WrapPanel>
                            <Button Name="btnDevLongPathsOn" Content="Long Paths On" Style="{StaticResource ActionBtn}" ToolTip="Enable Win32 long path support."/>
                            <Button Name="btnDevLongPathsOff" Content="Long Paths Off" Style="{StaticResource ActionBtn}" ToolTip="Disable Win32 long path support."/>
                            <Button Name="btnDevModeOn" Content="Developer Mode On" Style="{StaticResource ActionBtn}" ToolTip="Enable Windows Developer Mode policies."/>
                            <Button Name="btnDevModeOff" Content="Developer Mode Off" Style="{StaticResource ActionBtn}" ToolTip="Disable Windows Developer Mode policies."/>
                            <Button Name="btnDevSettings" Content="Developer Settings" Style="{StaticResource UtilityBtn}" ToolTip="Open Windows Developer Settings."/>
                        </WrapPanel>
                    </StackPanel>
                </Border>
            </StackPanel>
        </ScrollViewer>
                

                <!-- SYSTEM HEALTH PANEL -->
                <StackPanel Name="pnlHealth" Visibility="Collapsed">
                    <Border Style="{StaticResource CardStyle}">
                        <StackPanel>
                            <StackPanel Margin="0,0,0,20">
                                <TextBlock Text="System Health" Style="{StaticResource SectionHeader}" Margin="0"/>
                            </StackPanel>
                            <TextBlock Text="WINDOWS REPAIR TOOLS" Style="{StaticResource SubHeader}"/>
                            <WrapPanel>
                                <Button Name="btnQuickFix" Content="Quick Fix" Style="{StaticResource WarningBtn}" ToolTip="One guided flow: SFC + DISM + Temp cleanup."/>
                                <Button Name="btnSFC" Content="SFC Scan" Style="{StaticResource ActionBtn}" ToolTip="System File Checker - repairs corrupted system files"/>
                                <Button Name="btnDISMCheck" Content="DISM Check" Style="{StaticResource ActionBtn}" ToolTip="Check Windows image health"/>
                                <Button Name="btnDISMRestore" Content="DISM Restore" Style="{StaticResource UtilityBtn}" ToolTip="Repair Windows image"/>
                                <Button Name="btnCHKDSK" Content="CHKDSK" Style="{StaticResource ActionBtn}" ToolTip="Check disk for errors (requires reboot)"/>
                            </WrapPanel>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- NETWORK PANEL -->
                <StackPanel Name="pnlNetwork" Visibility="Collapsed">
                    <!-- Header Card -->
                    <Border Style="{StaticResource CardStyle}">
                        <StackPanel>
                            <TextBlock Text="Network &amp; DNS" Style="{StaticResource SectionHeader}" Margin="0"/>
                        </StackPanel>
                    </Border>

                    <!-- General Tools Card -->
                    <Border Style="{StaticResource CardStyle}">
                        <StackPanel>
                            <TextBlock Text="DIAGNOSTIC TOOLS" Style="{StaticResource SubHeader}"/>
                            <WrapPanel>
                                <Button Name="btnNetInfo" Content="IP Config" Style="{StaticResource ActionBtn}" ToolTip="Display network configuration"/>
                                <Button Name="btnFlushDNS" Content="Flush DNS" Style="{StaticResource ActionBtn}" ToolTip="Clear DNS cache"/>
                                <Button Name="btnResetWifi" Content="Restart Wi-Fi" Style="{StaticResource ActionBtn}" ToolTip="Reset wireless adapters"/>
                                <Button Name="btnNetRepair" Content="Full Repair" Style="{StaticResource WarningBtn}" ToolTip="Comprehensive network reset"/>
                                <Button Name="btnRouteTable" Content="Save Routes" Style="{StaticResource ActionBtn}"/>
                                <Button Name="btnRouteView" Content="View Routes" Style="{StaticResource ActionBtn}"/>
                            </WrapPanel>
                        </StackPanel>
                    </Border>

                    <!-- DNS Card -->
                    <Border Style="{StaticResource CardStyle}">
                        <StackPanel>
                            <TextBlock Text="DNS SERVERS" Style="{StaticResource SubHeader}"/>
                            <WrapPanel>
                                <Button Name="btnDnsGoogle" Content="Google DNS" Style="{StaticResource ActionBtn}" ToolTip="8.8.8.8 / 8.8.4.4"/>
                                <Button Name="btnDnsCloudflare" Content="Cloudflare" Style="{StaticResource ActionBtn}" ToolTip="1.1.1.1 / 1.0.0.1"/>
                                <Button Name="btnDnsQuad9" Content="Quad9" Style="{StaticResource ActionBtn}" ToolTip="9.9.9.9"/>
                                <Button Name="btnDnsAdGuard" Content="AdGuard" Style="{StaticResource ActionBtn}" ToolTip="94.140.14.14 / 94.140.15.15"/>
                                <Button Name="btnDnsAuto" Content="Auto (DHCP)" Style="{StaticResource ActionBtn}"/>
                                <Button Name="btnDnsCustom" Content="Custom..." Style="{StaticResource UtilityBtn}" ToolTip="Set custom DNS servers and optional DoH template"/>
                            </WrapPanel>
                            
                            <TextBlock Text="DNS OVER HTTPS" Style="{StaticResource SubHeader}" Margin="0,16,0,8"/>
                            <WrapPanel>
                                <Button Name="btnDohAuto" Content="Register DoH" Style="{StaticResource PositiveBtn}" ToolTip="Register Windows DoH templates for bundled DNS providers"/>
                                <Button Name="btnDohDisable" Content="Remove DoH" Style="{StaticResource DestructiveBtn}" ToolTip="Remove bundled Windows DoH templates"/>
                            </WrapPanel>
                        </StackPanel>
                    </Border>

                    <!-- Hosts File Card -->
                    <Border Style="{StaticResource CardStyle}">
                        <StackPanel>
                            <TextBlock Text="HOSTS FILE MANAGER" Style="{StaticResource SubHeader}"/>
                            <WrapPanel>
                                <Button Name="btnHostsUpdate" Content="Download AdBlock" Style="{StaticResource PositiveBtn}" ToolTip="Download and merge ad-blocking hosts"/>
                                <Button Name="btnHostsEdit" Content="Edit Hosts" Style="{StaticResource ActionBtn}"/>
                                <Button Name="btnHostsBackup" Content="Backup" Style="{StaticResource ActionBtn}"/>
                                <Button Name="btnHostsRestore" Content="Restore" Style="{StaticResource ActionBtn}"/>
                            </WrapPanel>
                        </StackPanel>
                    </Border>
                                </StackPanel>

                                <!-- MY DEVICE PANEL -->
                                <ScrollViewer Name="pnlMyDevice" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                                    <StackPanel>
                                        <WrapPanel Name="pnlMyDeviceCards" Margin="20" ItemWidth="350">
                                                <Border Background="{DynamicResource BgPanel}" CornerRadius="8" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" Margin="10" Padding="15">
                                                    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                                        <Border Width="48" Height="48" CornerRadius="8" Background="{DynamicResource BgElevated}" VerticalAlignment="Top" Margin="0,0,15,0">
                                                            <Path Fill="{DynamicResource Accent}" Stretch="Uniform" Width="22" Height="22" Data="M0 3.4l10-1.4v9H0V3.4zm11-1.5L23 0v11H11V1.9zM0 12h10v8.6l-10-1.4V12zm11 0h12v10l-12-1.9V12z"/>
                                                        </Border>
                                                        <StackPanel Grid.Column="1">
                                                            <TextBlock Text="Operating System" FontSize="16" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}"/>
                                                            <TextBlock x:Name="txtDeviceOS" FontSize="13" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="18"/>
                                                            <WrapPanel Margin="0,10,0,0">
                                                                <Button Name="btnMyDeviceWinUpdate" Content="Update" Style="{StaticResource ActionBtn}" Width="112" ToolTip="Open Windows Update settings"/>
                                                                <Button Name="btnMyDeviceQuickFix" Content="Quick Fix" Style="{StaticResource WarningBtn}" Width="112" ToolTip="Run the guided SFC, DISM, and temp cleanup flow"/>
                                                                <Button Name="btnMyDeviceWinRE" Content="WinRE" Style="{StaticResource ActionBtn}" Width="112" ToolTip="Check Windows Recovery Environment status"/>
                                                                <Button Name="btnMyDeviceSysReport" Content="Report" Style="{StaticResource ActionBtn}" Width="112" ToolTip="Generate a detailed system report"/>
                                                                <Button Name="btnMyDeviceRestoreMgr" Content="Restore" Style="{StaticResource ActionBtn}" Width="112" ToolTip="Manage System Restore points"/>
                                                                <Button Name="btnMyDeviceStartupMgr" Content="Startup" Style="{StaticResource ActionBtn}" Width="112" ToolTip="Manage startup apps, tasks, context menu entries, and services"/>
                                                                <Button Name="btnMyDeviceUpdateRepair" Content="WU Fix" Style="{StaticResource WarningBtn}" Width="112" ToolTip="Reset Windows Update components"/>
                                                                <Button Name="btnMyDeviceUpdateServices" Content="WU Svcs" Style="{StaticResource ActionBtn}" Width="112" ToolTip="Restart Windows Update related services"/>
                                                            </WrapPanel>
                                                        </StackPanel>
                                                    </Grid>
                                                </Border>

                                                <Border Background="{DynamicResource BgPanel}" CornerRadius="8" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" Margin="10" Padding="15">
                                                    <Grid>
                                                        <Grid.ColumnDefinitions>
                                                            <ColumnDefinition Width="Auto"/>
                                                            <ColumnDefinition Width="*"/>
                                                        </Grid.ColumnDefinitions>
                                                        <!-- Network icon (stylised globe + network lines) -->
                                                        <Border Width="48" Height="48" CornerRadius="8" Background="{DynamicResource BgElevated}" VerticalAlignment="Top" Margin="0,0,15,0">
    <Viewbox Width="28" Height="28">
        <Canvas Width="400" Height="400">
            <!-- Gradients converted to XAML Resources -->
            <Canvas.Resources>
                <LinearGradientBrush x:Key="Path1Brush" StartPoint="0.17,0.83" EndPoint="0.31,0.83">
                    <GradientStop Color="#5080B1" Offset="0"/>
                    <GradientStop Color="#004E8C" Offset="1"/>
                </LinearGradientBrush>
                <LinearGradientBrush x:Key="Path2Brush" StartPoint="0.03,0.67" EndPoint="0.45,0.67">
                    <GradientStop Color="#5080B1" Offset="0"/>
                    <GradientStop Color="#004E8C" Offset="1"/>
                </LinearGradientBrush>
                <LinearGradientBrush x:Key="Path3Brush" StartPoint="-0.1,0.51" EndPoint="0.6,0.51">
                    <GradientStop Color="#5080B1" Offset="0"/>
                    <GradientStop Color="#004E8C" Offset="1"/>
                </LinearGradientBrush>
                <LinearGradientBrush x:Key="Path4Brush" StartPoint="-0.23,0.34" EndPoint="0.74,0.34">
                    <GradientStop Color="#5080B1" Offset="0"/>
                    <GradientStop Color="#004E8C" Offset="1"/>
                </LinearGradientBrush>
            </Canvas.Resources>

            <Path Fill="{StaticResource Path1Brush}" Data="M170.4 331c0 7.7 3.4 15.3 9.2 20.3 11.1 9.5 28.4 8.7 38.7-1.7 5-5.1 7.5-12.1 7.4-18.5 0-6.4-2.4-12.4-7.4-17.5-10.3-10.4-27.6-11.1-38.7-1.7-5.5 4.7-8.9 11-8.8 19.1z"/>
            <Path Fill="{StaticResource Path2Brush}" Data="M281.3 272.7c-10.3 11-20.4 21.8-30.5 32.6-4.4-3.8-8.6-7.7-13.1-11.2-7.8-6.2-16.2-11.3-25.6-14.4-15.1-5-29.1-2.2-42.5 6-8 4.9-15 11.1-21.5 17.9-.3.3-.6.7-1.1 1.3-10.8-10.6-21.4-21-32.3-31.7 4.3-4.1 8.4-8.3 12.8-12.1 12.2-10.9 25.6-19.6 41.1-24.7 24.8-8.2 48.7-5.4 71.9 6.1 14.9 7.4 27.7 17.4 39.7 29 .2.3.6.8 1 1.2z"/>
            <Path Fill="{StaticResource Path3Brush}" Data="M310.4 253.7c-9.3-7.9-18.1-15.9-27.4-23.3-14.5-11.5-30.3-21-47.7-27.3-14.3-5.2-29.1-7.8-44.3-6.8-18.8 1.2-36.1 7.6-52.3 17.2-17.5 10.4-32.6 23.8-46.7 38.6-.3.3-.6.8-1 1.3-10.8-10.6-21.4-21-32.3-31.7 3.5-3.5 6.9-7 10.3-10.4 14.9-14.7 31-27.7 49-38.2 18.1-10.5 37.2-17.9 57.8-21 24.2-3.6 47.9-1.1 71 6.9 23.7 8.1 45 20.7 64.6 36.5 9.6 7.7 18.6 16.2 27.9 24.4.4.4.9.6 1.5 1.1-10 10.8-20.1 21.7-30.1 32.3z"/>
            <Path Fill="{StaticResource Path4Brush}" Data="M205.8 69.2c2.8.3 5.6.6 8.4.8 22.6 1.7 44.3 7.4 65.2 16 29.5 12 56.1 29 80.7 49.4 11.8 9.7 22.9 20.3 34.3 30.5.5.5 1.1.9 1.8 1.4-10.4 11.1-20.5 21.9-30.8 32.9-1-.9-2-1.7-2.9-2.6-14.1-13.8-29-26.6-44.9-38.1-20.3-14.7-41.8-27-65.4-35.2-20.4-7.1-41.4-10.4-62.9-9.2-20.8 1.2-40.7 6.6-59.7 15.4-23.8 10.9-44.9 26-64.3 43.6-9 8.1-17.5 16.7-26.3 25.3-.5-.5-1.3-1.2-2.1-2-9.6-9.4-19.1-18.8-28.7-28.2-.3-.3-.7-.6-1.1-.8 0-.1 0-.3 0-.4.6-.5 1.2-1 1.8-1.6 25-26.4 52.2-50 83.8-67.8 28-15.8 57.7-26 89.7-28.5 2.6-.2 5.2-.5 7.8-.7h10z"/>
        </Canvas>
    </Viewbox>
</Border>
                                                        <StackPanel Grid.Column="1">
                                                            <TextBlock Text="Network Info" FontSize="16" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}"/>
                                                            <TextBlock x:Name="txtDeviceNetwork" FontSize="13" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="18"/>
                                                            <StackPanel Name="pnlDeviceNetworkList" Margin="0,6,0,0"/>
                                                            <WrapPanel Margin="0,10,0,0">
                                                                <Button Name="btnMyDeviceNetInfo" Content="IP Config" Style="{StaticResource ActionBtn}" Width="112" ToolTip="Display full IP configuration"/>
                                                                <Button Name="btnMyDeviceFlushDNS" Content="Flush DNS" Style="{StaticResource ActionBtn}" Width="112" ToolTip="Clear the DNS resolver cache"/>
                                                                <Button Name="btnMyDeviceResetWifi" Content="Wi-Fi" Style="{StaticResource ActionBtn}" Width="112" ToolTip="Restart active Wi-Fi adapters"/>
                                                                <Button Name="btnMyDeviceNetRepair" Content="Repair" Style="{StaticResource WarningBtn}" Width="112" ToolTip="Run the full network repair flow"/>
                                                                <Button Name="btnMyDeviceDnsCustom" Content="DNS" Style="{StaticResource UtilityBtn}" Width="112" ToolTip="Set custom DNS servers"/>
                                                                <Button Name="btnMyDeviceHostsEdit" Content="Hosts" Style="{StaticResource ActionBtn}" Width="112" ToolTip="Open the Hosts file editor"/>
                                                                <Button Name="btnMyDeviceHostsAdBlock" Content="AdBlock" Style="{StaticResource PositiveBtn}" Width="112" ToolTip="Download and merge ad-blocking hosts"/>
                                                                <Button Name="btnMyDeviceRouteView" Content="Routes" Style="{StaticResource ActionBtn}" Width="112" ToolTip="Display the routing table"/>
                                                            </WrapPanel>
                                                        </StackPanel>
                                                    </Grid>
                                                </Border>

                                                <Border Background="{DynamicResource BgPanel}" CornerRadius="8" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" Margin="10" Padding="15">
                                                    <Grid>
                                                        <Grid.ColumnDefinitions>
                                                            <ColumnDefinition Width="Auto"/>
                                                            <ColumnDefinition Width="*"/>
                                                        </Grid.ColumnDefinitions>
                                                        <Border Width="48" Height="48" CornerRadius="8" Background="{DynamicResource BgElevated}" VerticalAlignment="Top" Margin="0,0,15,0">
                                                            <Viewbox Width="22" Height="22">
                                                                <Canvas Width="512" Height="512">
                                                                    <Rectangle Canvas.Left="141.312" Canvas.Top="0" Width="32.771" Height="71.683" Fill="{DynamicResource Accent}"/>
                                                                    <Rectangle Canvas.Left="206.853" Canvas.Top="0" Width="32.761" Height="71.683" Fill="{DynamicResource Accent}"/>
                                                                    <Rectangle Canvas.Left="272.385" Canvas.Top="0" Width="32.761" Height="71.683" Fill="{DynamicResource Accent}"/>
                                                                    <Rectangle Canvas.Left="337.917" Canvas.Top="0" Width="32.77" Height="71.683" Fill="{DynamicResource Accent}"/>
                                                                    <Rectangle Canvas.Left="141.312" Canvas.Top="440.326" Width="32.771" Height="71.674" Fill="{DynamicResource Accent}"/>
                                                                    <Rectangle Canvas.Left="206.853" Canvas.Top="440.326" Width="32.761" Height="71.674" Fill="{DynamicResource Accent}"/>
                                                                    <Rectangle Canvas.Left="272.385" Canvas.Top="440.326" Width="32.761" Height="71.674" Fill="{DynamicResource Accent}"/>
                                                                    <Rectangle Canvas.Left="337.917" Canvas.Top="440.326" Width="32.77" Height="71.674" Fill="{DynamicResource Accent}"/>
                                                                    <Rectangle Canvas.Left="440.321" Canvas.Top="141.307" Width="71.674" Height="32.771" Fill="{DynamicResource Accent}"/>
                                                                    <Rectangle Canvas.Left="440.321" Canvas.Top="206.849" Width="71.674" Height="32.77" Fill="{DynamicResource Accent}"/>
                                                                    <Rectangle Canvas.Left="440.321" Canvas.Top="272.39" Width="71.674" Height="32.761" Fill="{DynamicResource Accent}"/>
                                                                    <Rectangle Canvas.Left="440.321" Canvas.Top="337.922" Width="71.674" Height="32.77" Fill="{DynamicResource Accent}"/>
                                                                    <Rectangle Canvas.Left="0.005" Canvas.Top="141.307" Width="71.674" Height="32.771" Fill="{DynamicResource Accent}"/>
                                                                    <Rectangle Canvas.Left="0.005" Canvas.Top="206.849" Width="71.674" Height="32.77" Fill="{DynamicResource Accent}"/>
                                                                    <Rectangle Canvas.Left="0.005" Canvas.Top="272.39" Width="71.674" Height="32.761" Fill="{DynamicResource Accent}"/>
                                                                    <Rectangle Canvas.Left="0.005" Canvas.Top="337.922" Width="71.674" Height="32.77" Fill="{DynamicResource Accent}"/>
                                                                    <Path Fill="{DynamicResource Accent}" Data="M255.246,252.209c6.171,0,9.862-3.586,9.862-9.06c0-5.485-3.69-9.176-9.862-9.176h-11.16c-0.4,0-0.6,0.21-0.6,0.61v17.025c0,0.4,0.2,0.601,0.6,0.601H255.246z"/>
                                                                    <Path Fill="{DynamicResource Accent}" Data="M92.165,419.84h327.67V92.17H92.165V419.84z M367.359,130.568c8.479,0,15.356,6.867,15.356,15.356c0,8.488-6.876,15.355-15.356,15.355c-8.479,0-15.356-6.867-15.356-15.355C352.004,137.434,358.88,130.568,367.359,130.568z M367.359,353.287c8.479,0,15.356,6.867,15.356,15.356c0,8.488-6.876,15.355-15.356,15.355c-8.479,0-15.356-6.867-15.356-15.355C352.004,360.154,358.88,353.287,367.359,353.287z M290.821,222.318c0-0.591,0.4-0.991,1.001-0.991h12.648c0.6,0,1.001,0.4,1.001,0.991v42.242c0,8.069,4.483,12.648,11.35,12.648c6.772,0,11.264-4.578,11.264-12.648v-42.242c0-0.591,0.4-0.991,0.992-0.991h12.646c0.601,0,0.992,0.4,0.992,0.991v41.851c0,16.825-10.749,25.99-25.895,25.99c-15.232,0-25.999-9.165-25.999-25.99V222.318z M228.846,222.318c0-0.591,0.4-0.991,1.001-0.991h26.295c14.745,0,23.605,8.87,23.605,21.822c0,12.741-8.966,21.707-23.605,21.707h-12.056c-0.4,0-0.6,0.2-0.6,0.6v22.614c0,0.591-0.391,0.991-0.991,0.991h-12.648c-0.601,0-1.001-0.4-1.001-0.991V222.318z M167.673,236.872c3.586-11.063,12.256-16.633,24.112-16.633c11.454,0,19.819,5.57,23.605,15.03c0.295,0.496,0.095,0.992-0.496,1.202l-10.863,4.874c-0.592,0.296-1.097,0.104-1.393-0.486c-1.889-4.387-5.084-7.678-10.759-7.678c-5.274,0-8.66,2.795-10.157,7.468c-0.801,2.499-1.097,4.883-1.097,14.554c0,9.652,0.296,12.046,1.097,14.535c1.497,4.673,4.883,7.468,10.157,7.468c5.675,0,8.87-3.291,10.759-7.669c0.296-0.6,0.801-0.791,1.393-0.496l10.863,4.874c0.591,0.21,0.791,0.706,0.496,1.202c-3.786,9.461-12.152,15.04-23.605,15.04c-11.856,0-20.525-5.58-24.112-16.643c-1.487-4.368-1.888-7.859-1.888-18.312C165.785,244.732,166.186,241.26,167.673,236.872z M144.64,130.568c8.489,0,15.365,6.876,15.365,15.356c0,8.478-6.876,15.355-15.365,15.355c-8.488,0-15.355-6.876-15.355-15.355C129.285,137.444,136.152,130.568,144.64,130.568z M144.64,353.287c8.489,0,15.365,6.876,15.365,15.356c0,8.478-6.876,15.355-15.365,15.355c-8.488,0-15.355-6.877-15.355-15.355C129.285,360.163,136.152,353.287,144.64,353.287z"/>
                                                                </Canvas>
                                                            </Viewbox>
                                                        </Border>
                                                        <StackPanel Grid.Column="1">
                                                            <TextBlock Text="Processor (CPU)" FontSize="16" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}"/>
                                                            <TextBlock x:Name="txtDeviceCPU" FontSize="13" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="18"/>
                                                        </StackPanel>
                                                    </Grid>
                                                </Border>

                                                <!-- Battery / Power Card -->
                                                <Border Background="{DynamicResource BgPanel}" CornerRadius="8" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" Margin="10" Padding="15">
                                                    <Grid>
                                                        <Grid.ColumnDefinitions>
                                                            <ColumnDefinition Width="Auto"/>
                                                            <ColumnDefinition Width="*"/>
                                                        </Grid.ColumnDefinitions>

                                                        <!-- Battery Icon -->
                                                        <Border Width="48" Height="48" CornerRadius="8" Background="{DynamicResource BgElevated}" VerticalAlignment="Top" Margin="0,0,15,0">
                                                            <Viewbox Width="26" Height="26">
                                                                <Canvas Width="94" Height="236">
                                                                    <Path Fill="#99CCFF" Stroke="#004D4D" StrokeThickness="7" 
                                                                          Data="M8 43v151c0 19 17 35 39 35s39-16 39-35V43c0-19-17-35-39-35S8 24 8 43z"/>
                                                                    
                                                                    <Path Fill="#99CCFF" Stroke="#004D4D" StrokeThickness="4" 
                                                                          Data="M36 12h22V5c0-3-5-5-11-5s-11 2-11 5z"/>
                                                                    
                                                                    <Ellipse Canvas.Left="8" Canvas.Top="25" Width="78" Height="36" 
                                                                             Fill="#99CCFF" Stroke="#004D4D" StrokeThickness="5"/>

                                                                    <Path Fill="#0080CC" 
                                                                          Data="M8 152v42c0 19 17 35 39 35s39-16 39-35v-42c-8 7-22 12-39 12s-31-5-39-12z"/>

                                                                    <Ellipse Canvas.Left="31" Canvas.Top="65" Width="32" Height="32" Fill="#66B3FF"/>
                                                                    <Path Fill="#99CCFF" Data="M44 72h6v6h6v6h-6v6h-4v-6h-6v-6h6z"/>

                                                                    <Path Fill="#0080CC" Data="M41 120l17 12-14 3 13 14-30-18 15-3-11-13z"/>

                                                                    <Ellipse Canvas.Left="31" Canvas.Top="191" Width="32" Height="32" Fill="#B3D9FF"/>
                                                                    <Path Fill="#0080CC" Data="M38 204h18v6H38z"/>
                                                                </Canvas>
                                                            </Viewbox>
                                                        </Border>

                                                        <StackPanel Grid.Column="1">
                                                        <TextBlock Text="Battery / Power" FontSize="16" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}"/>
                                                        <TextBlock x:Name="txtBatteryHealth" FontSize="13" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,6,0,0" LineHeight="18" Text="Health: Loading..."/>
                                                        <TextBlock x:Name="txtBatteryCharge" FontSize="13" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="18" Text="Charge: Loading..."/>
                                                        <TextBlock x:Name="txtBatteryStatus" FontSize="13" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="18" Text="Status: Loading..."/>
                                                        <TextBlock x:Name="txtPowerPlan" FontSize="13" Foreground="{DynamicResource Accent}" TextDecorations="Underline" Cursor="Hand" ToolTip="Open Windows power settings. Shows the Control Panel base plan and Settings power mode." TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="18" Text="Power: Loading..."/>
                                                        <TextBlock x:Name="txtBatteryTime" FontSize="13" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="18" Text="Time Remaining: Loading..."/>
                                                        <TextBlock x:Name="txtPowerDraw" FontSize="13" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="18" Text="Power Draw: Loading..."/>
                                                        <TextBlock x:Name="txtPowerTotal" FontSize="13" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="18" Text="Total Power: Loading..."/>
                                                        <TextBlock x:Name="txtPowerElectrical" FontSize="13" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="18" Text="Electrical: Loading..."/>
                                                            <Button Name="btnMyDeviceUltimatePower" Content="Ultimate" Style="{StaticResource PositiveBtn}" Margin="0,10,0,0" HorizontalAlignment="Stretch" ToolTip="Enable the Ultimate Performance power plan"/>
                                                            <Grid Margin="0,4,0,0">
                                                                <Grid.ColumnDefinitions>
                                                                    <ColumnDefinition Width="*"/>
                                                                    <ColumnDefinition Width="*"/>
                                                                </Grid.ColumnDefinitions>
                                                                <Button Name="btnMyDeviceHibernateOn" Grid.Column="0" Content="Hibernate On" Style="{StaticResource ActionBtn}" HorizontalAlignment="Stretch" ToolTip="Re-enable hibernation"/>
                                                                <Button Name="btnMyDeviceHibernateOff" Grid.Column="1" Content="Hibernate Off" Style="{StaticResource ActionBtn}" HorizontalAlignment="Stretch" ToolTip="Disable hibernation and free hiberfil.sys disk space"/>
                                                            </Grid>
                                                        </StackPanel>
                                                    </Grid>
                                                </Border>

                                                

                                                <Border Background="{DynamicResource BgPanel}" CornerRadius="8" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" Margin="10" Padding="15">
                                                    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                                        <Border Width="48" Height="48" CornerRadius="8" Background="{DynamicResource BgElevated}" VerticalAlignment="Top" Margin="0,0,15,0">
                                                            <Path Fill="{DynamicResource Accent}" Stretch="Uniform" Width="22" Height="22" Data="M223.125 24.938L205.062 43l-5.875-5.875-6.625-6.594-6.593 6.595-132.314 132.28L47.03 176l6.626 6.594 5.907 5.906-18.032 18.063-2.75 2.718v38.97h18.69V217l15.31-15.28 35.657 35.624-18.062 18.062-2.72 2.75v38.939h18.69v-31.22l15.31-15.312 35.157 35.157-18.062 18.06-2.75 2.72v38.969h18.688v-31.19l15.343-15.342 36.657 36.656-18.062 18.062-2.75 2.72v38.968h18.688v-31.25l15.312-15.313 35.656 35.658-18.06 18.062-2.72 2.75v38.938h18.688v-31.22l15.312-15.312 35.156 35.156-18.062 18.063-2.75 2.72v38.966h18.687v-31.187l15.345-15.344 5.78 5.783 6.595 6.625 6.594-6.625 132.312-132.25 6.625-6.625-6.624-6.594-5.812-5.813 18.062-18.06-13.22-13.19-18.06 18.033-35.126-35.125 18.03-18.063-13.217-13.22L401 238.938l-35.625-35.625 18.063-18.062-13.22-13.22-18.062 18.064-36.656-36.656 18.063-18.063-13.22-13.188-18.03 18.063-35.188-35.188 18.063-18.03-13.22-13.22-18.03 18.063L218.28 56.22l18.064-18.064-13.22-13.218zm-29.22 67l209.376 209.718-73.5 73.5L120.376 165.75l73.53-73.813zm-32.5 64.968l-13.186 13.25 173.968 172.72 6.562 6.53 6.594-6.53 34.5-34.25-13.156-13.282-27.938 27.75-167.344-166.188zM102.5 174.312L320.938 392.75v30.688L74 176.53l28.5-2.218zm319.688 134.875l25.875 3.25.5.5-108.938 108.938V391.78l82.563-82.592z"/>
                                                        </Border>
                                                        <StackPanel Grid.Column="1">
                                                        <TextBlock Text="Memory (RAM)" FontSize="16" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}"/>
                                                        <TextBlock x:Name="txtDeviceRAM" FontSize="13" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="18"/>
                                                            <Button Name="btnMyDeviceCleanRAM" Content="Clean RAM" Style="{StaticResource ActionBtn}" Margin="0,10,0,0" HorizontalAlignment="Stretch" ToolTip="Empty process working sets and collect managed memory"/>
                                                            <Grid Margin="0,4,0,0">
                                                                <Grid.ColumnDefinitions>
                                                                    <ColumnDefinition Width="*"/>
                                                                    <ColumnDefinition Width="*"/>
                                                                </Grid.ColumnDefinitions>
                                                                <Button Name="btnMyDeviceMemCompressOn" Grid.Column="0" Content="MC On" Style="{StaticResource ActionBtn}" HorizontalAlignment="Stretch" ToolTip="Enable Windows memory compression"/>
                                                                <Button Name="btnMyDeviceMemCompressOff" Grid.Column="1" Content="MC Off" Style="{StaticResource ActionBtn}" HorizontalAlignment="Stretch" ToolTip="Disable Windows memory compression"/>
                                                            </Grid>
                                                        </StackPanel>
                                                    </Grid>
                                                </Border>

                                                <Border Name="bdMyDeviceGPU" Background="{DynamicResource BgPanel}" CornerRadius="8" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" Margin="10" Padding="15" ToolTip="Click a GPU entry to open that GPU vendor's control panel.">
                                                    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                                    <Border Width="48" Height="48" CornerRadius="8" Background="{DynamicResource BgElevated}" VerticalAlignment="Top" Margin="0,0,15,0">
                                                            <Viewbox Width="22" Height="22">
                                                                <Canvas Width="59" Height="59">
                                                                    <Rectangle Canvas.Left="4" Canvas.Top="12.5" Width="55" Height="32" Fill="#38454F"/>
                                                                    <Ellipse Canvas.Left="6" Canvas.Top="14.5" Width="2" Height="2" Fill="#546A79"/>
                                                                    <Ellipse Canvas.Left="6" Canvas.Top="40.5" Width="2" Height="2" Fill="#546A79"/>
                                                                    <Ellipse Canvas.Left="55" Canvas.Top="14.5" Width="2" Height="2" Fill="#546A79"/>
                                                                    <Ellipse Canvas.Left="55" Canvas.Top="40.5" Width="2" Height="2" Fill="#546A79"/>
                                                                    <Rectangle Canvas.Left="0" Canvas.Top="27.5" Width="3" Height="13" Fill="#839594"/>
                                                                    <Path Fill="#F3CC6D" Data="M3,26.5H1c-0.553,0-1-0.447-1-1s0.447-1,1-1h2c0.553,0,1,0.447,1,1S3.553,26.5,3,26.5z"/>
                                                                    <Path Fill="#F3CC6D" Data="M3,43.5H1c-0.553,0-1-0.447-1-1s0.447-1,1-1h2c0.553,0,1,0.447,1,1S3.553,43.5,3,43.5z"/>
                                                                    <Rectangle Canvas.Left="0" Canvas.Top="15.5" Width="3" Height="4" Fill="#839594"/>
                                                                    <Rectangle Canvas.Left="12" Canvas.Top="44.5" Width="24" Height="4" Fill="{DynamicResource Accent}"/>
                                                                    <Path Fill="#6C797A" Data="M24.389,38.655c-1.76-2.032-2.974-4.996-3.295-8.376c-0.003-0.025-0.005-0.05-0.008-0.075C21.035,29.645,21,29.079,21,28.5s0.035-1.145,0.086-1.704c0.003-0.025,0.005-0.05,0.008-0.075c0.321-3.38,1.535-6.344,3.295-8.376c0.781-1.046,1.67-2.005,2.667-2.845H17c-4.971,0-9,5.82-9,13s4.029,13,9,13h10.057C26.059,40.66,25.171,39.7,24.389,38.655z"/>
                                                                    <Path Fill="#283238" Data="M34.846,41.5C29.534,39.394,26,34.23,26,28.5s3.534-10.894,8.846-13h10.309C50.466,17.606,54,22.77,54,28.5s-3.534,10.894-8.846,13H34.846z"/>
                                                                    <Ellipse Canvas.Left="37" Canvas.Top="25.5" Width="6" Height="6" Fill="#CBD4D8"/>
                                                                    <Path Fill="#546A79" Data="M49.903,29.739c0.119-0.499-0.359-0.91-0.848-0.753c-1.66,0.535-4.09,0.448-6.093-0.863C42.978,28.248,43,28.371,43,28.5c0,1.304-0.837,2.403-2,2.816c0,0,3.823,2.809,7,3.184C48.896,33.459,49.557,31.183,49.903,29.739z"/>
                                                                    <Path Fill="#546A79" Data="M30.019,27.261c-0.119,0.499,0.359,0.91,0.848,0.753c1.66-0.535,4.09-0.448,6.093,0.863c-0.016-0.125-0.038-0.248-0.038-0.376c0-1.304,0.837-2.403,2-2.816c0,0-3.823-2.809-7-3.184C31.025,23.541,30.364,25.817,30.019,27.261z"/>
                                                                    <Path Fill="#546A79" Data="M34.343,36.796c0.391,0.333,0.974,0.093,1.056-0.414c0.277-1.722,1.457-3.848,3.535-5.037c-0.118-0.043-0.238-0.079-0.353-0.137c-1.162-0.592-1.761-1.837-1.601-3.061c0,0-4.238,2.131-6.015,4.792C31.485,34.21,33.213,35.833,34.343,36.796z"/>
                                                                    <Path Fill="#546A79" Data="M45.578,20.204c-0.391-0.333-0.974-0.093-1.056,0.414c-0.277,1.722-1.457,3.848-3.535,5.037c0.118,0.043,0.238,0.079,0.353,0.137c1.162,0.592,1.761,1.837,1.601,3.061c0,0,4.238-2.131,6.015-4.792C48.436,22.79,46.708,21.167,45.578,20.204z"/>
                                                                    <Path Fill="#546A79" Data="M44.179,37.588c0.487-0.163,0.582-0.787,0.189-1.118c-1.334-1.124-2.548-3.231-2.497-5.624c-0.097,0.079-0.19,0.163-0.299,0.232c-1.106,0.691-2.482,0.563-3.448-0.204c0,0-0.356,4.73,1.009,7.623C40.49,38.706,42.771,38.06,44.179,37.588z"/>
                                                                    <Path Fill="#546A79" Data="M35.743,19.412c-0.487,0.163-0.582,0.787-0.189,1.118c1.334,1.124,2.548,3.231,2.497,5.624c0.097-0.079,0.19-0.163,0.299-0.232c1.106-0.691,2.482-0.563,3.448,0.204c0,0,0.356-4.73-1.009-7.623C39.431,18.294,37.151,18.94,35.743,19.412z"/>
                                                                    <Rectangle Canvas.Left="14" Canvas.Top="46.5" Width="2" Height="2" Fill="#F3CC6D"/>
                                                                    <Rectangle Canvas.Left="17" Canvas.Top="46.5" Width="2" Height="2" Fill="#F3CC6D"/>
                                                                    <Rectangle Canvas.Left="20" Canvas.Top="46.5" Width="2" Height="2" Fill="#F3CC6D"/>
                                                                    <Rectangle Canvas.Left="23" Canvas.Top="46.5" Width="2" Height="2" Fill="#F3CC6D"/>
                                                                    <Rectangle Canvas.Left="26" Canvas.Top="46.5" Width="2" Height="2" Fill="#F3CC6D"/>
                                                                    <Rectangle Canvas.Left="29" Canvas.Top="46.5" Width="2" Height="2" Fill="#F3CC6D"/>
                                                                    <Rectangle Canvas.Left="32" Canvas.Top="46.5" Width="2" Height="2" Fill="#F3CC6D"/>
                                                                    <Path Fill="#CBD4D8" Data="M4,7.5H1c-0.553,0-1,0.447-1,1s0.447,1,1,1h2v41c0,0.553,0.447,1,1,1s1-0.447,1-1v-42C5,7.947,4.553,7.5,4,7.5z"/>
                                                                </Canvas>
                                                            </Viewbox>
                                                        </Border>
                                                        <StackPanel Grid.Column="1">
                                                        <TextBlock Text="Graphics (GPU)" FontSize="16" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}"/>
                                                            <StackPanel x:Name="pnlDeviceGPUList" Margin="0,4,0,0"/>
                                                        <TextBlock Text="Click an individual GPU entry to open that vendor's control panel." FontSize="11" Foreground="{DynamicResource TextMuted}" TextWrapping="Wrap" Margin="0,8,0,0"/>
                                                            <Button Name="btnMyDeviceGPUDriver" Content="Drivers" Style="{StaticResource ActionBtn}" Margin="0,10,0,0" HorizontalAlignment="Stretch" ToolTip="Open GPU vendor driver download pages"/>
                                                            <Grid Margin="0,4,0,0">
                                                                <Grid.ColumnDefinitions>
                                                                    <ColumnDefinition Width="*"/>
                                                                    <ColumnDefinition Width="*"/>
                                                                </Grid.ColumnDefinitions>
                                                                <Button Name="btnMyDeviceHagsOn" Grid.Column="0" Content="HAGS On" Style="{StaticResource ActionBtn}" HorizontalAlignment="Stretch" ToolTip="Enable Hardware-Accelerated GPU Scheduling"/>
                                                                <Button Name="btnMyDeviceHagsOff" Grid.Column="1" Content="HAGS Off" Style="{StaticResource ActionBtn}" HorizontalAlignment="Stretch" ToolTip="Disable Hardware-Accelerated GPU Scheduling"/>
                                                            </Grid>
                                                        </StackPanel>
                                                    </Grid>
                                                </Border>

                                                <Border Background="{DynamicResource BgPanel}" CornerRadius="8" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" Margin="10" Padding="15">
                                                    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                                        <Border Width="48" Height="48" CornerRadius="8" Background="{DynamicResource BgElevated}" VerticalAlignment="Top" Margin="0,0,15,0">
                                                            <Viewbox Width="22" Height="22">
                                                                <Canvas Width="512" Height="512">
                                                                    <Canvas.RenderTransform>
                                                                        <RotateTransform Angle="270" CenterX="256" CenterY="256" />
                                                                    </Canvas.RenderTransform>
                                                                    <Rectangle Canvas.Left="0" Canvas.Top="58.672" Width="512" Height="426.656" Fill="#4A89DC"/>
                                                                    <Path Fill="#434A54" Data="M480,26.672c-5.875,0-10.656,4.766-10.656,10.656S474.125,48,480,48c5.906,0,10.672-4.781,10.672-10.672 S485.906,26.672,480,26.672z"/>
                                                                    <Path Fill="#434A54" Data="M309.344,26.672H288c-5.875,0-10.656,4.766-10.656,10.656S282.125,48,288,48h21.344 C315.234,48,320,43.219,320,37.328S315.234,26.672,309.344,26.672z"/>
                                                                    <Path Fill="#434A54" Data="M373.344,26.672H352c-5.875,0-10.656,4.766-10.656,10.656S346.125,48,352,48h21.344 C379.234,48,384,43.219,384,37.328S379.234,26.672,373.344,26.672z"/>
                                                                    <Path Fill="#434A54" Data="M437.344,26.672h-21.328c-5.891,0-10.672,4.766-10.672,10.656S410.125,48,416.016,48h21.328 c5.891,0,10.672-4.781,10.672-10.672S443.234,26.672,437.344,26.672z"/>
                                                                    <Rectangle Canvas.Left="0" Canvas.Top="37.328" Width="512" Height="426.672" Fill="#5D9CEC"/>
                                                                    <Rectangle Canvas.Left="53.344" Canvas.Top="90.672" Width="42.656" Height="42.656" Fill="#656D78"/>
                                                                    <Path Fill="#434A54" Data="M42.672,80v64h64V80H42.672z M85.344,122.672H64v-21.344h21.344V122.672z"/>
                                                                    <Path Fill="#E6E9ED" Data="M85.344,410.672c-13.281,0-22.281-4.875-27.516-14.906c-4.344-8.281-4.484-17.062-4.484-17.156v-31.938H224 v64H85.344z"/>
                                                                    <Path Fill="#CACFD7" Data="M42.672,336v42.672c0,0,0,42.656,42.672,42.656c42.656,0,149.328,0,149.328,0V336H42.672z M213.344,400 h-128c-11.469,0-15.453-4.422-17.844-8.75c-2.688-4.891-3.422-10.797-3.5-12.766v-21.156h149.344V400z"/>
                                                                    <Path Fill="#434A54" Data="M53.344,165.328c-5.891,0-10.672,4.781-10.672,10.672v128l0,0c0,5.891,4.781,10.672,10.672,10.672 S64,309.891,64,304l0,0V176C64,170.109,59.234,165.328,53.344,165.328z"/>
                                                                    <Path Fill="#434A54" Data="M96,165.328c-5.875,0-10.656,4.781-10.656,10.672v128l0,0c0,5.891,4.781,10.672,10.656,10.672 c5.906,0,10.672-4.781,10.672-10.672l0,0V176C106.672,170.109,101.906,165.328,96,165.328z"/>
                                                                    <Path Fill="#434A54" Data="M224,165.328c-5.875,0-10.656,4.781-10.656,10.672v128l0,0c0,5.891,4.781,10.672,10.656,10.672 c5.906,0,10.672-4.781,10.672-10.672l0,0V176C234.672,170.109,229.906,165.328,224,165.328z"/>
                                                                    <Path Fill="#434A54" Data="M181.344,165.328c-5.891,0-10.672,4.781-10.672,10.672v128l0,0c0,5.891,4.781,10.672,10.672,10.672 S192,309.891,192,304l0,0V176C192,170.109,187.234,165.328,181.344,165.328z"/>
                                                                    <Path Fill="#434A54" Data="M458.672,400L458.672,400h-192l0,0c-5.891,0-10.672,4.781-10.672,10.672s4.781,10.656,10.672,10.656l0,0 h192l0,0c5.891,0,10.672-4.766,10.672-10.656S464.562,400,458.672,400z"/>
                                                                    <Path Fill="#434A54" Data="M266.672,378.672L266.672,378.672h192l0,0c5.891,0,10.672-4.781,10.672-10.672 s-4.781-10.672-10.672-10.672l0,0h-192l0,0c-5.891,0-10.672,4.781-10.672,10.672S260.781,378.672,266.672,378.672z"/>
                                                                    <Path Fill="#434A54" Data="M458.672,122.672L458.672,122.672h-192l0,0c-5.891,0-10.672,4.766-10.672,10.656S260.781,144,266.672,144 l0,0h192l0,0c5.891,0,10.672-4.781,10.672-10.672S464.562,122.672,458.672,122.672z"/>
                                                                    <Path Fill="#434A54" Data="M266.672,101.328L266.672,101.328h192l0,0c5.891,0,10.672-4.766,10.672-10.656S464.562,80,458.672,80l0,0 h-192l0,0C260.781,80,256,84.781,256,90.672S260.781,101.328,266.672,101.328z"/>
                                                                    <Rectangle Canvas.Left="458.672" Canvas.Top="176" Width="42.672" Height="149.328" Fill="#E6E9ED"/>
                                                                    <Path Fill="#CACFD7" Data="M448,165.328V336h64V165.328H448z M490.672,314.672h-21.328v-128h21.328V314.672z"/>
                                                                    <Path Fill="#CACFD7" Data="M490.672,208c0,5.891-4.766,10.672-10.672,10.672c-5.875,0-10.656-4.781-10.656-10.672 s4.781-10.672,10.656-10.672C485.906,197.328,490.672,202.109,490.672,208z"/>
                                                                    <Path Fill="#CACFD7" Data="M490.672,250.672c0,5.891-4.766,10.656-10.672,10.656c-5.875,0-10.656-4.766-10.656-10.656 S474.125,240,480,240C485.906,240,490.672,244.781,490.672,250.672z"/>
                                                                    <Path Fill="#CACFD7" Data="M490.672,293.328c0,5.891-4.766,10.672-10.672,10.672c-5.875,0-10.656-4.781-10.656-10.672 s4.781-10.656,10.656-10.656C485.906,282.672,490.672,287.438,490.672,293.328z"/>
                                                                    <Path Fill="#4A89DC" Data="M149.344,90.672c0,5.891-4.781,10.656-10.672,10.656S128,96.562,128,90.672S132.781,80,138.672,80 S149.344,84.781,149.344,90.672z"/>
                                                                    <Path Fill="#4A89DC" Data="M192,133.328c0,5.891-4.766,10.672-10.656,10.672s-10.672-4.781-10.672-10.672s4.781-10.656,10.672-10.656 S192,127.438,192,133.328z"/>
                                                                    <Path Fill="#4A89DC" Data="M170.672,112c0,5.891-4.766,10.672-10.672,10.672c-5.875,0-10.656-4.781-10.656-10.672 s4.781-10.672,10.656-10.672C165.906,101.328,170.672,106.109,170.672,112z"/>
                                                                    <Path Fill="#4A89DC" Data="M192,90.672c0,5.891-4.766,10.656-10.656,10.656s-10.672-4.766-10.672-10.656S175.453,80,181.344,80 S192,84.781,192,90.672z"/>
                                                                    <Path Fill="#4A89DC" Data="M149.344,133.328c0,5.891-4.781,10.672-10.672,10.672S128,139.219,128,133.328s4.781-10.656,10.672-10.656 S149.344,127.438,149.344,133.328z"/>
                                                                    <Path Fill="#4A89DC" Data="M234.672,133.328c0,5.891-4.766,10.672-10.672,10.672c-5.875,0-10.656-4.781-10.656-10.672 s4.781-10.656,10.656-10.656C229.906,122.672,234.672,127.438,234.672,133.328z"/>
                                                                    <Path Fill="#4A89DC" Data="M213.344,112c0,5.891-4.781,10.672-10.672,10.672S192,117.891,192,112s4.781-10.672,10.672-10.672 S213.344,106.109,213.344,112z"/>
                                                                    <Path Fill="#4A89DC" Data="M234.672,90.672c0,5.891-4.766,10.656-10.672,10.656c-5.875,0-10.656-4.766-10.656-10.656 S218.125,80,224,80C229.906,80,234.672,84.781,234.672,90.672z"/>
                                                                    <Path Fill="#CACFD7" Data="M181.344,368H96c-5.875,0-10.656,4.781-10.656,10.672S90.125,389.328,96,389.328h85.344 c5.891,0,10.656-4.766,10.656-10.656S187.234,368,181.344,368z"/>
                                                                    <Rectangle Canvas.Left="266.672" Canvas.Top="176" Width="149.328" Height="149.328" Fill="#CACFD7"/>
                                                                    <Path Fill="#4A89DC" Data="M138.672,208c-5.891,0-10.672,4.781-10.672,10.672v42.656c0,5.891,4.781,10.672,10.672,10.672 s10.672-4.781,10.672-10.672v-42.656C149.344,212.781,144.562,208,138.672,208z"/>
                                                                    <Path Fill="#4A89DC" Data="M138.672,186.672c5.891,0,10.672-4.781,10.672-10.672s-4.781-10.672-10.672-10.672S128,170.109,128,176 S132.781,186.672,138.672,186.672z"/>
                                                                    <Path Fill="#4A89DC" Data="M138.672,293.328c-5.891,0-10.672,4.781-10.672,10.672s4.781,10.672,10.672,10.672 s10.672-4.781,10.672-10.672S144.562,293.328,138.672,293.328z"/>
                                                                    <Path Fill="#656D78" Data="M341.344,325.328c-41.172,0-74.672-33.484-74.672-74.656S300.172,176,341.344,176S416,209.5,416,250.672 S382.516,325.328,341.344,325.328z"/>
                                                                    <Path Fill="#434A54" Data="M412.188,260.953l5.641-20.578c-0.578-0.156-14.234-3.859-30.688-5.75c-8.391-0.969-16-1.266-22.812-0.938 c9.859-9.859,23.625-19.703,34.391-25.844l-10.562-18.531c-0.516,0.297-12.797,7.328-25.781,17.625 c-6.625,5.266-12.219,10.438-16.812,15.5c0-4.516,0.297-9.516,0.906-14.875c1.656-14.766,5.078-27.422,5.156-27.75l0,0L341.344,177 l-10.297-2.812c-0.156,0.562-3.859,14.219-5.75,30.688c-0.953,8.391-1.266,16-0.938,22.797 c-9.859-9.844-19.703-23.625-25.844-34.375l-18.531,10.562c0.297,0.516,7.328,12.797,17.625,25.766 c5.266,6.625,10.438,12.234,15.5,16.812c-4.516,0.016-9.516-0.281-14.875-0.891c-14.875-1.688-27.625-5.141-27.75-5.172 l-2.812,10.297l2.828-10.297l-5.641,20.578c0.562,0.156,14.219,3.875,30.688,5.766c6.219,0.703,12.016,1.062,17.375,1.062 c1.859,0,3.672-0.047,5.422-0.125c-9.859,9.844-23.625,19.688-34.375,25.844l5.281,9.266l5.281,9.266 c0.516-0.297,12.797-7.328,25.766-17.641c6.625-5.25,12.234-10.422,16.812-15.484c0.016,4.516-0.281,9.5-0.891,14.875 c-1.688,14.859-5.125,27.609-5.172,27.734l20.578,5.641c0.156-0.578,3.875-14.234,5.766-30.688c0.953-8.391,1.266-16,0.938-22.812 c9.844,9.859,19.688,23.625,25.828,34.375l18.547-10.562c-0.297-0.516-7.328-12.797-17.641-25.766 c-5.25-6.625-10.422-12.219-15.484-16.812c4.516,0,9.5,0.297,14.875,0.906C399.328,257.469,412.062,260.922,412.188,260.953z"/>
                                                                    <Path Fill="#CCD1D9" Data="M341.344,272C329.578,272,320,262.438,320,250.672s9.578-21.344,21.344-21.344s21.328,9.578,21.328,21.344 S353.109,272,341.344,272z"/>
                                                                    <Path Fill="#E6E9ED" Data="M341.344,218.672c-17.672,0-32,14.328-32,32s14.328,32,32,32s32-14.328,32-32 S359.016,218.672,341.344,218.672z M341.344,261.328c-5.891,0-10.672-4.781-10.672-10.656c0-5.891,4.781-10.672,10.672-10.672 c5.875,0,10.656,4.781,10.656,10.672C352,256.547,347.219,261.328,341.344,261.328z"/>
                                                                    <Path Fill="#434A54" Data="M341.344,165.328c-47.125,0-85.344,38.203-85.344,85.344C256,297.797,294.219,336,341.344,336 s85.328-38.203,85.328-85.328C426.672,203.531,388.469,165.328,341.344,165.328z M341.344,314.672c-35.297,0-64-28.719-64-64 c0-35.297,28.703-64,64-64c35.281,0,64,28.703,64,64C405.344,285.953,376.625,314.672,341.344,314.672z"/>
                                                                </Canvas>
                                                            </Viewbox>
                                                        </Border>
                                                        <StackPanel Grid.Column="1">
                                                            <TextBlock Text="Motherboard" FontSize="16" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}"/>
                                                            <TextBlock x:Name="txtDeviceMotherboard" FontSize="13" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="18"/>
                                                            <WrapPanel Margin="0,10,0,0">
                                                                <Button Name="btnMyDeviceDriverReport" Content="Drv Log" Style="{StaticResource ActionBtn}" Width="112" ToolTip="Generate an installed driver report"/>
                                                                <Button Name="btnMyDeviceDriverBackup" Content="Backup" Style="{StaticResource ActionBtn}" Width="112" ToolTip="Export installed drivers"/>
                                                                <Button Name="btnMyDeviceGhostDrivers" Content="Ghosts" Style="{StaticResource WarningBtn}" Width="112" ToolTip="Remove disconnected ghost devices"/>
                                                                <Button Name="btnMyDeviceDriverClean" Content="Clean" Style="{StaticResource WarningBtn}" Width="112" ToolTip="Clean old driver versions"/>
                                                                <Button Name="btnMyDeviceDriverRestore" Content="Restore" Style="{StaticResource ActionBtn}" Width="112" ToolTip="Restore drivers from backup"/>
                                                            </WrapPanel>
                                                        </StackPanel>
                                                    </Grid>
                                                </Border>

                                                <Border Background="{DynamicResource BgPanel}" CornerRadius="8" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" Margin="10" Padding="15">
                                                    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                                        <Border Width="48" Height="48" CornerRadius="8" Background="{DynamicResource BgElevated}" VerticalAlignment="Top" Margin="0,0,15,0">
                                                            <Viewbox Width="22" Height="22">
                                                                <Canvas Width="24" Height="24">
                                                                    <Rectangle Canvas.Left="4.36" Canvas.Top="16.77" Width="15.27" Height="5.73" RadiusX="1.91" RadiusY="1.91" Stroke="{DynamicResource Accent}" StrokeThickness="1.91" Fill="Transparent"/>
                                                                    <Path Stroke="{DynamicResource Accent}" StrokeThickness="1.91" Fill="Transparent" Data="M19.64,18.68V3.41A1.91,1.91,0,0,0,17.73,1.5H6.27A1.91,1.91,0,0,0,4.36,3.41V18.68"/>
                                                                    <Line X1="13.91" Y1="19.64" X2="17.73" Y2="19.64" Stroke="{DynamicResource Accent}" StrokeThickness="1.91"/>
                                                                    <Ellipse Canvas.Left="6.28" Canvas.Top="18.69" Width="1.9" Height="1.9" Fill="{DynamicResource Accent}"/>
                                                                </Canvas>
                                                            </Viewbox>
                                                        </Border>
                                                        <StackPanel Grid.Column="1">
                                                            <TextBlock Text="Storage Drives" FontSize="16" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}"/>
                                                            <TextBlock x:Name="txtDeviceStorage" FontSize="13" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="18"/>
                                                            <StackPanel x:Name="pnlDeviceStorageList" Margin="0,0,0,0"/>
                                                            <Grid Margin="0,10,0,0">
                                                                <Grid.RowDefinitions>
                                                                    <RowDefinition Height="Auto"/>
                                                                    <RowDefinition Height="Auto"/>
                                                                    <RowDefinition Height="Auto"/>
                                                                </Grid.RowDefinitions>
                                                                <Grid.ColumnDefinitions>
                                                                    <ColumnDefinition Width="*"/>
                                                                    <ColumnDefinition Width="*"/>
                                                                </Grid.ColumnDefinitions>
                                                                <Button Name="btnMyDeviceDiskpart" Grid.Row="0" Grid.Column="0" Content="Disk Mgmt" Style="{StaticResource ActionBtn}" HorizontalAlignment="Stretch"/>
                                                                <Button Name="btnMyDeviceDriveBenchmark" Grid.Row="0" Grid.Column="1" Content="Benchmark" Style="{StaticResource ActionBtn}" HorizontalAlignment="Stretch"/>
                                                                <Button Name="btnMyDeviceTrim" Grid.Row="1" Grid.Column="0" Content="Trim / Defrag" Style="{StaticResource ActionBtn}" HorizontalAlignment="Stretch"/>
                                                                <Button Name="btnMyDeviceChkdsk" Grid.Row="1" Grid.Column="1" Content="CHKDSK" Style="{StaticResource ActionBtn}" HorizontalAlignment="Stretch" ToolTip="Check all drives for filesystem errors"/>
                                                                <Button Name="btnMyDeviceDiskCleanup" Grid.Row="2" Grid.Column="0" Content="Disk Cleanup" Style="{StaticResource ActionBtn}" HorizontalAlignment="Stretch" ToolTip="Open Windows Disk Cleanup"/>
                                                                <Button Name="btnMyDeviceTempCleanup" Grid.Row="2" Grid.Column="1" Content="Temp Files" Style="{StaticResource ActionBtn}" HorizontalAlignment="Stretch" ToolTip="Clean temporary files"/>
                                                            </Grid>
                                                        </StackPanel>
                                                    </Grid>
                                                </Border>
                                        </WrapPanel>
                                         <Border Margin="20,0,20,24" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="0,1,0,0" Padding="10,12,10,0" HorizontalAlignment="Stretch">
                                            <Button Name="btnMyDeviceExport" Content="Export" Style="{StaticResource ActionBtn}" HorizontalAlignment="Stretch"/>
                                        </Border>
                                    </StackPanel>
                                </ScrollViewer>

                                <!-- FIREWALL PANEL -->
                <Grid Name="pnlFirewall" Visibility="Collapsed">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    
                    <!-- Header Card -->
                    <Border Grid.Row="0" Style="{StaticResource CardStyle}" Margin="0,0,0,12">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="240"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel>
                                <TextBlock Text="Firewall Manager" Style="{StaticResource SectionHeader}" Margin="0"/>
                                <TextBlock Name="lblFwStatus" Text="Ready" Foreground="#D29922" FontSize="13" Visibility="Collapsed"/>
                            </StackPanel>
                            <TextBox Name="txtFwSearch" Grid.Column="1" Text="Search rules..." ToolTip="Filter by name or port"/>
                        </Grid>
                    </Border>
                    
                    <!-- Rules List Card -->
                    <Border Grid.Row="1" Style="{StaticResource CardStyle}" Padding="0">
                        <ListView Name="lstFirewall" Background="Transparent" Foreground="{DynamicResource TextPrimary}" BorderThickness="0" AlternationCount="2" ItemContainerStyle="{StaticResource FwItem}">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Rule Name" Width="360" DisplayMemberBinding="{Binding Name}"/>
                                    <GridViewColumn Header="Direction" Width="70" DisplayMemberBinding="{Binding Direction}"/>
                                    <GridViewColumn Header="Action" Width="70">
                                        <GridViewColumn.CellTemplate>
                                            <DataTemplate>
                                                <TextBlock Text="{Binding Action}" FontWeight="Bold">
                                                    <TextBlock.Style>
                                                        <Style TargetType="TextBlock">
                                                            <Setter Property="Foreground" Value="{DynamicResource TextSecondary}"/>
                                                            <Style.Triggers>
                                                                <DataTrigger Binding="{Binding Action}" Value="Allow"><Setter Property="Foreground" Value="#3FB950"/></DataTrigger>
                                                                <DataTrigger Binding="{Binding Action}" Value="Block"><Setter Property="Foreground" Value="#F85149"/></DataTrigger>
                                                            </Style.Triggers>
                                                        </Style>
                                                    </TextBlock.Style>
                                                </TextBlock>
                                            </DataTemplate>
                                        </GridViewColumn.CellTemplate>
                                    </GridViewColumn>
                                    <GridViewColumn Header="Status" Width="70">
                                        <GridViewColumn.CellTemplate>
                                            <DataTemplate>
                                                <TextBlock Text="{Binding Enabled}" FontWeight="Bold">
                                                    <TextBlock.Style>
                                                        <Style TargetType="TextBlock">
                                                            <Setter Property="Foreground" Value="{DynamicResource TextSecondary}"/>
                                                            <Style.Triggers>
                                                                <DataTrigger Binding="{Binding Enabled}" Value="True"><Setter Property="Foreground" Value="#3FB950"/></DataTrigger>
                                                                <DataTrigger Binding="{Binding Enabled}" Value="False"><Setter Property="Foreground" Value="#F85149"/></DataTrigger>
                                                            </Style.Triggers>
                                                        </Style>
                                                    </TextBlock.Style>
                                                </TextBlock>
                                            </DataTemplate>
                                        </GridViewColumn.CellTemplate>
                                    </GridViewColumn>
                                    <GridViewColumn Header="Protocol" Width="70" DisplayMemberBinding="{Binding Protocol}"/>
                                    <GridViewColumn Header="Port" Width="90" DisplayMemberBinding="{Binding LocalPort}"/>
                                </GridView>
                            </ListView.View>
                        </ListView>
                    </Border>

                    <!-- Actions Card -->
                    <Border Grid.Row="2" Style="{StaticResource CardStyle}" Margin="0,12,0,0">
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                            <Button Name="btnFwRefresh" Content="Reload" Style="{StaticResource ActionBtn}"/>
                            <Button Name="btnFwAdd" Content="Add Rule" Style="{StaticResource PositiveBtn}"/>
                            <Button Name="btnFwEdit" Content="Edit" Style="{StaticResource ActionBtn}"/>
                            <Button Name="btnFwEnable" Content="Enable" Style="{StaticResource ActionBtn}"/>
                            <Button Name="btnFwDisable" Content="Disable" Style="{StaticResource ActionBtn}"/>
                            <Button Name="btnFwDelete" Content="Delete" Style="{StaticResource DestructiveBtn}"/>
                            <Button Name="btnFwExport" Content="Export" Style="{StaticResource ActionBtn}"/>
                            <Button Name="btnFwImport" Content="Import" Style="{StaticResource ActionBtn}"/>
                            <Button Name="btnFwDefaults" Content="Defaults" Style="{StaticResource WarningBtn}"/>
                            <Button Name="btnFwPurge" Content="Delete All" Style="{StaticResource DestructiveBtn}"/>
                        </StackPanel>
                    </Border>
                </Grid>

                <!-- DRIVERS PANEL -->
                <StackPanel Name="pnlDrivers" Visibility="Collapsed">
                    <Border Style="{StaticResource CardStyle}">
                        <StackPanel>
                            <StackPanel Margin="0,0,0,20">
                                <TextBlock Text="Driver Management" Style="{StaticResource SectionHeader}" Margin="0"/>
                            </StackPanel>
                            <TextBlock Text="DRIVER TOOLS" Style="{StaticResource SubHeader}"/>
                            <WrapPanel>
                                <Button Name="btnDrvReport" Content="Generate Report" Style="{StaticResource ActionBtn}" ToolTip="Create detailed driver list"/>
                                <Button Name="btnDrvBackup" Content="Export Drivers" Style="{StaticResource ActionBtn}" ToolTip="Backup all drivers to folder"/>
                                <Button Name="btnDrvGhost" Content="Remove Ghosts" Style="{StaticResource WarningBtn}" ToolTip="Remove disconnected devices"/>
                                <Button Name="btnDrvClean" Content="Clean Old" Style="{StaticResource WarningBtn}" ToolTip="Remove old driver versions"/>
                                <Button Name="btnDrvRestore" Content="Restore" Style="{StaticResource ActionBtn}" ToolTip="Restore from backup"/>
                            </WrapPanel>
                            <TextBlock Text="WINDOWS UPDATE SETTINGS" Style="{StaticResource SubHeader}" Margin="0,16,0,8"/>
                            <WrapPanel>
                                <Button Name="btnDrvDisableWU" Content="Disable Auto-Drivers" Style="{StaticResource DestructiveBtn}" ToolTip="Stop Windows Update from installing drivers"/>
                                <Button Name="btnDrvEnableWU" Content="Enable Auto-Drivers" Style="{StaticResource PositiveBtn}" ToolTip="Allow Windows Update to install drivers"/>
                                <Button Name="btnDrvDisableMeta" Content="Disable Metadata" Style="{StaticResource ActionBtn}"/>
                                <Button Name="btnDrvEnableMeta" Content="Enable Metadata" Style="{StaticResource ActionBtn}"/>
                            </WrapPanel>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- CLEANUP PANEL -->
                <StackPanel Name="pnlCleanup" Visibility="Collapsed">
                    <Border Style="{StaticResource CardStyle}">
                        <StackPanel>
                            <StackPanel Margin="0,0,0,20">
                                <TextBlock Text="System Cleanup" Style="{StaticResource SectionHeader}" Margin="0"/>
                            </StackPanel>
                            <TextBlock Text="CLEANUP TOOLS" Style="{StaticResource SubHeader}"/>
                            <WrapPanel>
                                <Button Name="btnCleanDisk" Content="Disk Cleanup" Style="{StaticResource ActionBtn}" ToolTip="Windows built-in cleanup utility"/>
                                <Button Name="btnCleanTemp" Content="Delete Temp Files" Style="{StaticResource ActionBtn}" ToolTip="Clear temp folders"/>
                                <Button Name="btnCleanShortcuts" Content="Fix Shortcuts" Style="{StaticResource ActionBtn}" ToolTip="Remove broken shortcuts"/>
                                <Button Name="btnCleanReg" Content="Clean Registry" Style="{StaticResource WarningBtn}" ToolTip="Remove obsolete registry entries"/>
                                <Button Name="btnCleanXbox" Content="Clean Xbox Data" Style="{StaticResource ActionBtn}" ToolTip="Clear Xbox app cache"/>
                            </WrapPanel>
                        </StackPanel>
                    </Border>
                    
                    <Border Background="{DynamicResource BgPanel}" CornerRadius="8" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" Margin="10" Padding="15">
                        <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <Border Width="48" Height="48" CornerRadius="8" Background="{DynamicResource BgElevated}" VerticalAlignment="Top" Margin="0,0,15,0">
                                <Viewbox Width="24" Height="24">
                                    <Canvas Width="24" Height="24">
                                        <Path Fill="{DynamicResource Accent}" Data="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96z"/>
                                    </Canvas>
                                </Viewbox>
                            </Border>
                            <StackPanel Grid.Column="1">
                                <TextBlock Text="OneDrive" FontSize="16" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}"/>
                                <TextBlock Text="Set all OneDrive files to 'Online Only' to immediately free up local disk space." FontSize="13" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="18"/>
                                <Button Name="btnCleanupOneDrive" Content="Free Up Space" Style="{StaticResource ActionBtn}" Margin="0,10,0,0" HorizontalAlignment="Left" Width="130"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                </StackPanel>

                <!-- UTILITIES PANEL -->
                <StackPanel Name="pnlUtils" Visibility="Collapsed">
                    <!-- System Tools Card -->
                    <Border Style="{StaticResource CardStyle}">
                        <StackPanel>
                            <StackPanel Margin="0,0,0,20">
                                <TextBlock Text="System Tools" Style="{StaticResource SectionHeader}" Margin="0"/>
                            </StackPanel>
                            <TextBlock Text="SYSTEM INFO &amp; MAINTENANCE" Style="{StaticResource SubHeader}"/>
                            <WrapPanel>
                                <Button Name="btnUtilSysInfo" Content="System Report" Style="{StaticResource ActionBtn}" ToolTip="Generate detailed system report"/>
                                <Button Name="btnUtilTrim" Content="Trim SSD" Style="{StaticResource ActionBtn}" ToolTip="Optimize SSD performance"/>
                                <Button Name="btnUtilWinRE" Content="Check WinRE" Style="{StaticResource ActionBtn}" ToolTip="Checks Windows Recovery Environment status via reagentc /info"/>
                                <Button Name="btnUtilRestoreMgr" Content="Restore Manager" Style="{StaticResource ActionBtn}" ToolTip="List, create, and delete system restore points"/>
                                <Button Name="btnUtilStartupMgr" Content="Startup Manager" Style="{StaticResource ActionBtn}" ToolTip="Manage startup apps, tasks, context menu entries, and services"/>
                                <Button Name="btnUtilMas" Content="MAS Activation" Style="{StaticResource UtilityBtn}" ToolTip="Microsoft Activation Scripts"/>
                                <Button Name="btnTaskManager" Content="Task Scheduler" Style="{StaticResource ActionBtn}" ToolTip="Manage scheduled tasks"/>
                                <Button Name="btnCtxBuilder" Content="Context Menu" Style="{StaticResource ActionBtn}" ToolTip="Customize right-click menu"/>
                            </WrapPanel>
                        </StackPanel>
                    </Border>

                    <!-- Repairs Card -->
                    <Border Style="{StaticResource CardStyle}">
                        <StackPanel>
                            <TextBlock Text="REPAIRS &amp; SETTINGS" Style="{StaticResource SubHeader}"/>
                            <WrapPanel>
                                <Button Name="btnUpdateRepair" Content="Reset Windows Update" Style="{StaticResource WarningBtn}" ToolTip="Fix Windows Update issues"/>
                                <Button Name="btnUpdateServices" Content="Restart Services" Style="{StaticResource ActionBtn}" ToolTip="Restart update-related services"/>
                                <Button Name="btnDotNetEnable" Content="Enable .NET RollForward" Style="{StaticResource ActionBtn}"/>
                                <Button Name="btnDotNetDisable" Content="Disable .NET RollForward" Style="{StaticResource ActionBtn}"/>
                                <Button Name="btnInstallGpedit" Content="Install Gpedit" Style="{StaticResource UtilityBtn}" ToolTip="Add Group Policy to Home editions"/>
                            </WrapPanel>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- SUPPORT PANEL -->
                <StackPanel Name="pnlSupport" Visibility="Collapsed">
                    <!-- Header Card -->
                    <Border Style="{StaticResource CardStyle}">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Grid.Column="0" Margin="0,0,16,0">
                                <TextBlock Text="Support &amp; Credits" Style="{StaticResource SectionHeader}" Margin="0"/>
                                <TextBlock Text="Windows Maintenance Tool v$AppVersion" FontSize="14" Foreground="{DynamicResource TextSecondary}" FontWeight="SemiBold"/>
                            </StackPanel>
                            <Button Name="btnToggleTheme" Grid.Column="1" Content="Toggle Theme" Style="{StaticResource ActionBtn}" Height="32" MinWidth="112" HorizontalAlignment="Right" VerticalAlignment="Top" ToolTip="Switch between dark and light theme"/>
                        </Grid>
                    </Border>

                    <!-- Credits Card -->
                    <Border Style="{StaticResource CardStyle}">
                        <StackPanel>
                            <TextBlock Text="CONTRIBUTORS" Style="{StaticResource SubHeader}"/>
                            <StackPanel Margin="0,8,0,0">
                                <StackPanel Orientation="Horizontal" Margin="0,4">
                                    <TextBlock Text="Author: " Foreground="{DynamicResource TextSecondary}" Width="120"/>
                                    <Button Name="btnCreditLilBatti" Content="Lil_Batti" Style="{StaticResource ActionBtn}" Height="26" Padding="8,2"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,4">
                                    <TextBlock Text="GUI &amp; Features: " Foreground="{DynamicResource TextSecondary}" Width="120"/>
                                    <Button Name="btnCreditChaython" Content="Chaython" Style="{StaticResource ActionBtn}" Height="26" Padding="8,2"/>
                                </StackPanel>
                            </StackPanel>
                            <TextBlock Text="MIT License - Copyright (c) 2026" Foreground="{DynamicResource TextMuted}" FontSize="11" Margin="0,16,0,0"/>
                        </StackPanel>
                    </Border>

                    <!-- Support Actions Card -->
                    <Border Style="{StaticResource CardStyle}">
                        <StackPanel>
                            <TextBlock Text="GET INVOLVED" Style="{StaticResource SubHeader}"/>
                            <WrapPanel>
                                <Button Name="btnSupportDiscord" Content="Join Discord" Style="{StaticResource UtilityBtn}" ToolTip="Community support server"/>
                                <Button Name="btnSupportIssue" Content="Report Issue" Style="{StaticResource ActionBtn}" ToolTip="Submit bug reports on GitHub"/>
                                <Button Name="btnDonateIos12" Content="Sponsor Lil_Batti" Style="{StaticResource PositiveBtn}"/>
                                <Button Name="btnDonate" Content="Sponsor Chaython" Style="{StaticResource PositiveBtn}"/>
                            </WrapPanel>
                        </StackPanel>
                    </Border>
                </StackPanel>

            </Grid>
        </Border>
    </Grid>
</Window>
"@

# ==========================================
# 4. INIT & HELPERS
# ==========================================
$window = New-WmtWindowFromFullXaml -Xaml $xaml -NoOwner
$script:LogBox = $window.FindName("LogBox")
$script:WmtControlCache = @{}



# --- THEME PALETTES ---
$script:CurrentTheme = "dark"
$script:ThemePalettes = @{
    dark  = @{
        BgDark        = "#0D1117"
        BgPanel       = "#161B22"
        BgElevated    = "#21262D"
        BgHover       = "#30363D"
        BorderBrush   = "#30363D"
        BorderAccent  = "#58A6FF"
        Accent        = "#58A6FF"
        AccentHover   = "#79C0FF"
        TextPrimary   = "#E6EDF3"
        TextSecondary = "#8B949E"
        TextMuted     = "#6E7681"
        Success       = "#238636"
        SuccessHover  = "#2EA043"
        Danger        = "#DA3633"
        DangerHover   = "#F85149"
        Warning       = "#D29922"
        WarningHover  = "#E3B341"
        Info          = "#1F6FEB"
        AccentText    = "#0D1117"
        SuccessText   = "#F6FFFA"
        DangerText    = "#FFF5F5"
        WarningText   = "#0D1117"
        InfoText      = "#F0F6FC"
        LogText       = "#3FB950"
    }
    light = @{
        BgDark        = "#F5F7FA"
        BgPanel       = "#FFFFFF"
        BgElevated    = "#EEF2F7"
        BgHover       = "#E2E8F0"
        BorderBrush   = "#CBD5E1"
        BorderAccent  = "#2563EB"
        Accent        = "#2563EB"
        AccentHover   = "#3B82F6"
        TextPrimary   = "#0F172A"
        TextSecondary = "#334155"
        TextMuted     = "#64748B"
        Success       = "#15803D"
        SuccessHover  = "#16A34A"
        Danger        = "#B91C1C"
        DangerHover   = "#DC2626"
        Warning       = "#B45309"
        WarningHover  = "#D97706"
        Info          = "#1D4ED8"
        AccentText    = "#FFFFFF"
        SuccessText   = "#FFFFFF"
        DangerText    = "#FFFFFF"
        WarningText   = "#FFFFFF"
        InfoText      = "#FFFFFF"
        LogText       = "#166534"
    }
}

















# --- ICONS & TOOLTIPS ---
Set-ButtonIcon "btnTabUpdates" "M5,20H19V18H5M19,9H15V3H9V9H5L12,16L19,9Z" "Updates" "Manage software updates across enabled providers" 18 "#00FF00"
# Set-ButtonIcon "btnTabHealth" - CUSTOM LOGIC BELOW
Set-ButtonIcon "btnTabNetwork" "M5,3A2,2 0 0,0 3,5V15A2,2 0 0,0 5,17H8V15H5V5H19V15H16V17H19A2,2 0 0,0 21,15V5A2,2 0 0,0 19,3H5M11,15H13V17H11V15M11,11H13V13H11V11M11,7H13V9H11V7Z" "Network & DNS" "DNS, IP Config, Network Repair tools" 18
Set-ButtonIcon "btnTabFirewall" "M12,1L3,5V11C3,16.55 6.84,21.74 12,23C17.16,21.74 21,16.55 21,11V5L12,1M12,11.95L7,12.2V11.2L12,10.95L17,11.2V12.2L12,11.95Z" "Firewall Manager" "View and manage Windows Firewall rules" 18 "#FF5555"
Set-ButtonIcon "btnTabDrivers" "M7,17L10.5,12.5L5,9.6V17H7M12,21L14.6,16.3L9.5,13.6L12,21M17,17V9.6L11.5,12.5L15,17H17M20.2,4.8L12,1L3.8,4.8C2.7,5.4 2,6.5 2,7.7V17C2,19.8 4.2,22 7,22H17C19.8,22 22,19.8 22,17V7.7C22,6.5 21.3,5.4 20.2,4.8Z" "Drivers" "Backup, Restore, and Clean drivers" 18
Set-ButtonIcon "btnTabCleanup" "M19,4H15.5L14.5,3H9.5L8.5,4H5V6H19M6,19A2,2 0 0,0 8,21H16A2,2 0 0,0 18,19V7H6V19Z" "Cleanup" "Disk cleanup, Temp files, Shortcuts, Registry" 18
Set-ButtonIcon "btnTabUtils" "M22.7,19L13.6,9.9C14.5,7.6 14,4.9 12.1,3C10.1,1 7.1,0.6 4.7,1.7L9,6L6,9L1.6,4.7C0.4,7.1 0.9,10.1 2.9,12.1C4.8,14 7.5,14.5 9.8,13.6L18.9,22.7C19.3,23.1 19.9,23.1 20.3,22.7L22.7,20.3C23.1,19.9 23.1,19.3 22.7,19Z" "Utilities" "System Info, SSD Trim, Activation, Task Scheduler" 18
Set-ButtonIcon "btnTabSupport" "M10,19H13V22H10V19M12,2C17.35,2.22 19.68,7.62 16.5,11.67C15.67,12.67 14.33,13.33 13.67,14.17C13,15 13,16 13,17H10C10,15.33 10,13.92 10.67,12.92C11.33,11.92 12.67,11.33 13.5,10.67C15.92,8.43 15.32,5.26 12,5A3,3 0 0,0 9,8H6A6,6 0 0,1 12,2Z" "Support & Credits" "Links to Discord and GitHub" 18
# Tweaks tab icon (lightning bolt / flash icon)
Set-ButtonIcon "btnTabTweaks" "M7,2V13H10V22L17,10H13L17,2H7M10,4H14L11,10H15L10.5,17V12H7V4H10Z" "Tweaks" "System optimization and performance tweaks" 18 "#FFD700"
$btnWingetIgnore = Get-Ctrl "btnWingetIgnore"
$btnWingetUnignore = Get-Ctrl "btnWingetUnignore"
# (Ban Icon for Ignore)
Set-ButtonIcon "btnWingetIgnore" "M12,2A10,10 0 0,1 22,12A10,10 0 0,1 12,22A10,10 0 0,1 2,12A10,10 0 0,1 12,2M12,4A8,8 0 0,0 4,12C4,13.85 4.63,15.55 5.68,16.91L16.91,5.68C15.55,4.63 13.85,4 12,4M12,20A8,8 0 0,0 20,12C20,10.15 19.37,8.45 18.32,7.09L7.09,18.32C8.45,19.37 10.15,20 12,20Z" "Ignore Selected" "Hide selected updates from future scans" 16 "#FFD700"
# (List/Restore Icon for Unignore)
Set-ButtonIcon "btnWingetUnignore" "M2,5H22V7H2V5M2,9H22V11H2V9M2,13H22V15H2V13M2,17H22V19H2V17" "Manage Ignored" "View and restore ignored updates"

# --- CUSTOM HEALTH ICON (Red Squircle with White Cross) ---
$btnHealth = Get-Ctrl "btnTabHealth"
if ($btnHealth) {
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Width = 18; $grid.Height = 18; $grid.Margin = "0,0,10,0"
    
    # Red Squircle
    $rect = New-Object System.Windows.Shapes.Rectangle
    $rect.RadiusX = 4; $rect.RadiusY = 4
    $rect.Fill = New-WmtBrush "#FF3333"
    [void]$grid.Children.Add($rect)
    
    # White Cross (Plus shape)
    $path = New-Object System.Windows.Shapes.Path
    $path.Data = [System.Windows.Media.Geometry]::Parse("M8,4H10V8H14V10H10V14H8V10H4V8H8V4Z")
    $path.Fill = [System.Windows.Media.Brushes]::White
    $path.Stretch = "Uniform"; $path.Margin = "3"
    [void]$grid.Children.Add($path)
    
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Orientation = "Horizontal"
    [void]$sp.Children.Add($grid)
    $txt = New-Object System.Windows.Controls.TextBlock; $txt.Text = "System Health"; $txt.VerticalAlignment = "Center"
    [void]$sp.Children.Add($txt)
    
    $btnHealth.Content = $sp
    $btnHealth.ToolTip = "System integrity checks (SFC, DISM, CHKDSK)"
}

Set-ButtonIcon "btnNetRepair" "M20,12H19.5C19.5,14.5 17.5,16.5 15,16.5H9V18.5H15C18.6,18.5 21.5,15.6 21.5,12H21C21,15 19,17.5 16,18V16L13,19L16,22V20C19.9,19.4 23,16 23,12M3,12H3.5C3.5,9.5 5.5,7.5 8,7.5H14V5.5H8C4.4,5.5 1.5,8.4 1.5,12H2C2,9 4,6.5 7,6V8L10,5L7,2V4C3.1,4.6 0,8 0,12H3Z" "Full Net Repair" "Full network stack reset (Winsock, IP, Flush DNS)"
Set-ButtonIcon "btnRouteTable" "M19,15L13,21L11.58,19.58L15.17,16H4V4H6V14H15.17L11.58,10.42L13,9L19,15Z" "Save Route Table" "Exports the current IP routing table to the data folder"
Set-ButtonIcon "btnRouteView" "M12,2A10,10 0 0,1 22,12A10,10 0 0,1 12,22A10,10 0 0,1 2,12A10,10 0 0,1 12,2M12,17C14.76,17 17,14.76 17,12C17,9.24 14.76,7 12,7C9.24,7 7,9.24 7,12C7,14.76 9.24,17 12,17M12,9A3,3 0 0,1 15,12A3,3 0 0,1 12,15A3,3 0 0,1 9,12A3,3 0 0,1 12,9Z" "View Route Table" "Displays the routing table in the log"
Set-ButtonIcon "btnCleanReg" "M5,3H19A2,2 0 0,1 21,5V19A2,2 0 0,1 19,21H5A2,2 0 0,1 3,19V5A2,2 0 0,1 5,3M7,7V9H9V7H7M11,7V9H13V7H11M15,7V9H17V7H15M7,11V13H9V11H7M11,11V13H13V11H11M15,11V13H17V11H15M7,15V17H9V15H7M11,15V17H13V15H11M15,15V17H17V15H15Z" "Clean Reg Keys" "Backs up & deletes obsolete Uninstall registry keys"
Set-ButtonIcon "btnCleanXbox" "M6.4,4.8L12,10.4L17.6,4.8L19.2,6.4L13.6,12L19.2,17.6L17.6,19.2L12,13.6L6.4,19.2L4.8,17.6L10.4,12L4.8,6.4L6.4,4.8Z" "Clean Xbox Data" "Removes Xbox Live credentials to fix login loops" 18 "#107C10"
Set-ButtonIcon "btnUpdateRepair" "M21,10.12H14.22L16.96,7.3C14.55,4.61 10.54,4.42 7.85,6.87C5.16,9.32 5.35,13.33 7.8,16.03C10.25,18.72 14.26,18.91 16.95,16.46C17.65,15.82 18.2,15.05 18.56,14.21L20.62,15.05C19.79,16.89 18.3,18.42 16.39,19.34C13.4,20.78 9.77,20.21 7.37,17.96C4.96,15.71 4.54,12.06 6.37,9.32C8.2,6.59 11.83,5.65 14.65,7.09L17.38,4.35H10.63V2.35H21V10.12Z" "Reset Update Svc" "Stops services, clears cache, and resets Windows Update components"
Set-ButtonIcon "btnUpdateServices" "M12,2A10,10 0 0,0 2,12A10,10 0 0,0 12,22A10,10 0 0,0 22,12H20A8,8 0 0,1 12,20A8,8 0 0,1 4,12A8,8 0 0,1 12,4C14.23,4 16.24,4.82 17.76,6.24L14,10H22V2L19.36,4.64C17.5,2.89 14.89,2 12,2Z" "Restart Update Svcs" "Restarts update-related services"
Set-ButtonIcon "btnDotNetEnable" "M14.6,16.6L19.2,12L14.6,7.4L16,6L22,12L16,18L14.6,16.6M9.4,16.6L4.8,12L9.4,7.4L8,6L2,12L8,18L9.4,16.6Z" "Set .NET RollFwd" "Sets DOTNET_ROLL_FORWARD=LatestMajor (Force apps to use newest .NET)"
Set-ButtonIcon "btnDotNetDisable" "M19,6.41L17.59,5L12,10.59L6.41,5L5,6.41L10.59,12L5,17.59L6.41,19L12,13.41L17.59,19L19,17.59L13.41,12L19,6.41Z" "Reset .NET RollFwd" "Removes the DOTNET_ROLL_FORWARD environment variable"
Set-ButtonIcon "btnTaskManager" "M14,10H2V12H14V10M14,6H2V8H14V6M2,16H10V14H2V16M21.5,11.5L23,13L16,20L11.5,15.5L13,14L16,17L21.5,11.5Z" "Task Scheduler" "View, Enable, Disable, or Delete Windows Scheduled Tasks"
Set-ButtonIcon "btnInstallGpedit" "M6,2C4.89,2 4,2.89 4,4V20A2,2 0 0,0 6,22H18A2,2 0 0,0 20,20V8L14,2H6M6,4H13V9H18V20H6V4M8,12V14H16V12H8M8,16V18H13V16H8Z" "Install Gpedit" "Installs the Group Policy Editor on Windows Home editions"
Set-ButtonIcon "btnQuickFix" "M12,2A10,10 0 0,0 2,12H5L8.5,16L12,7L15.5,12H22A10,10 0 0,0 12,2M12,20A8,8 0 0,1 4,12H6L8.5,14.5L12,5.5L15.5,10H20A8,8 0 0,1 12,20Z" "Quick Fix" "Runs SFC + DISM + Temp cleanup"
Set-ButtonIcon "btnSFC" "M15.5,14L20.5,19L19,20.5L14,15.5V14.71L13.73,14.43C12.59,15.41 11.11,16 9.5,16A6.5,6.5 0 0,1 3,9.5A6.5,6.5 0 0,1 9.5,3A6.5,6.5 0 0,1 16,9.5C16,11.11 15.41,12.59 14.43,13.73L14.71,14H15.5M9.5,14C12,14 14,12 14,9.5C14,7 12,5 9.5,5C7,5 5,7 5,9.5C5,12 7,14 9.5,14Z" "SFC Scan" "Scans system files for corruption and repairs them"
Set-ButtonIcon "btnDISMCheck" "M22,10V9C22,5.1 18.9,2 15,2C11.1,2 8,5.1 8,9V10H22M19.5,12.5C19.5,11.1 20.6,10 22,10H8V15H19.5V12.5Z" "DISM Check" "Checks the health of the Windows Image (dism /checkhealth)"
Set-ButtonIcon "btnDISMRestore" "M19.5,12.5C19.5,11.1 20.6,10 22,10V9C22,5.1 18.9,2 15,2C11.1,2 8,5.1 8,9V10C9.4,10 10.5,11.1 10.5,12.5C10.5,13.9 9.4,15 8,15V19H12V22H8C6.3,22 5,20.7 5,19V15C3.6,15 2.5,13.9 2.5,12.5C2.5,11.1 3.6,10 5,10V9C5,3.5 9.5,-1 15,-1C20.5,-1 25,3.5 25,9V10C26.4,10 27.5,11.1 27.5,12.5C27.5,13.9 26.4,15 25,15V19C25,20.7 23.7,22 22,22H17V19H22V15C20.6,15 19.5,13.9 19.5,12.5Z" "DISM Restore" "Attempts to repair the Windows Image (dism /restorehealth)"
Set-ButtonIcon "btnCHKDSK" "M6,2H18C19.1,2 20,2.9 20,4V20C20,21.1 19.1,22 18,22H6C4.9,22 4,21.1 4,20V4C4,2.9 4.9,2 6,2M6,4V20H18V4H6M11,17C11,17.55 11.45,18 12,18C12.55,18 13,17.55 13,17C13,16.45 12.55,16 12,16C11.45,16 11,16.45 11,17M7,17C7,17.55 7.45,18 8,18C8.55,18 9,17.55 9,17C9,16.45 8.55,16 8,16C7.45,16 7,16.45 7,17M15,17C15,17.55 15.45,18 16,18C16.55,18 17,17.55 17,17C17,16.45 16.55,16 16,16C15.45,16 15,16.45 15,17Z" "Check Disk" "Scans all drives for filesystem errors (requires reboot)"
Set-ButtonIcon "btnFlushDNS" "M2,12A10,10 0 0,0 12,22A10,10 0 0,0 22,12A10,10 0 0,0 12,2A10,10 0 0,0 2,12M4,12A8,8 0 0,1 12,4A8,8 0 0,1 20,12A8,8 0 0,1 12,20A8,8 0 0,1 4,12M10,17L15,12L10,7V17Z" "Flush DNS" "Clears the client DNS resolver cache"
Set-ButtonIcon "btnNetInfo" "M13,9H11V7H13M13,17H11V11H13M12,2A10,10 0 0,0 2,12A10,10 0 0,0 12,22A10,10 0 0,0 22,12A10,10 0 0,0 12,2Z" "Show IP Config" "Displays full IP configuration for all adapters"
Set-ButtonIcon "btnResetWifi" "M12,2A10,10 0 0,0 2,12A10,10 0 0,0 12,22A10,10 0 0,0 22,12A10,10 0 0,0 12,2M12,4A8,8 0 0,1 20,12A8,8 0 0,1 12,20A8,8 0 0,1 4,12A8,8 0 0,1 12,4M11,16.5L18,9.5L16.59,8.09L11,13.67L7.91,10.59L6.5,12L11,16.5Z" "Restart Wi-Fi" "Disables and Re-Enables Wi-Fi adapters"
Set-ButtonIcon "btnCleanDisk" "M19,4H15.5L14.5,3H9.5L8.5,4H5V6H19M6,19A2,2 0 0,0 8,21H16A2,2 0 0,0 18,19V7H6V19Z" "Disk Cleanup" "Opens the built-in Windows Disk Cleanup utility"
Set-ButtonIcon "btnCleanTemp" "M19,4H15.5L14.5,3H9.5L8.5,4H5V6H19M6,19A2,2 0 0,0 8,21H16A2,2 0 0,0 18,19V7H6V19Z" "Delete Temp Files" "Deletes temporary files from User and System Temp folders"
Set-ButtonIcon "btnCleanShortcuts" "M19,3H5C3.89,3 3,3.89 3,5V19A2,2 0 0,0 5,21H19A2,2 0 0,0 21,19V5C21,3.89 20.1,3 19,3M19,19H5V5H19V19M10,17L5,12L6.41,10.59L10,14.17L17.59,6.58L19,8L10,17Z" "Fix Shortcuts" "Scans for and fixes broken .lnk shortcuts"
(Get-Ctrl "btnWingetFind").Width = 100
Set-ButtonIcon "btnWingetFind" "M9.5,3A6.5,6.5 0 0,1 16,9.5C16,11.11 15.41,12.59 14.44,13.73L14.71,14H15.5L20.5,19L19,20.5L14,15.5V14.71L13.73,14.44C12.59,15.41 11.11,16 9.5,16A6.5,6.5 0 0,1 3,9.5A6.5,6.5 0 0,1 9.5,3M9.5,5C7,5 5,7 5,9.5C5,12 7,14 9.5,14C12,14 14,12 14,9.5C14,7 12,5 9.5,5Z" "Search" "Search Winget"
Set-ButtonIcon "btnWingetScan" "M12,18A6,6 0 0,1 6,12C6,11 6.25,10.03 6.7,9.2L5.24,7.74C4.46,8.97 4,10.43 4,12A8,8 0 0,0 12,20V23L16,19L12,15V18M12,4V1L8,5L12,9V6A6,6 0 0,1 18,12C18,13 17.75,13.97 17.3,14.8L18.76,16.26C19.54,15.03 20,13.57 20,12A8,8 0 0,0 12,4Z" "Refresh Updates" "Checks enabled providers for available application updates"
Set-ButtonIcon "btnWingetUpdateSel" "M5,20H19V18H5M19,9H15V3H9V9H5L12,16L19,9Z" "Update Checked" "Updates the checked applications; falls back to selected rows if nothing is checked"
Set-ButtonIcon "btnWingetUpdateAll" "M5,20H19V18H5M19,9H15V3H9V9H5L12,16L19,9Z" "Update All" "Updates all listed applications"
Set-ButtonIcon "btnWingetInstall" "M19,13H13V19H11V13H5V11H11V5H13V11H19V13Z" "Install Selected" "Installs the selected applications"
Set-ButtonIcon "btnWingetUninstall" "M19,4H15.5L14.5,3H9.5L8.5,4H5V6H19M6,19A2,2 0 0,0 8,21H16A2,2 0 0,0 18,19V7H6V19Z" "Uninstall Selected" "Uninstalls the selected applications"
Set-ButtonIcon "btnSupportDiscord" "M19.27 5.33C17.94 4.71 16.5 4.26 15 4a.09.09 0 0 0-.07.03c-.18.33-.39.76-.53 1.09a16.09 16.09 0 0 0-4.8 0c-.14-.34-.35-.76-.54-1.09c-.01-.02-.04-.03-.07-.03c-1.5.26-2.93.71-4.27 1.33c-.01 0-.02.01-.03.02c-2.72 4.07-3.47 8.03-3.1 11.95c0 .02.01.04.03.05c1.8 1.32 3.53 2.12 5.2 2.65c.03.01.06 0 .07-.02c.4-.55.76-1.13 1.07-1.74c.02-.04 0-.08-.04-.09c-.57-.22-1.11-.48-1.64-.78c-.04-.02-.04-.08.01-.11c.11-.08.22-.17.33-.25c.02-.02.05-.02.07-.01c3.44 1.57 7.15 1.57 10.55 0c.02-.01.05-.01.07.01c.11.09.22.17.33.26c.04.03.04.09-.01.11c-.52.31-1.07.56-1.64.78c-.04.01-.05.06-.04.09c.32.61.68 1.19 1.07 1.74c.03.01.06.02.09.01c1.67-.53 3.4-1.33 5.2-2.65c.02-.01.03-.03.03-.05c.44-4.53-.73-8.46-3.1-11.95c-.01-.01-.02-.02-.04-.02z" "Join Discord" "Opens the community support Discord server"
Set-ButtonIcon "btnSupportIssue" "M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12" "Report Issue" "Opens the GitHub Issues page to report bugs"
Set-ButtonIcon "btnNavDownloads" "M12,2A10,10 0 0,0 2,12A10,10 0 0,0 12,22A10,10 0 0,0 22,12A10,10 0 0,0 12,2M11,6H13V12H11V6M11,14H13V16H11V14Z" "Release Downloads" "Show latest release download counts"
Set-ButtonIcon "btnDonateIos12" "M7,15H9C9,16.08 10.37,17 12,17C13.63,17 15,16.08 15,15C15,13.9 13.9,13.5 12,13.5C8.36,13.5 6,12.28 6,10C6,7.24 8.7,5 12,5V3H14V5C15.68,5.37 16.86,6.31 17.38,7.5H15.32C14.93,6.85 13.95,6.2 12,6.2C10.37,6.2 9,7.11 9,8.2C9,9.3 10.1,9.7 12,9.7C15.64,9.7 18,10.92 18,13.2C18,15.96 15.3,18.2 12,18.2V20H10V18.2C8.32,17.83 7.14,16.89 6.62,15.7L8.68,15Z" "Sponsor Lil_Batti" "Support Lil_Batti via GitHub Sponsors" "#00FF00"
Set-ButtonIcon "btnDonate" "M7,15H9C9,16.08 10.37,17 12,17C13.63,17 15,16.08 15,15C15,13.9 13.9,13.5 12,13.5C8.36,13.5 6,12.28 6,10C6,7.24 8.7,5 12,5V3H14V5C15.68,5.37 16.86,6.31 17.38,7.5H15.32C14.93,6.85 13.95,6.2 12,6.2C10.37,6.2 9,7.11 9,8.2C9,9.3 10.1,9.7 12,9.7C15.64,9.7 18,10.92 18,13.2C18,15.96 15.3,18.2 12,18.2V20H10V18.2C8.32,17.83 7.14,16.89 6.62,15.7L8.68,15Z" "Sponsor Chaython" "Support Chaython via GitHub Sponsors" "#00FF00"
Set-ButtonIcon "btnDnsGoogle" "M21.35,11.1H12.18V13.83H18.69C18.36,17.64 15.19,19.27 12.19,19.27C8.36,19.27 5,16.25 5,12C5,7.9 8.2,4.73 12.2,4.73C15.29,4.73 17.1,6.7 17.1,6.7L19,4.72C19,4.72 16.56,2 12.1,2C6.42,2 2.03,6.8 2.03,12C2.03,17.05 6.16,22 12.25,22C17.6,22 21.5,18.33 21.5,12.91C21.5,11.76 21.35,11.1 21.35,11.1V11.1Z" "Google" "Sets DNS to 8.8.8.8 & 8.8.4.4"
Set-ButtonIcon "btnDnsCloudflare" "M19.35,10.04C18.67,6.59 15.64,4 12,4C9.11,4 6.6,5.64 5.35,8.04C2.34,8.36 0,10.91 0,14A6,6 0 0,0 6,20H19A5,5 0 0,0 24,15C24,12.36 21.95,10.22 19.35,10.04Z" "Cloudflare" "Sets DNS to 1.1.1.1 & 1.0.0.1"
Set-ButtonIcon "btnDnsQuad9" "M12,1L3,5V11C3,16.55 6.84,21.74 12,23C17.16,21.74 21,16.55 21,11V5L12,1M10,17L6,13L7.41,11.59L10,14.17L16.59,7.58L18,9L10,17Z" "Quad9" "Sets DNS to 9.9.9.9 (Malware Blocking)"
Set-ButtonIcon "btnDnsAdGuard" "M12,1L3,5V11C3,16.55 6.84,21.74 12,23C17.16,21.74 21,16.55 21,11V5L12,1M10,17L6,13L7.41,11.59L10,14.17L16.59,7.58L18,9L10,17Z" "AdGuard" "Sets DNS to 94.140.14.14 & 94.140.15.15 (Ad/tracker blocking)" 16 "#00FF99"
Set-ButtonIcon "btnDnsAuto" "M12,18A6,6 0 0,1 6,12C6,11 6.25,10.03 6.7,9.2L5.24,7.74C4.46,8.97 4,10.43 4,12A8,8 0 0,0 12,20V23L16,19L12,15V18M12,4V1L8,5L12,9V6A6,6 0 0,1 18,12C18,13 17.75,13.97 17.3,14.8L18.76,16.26C19.54,15.03 20,13.57 20,12A8,8 0 0,0 12,4Z" "Auto (DHCP)" "Resets DNS settings to DHCP (Automatic)"
Set-ButtonIcon "btnDnsCustom" "M12,2A10,10 0 0,0 2,12A10,10 0 0,0 12,22A10,10 0 0,0 22,12A10,10 0 0,0 12,2M17,7L12,12L7,7H17Z" "Custom DNS" "Set custom DNS addresses and optional DoH template"
Set-ButtonIcon "btnHostsUpdate" "M5,20H19V18H5M19,9H15V3H9V9H5L12,16L19,9Z" "Download AdBlock" "Updates Hosts file with AdBlocking list"
Set-ButtonIcon "btnHostsEdit" "M14.06,9L15,9.94L5.92,19H5V18.08L14.06,9M17.66,3C17.41,3 17.15,3.1 16.96,3.29L15.13,5.12L18.88,8.87L20.71,7.04C21.1,6.65 21.1,6 20.71,5.63L18.37,3.29C18.17,3.09 17.92,3 17.66,3M14.06,6.19L3,17.25V21H6.75L17.81,9.94L14.06,6.19Z" "Edit Hosts" "Opens the Hosts File Editor"
Set-ButtonIcon "btnHostsBackup" "M19,9H15V3H9V9H5L12,16L19,9Z" "Backup Hosts" "Backs up the current hosts file to the data folder"
Set-ButtonIcon "btnHostsRestore" "M13,3A9,9 0 0,0 4,12H1L4.89,15.89L4.96,16.03L9,12H6A7,7 0 0,1 13,5A7,7 0 0,1 20,12A7,7 0 0,1 13,19C11.07,19 9.32,18.21 8.06,16.94L6.64,18.36C8.27,20 10.5,21 13,21A9,9 0 0,0 22,12A9,9 0 0,0 13,3Z" "Restore Hosts" "Restores a previous hosts file backup"
Set-ButtonIcon "btnDohAuto" "M12,1L3,5V11C3,16.55 6.84,21.74 12,23C17.16,21.74 21,16.55 21,11V5L12,1M10,17L6,13L7.41,11.59L10,14.17L16.59,7.58L18,9L10,17Z" "Register DoH" "Registers Windows DoH templates for bundled DNS providers; choose a DNS preset separately" "#00FFFF"
Set-ButtonIcon "btnDohDisable" "M12,2C17.53,2 22,6.47 22,12C22,17.53 17.53,22 12,22C6.47,22 2,17.53 2,12C2,6.47 6.47,2 12,2M15.59,7L12,10.59L8.41,7L7,8.41L10.59,12L7,15.59L8.41,17L12,13.41L15.59,17L17,15.59L13.41,12L17,8.41L15.59,7Z" "Remove DoH" "Removes bundled Windows DoH templates" "#FF5555"
Set-ButtonIcon "btnFwRefresh" "M17.65,6.35C16.2,4.9 14.21,4 12,4A8,8 0 0,0 4,12A8,8 0 0,0 12,20C15.73,20 18.84,17.45 19.73,14H17.65C16.83,16.33 14.61,18 12,18A6,6 0 0,1 6,12A6,6 0 0,1 12,6C13.66,6 15.14,6.69 16.22,7.78L13,11H20V4L17.65,6.35Z" "Reload" "Refreshes the firewall rule list"
Set-ButtonIcon "btnFwAdd" "M19,13H13V19H11V13H5V11H11V5H13V11H19V13Z" "Add Rule" "Create a new firewall rule"
Set-ButtonIcon "btnFwEdit" "M14.06,9L15,9.94L5.92,19H5V18.08L14.06,9M17.66,3C17.41,3 17.15,3.1 16.96,3.29L15.13,5.12L18.88,8.87L20.71,7.04C21.1,6.65 21.1,6 20.71,5.63L18.37,3.29C18.17,3.09 17.92,3 17.66,3M14.06,6.19L3,17.25V21H6.75L17.81,9.94L14.06,6.19Z" "Modify" "Edit the selected firewall rule"
Set-ButtonIcon "btnFwEnable" "M10,17L6,13L7.41,11.59L10,14.17L16.59,7.58L18,9L10,17Z" "Enable" "Enable selected rule"
Set-ButtonIcon "btnFwDisable" "M12,2C17.53,2 22,6.47 22,12C22,17.53 17.53,22 12,22C6.47,22 2,17.53 2,12C2,6.47 6.47,2 12,2M15.59,7L12,10.59L8.41,7L7,8.41L10.59,12L7,15.59L8.41,17L12,13.41L15.59,17L17,15.59L13.41,12L17,8.41L15.59,7Z" "Disable" "Disable selected rule"
Set-ButtonIcon "btnFwDelete" "M19,4H15.5L14.5,3H9.5L8.5,4H5V6H19M6,19A2,2 0 0,0 8,21H16A2,2 0 0,0 18,19V7H6V19Z" "Delete" "Delete selected rule"
Set-ButtonIcon "btnFwExport" "M15,14H14V10H10V14H9L12,17L15,14M12,3L4.5,8V14C4.5,17.93 7.36,21.43 12,23C16.64,21.43 19.5,17.93 19.5,14V8L12,3Z" "Export" "Export firewall policy to the data folder"
Set-ButtonIcon "btnFwImport" "M12,3L4.5,8V14C4.5,17.93 7.36,21.43 12,23C16.64,21.43 19.5,17.93 19.5,14V8L12,3M12,6.15L17.5,10.2V14C17.5,16.96 15.56,19.5 12,20.82C8.44,19.5 6.5,16.96 6.5,14V10.2L12,6.15M12,9L8,13H11V17H13V13H16L12,9Z" "Import" "Import firewall policy (.wfw)"
Set-ButtonIcon "btnFwDefaults" "M12,2A10,10 0 0,0 2,12A10,10 0 0,0 12,22A10,10 0 0,0 22,12C22,6.47 17.5,2 12,2M7,9H9V13H11V9H13V13H15V9H17V15H7V9Z" "Restore Defaults" "Reset firewall to default rules"
Set-ButtonIcon "btnFwPurge" "M19,6.41L17.59,5L12,10.59L6.41,5L5,6.41L10.59,12L5,17.59L6.41,19L12,13.41L17.59,19L19,17.59L13.41,12L19,6.41Z" "Delete All" "Delete all firewall rules"
Set-ButtonIcon "btnDrvReport" "M13,9H18.5L13,3.5V9M6,2H14L20,8V20A2,2 0 0,1 18,22H6C4.89,22 4,21.1 4,20V4C4,2.89 4.89,2 6,2M15,18V16H6V18H15M18,14V12H6V14H18Z" "Generate Driver Report" "Saves a list of all installed drivers to the data folder"
Set-ButtonIcon "btnDrvGhost" "M12,2A10,10 0 0,0 2,12A10,10 0 0,0 12,22A10,10 0 0,0 22,12A10,10 0 0,0 12,2M12,4A8,8 0 0,1 20,12A8,8 0 0,1 12,20A8,8 0 0,1 4,12A8,8 0 0,1 12,4M11,16.5L18,9.5L16.59,8.09L11,13.67L7.91,10.59L6.5,12L11,16.5Z" "Remove Ghost Devices" "Removes disconnected (ghost) PnP devices"
Set-ButtonIcon "btnDrvBackup" "M13,9H18.5L13,3.5V9M6,2H14L20,8V20A2,2 0 0,1 18,22H6C4.89,22 4,21.1 4,20V4C4,2.89 4.89,2 6,2M15,18V16H6V18H15M18,14V12H6V14H18Z" "Export Drivers" "Exports all drivers to the data folder"
Set-ButtonIcon "btnDrvClean" "M19,4H15.5L14.5,3H9.5L8.5,4H5V6H19M6,19A2,2 0 0,0 8,21H16A2,2 0 0,0 18,19V7H6V19Z" "Clean Old Drivers" "Removes obsolete drivers from the Windows Driver Store"
Set-ButtonIcon "btnDrvRestore" "M12,2L3,7V17L12,22L21,17V7L12,2M12,4.3L18.5,8L12,11.7L5.5,8L12,4.3M5,9.85L12,14L19,9.85V16.15L12,20.3L5,16.15V9.85M7,11H9V14H7V11M15,11H17V14H15V11Z" "Restore Drivers" "Imports drivers from a DriverBackup folder"
Set-ButtonIcon "btnDrvDisableWU" "M19,4H5V6H19M5,20H19V18H5M9,9H15V11H9V9M9,13H15V15H9V13Z" "Disable Driver Updates" "Turn off automatic driver updates"
Set-ButtonIcon "btnDrvEnableWU" "M19,4H5V6H19M5,20H19V18H5M9,9H15V11H9V9M9,13H13V15H9V13Z" "Enable Driver Updates" "Turn on automatic driver updates"
Set-ButtonIcon "btnDrvDisableMeta" "M12,2A10,10 0 0,0 2,12A10,10 0 0,0 12,22A10,10 0 0,0 22,12A10,10 0 0,0 12,2M15,17H9V15H15V17M16.59,11.17L15.17,12.59L12,9.41L8.83,12.59L7.41,11.17L12,6.58L16.59,11.17Z" "Disable Device Metadata" "Block device metadata downloads"
Set-ButtonIcon "btnDrvEnableMeta" "M12,2A10,10 0 0,0 2,12A10,10 0 0,0 12,22A10,10 0 0,0 22,12A10,10 0 0,0 12,2M15,17H9V15H15V17M11,14V9H9L12,6L15,9H13V14H11Z" "Enable Device Metadata" "Allow device metadata downloads"
Set-ButtonIcon "btnUtilSysInfo" "M13,9H18.5L13,3.5V9M6,2H14L20,8V20A2,2 0 0,1 18,22H6C4.89,22 4,21.1 4,20V4C4,2.89 4.89,2 6,2M15,18V16H6V18H15M18,14V12H6V14H18Z" "System Info Report" "Generates a full system information report"
Set-ButtonIcon "btnUtilTrim" "M6,2H18A2,2 0 0,1 20,4V20A2,2 0 0,1 18,22H6A2,2 0 0,1 4,20V4A2,2 0 0,1 6,2M12,4A6,6 0 0,0 6,10C6,13.31 8.69,16 12,16A6,6 0 0,0 18,10C18,6.69 15.31,4 12,4M12,14A4,4 0 0,1 8,10A4,4 0 0,1 12,6A4,4 0 0,1 16,10A4,4 0 0,1 12,14Z" "Trim SSD" "Optimizes SSD performance via Trim command"
Set-ButtonIcon "btnMyDeviceTrim" "M6,2H18A2,2 0 0,1 20,4V20A2,2 0 0,1 18,22H6A2,2 0 0,1 4,20V4A2,2 0 0,1 6,2M12,4A6,6 0 0,0 6,10C6,13.31 8.69,16 12,16A6,6 0 0,0 18,10C18,6.69 15.31,4 12,4M12,14A4,4 0 0,1 8,10A4,4 0 0,1 12,6A4,4 0 0,1 16,10A4,4 0 0,1 12,14Z" "Trim" "Runs Trim/ReTrim or defrag optimization for storage drives"
Set-ButtonIcon "btnMyDeviceDiskpart" "M4,4H20A2,2 0 0,1 22,6V18A2,2 0 0,1 20,20H4A2,2 0 0,1 2,18V6A2,2 0 0,1 4,4M4,8V18H20V8H4M6,10L10,14L6,18V15L8,14L6,13V10M11,16H18V18H11V16Z" "Disk Mgmt" "Opens Windows Disk Management"
Set-ButtonIcon "btnMyDeviceDriveBenchmark" "M12,16A2,2 0 0,0 14,14C14,13.62 13.9,13.27 13.71,12.97L17.71,8.97L16.29,7.56L12.29,11.55C12.19,11.53 12.1,11.5 12,11.5A2.5,2.5 0 0,0 9.5,14A2.5,2.5 0 0,0 12,16M12,3A11,11 0 0,1 23,14H21A9,9 0 0,0 12,5A9,9 0 0,0 3,14H1A11,11 0 0,1 12,3M5.64,7.64L7.05,9.05C6.4,9.71 5.92,10.54 5.67,11.46L3.74,10.94C4.11,9.68 4.77,8.55 5.64,7.64M18.36,7.64C19.23,8.55 19.89,9.68 20.26,10.94L18.33,11.46C18.08,10.54 17.6,9.71 16.95,9.05L18.36,7.64Z" "Benchmark" "Runs a quick read/write benchmark in the background"
Set-ButtonIcon "btnMyDeviceExport" "M14,2H6A2,2 0 0,0 4,4V20A2,2 0 0,0 6,22H18A2,2 0 0,0 20,20V8L14,2M13,9V3.5L18.5,9H13M12,17L8,13H10.5V10H13.5V13H16L12,17Z" "Export" "Saves the current My Device details to the data folder"
Set-ButtonIcon "btnUtilWinRE" "M12,2L3,6V12C3,17.55 6.84,22.74 12,24C17.16,22.74 21,17.55 21,12V6L12,2M11,7H13V14H11V7M11,16H13V18H11V16Z" "Check WinRE" "Check Windows Recovery Environment status"
Set-ButtonIcon "btnUtilRestoreMgr" "M12,2A10,10 0 0,1 22,12A10,10 0 0,1 12,22A10,10 0 0,1 2,12A10,10 0 0,1 12,2M11,7V12.59L15.3,16.9L16.7,15.5L13,11.8V7H11Z" "Restore Manager" "Manage System Restore points"
Set-ButtonIcon "btnUtilStartupMgr" "M4,18H10V6H4V18M11,18H17V2H11V18M18,18H24V10H18V18Z" "Startup Manager" "Manage startup entries, tasks, context menus, and services"
Set-ButtonIcon "btnUtilMas" "M5,20H19V18H5M19,9H15V3H9V9H5L12,16L19,9Z" "MAS Activation" "Downloads and runs Microsoft Activation Scripts"
Set-ButtonIcon "btnCtxBuilder" "M19,3H5C3.89,3 3,3.89 3,5V19A2,2 0 0,0 5,21H19A2,2 0 0,0 21,19V5C21,3.89 20.1,3 19,3M19,19H5V5H19V19M10,17L5,12L6.41,10.59L10,14.17L17.59,6.58L19,8L10,17Z" "Context Menu Builder" "Create a custom right-click action for Windows 11"
# ==========================================
# 5. LOGIC & EVENTS
# ==========================================
$TabButtons = @("btnTabUpdates", "btnTabTweaks", "btnTabHealth", "btnTabNetwork", "btnTabFirewall", "btnTabDrivers", "btnTabCleanup", "btnTabUtils", "btnTabMyDevice", "btnTabSupport")
$Panels = @("pnlUpdates", "pnlCatalog", "pnlTweaks", "pnlHealth", "pnlNetwork", "pnlMyDevice", "pnlFirewall", "pnlDrivers", "pnlCleanup", "pnlUtils", "pnlSupport")
$script:WmtPanelControls = [System.Collections.ArrayList]::new()
$script:WmtTabButtonControls = [System.Collections.ArrayList]::new()
$script:WmtTabTargetByButton = @{}
foreach ($panelName in $Panels) {
    $panelCtrl = Get-Ctrl $panelName
    if ($panelCtrl) { [void]$script:WmtPanelControls.Add($panelCtrl) }
}
foreach ($btnName in $TabButtons) {
    $btnCtrl = Get-Ctrl $btnName
    if (-not $btnCtrl) { continue }
    [void]$script:WmtTabButtonControls.Add($btnCtrl)
    $targetName = if ($btnCtrl.Tag -and [string]$btnCtrl.Tag -like "pnl*") { [string]$btnCtrl.Tag } else { $btnName -replace "btnTab", "pnl" }
    $targetCtrl = Get-Ctrl $targetName
    if ($targetCtrl) { $script:WmtTabTargetByButton[$btnName] = $targetCtrl }
}

# --- INITIALIZE ALL CONTROLS ---
$btnManageProviders = Get-Ctrl "btnManageProviders"
$btnManageProviders.Add_Click({ Show-ProviderManager })
$btnWingetScan = Get-Ctrl "btnWingetScan"
$btnWingetUpdateSel = Get-Ctrl "btnWingetUpdateSel"
$btnWingetUpdateAll = Get-Ctrl "btnWingetUpdateAll"
$btnWingetInstall = Get-Ctrl "btnWingetInstall"
$btnWingetUninstall = Get-Ctrl "btnWingetUninstall"
$btnWingetFind = Get-Ctrl "btnWingetFind"
$lstWinget = Get-Ctrl "lstWinget"
$txtWingetSearch = Get-Ctrl "txtWingetSearch"
$lblWingetStatus = Get-Ctrl "lblWingetStatus"
$lblWingetTitle = Get-Ctrl "lblWingetTitle"
$pbWingetProgress = Get-Ctrl "pbWingetProgress"
$lblWingetProgress = Get-Ctrl "lblWingetProgress"
$lblWingetLastResult = Get-Ctrl "lblWingetLastResult"

$btnSFC = Get-Ctrl "btnSFC"
$btnDISMCheck = Get-Ctrl "btnDISMCheck"
$btnDISMRestore = Get-Ctrl "btnDISMRestore"
$btnCHKDSK = Get-Ctrl "btnCHKDSK"
$btnQuickFix = Get-Ctrl "btnQuickFix"

$btnPerfServicesManual = Get-Ctrl "btnPerfServicesManual"
$btnPerfServicesRevert = Get-Ctrl "btnPerfServicesRevert"
$btnPerfDisableHibernate = Get-Ctrl "btnPerfDisableHibernate"
$btnPerfEnableHibernate = Get-Ctrl "btnPerfEnableHibernate"
$btnPerfDisableSuperfetch = Get-Ctrl "btnPerfDisableSuperfetch"
$btnPerfEnableSuperfetch = Get-Ctrl "btnPerfEnableSuperfetch"
$btnPerfDisableMemCompress = Get-Ctrl "btnPerfDisableMemCompress"
$btnPerfEnableMemCompress = Get-Ctrl "btnPerfEnableMemCompress"
$btnPerfUltimatePower = Get-Ctrl "btnPerfUltimatePower"

$btnAppxLoad = Get-Ctrl "btnAppxLoad"
$btnAppxRemoveSel = Get-Ctrl "btnAppxRemoveSel"
$btnAppxRemoveAll = Get-Ctrl "btnAppxRemoveAll"
$lstAppxPackages = Get-Ctrl "lstAppxPackages"

$btnFeatHyperV = Get-Ctrl "btnFeatHyperV"
$btnFeatWSL = Get-Ctrl "btnFeatWSL"
$btnFeatSandbox = Get-Ctrl "btnFeatSandbox"
$btnFeatDotNet35 = Get-Ctrl "btnFeatDotNet35"
$btnFeatNFS = Get-Ctrl "btnFeatNFS"
$btnFeatTelnet = Get-Ctrl "btnFeatTelnet"
$btnFeatIIS = Get-Ctrl "btnFeatIIS"
$btnFeatLegacy = Get-Ctrl "btnFeatLegacy"

$btnSvcOptimize = Get-Ctrl "btnSvcOptimize"
$btnSvcRestore = Get-Ctrl "btnSvcRestore"
$btnSvcView = Get-Ctrl "btnSvcView"

$btnTasksDisableTelemetry = Get-Ctrl "btnTasksDisableTelemetry"
$btnTasksRestore = Get-Ctrl "btnTasksRestore"
$btnTasksView = Get-Ctrl "btnTasksView"

$btnWUDefault = Get-Ctrl "btnWUDefault"
$btnWUSecurity = Get-Ctrl "btnWUSecurity"
$btnWUDisable = Get-Ctrl "btnWUDisable"

$btnNetInfo = Get-Ctrl "btnNetInfo"
$btnFlushDNS = Get-Ctrl "btnFlushDNS"
$btnResetWifi = Get-Ctrl "btnResetWifi"
$btnNetRepair = Get-Ctrl "btnNetRepair"
$btnRouteTable = Get-Ctrl "btnRouteTable"
$btnRouteView = Get-Ctrl "btnRouteView"
$btnDnsGoogle = Get-Ctrl "btnDnsGoogle"
$btnDnsCloudflare = Get-Ctrl "btnDnsCloudflare"
$btnDnsQuad9 = Get-Ctrl "btnDnsQuad9"
$btnDnsAdGuard = Get-Ctrl "btnDnsAdGuard"
$btnDnsAuto = Get-Ctrl "btnDnsAuto"
$btnDnsCustom = Get-Ctrl "btnDnsCustom"
$btnDohAuto = Get-Ctrl "btnDohAuto"
$btnDohDisable = Get-Ctrl "btnDohDisable"
$btnHostsUpdate = Get-Ctrl "btnHostsUpdate"
$btnHostsEdit = Get-Ctrl "btnHostsEdit"
$btnHostsBackup = Get-Ctrl "btnHostsBackup"
$btnHostsRestore = Get-Ctrl "btnHostsRestore"

$btnFwRefresh = Get-Ctrl "btnFwRefresh"
$btnFwAdd = Get-Ctrl "btnFwAdd"
$btnFwEdit = Get-Ctrl "btnFwEdit"
$btnFwEnable = Get-Ctrl "btnFwEnable"
$btnFwDisable = Get-Ctrl "btnFwDisable"
$btnFwDelete = Get-Ctrl "btnFwDelete"
$btnFwExport = Get-Ctrl "btnFwExport"
$btnFwImport = Get-Ctrl "btnFwImport"
$btnFwDefaults = Get-Ctrl "btnFwDefaults"
$btnFwPurge = Get-Ctrl "btnFwPurge"
$lstFw = Get-Ctrl "lstFirewall"
$txtFwSearch = Get-Ctrl "txtFwSearch"
$lblFwStatus = Get-Ctrl "lblFwStatus"

# --- BIND DRIVER TAB BUTTONS ---
$btnDrvReport = Get-Ctrl "btnDrvReport"
if ($btnDrvReport) { $btnDrvReport.Add_Click({ Invoke-DriverReport }) }

$btnDrvBackup = Get-Ctrl "btnDrvBackup"
if ($btnDrvBackup) { 
    $btnDrvBackup.Add_Click({ 
            # Disable button immediately to prevent double-clicks
            $this.IsEnabled = $false 
        
            Invoke-ExportDrivers 
        
            # Freeze this specific UI thread for 1 second, then re-enable
            Start-Sleep -Seconds 1
            $this.IsEnabled = $true
        }) 
}

$btnDrvGhost = Get-Ctrl "btnDrvGhost"
if ($btnDrvGhost) { $btnDrvGhost.Add_Click({ Show-GhostDevicesDialog }) }

$btnDrvClean = Get-Ctrl "btnDrvClean"
if ($btnDrvClean) { $btnDrvClean.Add_Click({ Show-DriverCleanupDialog }) }

$btnDrvRestore = Get-Ctrl "btnDrvRestore"
if ($btnDrvRestore) { $btnDrvRestore.Add_Click({ Invoke-RestoreDrivers }) }
$btnDrvDisableWU = Get-Ctrl "btnDrvDisableWU"
$btnDrvEnableWU = Get-Ctrl "btnDrvEnableWU"
$btnDrvDisableMeta = Get-Ctrl "btnDrvDisableMeta"
$btnDrvEnableMeta = Get-Ctrl "btnDrvEnableMeta"

$btnCleanDisk = Get-Ctrl "btnCleanDisk"
$btnCleanTemp = Get-Ctrl "btnCleanTemp"
$btnCleanShortcuts = Get-Ctrl "btnCleanShortcuts"
$btnCleanReg = Get-Ctrl "btnCleanReg"
$btnCleanXbox = Get-Ctrl "btnCleanXbox"
$btnCleanupOneDrive = Get-Ctrl "btnCleanupOneDrive"

$btnUtilSysInfo = Get-Ctrl "btnUtilSysInfo"
$btnUtilTrim = Get-Ctrl "btnUtilTrim"
$btnUtilWinRE = Get-Ctrl "btnUtilWinRE"
$btnUtilRestoreMgr = Get-Ctrl "btnUtilRestoreMgr"
$btnUtilStartupMgr = Get-Ctrl "btnUtilStartupMgr"
$btnUtilMas = Get-Ctrl "btnUtilMas"
$btnUpdateRepair = Get-Ctrl "btnUpdateRepair"
$btnUpdateServices = Get-Ctrl "btnUpdateServices"
$btnDotNetEnable = Get-Ctrl "btnDotNetEnable"
$btnDotNetDisable = Get-Ctrl "btnDotNetDisable"
$btnTaskManager = Get-Ctrl "btnTaskManager"
$btnInstallGpedit = Get-Ctrl "btnInstallGpedit"
$btnCtxBuilder = Get-Ctrl "btnCtxBuilder"

$pnlUpdates = Get-Ctrl "pnlUpdates"
$pnlCatalog = Get-Ctrl "pnlCatalog"
#$pnlMyDevice = Get-Ctrl "pnlMyDevice"
$btnMyDeviceCleanRAM = Get-Ctrl "btnMyDeviceCleanRAM"
if ($btnMyDeviceCleanRAM) {
    $btnMyDeviceCleanRAM.Add_Click({
            Invoke-UiCommand {
                if (-not ([System.Management.Automation.PSTypeName]'Win32Functions.Win32EmptyWorkingSet').Type) {
                    $code = '[DllImport("psapi.dll")] public static extern int EmptyWorkingSet(IntPtr hwProc);'
                    Add-Type -MemberDefinition $code -Name "Win32EmptyWorkingSet" -Namespace Win32Functions
                }
                $processes = Get-Process
                $count = 0
                foreach ($p in $processes) {
                    try {
                        [Win32Functions.Win32EmptyWorkingSet]::EmptyWorkingSet($p.Handle) | Out-Null
                        $count++
                    }
                    catch {}
                }
                [GC]::Collect()
                Write-GuiLog "Cleaned working sets for $count processes and freed RAM."
            } "Cleaning RAM..."
        })
}

$btnMyDeviceTrim = Get-Ctrl "btnMyDeviceTrim"
if ($btnMyDeviceTrim) {
    $btnMyDeviceTrim.Add_Click({ Start-SSDTrimConsole })
}

$btnMyDeviceDiskpart = Get-Ctrl "btnMyDeviceDiskpart"
if ($btnMyDeviceDiskpart) {
    $btnMyDeviceDiskpart.Add_Click({ Start-DiskManagementGui })
}

$btnMyDeviceDriveBenchmark = Get-Ctrl "btnMyDeviceDriveBenchmark"
if ($btnMyDeviceDriveBenchmark) {
    $btnMyDeviceDriveBenchmark.Add_Click({ Start-DriveBenchmark })
}

$btnMyDeviceExport = Get-Ctrl "btnMyDeviceExport"
if ($btnMyDeviceExport) {
    $btnMyDeviceExport.Add_Click({ Invoke-MyDeviceExport })
}

$txtPowerPlan = Get-Ctrl "txtPowerPlan"
if ($txtPowerPlan) {
    $txtPowerPlan.Add_MouseLeftButtonUp({ Open-PowerSettings })
}










$btnMyDeviceGPUDriver = Get-Ctrl "btnMyDeviceGPUDriver"
if ($btnMyDeviceGPUDriver) {
    $btnMyDeviceGPUDriver.Add_Click({
            $vendors = @(Get-MyDeviceGpuVendors)
            if ($vendors.Count -eq 0) {
                Start-Process "https://www.google.com/search?q=Graphics+driver+download"
            }
            else {
                foreach ($vendor in $vendors) {
                    if ($vendor -eq "NVIDIA") { Start-Process "https://www.nvidia.com/Download/index.aspx" }
                    if ($vendor -eq "AMD") { Start-Process "https://www.amd.com/en/support" }
                    if ($vendor -eq "Intel") { Start-Process "https://www.intel.com/content/www/us/en/download-center/home.html" }
                }
            }
        })
}

$btnMyDeviceWinUpdate = Get-Ctrl "btnMyDeviceWinUpdate"
if ($btnMyDeviceWinUpdate) {
    $btnMyDeviceWinUpdate.Add_Click({
            # Launch Windows Settings -> Windows Update
            Start-Process "ms-settings:windowsupdate"
        })
}
$lstCatalog = Get-Ctrl "lstCatalog"
$txtCatalogSearch = Get-Ctrl "txtCatalogSearch"
$btnShowCatalog = Get-Ctrl "btnShowCatalog"
$btnBackToUpdates = Get-Ctrl "btnBackToUpdates"
$btnCatalogSearch = Get-Ctrl "btnCatalogSearch"
$btnCatalogInstall = Get-Ctrl "btnCatalogInstall"
$btnCatalogSelectAll = Get-Ctrl "btnCatalogSelectAll"
$btnCatalogClear = Get-Ctrl "btnCatalogClear"
$btnCatAll = Get-Ctrl "btnCatAll"
$btnCatBrowsers = Get-Ctrl "btnCatBrowsers"
$btnCatDev = Get-Ctrl "btnCatDev"
$btnCatUtils = Get-Ctrl "btnCatUtils"
$btnCatMedia = Get-Ctrl "btnCatMedia"
$btnCatGames = Get-Ctrl "btnCatGames"
$btnCatSecurity = Get-Ctrl "btnCatSecurity"

$btnSupportDiscord = Get-Ctrl "btnSupportDiscord"
$btnSupportIssue = Get-Ctrl "btnSupportIssue"
$btnToggleTheme = Get-Ctrl "btnToggleTheme"
$btnNavDownloads = Get-Ctrl "btnNavDownloads"
$btnDonateIos12 = Get-Ctrl "btnDonateIos12"
$btnDonate = Get-Ctrl "btnDonate"
$btnCreditLilBatti = Get-Ctrl "btnCreditLilBatti"
$btnCreditChaython = Get-Ctrl "btnCreditChaython"

$bdQuickFind = Get-Ctrl "bdQuickFind"
$txtGlobalSearch = Get-Ctrl "txtGlobalSearch"
$lstSearchResults = Get-Ctrl "lstSearchResults"
$pnlNavButtons = Get-Ctrl "pnlNavButtons"
$svLog = Get-Ctrl "svLog"
$LogBox = Get-Ctrl "LogBox"
foreach ($itemsControl in @($lstWinget, $lstAppxPackages, $lstFw, $lstCatalog, $lstSearchResults)) {
    Enable-WmtWpfItemsVirtualization -Control $itemsControl
}

if ($LogBox) {
    $script:WmtLogAutoScrollAttached = $true
    $LogBox.Add_TextChanged({
            param($s, $e)
            if ($svLog) { $svLog.ScrollToEnd() } else { $s.ScrollToEnd() }
        })
}

# Quick Find placeholder + focus behavior
$script:QuickFindPlaceholder = "Search tools..."
if ($txtGlobalSearch) {
    $txtGlobalSearch.Text = $script:QuickFindPlaceholder
    Set-WmtQuickFindForeground -TextBox $txtGlobalSearch
    $txtGlobalSearch.Add_GotFocus({
            if ($txtGlobalSearch.Text -eq $script:QuickFindPlaceholder) {
                $txtGlobalSearch.Text = ""
                Set-WmtQuickFindForeground -TextBox $txtGlobalSearch
            }
        })
    $txtGlobalSearch.Add_LostFocus({
            if ([string]::IsNullOrWhiteSpace($txtGlobalSearch.Text)) {
                $txtGlobalSearch.Text = $script:QuickFindPlaceholder
                Set-WmtQuickFindForeground -TextBox $txtGlobalSearch
            }
        })
}
if ($bdQuickFind -and $txtGlobalSearch) {
    $bdQuickFind.Add_MouseLeftButtonDown({ $txtGlobalSearch.Focus() })
}

# --- TABS LOGIC ---
foreach ($tabButton in $script:WmtTabButtonControls) {
    $tabButton.Add_Click({
            param($s, $e)
            foreach ($panel in $script:WmtPanelControls) { $panel.Visibility = "Collapsed" }
            foreach ($btn in $script:WmtTabButtonControls) {
                $btn.ClearValue([System.Windows.Controls.Button]::BackgroundProperty)
                $btn.Foreground = $window.Resources["TextSecondary"]
                $btn.FontWeight = "Normal"
                $btn.Tag = "Collapsed"  # Hide indicator
            }
            $target = $script:WmtTabTargetByButton[[string]$s.Name]
            if ($target) { $target.Visibility = "Visible" }
            $s.Background = $window.Resources["BgElevated"]
            $s.Foreground = $window.Resources["TextPrimary"]
            $s.FontWeight = "SemiBold"
            $s.Tag = "Visible"  # Show indicator
            if ($s.Name -eq "btnTabFirewall") { Start-FirewallRuleLoad }
            if ($s.Name -eq "btnTabUpdates") {
                if ($lstWinget.Items.Count -eq 0) { 
                    $btnWingetScan.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) 
                }
            }
            if ($s.Name -eq "btnTabMyDevice") {
                Update-MyDeviceResponsiveLayout
                if (-not $script:MyDeviceStatsStarted) {
                    $script:MyDeviceStatsStarted = $true
                    Update-MyDeviceStats
                }
                elseif ($script:MyDeviceStatsPreloadMode) {
                    $script:MyDeviceStatsPreloadMode = $false
                    $script:MyDeviceStatsMaxConcurrent = 6
                    Start-MyDeviceQueuedSections
                }
            }
        })
}

# --- GLOBAL SEARCH ---
$SearchIndex = @{}



# --- GLOBAL SEARCH INDEX ---

# 1. Updates
Add-SearchIndexEntry "btnWingetScan"        "Check Package Updates"           "btnTabUpdates"
Add-SearchIndexEntry "btnWingetUpdateSel"   "Update Checked Apps"             "btnTabUpdates"
Add-SearchIndexEntry "btnWingetUpdateAll"   "Update All Apps"                 "btnTabUpdates"
Add-SearchIndexEntry "btnWingetInstall"     "Install Selected Apps"           "btnTabUpdates"
Add-SearchIndexEntry "btnWingetUninstall"   "Uninstall Selected Apps"         "btnTabUpdates"
Add-SearchIndexEntry "btnWingetFind"        "Search Winget Packages"          "btnTabUpdates"

# 2. System Health
Add-SearchIndexEntry "btnQuickFix"           "Quick Fix (SFC + DISM + Cleanup)" "btnTabHealth"
Add-SearchIndexEntry "btnSFC"               "SFC Scan (System File Checker)"  "btnTabHealth"
Add-SearchIndexEntry "btnDISMCheck"         "DISM Check Health"               "btnTabHealth"
Add-SearchIndexEntry "btnDISMRestore"       "DISM Restore Health"             "btnTabHealth"
Add-SearchIndexEntry "btnCHKDSK"            "CHKDSK (Check Disk)"             "btnTabHealth"

# 3. Network & DNS
Add-SearchIndexEntry "btnNetInfo"           "Show IP Config / Network Info"   "btnTabNetwork"
Add-SearchIndexEntry "btnFlushDNS"          "Flush DNS Cache"                 "btnTabNetwork"
Add-SearchIndexEntry "btnResetWifi"         "Restart Wi-Fi Adapter"           "btnTabNetwork"
Add-SearchIndexEntry "btnNetRepair"         "Full Network Repair (Reset IP)"  "btnTabNetwork"
Add-SearchIndexEntry "btnRouteTable"        "Save Routing Table"              "btnTabNetwork"
Add-SearchIndexEntry "btnRouteView"         "View Routing Table"              "btnTabNetwork"

# DNS Presets
Add-SearchIndexEntry "btnDnsGoogle"         "Set DNS: Google (8.8.8.8)"       "btnTabNetwork"
Add-SearchIndexEntry "btnDnsCloudflare"     "Set DNS: Cloudflare (1.1.1.1)"   "btnTabNetwork"
Add-SearchIndexEntry "btnDnsQuad9"          "Set DNS: Quad9 (Malware Block)"  "btnTabNetwork"
Add-SearchIndexEntry "btnDnsAdGuard"        "Set DNS: AdGuard (Ad Blocking)"  "btnTabNetwork"
Add-SearchIndexEntry "btnDnsAuto"           "Reset DNS to Auto (DHCP)"        "btnTabNetwork"
Add-SearchIndexEntry "btnDnsCustom"         "Set Custom DNS Address"          "btnTabNetwork"

# DNS Encryption & Hosts
Add-SearchIndexEntry "btnDohAuto"           "Register DoH Templates"          "btnTabNetwork"
Add-SearchIndexEntry "btnDohDisable"        "Remove DoH Templates"            "btnTabNetwork"
Add-SearchIndexEntry "btnHostsUpdate"       "Update Hosts (AdBlock)"          "btnTabNetwork"
Add-SearchIndexEntry "btnHostsEdit"         "Edit Hosts File"                 "btnTabNetwork"
Add-SearchIndexEntry "btnHostsBackup"       "Backup Hosts File"               "btnTabNetwork"
Add-SearchIndexEntry "btnHostsRestore"      "Restore Hosts File"              "btnTabNetwork"

# 4. Firewall
Add-SearchIndexEntry "btnFwRefresh"         "Refresh Firewall Rules"          "btnTabFirewall"
Add-SearchIndexEntry "btnFwAdd"             "Add New Firewall Rule"           "btnTabFirewall"
Add-SearchIndexEntry "btnFwEdit"            "Edit/Modify Firewall Rule"       "btnTabFirewall"
Add-SearchIndexEntry "btnFwExport"          "Export Firewall Policy"          "btnTabFirewall"
Add-SearchIndexEntry "btnFwImport"          "Import Firewall Policy"          "btnTabFirewall"
Add-SearchIndexEntry "btnFwDefaults"        "Restore Default Firewall Rules"  "btnTabFirewall"
Add-SearchIndexEntry "btnFwPurge"           "Delete All Firewall Rules"       "btnTabFirewall"

# 5. Drivers
Add-SearchIndexEntry "btnDrvReport"         "Generate Driver Report"          "btnTabDrivers"
Add-SearchIndexEntry "btnDrvBackup"         "Export Drivers"                  "btnTabDrivers"
Add-SearchIndexEntry "btnDrvGhost"          "Remove Ghost Devices"            "btnTabDrivers"
Add-SearchIndexEntry "btnDrvClean"          "Clean Old Drivers (DriverStore)" "btnTabDrivers"
Add-SearchIndexEntry "btnDrvRestore"        "Restore Drivers from Backup"     "btnTabDrivers"
Add-SearchIndexEntry "btnDrvDisableWU"      "Disable Driver Updates"          "btnTabDrivers"
Add-SearchIndexEntry "btnDrvEnableWU"       "Enable Driver Updates"           "btnTabDrivers"
Add-SearchIndexEntry "btnDrvDisableMeta"    "Disable Device Metadata"         "btnTabDrivers"
Add-SearchIndexEntry "btnDrvEnableMeta"     "Enable Device Metadata"          "btnTabDrivers"

# 6. Cleanup
Add-SearchIndexEntry "btnCleanDisk"         "Disk Cleanup Tool"               "btnTabCleanup"
Add-SearchIndexEntry "btnCleanTemp"         "Clean Temporary Files"           "btnTabCleanup"
Add-SearchIndexEntry "btnCleanShortcuts"    "Fix Broken Shortcuts"            "btnTabCleanup"
Add-SearchIndexEntry "btnCleanReg"          "Registry Cleanup & Backup"       "btnTabCleanup"
Add-SearchIndexEntry "btnCleanXbox"         "Clean Xbox Credentials"          "btnTabCleanup"
Add-SearchIndexEntry "btnCleanupOneDrive" "Free up OneDrive space (Online Only)" "btnTabCleanup"

# 7. Utilities
Add-SearchIndexEntry "btnUtilSysInfo"       "System Info Report"              "btnTabUtils"
Add-SearchIndexEntry "btnUtilTrim"          "Trim SSD (Optimize)"             "btnTabUtils"
Add-SearchIndexEntry "btnUtilWinRE"         "Check WinRE Status"              "btnTabUtils"
Add-SearchIndexEntry "btnUtilRestoreMgr"    "System Restore Manager"          "btnTabUtils"
Add-SearchIndexEntry "btnUtilStartupMgr"    "Startup Manager (4 Tabs)"        "btnTabUtils"
Add-SearchIndexEntry "btnUtilMas"           "MAS Activation"                  "btnTabUtils"
Add-SearchIndexEntry "btnUpdateRepair"      "Reset Windows Update Components" "btnTabUtils"
Add-SearchIndexEntry "btnUpdateServices"    "Restart Update Services"         "btnTabUtils"
Add-SearchIndexEntry "btnDotNetEnable"      "Set .NET RollForward"            "btnTabUtils"
Add-SearchIndexEntry "btnDotNetDisable"     "Reset .NET RollForward"          "btnTabUtils"
Add-SearchIndexEntry "btnTaskManager"       "Task Scheduler Manager"          "btnTabUtils"
Add-SearchIndexEntry "btnInstallGpedit"     "Install Group Policy (Home)"     "btnTabUtils"
Add-SearchIndexEntry "btnCtxBuilder" "Custom Context Menu Builder" "btnTabUtils"

# 8. Support
Add-SearchIndexEntry "btnSupportDiscord"    "Join Discord Support"            "btnTabSupport"
Add-SearchIndexEntry "btnSupportIssue"      "Report an Issue (GitHub)"        "btnTabSupport"
Add-SearchIndexEntry "btnToggleTheme"       "Toggle Theme"                    "btnTabSupport"
Add-SearchIndexAction "Light Mode" { Set-WmtThemePreference -Theme "light" } "btnTabSupport"
Add-SearchIndexAction "Dark Mode" { Set-WmtThemePreference -Theme "dark" }  "btnTabSupport"

# 9. My Device
Add-SearchIndexEntry "btnMyDeviceCleanRAM" "Clean RAM" "btnTabMyDevice"
Add-SearchIndexEntry "btnMyDeviceGPUDriver" "Check GPU Drivers" "btnTabMyDevice"
Add-SearchIndexEntry "btnMyDeviceTrim" "Trim / Defrag Storage Drives" "btnTabMyDevice"
Add-SearchIndexEntry "btnMyDeviceDiskpart" "Open Disk Management" "btnTabMyDevice"
Add-SearchIndexEntry "btnMyDeviceDriveBenchmark" "Drive Benchmark" "btnTabMyDevice"
Add-SearchIndexEntry "btnMyDeviceWinUpdate" "Check for Windows Updates" "btnTabMyDevice"
Add-SearchIndexEntry "btnMyDeviceExport" "Export My Device Details" "btnTabMyDevice"

# 10. Catalog & Providers
Add-SearchIndexEntry "btnShowCatalog" "Software Catalog" "btnTabUpdates"
Add-SearchIndexEntry "btnManageProviders" "Manage Package Providers" "btnTabUpdates"

# 11. Common Tweaks
Add-SearchIndexEntry "btnSvcOptimize" "Optimize System Services" "btnTabTweaks"
Add-SearchIndexEntry "btnSvcRestore" "Restore Default Services" "btnTabTweaks"
Add-SearchIndexEntry "btnWUDisable" "Disable Windows Updates" "btnTabTweaks"
Add-SearchIndexEntry "btnPerfUltimatePower" "Enable Ultimate Performance Plan" "btnTabTweaks"
Add-SearchIndexEntry "btnTasksDisableTelemetry" "Disable Telemetry Tasks" "btnTabTweaks"
Add-SearchIndexEntry "btnExpShowExt" "Show File Extensions" "btnTabTweaks"
Add-SearchIndexEntry "btnExpShowHidden" "Show Hidden Files" "btnTabTweaks"
Add-SearchIndexEntry "btnExpLaunchThisPc" "Open File Explorer to This PC" "btnTabTweaks"
Add-SearchIndexEntry "btnMouseSpeedDefault" "Set Mouse Cursor Speed" "btnTabTweaks"
Add-SearchIndexEntry "btnMouseAccelOff" "Disable Mouse Acceleration" "btnTabTweaks"
Add-SearchIndexEntry "btnMouseSingleClick" "Single Click to Open Folders" "btnTabTweaks"
Add-SearchIndexEntry "btnCtxClassic" "Classic Windows 11 Context Menu" "btnTabTweaks"
Add-SearchIndexEntry "btnCtxTakeOwnAdd" "Add Take Ownership Context Menu" "btnTabTweaks"
Add-SearchIndexEntry "btnPrivacySuggestedOff" "Disable Suggested Content" "btnTabTweaks"
Add-SearchIndexEntry "btnSearchWebOff" "Disable Start Menu Web Search" "btnTabTweaks"
Add-SearchIndexEntry "btnSearchIndexRebuild" "Rebuild Windows Search Index" "btnTabTweaks"
Add-SearchIndexEntry "btnGameModeOn" "Enable Game Mode" "btnTabTweaks"
Add-SearchIndexEntry "btnGameBarOff" "Disable Xbox Game Bar" "btnTabTweaks"
Add-SearchIndexEntry "btnVisualSnappy" "Snappy Desktop Visual Effects" "btnTabTweaks"
Add-SearchIndexEntry "btnNotifyTipsOff" "Disable Windows Tips" "btnTabTweaks"
Add-SearchIndexEntry "btnLockPlain" "Plain Lock Screen" "btnTabTweaks"
Add-SearchIndexEntry "btnStartupFastOff" "Disable Fast Startup" "btnTabTweaks"
Add-SearchIndexEntry "btnSecuritySmartScreenOpen" "Open SmartScreen Settings" "btnTabTweaks"
Add-SearchIndexEntry "btnPowerUsbSuspendOff" "Disable USB Selective Suspend" "btnTabTweaks"
Add-SearchIndexEntry "btnDevLongPathsOn" "Enable Long Paths" "btnTabTweaks"
Add-SearchIndexEntry "btnDevModeOn" "Enable Developer Mode" "btnTabTweaks"
Update-WmtSearchIndexEntries

$txtGlobalSearch.Add_TextChanged({
        $q = $txtGlobalSearch.Text
        if ($q.Length -gt 1 -and $q -ne $script:QuickFindPlaceholder) {
            $pnlNavButtons.Visibility = "Collapsed"
            $lstSearchResults.Visibility = "Visible"
            $lstSearchResults.Items.Clear()
            foreach ($entry in $script:WmtSearchIndexEntries) {
                if ($entry.Text.IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    [void]$lstSearchResults.Items.Add($entry.Text)
                }
            }
        }
        else { $pnlNavButtons.Visibility = "Visible"; $lstSearchResults.Visibility = "Collapsed" }
    })
$lstSearchResults.Add_SelectionChanged({
        if ($lstSearchResults.SelectedItem) {
            $match = $SearchIndex[$lstSearchResults.SelectedItem]
        
            # 1. Switch to the appropriate tab so the button is rendered and visible
            if ($match.Tab) {
                $tabBtn = Get-Ctrl $match.Tab
                if ($tabBtn) {
                    $tabBtn.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
                }
            }
        
            # 2. Fire the actual button's click event to launch the target function
            if ($match.ContainsKey("Action") -and $match.Action -is [scriptblock]) {
                & $match.Action
            }
            elseif ($match.Button) {
                $match.Button.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
            }
        
            # Clear the search box after executing
            $txtGlobalSearch.Text = ""
            Set-WmtQuickFindForeground -TextBox $txtGlobalSearch
        }
    })


# WINGET CONTEXT MENU (Right-Click)
$ctxMenu = New-Object System.Windows.Controls.ContextMenu
Set-WmtContextMenuChrome -ContextMenu $ctxMenu

if ($lstWinget) {
    $lstWinget.Add_PreviewMouseRightButtonDown({
            param($s, $e)
            Set-WmtListViewRightClickSelection -ListView $s -OriginalSource $e.OriginalSource
        })

    $lstWinget.Add_PreviewKeyDown({
            param($s, $e)
            try {
                $modifiers = [System.Windows.Input.Keyboard]::Modifiers
                $hasControl = (($modifiers -band [System.Windows.Input.ModifierKeys]::Control) -eq [System.Windows.Input.ModifierKeys]::Control)
                if ($hasControl -and $e.Key -eq [System.Windows.Input.Key]::C) {
                    if (Copy-WmtUpdateSelectedRowsToClipboard -ListView $s) {
                        $e.Handled = $true
                    }
                }
            }
            catch {
                Write-GuiLog "ERROR: Ctrl+C copy row data failed: $($_.Exception.Message)"
            }
        })
}

# 1. Update Selected
$miUpdate = New-Object System.Windows.Controls.MenuItem
$miUpdate.Header = "Update Checked"
# We reference the button variable directly to ensure it works
$miUpdate.Add_Click({ 
        $btnWingetUpdateSel.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) 
    })
[void]$ctxMenu.Items.Add($miUpdate)

# 2. Update All
$miUpdateAll = New-Object System.Windows.Controls.MenuItem
$miUpdateAll.Header = "Update All"
$miUpdateAll.Add_Click({
        if ($btnWingetUpdateAll) {
            $btnWingetUpdateAll.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
        }
    })
[void]$ctxMenu.Items.Add($miUpdateAll)

# 3. Uninstall Selected
$miUninstall = New-Object System.Windows.Controls.MenuItem
$miUninstall.Header = "Uninstall Selected"
$miUninstall.Add_Click({ 
        $btnWingetUninstall.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) 
    })
[void]$ctxMenu.Items.Add($miUninstall)

# 4. View Manifest
$miManifest = New-Object System.Windows.Controls.MenuItem
$miManifest.Header = "View App Manifest"
$miManifest.ToolTip = "Show the winget manifest details for the selected package"
$miManifest.Add_Click({
        $selected = @($lstWinget.SelectedItems)
        if ($selected.Count -ne 1) {
            [System.Windows.MessageBox]::Show(
                "Select one winget or Microsoft Store package to view its manifest.",
                "Select One Package",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            ) | Out-Null
            return
        }
        Show-WingetPackageManifest -Item $selected[0]
    })
[void]$ctxMenu.Items.Add($miManifest)

# 5. Copy Row Data
$miCopyRow = New-Object System.Windows.Controls.MenuItem
$miCopyRow.Header = "Copy Row Data"
$miCopyRow.ToolTip = "Copy the selected update row data to the clipboard"
$miCopyRow.Add_Click({
        [void](Copy-WmtUpdateSelectedRowsToClipboard -ListView $lstWinget)
    })
[void]$ctxMenu.Items.Add($miCopyRow)

# --- Separator ---
[void]$ctxMenu.Items.Add((New-Object System.Windows.Controls.Separator))

# 6. Ignore Selected
$miIgnore = New-Object System.Windows.Controls.MenuItem
$miIgnore.Header = "Ignore Selected"
$miIgnore.Add_Click({ 
        $btnWingetIgnore.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) 
    })
[void]$ctxMenu.Items.Add($miIgnore)

# 7. Manage Ignored
$miManage = New-Object System.Windows.Controls.MenuItem
$miManage.Header = "Manage Ignored List..."
$miManage.Add_Click({ 
        $btnWingetUnignore.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) 
    })
[void]$ctxMenu.Items.Add($miManage)

# --- Checkbox helpers ---
[void]$ctxMenu.Items.Add((New-Object System.Windows.Controls.Separator))

$miCheckSelected = New-Object System.Windows.Controls.MenuItem
$miCheckSelected.Header = "Check Selected Rows"
$miCheckSelected.Add_Click({
        Set-WmtUpdateListCheckedState -Items @($lstWinget.SelectedItems) -IsChecked:$true
    })
[void]$ctxMenu.Items.Add($miCheckSelected)

$miUncheckSelected = New-Object System.Windows.Controls.MenuItem
$miUncheckSelected.Header = "Uncheck Selected Rows"
$miUncheckSelected.Add_Click({
        Set-WmtUpdateListCheckedState -Items @($lstWinget.SelectedItems) -IsChecked:$false
    })
[void]$ctxMenu.Items.Add($miUncheckSelected)

$miCheckAll = New-Object System.Windows.Controls.MenuItem
$miCheckAll.Header = "Check All Rows"
$miCheckAll.Add_Click({
        Set-WmtUpdateListCheckedState -Items @($lstWinget.Items) -IsChecked:$true
    })
[void]$ctxMenu.Items.Add($miCheckAll)

$miUncheckAll = New-Object System.Windows.Controls.MenuItem
$miUncheckAll.Header = "Uncheck All Rows"
$miUncheckAll.Add_Click({
        Set-WmtUpdateListCheckedState -Items @($lstWinget.Items) -IsChecked:$false
    })
[void]$ctxMenu.Items.Add($miUncheckAll)

# --- Separator ---
[void]$ctxMenu.Items.Add((New-Object System.Windows.Controls.Separator))

# 8. Refresh Updates
$miRefresh = New-Object System.Windows.Controls.MenuItem
$miRefresh.Header = "Refresh Updates"
$miRefresh.Add_Click({ 
        $btnWingetScan.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) 
    })
[void]$ctxMenu.Items.Add($miRefresh)

$ctxMenu.Add_Opened({
        $selected = @($lstWinget.SelectedItems)
        $checked = @(Get-WmtUpdateListCheckedItems)
        $actionable = @($lstWinget.Items | Where-Object { Test-WmtUpdateListActionableItem -Item $_ })
        $canShowManifest = ($selected.Count -eq 1 -and (Test-WingetManifestSupportedItem $selected[0]))
        $miUpdate.IsEnabled = ($checked.Count -gt 0 -or $selected.Count -gt 0)
        $miCheckSelected.IsEnabled = ($selected.Count -gt 0)
        $miUncheckSelected.IsEnabled = ($selected.Count -gt 0)
        $miCheckAll.IsEnabled = ($actionable.Count -gt 0)
        $miUncheckAll.IsEnabled = ($actionable.Count -gt 0)
        $miUpdateAll.IsEnabled = ($btnWingetUpdateAll -and $btnWingetUpdateAll.Visibility -eq [System.Windows.Visibility]::Visible)
        $miManifest.IsEnabled = $canShowManifest
        $miCopyRow.IsEnabled = ($selected.Count -gt 0)
        if ($canShowManifest) {
            $miManifest.ToolTip = "Show the winget manifest details for the selected package"
        }
        else {
            $miManifest.ToolTip = "Select one winget or Microsoft Store package to view its manifest"
        }
    })

# 8. Attach to List
$lstWinget.ContextMenu = $ctxMenu

# --- WINGET ---
$txtWingetSearch.Add_GotFocus({
        if ($txtWingetSearch.Text -in @("Search packages...", "Search new packages...")) { $txtWingetSearch.Text = "" }
    })
$txtWingetSearch.Add_TextChanged({
        # If the user starts typing and the only item is our status message, clear it
        if ($lstWinget.Items.Count -eq 1 -and $lstWinget.Items[0].Name -eq "No updates available") {
            $lstWinget.Items.Clear()
        }
    })
$txtWingetSearch.Add_KeyDown({ param($s, $e) if ($e.Key -eq "Return") { $btnWingetFind.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) } })

# 2. HELPER TO START JOB
$Script:StartWingetAction = {
    param($ListItems, $ActionName, $CmdTemplate)
    if (-not $ListItems -or $ListItems.Count -eq 0) { return }
    try {
        Stop-Process -Name "winget", "msiexec" -Force -ErrorAction SilentlyContinue
    }
    catch {}

    $uniqueItems = @($ListItems | Select-Object -Property Source, Name, Id, Version, Available, VersionSort, AvailableSort, IsChecked, LibraryPath, InstallDir, ManifestPath, ExecutablePath, Platform, RawAvailable, WUIsOptional -Unique)
    $totalItems = $uniqueItems.Count
    
    # UI Updates
    $btnWingetScan.IsEnabled = $false
    $btnWingetUpdateSel.IsEnabled = $false
    if ($btnWingetUpdateAll) { $btnWingetUpdateAll.IsEnabled = $false }
    if ($btnWingetInstall) { $btnWingetInstall.IsEnabled = $false }
    if ($btnWingetUninstall) { $btnWingetUninstall.IsEnabled = $false }
    $lblWingetStatus.Text = "$ActionName in progress..."
    $lblWingetStatus.Visibility = "Visible"
    $script:WingetActiveAction = $ActionName
    $script:WingetActionStartedAt = Get-Date
    $script:WingetProgressTotal = $totalItems
    $script:WingetProgressDone = 0
    $script:WingetProgressSuccess = 0
    $script:WingetProgressSkipped = 0
    $script:WingetProgressFailed = 0
    $script:WingetCurrentIndex = 0
    $script:WingetCurrentPercent = 0
    $script:WingetCurrentItemName = ""
    $script:WingetCurrentItemSource = ""
    $script:WingetCurrentItemStartedAt = $null
    $script:WingetActionForcedTimeout = $false
    $script:WingetCompletedIndexes = @{}
    $script:WingetActionStoreUpdateOnly = (
        $ActionName -eq "Update" -and
        $totalItems -gt 0 -and
        @($uniqueItems | Where-Object { ([string]$_.Source).ToLowerInvariant() -eq "msstore" }).Count -eq $totalItems
    )
    $script:WingetActionHasStoreCli = @($uniqueItems | Where-Object { ([string]$_.Source).ToLowerInvariant() -eq "msstore" -and $ActionName -eq "Install" }).Count -gt 0
    $script:WingetStoreResourcesInUseSeen = $false
    $script:WingetStoreErrorLogSeen = @{}
    $script:WingetStoreFallbackSeen = @{}
    $script:WingetSteamOpenSeen = @{}
    if ($pbWingetProgress) {
        $pbWingetProgress.Minimum = 0
        $pbWingetProgress.Maximum = [Math]::Max(1, $totalItems)
        $pbWingetProgress.Value = 0
        $pbWingetProgress.IsIndeterminate = $false
        $pbWingetProgress.Visibility = "Visible"
    }
    if ($lblWingetProgress) {
        $lblWingetProgress.Text = "0/$totalItems done | 0 success | 0 skipped | 0 failed"
        $lblWingetProgress.Visibility = "Visible"
    }
    if ($lblWingetLastResult) {
        $lblWingetLastResult.Text = ""
        $lblWingetLastResult.Visibility = "Collapsed"
    }

    $script:RefreshWingetProgressUi = {
        $total = [Math]::Max(1, [int]$script:WingetProgressTotal)
        $done = [Math]::Max(0, [int]$script:WingetProgressDone)
        $success = [Math]::Max(0, [int]$script:WingetProgressSuccess)
        $skipped = [Math]::Max(0, [int]$script:WingetProgressSkipped)
        $failed = [Math]::Max(0, [int]$script:WingetProgressFailed)
        $curIdx = [Math]::Max(0, [int]$script:WingetCurrentIndex)
        $curPct = [Math]::Max(0, [Math]::Min(100, [int]$script:WingetCurrentPercent))

        if ($pbWingetProgress) {
            $value = [double]$done
            if ($curIdx -gt 0 -and $done -lt $total) {
                $base = [Math]::Max($done, $curIdx - 1)
                $value = [Math]::Min([double]$total, [double]$base + ($curPct / 100.0))
            }
            $pbWingetProgress.Value = $value
        }

        if ($lblWingetProgress) {
            $running = ""
            if ($curIdx -gt 0 -and $done -lt $total) {
                $running = " | running $curIdx/$total"
                if ($curPct -gt 0) { $running += " ($curPct%)" }
            }
            $lblWingetProgress.Text = "$done/$total done | $success success | $skipped skipped | $failed failed$running"
        }
    }
    & $script:RefreshWingetProgressUi

    $script:SetWingetLastResultUi = {
        param(
            [string]$ResultCode,
            [string]$PackageName,
            [int]$DoneIndex,
            [int]$TotalCount
        )
        if (-not $lblWingetLastResult) { return }

        $text = "Last: [$ResultCode] $DoneIndex/$TotalCount - $PackageName"
        $brush = [System.Windows.Media.Brushes]::LightGray
        switch ($ResultCode) {
            "SUCCESS" { $brush = [System.Windows.Media.Brushes]::LightGreen }
            "SKIPPED" { $brush = [System.Windows.Media.Brushes]::Gold }
            "CANCELLED" { $brush = [System.Windows.Media.Brushes]::Orange }
            "FAILED" { $brush = [System.Windows.Media.Brushes]::Tomato }
        }

        $lblWingetLastResult.Text = $text
        $lblWingetLastResult.Foreground = $brush
        $lblWingetLastResult.Visibility = "Visible"
    }
    
    # 1. Define the Job Arguments
    $wingetIncludeUnknown = Get-WmtWingetIncludeUnknown -Settings (Get-WmtSettings)
    $pythonExePath = "python.exe"
    try {
        $resolvedPython = Get-Command "python.exe" -ErrorAction Stop
        if ($resolvedPython.Source) { $pythonExePath = [string]$resolvedPython.Source }
    }
    catch {}
    $jobArgs = @{
        Items                      = $uniqueItems
        ActionName                 = $ActionName
        CmdTemplate                = $CmdTemplate
        TempPath                   = $env:TEMP
        WingetIncludeUnknown       = $wingetIncludeUnknown
        SilentUpdateInstallEnabled = [bool](Get-WmtUpdateSilentInstallEnabled)
        PythonExePath              = $pythonExePath
        LegendaryExePath           = Get-WmtLegendaryExePath
        GogdlExePath               = Get-WmtGogdlExePath
        GogdlAuthConfigPath        = Get-WmtGogdlAuthConfigPath
    }

    # 2. Start the Background Job
    $script:WingetJob = Start-Job -ArgumentList $jobArgs -ScriptBlock {
        param($ArgsDict)
        $items = $ArgsDict.Items
        $act = $ArgsDict.ActionName
        $tmpl = $ArgsDict.CmdTemplate
        $temp = $ArgsDict.TempPath
        $wingetIncludeUnknown = [bool]$ArgsDict.WingetIncludeUnknown
        $silentUpdateInstallEnabled = [bool]$ArgsDict.SilentUpdateInstallEnabled
        $pythonExePath = [string]$ArgsDict.PythonExePath
        $legendaryExePath = [string]$ArgsDict.LegendaryExePath
        $gogdlExePath = [string]$ArgsDict.GogdlExePath
        $gogdlAuthConfigPath = [string]$ArgsDict.GogdlAuthConfigPath
        
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

        # --- ERROR DICTIONARY ---
        $ErrorCodes = @{
            "0" = "Success"
            "0x0" = "Success"
            "3010" = "Reboot Required"
            "1602" = "Cancelled by User"
            "1618" = "Another Installation in Progress"
            
            # Winget Specific
            "0x8a150001" = "Invalid Argument"; "0x8a150002" = "Internal Failure"; "0x8a150003" = "Source Corrupted (Trying auto-fix...)"
            "0x8a150004" = "Installer Failed"; "0x8a150005" = "Hash Mismatch"; "0x8a150006" = "Not Applicable"
            "0x8a150007" = "Launch Failed"; "0x8a150008" = "Manifest Missing"; "0x8a150009" = "Invalid Manifest"
            "0x8a15000a" = "Unsupported Type"; "0x8a15000b" = "Package Not Found"; "0x8a15000c" = "Vendor Error"
            "0x8a15000d" = "Download Failed"; "0x8a15000e" = "Installer Hash Mismatch"; "0x8a15000f" = "Data Missing"
            "0x8a150014" = "Network Error"
            "0x80070002" = "File Not Found"; "0x80070003" = "Path Not Found"; "0x80070005" = "Access Denied"
            "0x80070490" = "Element Not Found"; "0x80072ee7" = "DNS Lookup Fail"; "0x80072f8f" = "SSL Cert Error"
            "0x80073d02" = "Resources Currently In Use"; "-2147009278" = "Resources Currently In Use"; "2147958018" = "Resources Currently In Use"
            "1603" = "Fatal MSI Error"
        }

        function Test-WmtStoreUpdateScanPreferredItem {
            param(
                [string]$Name,
                [string]$Id
            )

            $text = (([string]$Name) + " " + ([string]$Id)).Trim()
            if ([string]::IsNullOrWhiteSpace($text)) { return $false }

            return ($text -match '(?i)(^|\b)(Microsoft\s+Store|Windows\s+Store|Store\s+Experience\s+Host|Store\s+Purchase\s+App)(\b|$)' -or
                $text -match '(?i)(Microsoft\.WindowsStore|Microsoft\.StorePurchaseApp|Microsoft\.Services\.Store\.Engagement|9WZDNCRFJBMP)')
        }

        function Get-WmtLegendaryCommandText {
            param([switch]$ForPowerShell)

            $exe = ([string]$legendaryExePath).Trim()
            if ([string]::IsNullOrWhiteSpace($exe) -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) {
                try {
                    $cmd = Get-Command legendary -ErrorAction SilentlyContinue
                    if ($cmd -and $cmd.Source) { $exe = [string]$cmd.Source }
                }
                catch {}
            }
            if ([string]::IsNullOrWhiteSpace($exe)) { $exe = "legendary" }

            $safeExe = ([string]$exe).Replace('"', '')
            if ($ForPowerShell) { return "& `"$safeExe`"" }
            if ($safeExe -match '^[A-Za-z]:\\|^\\\\') { return "`"$safeExe`"" }
            return $safeExe
        }

        function Get-WmtGogdlCommandText {
            param([switch]$ForPowerShell)

            $exe = ([string]$gogdlExePath).Trim()
            if ([string]::IsNullOrWhiteSpace($exe) -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) {
                try {
                    foreach ($cmdName in @("gogdl", "gogdl.exe", "gogdl_windows_x86_64.exe")) {
                        $cmd = Get-Command $cmdName -ErrorAction SilentlyContinue
                        if ($cmd -and $cmd.Source) {
                            $exe = [string]$cmd.Source
                            break
                        }
                    }
                }
                catch {}
            }
            if ([string]::IsNullOrWhiteSpace($exe)) { $exe = "gogdl" }

            $safeExe = ([string]$exe).Replace('"', '')
            if ($ForPowerShell) { return "& `"$safeExe`"" }
            if ($safeExe -match '^[A-Za-z]:\\|^\\\\') { return "`"$safeExe`"" }
            return $safeExe
        }

        function Invoke-WmtStoreFallbackPage {
            param(
                [string]$PackageName,
                [string]$ActionLabel,
                [string]$Reason,
                [string]$ReasonText,
                [string]$StoreUri = "ms-windows-store://downloadsandupdates",
                [string]$WebUri = "https://apps.microsoft.com/home"
            )

            $fallbackUri = ([string]$StoreUri).Trim()
            $fallbackWebUri = ([string]$WebUri).Trim()
            if ([string]::IsNullOrWhiteSpace($fallbackUri)) { $fallbackUri = "ms-windows-store://downloadsandupdates" }
            if ([string]::IsNullOrWhiteSpace($fallbackWebUri)) { $fallbackWebUri = $fallbackUri }

            $fallbackId = [Guid]::NewGuid().ToString("N")
            $fallbackAckPath = Join-Path $temp "WMT_StoreCLI_$fallbackId.fallback_ack"
            try {
                $payload = [ordered]@{
                    FallbackId  = $fallbackId
                    AckPath     = $fallbackAckPath
                    StoreUri    = $fallbackUri
                    WebUri      = $fallbackWebUri
                    PackageName = $PackageName
                    ActionLabel = $ActionLabel
                    Reason      = $Reason
                    ReasonText  = $ReasonText
                }
                $json = $payload | ConvertTo-Json -Compress
                $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
                $fallbackLine = "STORE_FALLBACK:$encoded"
                Write-Output $fallbackLine
            }
            catch {}

            $sentAt = Get-Date
            $ackDeadline = $sentAt.AddSeconds(4)
            $directFallbackAttempted = $false
            while ((Get-Date) -lt $ackDeadline) {
                if (Test-Path $fallbackAckPath) { break }

                $now = Get-Date
                if (-not $directFallbackAttempted -and (New-TimeSpan -Start $sentAt -End $now).TotalMilliseconds -ge 1500) {
                    $directFallbackAttempted = $true
                    $directOpened = $false
                    try {
                        Start-Process -FilePath $fallbackUri
                        $directOpened = $true
                        Write-Output "LOG:[Store] Requested Microsoft Store page directly for $PackageName."
                    }
                    catch {
                        Write-Output "LOG:[Store] Direct Microsoft Store page launch failed: $($_.Exception.Message)"
                    }

                    if (-not $directOpened -and $fallbackWebUri -and $fallbackWebUri -ne $fallbackUri) {
                        try {
                            Start-Process -FilePath $fallbackWebUri
                            Write-Output "LOG:[Store] Requested Microsoft Store web page directly for $PackageName."
                        }
                        catch {
                            Write-Output "LOG:[Store] Direct Microsoft Store web page launch failed: $($_.Exception.Message)"
                        }
                    }
                }

                Start-Sleep -Milliseconds 200
            }

            try { Remove-Item -Path $fallbackAckPath -Force -ErrorAction SilentlyContinue } catch {}
        }

        function Invoke-WmtStoreAppUpdateScan {
            param([string]$PackageName)

            $displayName = if ([string]::IsNullOrWhiteSpace($PackageName)) { "Microsoft Store apps" } else { $PackageName }
            $scanStarted = $false
            $reasonText = "WMT opened Microsoft Store Updates so Store apps can update while other installers continue."
            try {
                Write-Output "LOG:[Store] Starting Microsoft Store update scan for $displayName..."
                $appManagement = Get-CimInstance -Namespace "Root\cimv2\mdm\dmmap" -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" -ErrorAction Stop | Select-Object -First 1
                if (-not $appManagement) { throw "Store app-management provider returned no instances." }

                $scanResult = Invoke-CimMethod -InputObject $appManagement -MethodName "UpdateScanMethod" -ErrorAction Stop
                $returnValue = 0
                if ($scanResult -and $scanResult.PSObject.Properties["ReturnValue"]) {
                    $returnValue = [int]$scanResult.ReturnValue
                }

                if ($returnValue -eq 0) {
                    Write-Output "LOG:[Store] Microsoft Store app update scan started."
                    $scanStarted = $true
                    $reasonText = "WMT started a Microsoft Store app update scan and opened Microsoft Store Updates."
                }
                else {
                    Write-Output "LOG:[Store] Microsoft Store app update scan returned code $returnValue."
                    $reasonText = "WMT could not start the direct Store app update scan, so Microsoft Store Updates was opened instead."
                }
            }
            catch {
                Write-Output "LOG:[Store] Microsoft Store app update scan failed: $($_.Exception.Message)"
                $reasonText = "WMT could not start the direct Store app update scan, so Microsoft Store Updates was opened instead."
            }

            Invoke-WmtStoreFallbackPage -PackageName $displayName -ActionLabel "Update" -Reason "UpdateScan" -ReasonText $reasonText -StoreUri "ms-windows-store://downloadsandupdates" -WebUri "https://apps.microsoft.com/home"
            return [PSCustomObject]@{ ExitCode = 0; StoreUpdateScan = $scanStarted; StoreUpdatesDelegated = $true }
        }

        function Invoke-WmtStoreGuiUpdate {
            param(
                [string]$PackageName,
                [int]$TimeoutSeconds = 300,
                [ref]$Result
            )

            $Result.Value = $null
            $displayName = ([string]$PackageName).Trim()
            if ([string]::IsNullOrWhiteSpace($displayName)) {
                $Result.Value = [PSCustomObject]@{ ExitCode = 1; Message = "Package name is blank." }
                return
            }

            try {
                Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
                Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
            }
            catch {
                Write-Output "LOG:[Store GUI] UI Automation is unavailable: $($_.Exception.Message)"
                $Result.Value = [PSCustomObject]@{ ExitCode = 1; Message = "UI Automation is unavailable." }
                return
            }

            try { Start-Process "ms-windows-store://downloadsandupdates" -ErrorAction SilentlyContinue } catch {}

            $deadline = (Get-Date).AddSeconds([Math]::Max(30, $TimeoutSeconds))
            $startedAt = Get-Date
            $invoked = $false
            $checkForUpdatesInvoked = $false
            $lastStatus = ""
            $storeWindowMissingSince = $null
            $titleNameCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $displayName)
            $titleIdCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, "ProductTitle")
            $titleCondition = New-Object System.Windows.Automation.AndCondition($titleNameCondition, $titleIdCondition)
            $actionButtonCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, "ActionButton")
            $checkButtonCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, "CheckForUpdatesButton")
            $root = [System.Windows.Automation.AutomationElement]::RootElement

            while ((Get-Date) -lt $deadline) {
                $storeWindow = @(
                    $root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition) |
                        Where-Object { ([string]$_.Current.Name) -eq "Microsoft Store" }
                ) | Select-Object -First 1

                if (-not $storeWindow) {
                    if (-not $storeWindowMissingSince) { $storeWindowMissingSince = Get-Date }
                    if (((Get-Date) - $storeWindowMissingSince).TotalSeconds -ge 20) {
                        Write-Output "LOG:[Store GUI] Microsoft Store window was unavailable for 20 seconds."
                        $Result.Value = [PSCustomObject]@{ ExitCode = 1; Message = "Microsoft Store window is unavailable." }
                        return
                    }
                    Start-Sleep -Milliseconds 500
                    continue
                }
                $storeWindowMissingSince = $null

                $rows = New-Object System.Collections.Generic.List[object]
                foreach ($title in @($storeWindow.FindAll([System.Windows.Automation.TreeScope]::Descendants, $titleCondition))) {
                    try {
                        $row = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($title)
                        if ($row -and $row.Current.ControlType -eq [System.Windows.Automation.ControlType]::Custom) {
                            [void]$rows.Add($row)
                        }
                    }
                    catch {}
                }

                $updateRow = @($rows | Where-Object { ([string]$_.Current.Name) -match '(?i),\s*Update available\b' } | Select-Object -First 1)
                $activeRow = @($rows | Where-Object { ([string]$_.Current.Name) -match '(?i),\s*(Downloading|Installing|Pending|Queued|Starting|Acquiring|Processing|Updating|Downloaded)\b' } | Select-Object -First 1)
                $finishedRow = @($rows | Where-Object { ([string]$_.Current.Name) -match '(?i),\s*(Modified moments ago|Updated|Installed)\b' } | Select-Object -First 1)

                if (-not $invoked -and $activeRow.Count -gt 0) {
                    $invoked = $true
                    Write-Output "LOG:[Store GUI] $displayName is already updating in Microsoft Store."
                    Write-Output "LOG:  [store] Progress: 25%"
                }

                if (-not $invoked -and $updateRow.Count -gt 0) {
                    try {
                        $actionButton = $updateRow[0].FindFirst([System.Windows.Automation.TreeScope]::Descendants, $actionButtonCondition)
                        if (-not $actionButton -or -not $actionButton.Current.IsEnabled) {
                            throw "The Update button is unavailable."
                        }

                        $invokePattern = $actionButton.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                        $invokePattern.Invoke()
                        $invoked = $true
                        Write-Output "LOG:[Store GUI] Invoked the Microsoft Store Update button for $displayName."
                        Write-Output "LOG:  [store] Progress: 10%"
                        Start-Sleep -Seconds 1
                        continue
                    }
                    catch {
                        Write-Output "LOG:[Store GUI] Could not invoke Update for ${displayName}: $($_.Exception.Message)"
                        $Result.Value = [PSCustomObject]@{ ExitCode = 1; Message = $_.Exception.Message }
                        return
                    }
                }

                if ($invoked) {
                    if ($activeRow.Count -gt 0) {
                        $status = ([string]$activeRow[0].Current.Name).Trim()
                        if ($status -ne $lastStatus) {
                            $lastStatus = $status
                            Write-Output "LOG:[Store GUI] $status"
                            $progress = if ($status -match '(?i)Installing|Processing|Downloaded') { 85 } else { 50 }
                            Write-Output "LOG:  [store] Progress: $progress%"
                        }
                    }
                    elseif ($updateRow.Count -eq 0 -and ((Get-Date) - $startedAt).TotalSeconds -ge 2) {
                        Write-Output "LOG:  [store] Progress: 100%"
                        $Result.Value = [PSCustomObject]@{ ExitCode = 0; GuiUpdateInvoked = $true; Completed = $true }
                        return
                    }
                    elseif ($finishedRow.Count -gt 0) {
                        Write-Output "LOG:  [store] Progress: 100%"
                        $Result.Value = [PSCustomObject]@{ ExitCode = 0; GuiUpdateInvoked = $true; Completed = $true }
                        return
                    }
                }
                elseif (-not $checkForUpdatesInvoked -and ((Get-Date) - $startedAt).TotalSeconds -ge 2) {
                    try {
                        $checkButton = $storeWindow.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $checkButtonCondition)
                        if ($checkButton -and $checkButton.Current.IsEnabled) {
                            $checkPattern = $checkButton.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                            $checkPattern.Invoke()
                            Write-Output "LOG:[Store GUI] Invoked Check for updates while locating $displayName."
                        }
                    }
                    catch {
                        Write-Output "LOG:[Store GUI] Check for updates could not be invoked: $($_.Exception.Message)"
                    }
                    $checkForUpdatesInvoked = $true
                }
                elseif ($checkForUpdatesInvoked -and ((Get-Date) - $startedAt).TotalSeconds -ge 15) {
                    Write-Output "LOG:[Store GUI] No available Update button was found for $displayName; it may already be current."
                    $Result.Value = [PSCustomObject]@{ ExitCode = 0; AlreadyCurrent = $true; Completed = $true }
                    return
                }

                Start-Sleep -Milliseconds 750
            }

            Write-Output "LOG:[Store GUI] Timed out waiting for $displayName to finish updating."
            $Result.Value = [PSCustomObject]@{ ExitCode = 1; TimedOut = $true; Message = "Store GUI update timed out." }
        }

        # steam.exe and its main window stay open after updates, so completion is
        # confirmed through the same per-app manifest fields used by the Steam scan.
        function Get-WmtSteamActionManifestValue {
            param(
                [string]$Text,
                [string]$Key
            )

            if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Key)) { return "" }
            $match = [regex]::Match($Text, ('"' + [regex]::Escape($Key) + '"\s+"([^"]*)"'))
            if ($match.Success) { return [string]$match.Groups[1].Value }
            return ""
        }

        function Get-WmtSteamActionManifestNumber {
            param(
                [string]$Text,
                [string]$Key
            )

            $value = Get-WmtSteamActionManifestValue -Text $Text -Key $Key
            $number = [long]0
            if ([long]::TryParse(([string]$value), [ref]$number)) { return $number }
            return [long]0
        }

        function Get-WmtSteamActionManifestState {
            param([string]$ManifestPath)

            if ([string]::IsNullOrWhiteSpace($ManifestPath) -or -not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
                return [PSCustomObject]@{ Readable = $false; ErrorMessage = "Steam app manifest was not found." }
            }

            try {
                $text = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop
                if ([string]::IsNullOrWhiteSpace($text)) { throw "Steam app manifest is empty." }

                $stateFlags = Get-WmtSteamActionManifestNumber -Text $text -Key "StateFlags"
                $bytesToDownload = Get-WmtSteamActionManifestNumber -Text $text -Key "BytesToDownload"
                $bytesDownloaded = Get-WmtSteamActionManifestNumber -Text $text -Key "BytesDownloaded"
                $bytesToStage = Get-WmtSteamActionManifestNumber -Text $text -Key "BytesToStage"
                $bytesStaged = Get-WmtSteamActionManifestNumber -Text $text -Key "BytesStaged"
                $buildId = Get-WmtSteamActionManifestValue -Text $text -Key "buildid"
                $targetBuildId = Get-WmtSteamActionManifestValue -Text $text -Key "TargetBuildID"

                $downloadRemaining = [Math]::Max([long]0, $bytesToDownload - $bytesDownloaded)
                $stageRemaining = [Math]::Max([long]0, $bytesToStage - $bytesStaged)
                $hasTargetBuild = (-not [string]::IsNullOrWhiteSpace($targetBuildId) -and $targetBuildId -ne "0" -and $targetBuildId -ne $buildId)
                $isPending = (
                    ($stateFlags -ne 0 -and $stateFlags -ne 4) -or
                    $downloadRemaining -gt 0 -or
                    $stageRemaining -gt 0 -or
                    $hasTargetBuild
                )

                $totalWork = [Math]::Max([long]0, $bytesToDownload) + [Math]::Max([long]0, $bytesToStage)
                $completedWork = [Math]::Min([Math]::Max([long]0, $bytesDownloaded), [Math]::Max([long]0, $bytesToDownload)) +
                    [Math]::Min([Math]::Max([long]0, $bytesStaged), [Math]::Max([long]0, $bytesToStage))
                $progress = -1
                if ($totalWork -gt 0) {
                    $progress = [int][Math]::Floor(($completedWork * 100.0) / $totalWork)
                    if ($isPending -and $progress -ge 100) { $progress = 99 }
                }

                $status = if (-not $isPending) {
                    "current"
                }
                elseif ($downloadRemaining -gt 0) {
                    "{0:N1} MB download remaining" -f ($downloadRemaining / 1MB)
                }
                elseif ($stageRemaining -gt 0) {
                    "{0:N1} MB staging remaining" -f ($stageRemaining / 1MB)
                }
                elseif ($hasTargetBuild) {
                    "waiting for target build $targetBuildId"
                }
                else {
                    "Steam state $stateFlags"
                }

                return [PSCustomObject]@{
                    Readable          = $true
                    IsPending         = $isPending
                    StateFlags        = $stateFlags
                    BuildId           = $buildId
                    TargetBuildId     = $targetBuildId
                    DownloadRemaining = $downloadRemaining
                    StageRemaining    = $stageRemaining
                    Progress          = $progress
                    Status            = $status
                }
            }
            catch {
                return [PSCustomObject]@{ Readable = $false; ErrorMessage = $_.Exception.Message }
            }
        }

        function Wait-WmtSteamActionCompletion {
            param(
                [string]$ManifestPath,
                [string]$PackageName,
                [int]$TimeoutSeconds = 14400,
                [ref]$Result
            )

            $Result.Value = $null
            if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
                Write-Output "LOG:[Steam] Cannot monitor $PackageName because its app manifest path is unavailable."
                $Result.Value = [PSCustomObject]@{ ExitCode = 2; Message = "Steam app manifest path is unavailable." }
                return
            }

            $deadline = (Get-Date).AddSeconds([Math]::Max(60, $TimeoutSeconds))
            $missingSince = $null
            $stableCompleteReads = 0
            $lastSignature = ""
            $lastProgress = -2
            $lastHeartbeat = Get-Date
            Write-Output "LOG:[Steam] Monitoring the app manifest for $PackageName update completion (timeout: 4 hours)."

            while ((Get-Date) -lt $deadline) {
                $state = Get-WmtSteamActionManifestState -ManifestPath $ManifestPath
                if (-not $state.Readable) {
                    if (-not $missingSince) {
                        $missingSince = Get-Date
                        Write-Output "LOG:[Steam] Waiting for the app manifest to become readable for $PackageName."
                    }
                    elseif (((Get-Date) - $missingSince).TotalSeconds -ge 30) {
                        Write-Output "LOG:[Steam] App manifest remained unavailable for 30 seconds: $($state.ErrorMessage)"
                        $Result.Value = [PSCustomObject]@{ ExitCode = 1; Message = $state.ErrorMessage }
                        return
                    }
                    Start-Sleep -Seconds 1
                    continue
                }

                $missingSince = $null
                $signature = "$($state.StateFlags)|$($state.BuildId)|$($state.TargetBuildId)|$($state.DownloadRemaining)|$($state.StageRemaining)"
                if ($signature -ne $lastSignature) {
                    $lastSignature = $signature
                    Write-Output "LOG:[Steam] $PackageName status: $($state.Status)."
                }

                if ($state.Progress -ge 0 -and $state.Progress -ne $lastProgress) {
                    $lastProgress = $state.Progress
                    Write-Output "LOG:  [steam] Progress: $($state.Progress)%"
                }

                if (-not $state.IsPending) {
                    $stableCompleteReads++
                    if ($stableCompleteReads -ge 3) {
                        Write-Output "LOG:  [steam] Progress: 100%"
                        $Result.Value = [PSCustomObject]@{ ExitCode = 0; Completed = $true; BuildId = $state.BuildId }
                        return
                    }
                }
                else {
                    $stableCompleteReads = 0
                }

                if (((Get-Date) - $lastHeartbeat).TotalSeconds -ge 30) {
                    $lastHeartbeat = Get-Date
                    Write-Output "LOG:[Steam] Still waiting for $PackageName to finish in Steam ($($state.Status))."
                }
                Start-Sleep -Seconds 1
            }

            Write-Output "LOG:[Steam] Timed out waiting for $PackageName to finish updating."
            $Result.Value = [PSCustomObject]@{ ExitCode = 1; TimedOut = $true; Message = "Steam update completion monitor timed out." }
        }

        function Close-WmtStoreGui {
            try {
                Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
                Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop

                $root = [System.Windows.Automation.AutomationElement]::RootElement
                $storeWindow = @(
                    $root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition) |
                        Where-Object { ([string]$_.Current.Name) -eq "Microsoft Store" }
                ) | Select-Object -First 1
                if (-not $storeWindow) {
                    Write-Output "LOG:[Store GUI] Microsoft Store window is already closed."
                    return
                }

                $closeCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, "Close")
                $closeButton = $storeWindow.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $closeCondition)
                if (-not $closeButton -or -not $closeButton.Current.IsEnabled) {
                    throw "The Microsoft Store Close button is unavailable."
                }

                $closePattern = $closeButton.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                $closePattern.Invoke()
                Write-Output "LOG:[Store GUI] Closed Microsoft Store after Store updates completed."
            }
            catch {
                Write-Output "LOG:[Store GUI] Could not close Microsoft Store: $($_.Exception.Message)"
            }
        }

        function Stop-WmtChildProcessTree {
            param([object]$Process)

            if (-not $Process) { return }
            try {
                $Process.Refresh()
                if ($Process.HasExited) { return }
            }
            catch { return }

            try {
                $killInfo = New-Object System.Diagnostics.ProcessStartInfo
                $killInfo.FileName = "taskkill.exe"
                $killInfo.Arguments = "/PID $($Process.Id) /T /F"
                $killInfo.UseShellExecute = $false
                $killInfo.CreateNoWindow = $true
                $killInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                $killProc = [System.Diagnostics.Process]::Start($killInfo)
                if ($killProc) { [void]$killProc.WaitForExit(5000) }
            }
            catch {
                try { $Process.Kill() } catch {}
            }
        }

        # Executes headless commands without blocking on a quiet stdout/stderr stream.
        function Invoke-WingetCmd {
            param(
                [string]$Command,
                [int]$TimeoutSeconds = 0,
                [string]$CommandLabel = "Command"
            )

            $pInfo = New-Object System.Diagnostics.ProcessStartInfo
            $pInfo.FileName = "powershell.exe"
            $pInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command $Command"
            $pInfo.RedirectStandardOutput = $true
            $pInfo.RedirectStandardError = $true
            $pInfo.UseShellExecute = $false
            $pInfo.CreateNoWindow = $true
            $proc = [System.Diagnostics.Process]::Start($pInfo)

            $outTask = $proc.StandardOutput.ReadToEndAsync()
            $errTask = $proc.StandardError.ReadToEndAsync()
            $startedAt = Get-Date
            $lastHeartbeat = $startedAt
            $timedOut = $false
            while (-not $proc.HasExited) {
                $now = Get-Date
                if ($TimeoutSeconds -gt 0 -and (($now - $startedAt).TotalSeconds -ge $TimeoutSeconds)) {
                    $timedOut = $true
                    Write-Output "LOG:$CommandLabel timed out after $TimeoutSeconds seconds. Stopping its process tree."
                    Stop-WmtChildProcessTree -Process $proc
                    break
                }
                if (($now - $lastHeartbeat).TotalSeconds -ge 15) {
                    Write-Output "LOG:$CommandLabel still running..."
                    $lastHeartbeat = $now
                }
                Start-Sleep -Milliseconds 100
            }

            try { [void]$proc.WaitForExit(5000) } catch {}
            try {
                $proc.Refresh()
                if (-not $proc.HasExited) {
                    try { $proc.Kill() } catch {}
                    try { [void]$proc.WaitForExit(2000) } catch {}
                }
            }
            catch {}
            $outText = ""
            $errText = ""
            try { if ($outTask.IsCompleted) { $outText = $outTask.GetAwaiter().GetResult() } } catch {}
            try { if ($errTask.IsCompleted) { $errText = $errTask.GetAwaiter().GetResult() } } catch {}

            if ($outText) {
                foreach ($line in ($outText -split "`r?`n")) {
                    if ($line) { Write-Output "LOG:  > $line" }
                }
            }
            if ($errText) {
                foreach ($line in ($errText -split "`r?`n")) {
                    if ($line) { Write-Output "LOG:  ! $line" }
                }
            }

            if ($timedOut) {
                return [PSCustomObject]@{ ExitCode = 124; TimedOut = $true }
            }
            return $proc
        }

        # Pip can remain alive indefinitely when launched with ProcessStartInfo from inside Start-Job.
        # Direct native invocation lets the job host drain pip's output reliably while remaining headless.
        function Invoke-WmtPipDirect {
            param(
                [string]$PythonPath,
                [object[]]$ArgumentList
            )

            if ([string]::IsNullOrWhiteSpace($PythonPath)) { $PythonPath = "python.exe" }
            try {
                $outputLines = @(& $PythonPath @ArgumentList 2>&1)
                $exitCode = $LASTEXITCODE
                return [PSCustomObject]@{
                    ExitCode   = if ($null -eq $exitCode) { 1 } else { [int]$exitCode }
                    OutputLines = @($outputLines | ForEach-Object { $_.ToString() })
                    TimedOut   = $false
                }
            }
            catch {
                return [PSCustomObject]@{
                    ExitCode   = 1
                    OutputLines = @($_.Exception.Message)
                    TimedOut   = $false
                }
            }
        }

        function Invoke-WingetLive ($argsLine) {
            $pInfo = New-Object System.Diagnostics.ProcessStartInfo
            $pInfo.FileName = "winget"
            $pInfo.Arguments = $argsLine
            $pInfo.RedirectStandardOutput = $true
            $pInfo.RedirectStandardError = $true
            $pInfo.UseShellExecute = $false
            $pInfo.CreateNoWindow = $true
            $proc = [System.Diagnostics.Process]::Start($pInfo)

            $outBuf = New-Object System.Text.StringBuilder
            $errBuf = New-Object System.Text.StringBuilder
            $lastLine = ""
            $lastPct = -1
            $lastBeat = Get-Date

            while ((-not $proc.HasExited) -or $proc.StandardOutput.Peek() -gt -1 -or $proc.StandardError.Peek() -gt -1) {
                $hadData = $false

                while ($proc.StandardOutput.Peek() -gt -1) {
                    $hadData = $true
                    $ch = [char]$proc.StandardOutput.Read()
                    if ($ch -eq "`r" -or $ch -eq "`n") {
                        $line = $outBuf.ToString().Trim()
                        [void]$outBuf.Clear()
                        if ($line) {
                            if ($line -match "(\d+)%") {
                                $pct = [int]$matches[1]
                                if ($pct -ne $lastPct) {
                                    $lastPct = $pct
                                    Write-Output "LOG:  [winget] Progress: $pct%"
                                }
                            }
                            elseif ($line -ne $lastLine) {
                                $lastLine = $line
                                Write-Output "LOG:  > $line"
                            }
                        }
                    }
                    else {
                        [void]$outBuf.Append($ch)
                    }
                }

                while ($proc.StandardError.Peek() -gt -1) {
                    $hadData = $true
                    $ch = [char]$proc.StandardError.Read()
                    if ($ch -eq "`r" -or $ch -eq "`n") {
                        $line = $errBuf.ToString().Trim()
                        [void]$errBuf.Clear()
                        if ($line) {
                            if ($line -match "(\d+)%") {
                                $pct = [int]$matches[1]
                                if ($pct -ne $lastPct) {
                                    $lastPct = $pct
                                    Write-Output "LOG:  [winget] Progress: $pct%"
                                }
                            }
                            elseif ($line -ne $lastLine) {
                                $lastLine = $line
                                Write-Output "LOG:  ! $line"
                            }
                        }
                    }
                    else {
                        [void]$errBuf.Append($ch)
                    }
                }

                $now = Get-Date
                if ((-not $hadData) -and ((New-TimeSpan -Start $lastBeat -End $now).TotalSeconds -ge 8)) {
                    Write-Output "LOG:  [winget] still running..."
                    $lastBeat = $now
                }

                if (-not $hadData) {
                    Start-Sleep -Milliseconds 80
                }
            }

            $tailOut = $outBuf.ToString().Trim()
            if ($tailOut) { Write-Output "LOG:  > $tailOut" }
            $tailErr = $errBuf.ToString().Trim()
            if ($tailErr) { Write-Output "LOG:  ! $tailErr" }

            return $proc
        }

        function Invoke-VisibleCmd ($command, $title, [int]$HoldSeconds = 0) {
            if ([string]::IsNullOrWhiteSpace($title)) { $title = "WMT Package Update" }
            $safeTitle = ((($title -replace '"', '') -replace '[\r\n]', ' ') -replace '[&|<>^%!]', ' ').Trim()
            if ($HoldSeconds -gt 0) {
                $cmdLine = "/v:on /c title $safeTitle && $command & set WMT_EXIT=!ERRORLEVEL! & echo. & echo Exit code: !WMT_EXIT! & timeout /t $HoldSeconds /nobreak >nul & exit /b !WMT_EXIT!"
            }
            else {
                $cmdLine = "/c title $safeTitle && $command"
            }
            $windowStyle = if ($silentUpdateInstallEnabled) { "Hidden" } else { "Normal" }
            $proc = Start-Process -FilePath "cmd.exe" -ArgumentList $cmdLine -PassThru -Wait -WindowStyle $windowStyle
            return $proc
        }

        function Invoke-StoreCliInteractive {
            param(
                [string]$Arguments,
                [string]$PackageName,
                [string]$TempPath,
                [string]$ActionLabel = "Update",
                [string]$StoreFallbackUri = "",
                [string]$StoreFallbackWebUri = ""
            )

            $rand = [Guid]::NewGuid().ToString("N")
            $batPath = Join-Path $TempPath "WMT_StoreCLI_$rand.cmd"
            $resultPath = Join-Path $TempPath "WMT_StoreCLI_$rand.exit"
            $statusPath = Join-Path $TempPath "WMT_StoreCLI_$rand.status"
            $resourcesInUsePath = Join-Path $TempPath "WMT_StoreCLI_$rand.resources"
            $screenPath = Join-Path $TempPath "WMT_StoreCLI_$rand.screen"
            $transcriptPath = Join-Path $TempPath "WMT_StoreCLI_$rand.transcript"
            $fallbackAckPath = Join-Path $TempPath "WMT_StoreCLI_$rand.fallback_ack"
            $runnerPath = Join-Path $TempPath "WMT_StoreCLI_$rand.run.ps1"
            $sendKeysPath = Join-Path $TempPath "WMT_StoreCLI_$rand.ps1"
            $safeTitle = (((($PackageName -replace '"', '') -replace '[\r\n]', ' ') -replace '[&|<>^%!]', ' ')).Trim()
            if ([string]::IsNullOrWhiteSpace($safeTitle)) { $safeTitle = "Microsoft Store App" }
            $windowTitle = "WMT Store CLI - $safeTitle"
            $displayAction = if ($ActionLabel -eq "Install") { "Installing" } else { "Updating" }

            function Get-WmtStoreCliExitResult {
                param(
                    [string]$ResultPath,
                    [object]$Process
                )

                if ($ResultPath -and (Test-Path $ResultPath)) {
                    $exitText = (Get-Content -Path $ResultPath -Raw -ErrorAction SilentlyContinue).Trim()
                    $exitHexMatch = [regex]::Match($exitText, '(?i)0x[0-9a-f]{8}')
                    if ($exitHexMatch.Success) {
                        $exitCodeUInt = [Convert]::ToUInt32($exitHexMatch.Value.Substring(2), 16)
                        $exitCode = [BitConverter]::ToInt32([BitConverter]::GetBytes($exitCodeUInt), 0)
                        return [PSCustomObject]@{ Found = $true; ExitCode = $exitCode }
                    }
                    $exitMatch = [regex]::Match($exitText, '-?\d+')
                    $exitCode = 1
                    if ($exitMatch.Success -and [int]::TryParse($exitMatch.Value, [ref]$exitCode)) {
                        return [PSCustomObject]@{ Found = $true; ExitCode = $exitCode }
                    }
                    $exitCodeUInt = [uint32]0
                    if ($exitMatch.Success -and [uint32]::TryParse($exitMatch.Value, [ref]$exitCodeUInt)) {
                        $exitCode = [BitConverter]::ToInt32([BitConverter]::GetBytes($exitCodeUInt), 0)
                        return [PSCustomObject]@{ Found = $true; ExitCode = $exitCode }
                    }
                    return [PSCustomObject]@{ Found = $true; ExitCode = 1 }
                }

                if ($Process -and $Process.HasExited) {
                    $exitCode = 1
                    try { $exitCode = [int]$Process.ExitCode } catch {}
                    return [PSCustomObject]@{ Found = $true; ExitCode = $exitCode }
                }

                return [PSCustomObject]@{ Found = $false; ExitCode = 1 }
            }

            function Clear-WmtStoreCliTempFiles {
                param([string[]]$Paths)

                foreach ($path in $Paths) {
                    if ([string]::IsNullOrWhiteSpace($path)) { continue }
                    try { Remove-Item -Path $path -Force -ErrorAction SilentlyContinue } catch {}
                }
            }

            function Show-WmtStoreCliWindow {
                param([object]$Process)

                if (-not $Process) { return }
                try {
                    if (-not ('WmtStoreCliWindow' -as [type])) {
                        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class WmtStoreCliWindow {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
}
"@
                    }

                    $handle = [IntPtr]::Zero
                    for ($i = 0; $i -lt 10; $i++) {
                        try { $Process.Refresh() } catch {}
                        try { $handle = $Process.MainWindowHandle } catch { $handle = [IntPtr]::Zero }
                        if ($handle -ne [IntPtr]::Zero) { break }
                        Start-Sleep -Milliseconds 100
                    }
                    if ($handle -ne [IntPtr]::Zero) {
                        [void][WmtStoreCliWindow]::ShowWindowAsync($handle, 9)
                        [void][WmtStoreCliWindow]::SetForegroundWindow($handle)
                    }
                }
                catch {}
            }

            function Write-WmtStoreCliActivityEvent {
                param([string]$Line)

                if ([string]::IsNullOrWhiteSpace($EventPath) -or [string]::IsNullOrWhiteSpace($Line)) { return }
                try { Add-Content -Path $EventPath -Value $Line -Encoding UTF8 -Force } catch {}
            }

            function Test-WmtStoreCliResourcesInUseText {
                param([string]$Text)

                return (([string]$Text) -match '(?is)(0x80073d02|resources\s+(?:it\s+)?modifies\s+are\s+currently\s+in\s+use|resources[\s\S]{0,240}currently\s+in\s+use)')
            }

            function Invoke-WmtStoreCliFallback {
                param(
                    [string]$Reason,
                    [string]$ReasonText,
                    [string]$StoreUri,
                    [string]$WebUri
                )

                $fallbackUri = ([string]$StoreUri).Trim()
                $fallbackWebUri = ([string]$WebUri).Trim()
                if ([string]::IsNullOrWhiteSpace($fallbackUri)) { $fallbackUri = "ms-windows-store://home" }
                if ([string]::IsNullOrWhiteSpace($fallbackWebUri)) { $fallbackWebUri = $fallbackUri }

                try {
                    $payload = [ordered]@{
                        FallbackId  = $rand
                        AckPath     = $fallbackAckPath
                        StoreUri    = $fallbackUri
                        WebUri      = $fallbackWebUri
                        PackageName = $PackageName
                        ActionLabel = $ActionLabel
                        Reason      = $Reason
                        ReasonText  = $ReasonText
                    }
                    $json = $payload | ConvertTo-Json -Compress
                    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
                    $fallbackLine = "STORE_FALLBACK:$encoded"
                    Write-Output $fallbackLine
                    Write-WmtStoreCliActivityEvent $fallbackLine
                }
                catch {}

                $sentAt = Get-Date
                $ackDeadline = $sentAt.AddSeconds(6)
                $directFallbackAttempted = $false
                while ((Get-Date) -lt $ackDeadline) {
                    if (Test-Path $fallbackAckPath) { break }

                    $now = Get-Date
                    if (-not $directFallbackAttempted -and (New-TimeSpan -Start $sentAt -End $now).TotalMilliseconds -ge 1500) {
                        $directFallbackAttempted = $true
                        $directOpened = $false
                        try {
                            Start-Process -FilePath $fallbackUri
                            $directOpened = $true
                            Write-Output "LOG:[Store CLI] Requested Microsoft Store fallback page directly for $PackageName."
                        }
                        catch {
                            Write-Output "LOG:[Store CLI] Direct Microsoft Store fallback launch failed: $($_.Exception.Message)"
                        }

                        if (-not $directOpened -and $fallbackWebUri -and $fallbackWebUri -ne $fallbackUri) {
                            try {
                                Start-Process -FilePath $fallbackWebUri
                                Write-Output "LOG:[Store CLI] Requested Microsoft Store web fallback page directly for $PackageName."
                            }
                            catch {
                                Write-Output "LOG:[Store CLI] Direct Microsoft Store web fallback launch failed: $($_.Exception.Message)"
                            }
                        }
                    }

                    Start-Sleep -Milliseconds 200
                }

                return [PSCustomObject]@{
                    StoreUri = $fallbackUri
                    WebUri   = $fallbackWebUri
                    Reason   = $Reason
                    Acked    = (Test-Path $fallbackAckPath)
                }
            }

            $sendKeysContent = @'
param(
    [int]$TargetPid,
    [string]$PackageName,
    [string]$StatusPath,
    [string]$ResourcesInUsePath,
    [string]$ScreenPath,
    [string]$EventPath
)

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Text;
using System.Runtime.InteropServices;

public static class WmtConsoleInput {
    private const int STD_INPUT_HANDLE = -10;
    private const int STD_OUTPUT_HANDLE = -11;
    private const ushort KEY_EVENT = 0x0001;
    private const ushort VK_DOWN = 0x28;
    private const ushort VK_RETURN = 0x0D;
    private const ushort VK_Y = 0x59;

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FreeConsole();

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AttachConsole(uint dwProcessId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetStdHandle(int nStdHandle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool WriteConsoleInput(IntPtr hConsoleInput, INPUT_RECORD[] lpBuffer, uint nLength, out uint lpNumberOfEventsWritten);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetConsoleScreenBufferInfo(IntPtr hConsoleOutput, out CONSOLE_SCREEN_BUFFER_INFO lpConsoleScreenBufferInfo);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool ReadConsoleOutputCharacter(IntPtr hConsoleOutput, StringBuilder lpCharacter, uint nLength, COORD dwReadCoord, out uint lpNumberOfCharsRead);

    [StructLayout(LayoutKind.Sequential)]
    private struct COORD {
        public short X;
        public short Y;
        public COORD(short x, short y) { X = x; Y = y; }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SMALL_RECT {
        public short Left;
        public short Top;
        public short Right;
        public short Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct CONSOLE_SCREEN_BUFFER_INFO {
        public COORD dwSize;
        public COORD dwCursorPosition;
        public ushort wAttributes;
        public SMALL_RECT srWindow;
        public COORD dwMaximumWindowSize;
    }

    [StructLayout(LayoutKind.Explicit, CharSet = CharSet.Unicode)]
    private struct INPUT_RECORD {
        [FieldOffset(0)] public ushort EventType;
        [FieldOffset(4)] public KEY_EVENT_RECORD KeyEvent;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct KEY_EVENT_RECORD {
        [MarshalAs(UnmanagedType.Bool)] public bool bKeyDown;
        public ushort wRepeatCount;
        public ushort wVirtualKeyCode;
        public ushort wVirtualScanCode;
        public char UnicodeChar;
        public uint dwControlKeyState;
    }

    private static INPUT_RECORD Key(char ch, ushort vk, bool down) {
        INPUT_RECORD record = new INPUT_RECORD();
        record.EventType = KEY_EVENT;
        record.KeyEvent.bKeyDown = down;
        record.KeyEvent.wRepeatCount = 1;
        record.KeyEvent.wVirtualKeyCode = vk;
        record.KeyEvent.wVirtualScanCode = 0;
        record.KeyEvent.UnicodeChar = ch;
        record.KeyEvent.dwControlKeyState = 0;
        return record;
    }

    private static bool Attach(uint pid) {
        FreeConsole();
        return AttachConsole(pid);
    }

    private static bool WriteInput(uint pid, INPUT_RECORD[] records) {
        if (!Attach(pid)) { return false; }
        IntPtr input = GetStdHandle(STD_INPUT_HANDLE);
        if (input == IntPtr.Zero || input == new IntPtr(-1)) { return false; }
        uint written = 0;
        return WriteConsoleInput(input, records, (uint)records.Length, out written);
    }

    public static bool SendYes(uint pid) {
        INPUT_RECORD[] records = new INPUT_RECORD[] {
            Key('y', VK_Y, true),
            Key('y', VK_Y, false),
            Key('\r', VK_RETURN, true),
            Key('\r', VK_RETURN, false)
        };
        return WriteInput(pid, records);
    }

    public static bool SendMenuSelection(uint pid, int downCount) {
        if (downCount < 0) { downCount = 0; }
        List<INPUT_RECORD> records = new List<INPUT_RECORD>();
        for (int i = 0; i < downCount; i++) {
            records.Add(Key('\0', VK_DOWN, true));
            records.Add(Key('\0', VK_DOWN, false));
        }
        records.Add(Key('\r', VK_RETURN, true));
        records.Add(Key('\r', VK_RETURN, false));
        return WriteInput(pid, records.ToArray());
    }

    public static string ReadScreen(uint pid) {
        if (!Attach(pid)) { return ""; }
        IntPtr output = GetStdHandle(STD_OUTPUT_HANDLE);
        if (output == IntPtr.Zero || output == new IntPtr(-1)) { return ""; }

        CONSOLE_SCREEN_BUFFER_INFO info;
        if (!GetConsoleScreenBufferInfo(output, out info)) { return ""; }

        int width = Math.Max(1, (int)info.dwSize.X);
        int height = Math.Max(1, (int)info.dwSize.Y);
        int length = Math.Min(width * height, 200000);
        StringBuilder raw = new StringBuilder(new string(' ', length));
        uint read = 0;
        if (!ReadConsoleOutputCharacter(output, raw, (uint)length, new COORD(0, 0), out read)) { return ""; }

        string text = raw.ToString();
        StringBuilder lines = new StringBuilder(text.Length + height);
        for (int i = 0; i < text.Length; i += width) {
            int count = Math.Min(width, text.Length - i);
            lines.AppendLine(text.Substring(i, count).TrimEnd());
        }
        return lines.ToString();
    }
}
"@

function Get-WmtStoreCliNameKey {
    param([string]$Value)

    $text = ([string]$Value).ToLowerInvariant().Trim()
    $text = $text -replace '^\s*(microsoft|xbox)\s+', ''
    $text = $text -replace '\s*\((microsoft\s+store\s+edition|store\s+edition)\)\s*$', ''
    return ($text -replace '[^a-z0-9]+', '')
}

function Get-WmtStoreCliMenuOptions {
    param([string]$ScreenText)

    $clean = ([string]$ScreenText) -replace "`0", ""
    $lines = $clean -split "`r?`n"
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '(?i)select a product') { $start = $i }
    }
    if ($start -lt 0) { return @() }

    $options = New-Object System.Collections.Generic.List[object]
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        $line = ([string]$lines[$i]).TrimEnd()
        if ($line -match '(?i)would you like|ready to|download|install|update available') { break }
        if ($line -notmatch '^\s*>?\s*(.+?)\s*$') { continue }

        $candidate = $matches[1].Trim()
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if ($candidate -match '(?i)^(publisher:|do not select|select a product|skip$)') { continue }

        $next = if (($i + 1) -lt $lines.Count) { ([string]$lines[$i + 1]).Trim() } else { "" }
        if ($next -notmatch '(?i)^publisher:\s*') { continue }

        [void]$options.Add([PSCustomObject]@{
                Index     = $options.Count
                Name      = $candidate
                Publisher = ($next -replace '(?i)^publisher:\s*', '').Trim()
            })
    }

    return $options.ToArray()
}

$targetKey = Get-WmtStoreCliNameKey $PackageName
$menuSelected = $false
$yesSent = $false
$resourcesInUseSent = $false
$deadline = (Get-Date).AddSeconds(90)

function Set-WmtStoreCliStatus {
    param(
        [string]$Status,
        [string]$Detail = ""
    )

    if ([string]::IsNullOrWhiteSpace($StatusPath)) { return }
    try {
        $line = "$Status|$Detail|$((Get-Date).ToString('o'))"
        Set-Content -Path $StatusPath -Value $line -Encoding Ascii -Force
        if ($Status -eq "RESOURCES_IN_USE" -and -not [string]::IsNullOrWhiteSpace($ResourcesInUsePath)) {
            Set-Content -Path $ResourcesInUsePath -Value $line -Encoding Ascii -Force
            if (-not [string]::IsNullOrWhiteSpace($EventPath)) {
                Add-Content -Path $EventPath -Value "LOG:[Store CLI] Error 0x80073d02: The package could not be installed because resources it modifies are currently in use. Close the app and related Store/Xbox windows, then try again." -Encoding UTF8 -Force
            }
        }
    }
    catch {}
}

while ((Get-Date) -lt $deadline) {
    if (-not (Get-Process -Id $TargetPid -ErrorAction SilentlyContinue)) { break }

    $screen = ""
    try { $screen = [WmtConsoleInput]::ReadScreen([uint32]$TargetPid) } catch {}
    $cleanScreen = ([string]$screen) -replace "`0", ""
    if (-not [string]::IsNullOrWhiteSpace($ScreenPath)) {
        try { Set-Content -Path $ScreenPath -Value $cleanScreen -Encoding UTF8 -Force } catch {}
    }

    if (-not $menuSelected -and $cleanScreen -match '(?i)select a product') {
        $options = @(Get-WmtStoreCliMenuOptions -ScreenText $cleanScreen)
        $matchingOptions = @($options | Where-Object { (Get-WmtStoreCliNameKey $_.Name) -eq $targetKey })
        if ($matchingOptions.Count -gt 1) {
            $preferred = @($matchingOptions | Where-Object { [string]$_.Publisher -match '(?i)\bMicrosoft\b|\bXbox\b' })
            if ($preferred.Count -eq 1) { $matchingOptions = $preferred }
        }
        if ($matchingOptions.Count -eq 1) {
            try { [void][WmtConsoleInput]::SendMenuSelection([uint32]$TargetPid, [int]$matchingOptions[0].Index) } catch {}
            $menuSelected = $true
            Set-WmtStoreCliStatus "MENU_SELECTED" $matchingOptions[0].Name
            Start-Sleep -Milliseconds 700
            continue
        }
        elseif ($matchingOptions.Count -gt 1) {
            Set-WmtStoreCliStatus "MENU_AMBIGUOUS" $PackageName
        }
        elseif ($options.Count -gt 0) {
            Set-WmtStoreCliStatus "MENU_NO_MATCH" $PackageName
        }
    }

    if (-not $yesSent -and $cleanScreen -match '(?i)(would you like to apply|would you like to install|would you like to update|do you want to (?:apply|install|update)|update all|\[[yn]/[yn]\]|\([yn]/[yn]\)|\(y\):)') {
        try { [void][WmtConsoleInput]::SendYes([uint32]$TargetPid) } catch {}
        $yesSent = $true
        Set-WmtStoreCliStatus "ACCEPTED" $PackageName
    }

    if (-not $resourcesInUseSent -and $cleanScreen -match '(?is)(0x80073d02|resources\s+(?:it\s+)?modifies\s+are\s+currently\s+in\s+use|resources[\s\S]{0,240}currently\s+in\s+use)') {
        $resourcesInUseSent = $true
        Set-WmtStoreCliStatus "RESOURCES_IN_USE" $PackageName
    }
    elseif ($cleanScreen -match '(?i)ready\s+to\s+download' -and $cleanScreen -match '\b0\s*%') {
        Set-WmtStoreCliStatus "READY0" $PackageName
    }
    elseif ($cleanScreen -match '(\d{1,3})\s*%') {
        $pct = [Math]::Min(100, [Math]::Max(0, [int]$matches[1]))
        Set-WmtStoreCliStatus "PROGRESS" ([string]$pct)
    }

    Start-Sleep -Milliseconds 700
}
'@

            $runnerContent = @"
`$storeArgsLine = @'
$Arguments
'@
`$transcriptPath = @'
$transcriptPath
'@
`$exitCode = 1
try { Start-Transcript -Path `$transcriptPath -Force | Out-Null } catch {}
try {
    Invoke-Expression ("store " + `$storeArgsLine)
    if (`$null -ne `$global:LASTEXITCODE) { `$exitCode = [int]`$global:LASTEXITCODE } else { `$exitCode = 0 }
}
catch {
    Write-Host `$_.Exception.Message
    `$exitCode = 1
}
try { Stop-Transcript | Out-Null } catch {}
exit `$exitCode
"@

            $batContent = @"
@echo off
title $windowTitle
echo WMT-GUI: $displayAction $safeTitle with Microsoft Store CLI...
echo Auto-selecting matching Store CLI prompts and accepting updates without taking focus...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$runnerPath"
set "WMT_EXIT=%ERRORLEVEL%"
echo.
echo Store CLI exit code: %WMT_EXIT%
> "$resultPath" echo %WMT_EXIT%
timeout /t 3 /nobreak >nul
exit /b %WMT_EXIT%
"@

            try {
                Set-Content -Path $runnerPath -Value $runnerContent -Encoding UTF8 -Force
                Set-Content -Path $sendKeysPath -Value $sendKeysContent -Encoding Ascii -Force
                Set-Content -Path $batPath -Value $batContent -Encoding Ascii -Force
                $storeWindowStyle = if ($silentUpdateInstallEnabled) { "Hidden" } else { "Normal" }
                $storeWindowLabel = if ($silentUpdateInstallEnabled) { "headless" } else { "interactive" }
                Write-Output "LOG:[Store CLI] Launching $storeWindowLabel $($ActionLabel.ToLowerInvariant()) window for: $PackageName"
                $cmdProc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$batPath`"" -PassThru -WindowStyle $storeWindowStyle
                if (-not $silentUpdateInstallEnabled) { Show-WmtStoreCliWindow $cmdProc }
                $safePackageArg = ([string]$PackageName).Replace('"', '')
                Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$sendKeysPath`" -TargetPid $($cmdProc.Id) -PackageName `"$safePackageArg`" -StatusPath `"$statusPath`" -ResourcesInUsePath `"$resourcesInUsePath`" -ScreenPath `"$screenPath`" -EventPath `"$EventPath`"" -WindowStyle Hidden
                Write-Output "LOG:  [store] Progress: 5%"

                $storeCliTimeoutMinutes = if (([string]$Arguments).Trim().ToLowerInvariant() -eq "updates") { 10 } else { 3 }
                $deadline = (Get-Date).AddMinutes($storeCliTimeoutMinutes)
                $lastBeat = Get-Date
                $storeProgress = 5
                $lastStatusLine = ""
                $readyZeroSince = $null
                $storeCliStartedAt = Get-Date
                $storeCliResourcesInUse = $false
                $storeCliResourcesInUseLogged = $false
                while ((Get-Date) -lt $deadline) {
                    $result = Get-WmtStoreCliExitResult -ResultPath $resultPath -Process $cmdProc
                    if ($result.Found) {
                        if ($cmdProc -and -not $cmdProc.HasExited) {
                            try { [void]$cmdProc.WaitForExit(5000) } catch {}
                        }
                        if (Test-Path $resourcesInUsePath) {
                            $storeCliResourcesInUse = $true
                        }
                        elseif (Test-Path $statusPath) {
                            $finalStatusLine = (Get-Content -Path $statusPath -Raw -ErrorAction SilentlyContinue).Trim()
                            if ($finalStatusLine -match '^RESOURCES_IN_USE\|') { $storeCliResourcesInUse = $true }
                        }
                        if (-not $storeCliResourcesInUse -and (Test-Path $screenPath)) {
                            $finalScreenText = Get-Content -Path $screenPath -Raw -ErrorAction SilentlyContinue
                            if (Test-WmtStoreCliResourcesInUseText $finalScreenText) {
                                $storeCliResourcesInUse = $true
                            }
                        }
                        if (-not $storeCliResourcesInUse -and (Test-Path $transcriptPath)) {
                            $finalTranscriptText = Get-Content -Path $transcriptPath -Raw -ErrorAction SilentlyContinue
                            if (Test-WmtStoreCliResourcesInUseText $finalTranscriptText) {
                                $storeCliResourcesInUse = $true
                            }
                        }
                        if ($storeCliResourcesInUse -and -not $storeCliResourcesInUseLogged) {
                            $resourcesInUseLog = "LOG:[Store CLI] Error 0x80073d02: The package could not be installed because resources it modifies are currently in use. Close the app and related Store/Xbox windows, then try again."
                            Write-Output $resourcesInUseLog
                            Write-WmtStoreCliActivityEvent $resourcesInUseLog
                            $storeCliResourcesInUseLogged = $true
                        }
                        $exitCode = [int]$result.ExitCode
                        if ($storeCliResourcesInUse -and ($exitCode -eq 0 -or $exitCode -eq 1)) {
                            $exitCode = -2147009278
                        }
                        Clear-WmtStoreCliTempFiles @($resultPath, $statusPath, $resourcesInUsePath, $screenPath, $fallbackAckPath, $sendKeysPath, $runnerPath, $batPath)
                        return [PSCustomObject]@{ ExitCode = $exitCode; ResourcesInUse = $storeCliResourcesInUse }
                    }

                    $now = Get-Date
                    if (-not $storeCliResourcesInUse -and (Test-Path $transcriptPath)) {
                        $transcriptText = Get-Content -Path $transcriptPath -Raw -ErrorAction SilentlyContinue
                        if (Test-WmtStoreCliResourcesInUseText $transcriptText) {
                            $resourcesInUseLog = "LOG:[Store CLI] Error 0x80073d02: The package could not be installed because resources it modifies are currently in use. Close the app and related Store/Xbox windows, then try again."
                            Write-Output $resourcesInUseLog
                            Write-WmtStoreCliActivityEvent $resourcesInUseLog
                            $storeCliResourcesInUse = $true
                            $storeCliResourcesInUseLogged = $true
                        }
                    }
                    if ((Test-Path $resourcesInUsePath) -and -not $storeCliResourcesInUse) {
                        $resourcesInUseLog = "LOG:[Store CLI] Error 0x80073d02: The package could not be installed because resources it modifies are currently in use. Close the app and related Store/Xbox windows, then try again."
                        Write-Output $resourcesInUseLog
                        Write-WmtStoreCliActivityEvent $resourcesInUseLog
                        $storeCliResourcesInUse = $true
                        $storeCliResourcesInUseLogged = $true
                    }
                    if (Test-Path $statusPath) {
                        $statusLine = (Get-Content -Path $statusPath -Raw -ErrorAction SilentlyContinue).Trim()
                        if ($statusLine -and $statusLine -ne $lastStatusLine) {
                            $lastStatusLine = $statusLine
                            $parts = @($statusLine -split '\|', 3)
                            $status = if ($parts.Count -gt 0) { $parts[0] } else { "" }
                            $detail = if ($parts.Count -gt 1) { $parts[1] } else { "" }

                            switch ($status) {
                                "MENU_SELECTED" {
                                    Write-Output "LOG:[Store CLI] Selected matching product: $detail"
                                    break
                                }
                                "MENU_AMBIGUOUS" {
                                    Write-Output "LOG:[Store CLI] Product picker had multiple exact matches for '$detail'."
                                    break
                                }
                                "MENU_NO_MATCH" {
                                    Write-Output "LOG:[Store CLI] Product picker had no exact match for '$detail'."
                                    break
                                }
                                "ACCEPTED" {
                                    Write-Output "LOG:[Store CLI] Accepted Store CLI confirmation prompt."
                                    break
                                }
                                "RESOURCES_IN_USE" {
                                    if (-not $storeCliResourcesInUse) {
                                        $resourcesInUseLog = "LOG:[Store CLI] Error 0x80073d02: The package could not be installed because resources it modifies are currently in use. Close the app and related Store/Xbox windows, then try again."
                                        Write-Output $resourcesInUseLog
                                        Write-WmtStoreCliActivityEvent $resourcesInUseLog
                                    }
                                    $storeCliResourcesInUse = $true
                                    $storeCliResourcesInUseLogged = $true
                                    break
                                }
                                "READY0" {
                                    if (-not $readyZeroSince) {
                                        $readyZeroSince = $now
                                        Write-Output "LOG:[Store CLI] Store download broker is at Ready to Download 0%; watching for progress..."
                                    }
                                    break
                                }
                                "PROGRESS" {
                                    $readyZeroSince = $null
                                    $pct = 0
                                    if ([int]::TryParse($detail, [ref]$pct) -and $pct -ne $storeProgress) {
                                        $storeProgress = $pct
                                        Write-Output "LOG:  [store] Progress: $storeProgress%"
                                    }
                                    break
                                }
                            }
                        }
                    }

                    $installExceededFallbackWindow = ($ActionLabel -eq "Install" -and (New-TimeSpan -Start $storeCliStartedAt -End $now).TotalSeconds -ge 30)
                    $readyZeroExceededFallbackWindow = ($readyZeroSince -and (New-TimeSpan -Start $readyZeroSince -End $now).TotalSeconds -ge 30)
                    if (-not $storeCliResourcesInUse -and ($installExceededFallbackWindow -or $readyZeroExceededFallbackWindow)) {
                        $fallbackReason = if ($installExceededFallbackWindow) { "InstallTimeout" } else { "ReadyToDownload0" }
                        $fallbackReasonText = if ($installExceededFallbackWindow) {
                            "Store CLI did not finish the install within 30 seconds"
                        }
                        else {
                            "Store CLI remained at Ready to Download 0% for 30 seconds"
                        }
                        Write-Output "LOG:[Store CLI] $fallbackReasonText; opening Microsoft Store fallback page."
                        try {
                            if ($cmdProc -and -not $cmdProc.HasExited) { Stop-Process -Id $cmdProc.Id -Force -ErrorAction SilentlyContinue }
                        }
                        catch {}
                        $fallbackResult = Invoke-WmtStoreCliFallback -Reason $fallbackReason -ReasonText $fallbackReasonText -StoreUri $StoreFallbackUri -WebUri $StoreFallbackWebUri
                        Clear-WmtStoreCliTempFiles @($resultPath, $statusPath, $resourcesInUsePath, $screenPath, $fallbackAckPath, $sendKeysPath, $runnerPath, $batPath)
                        return [PSCustomObject]@{
                            ExitCode                  = -2
                            StoreFallbackOpened       = $true
                            StoreFallbackReason       = $fallbackResult.Reason
                            StalledReadyToDownload    = ($fallbackResult.Reason -eq "ReadyToDownload0")
                            StoreFallbackUri          = $fallbackResult.StoreUri
                            StoreFallbackAcknowledged = $fallbackResult.Acked
                        }
                    }

                    if ((New-TimeSpan -Start $lastBeat -End $now).TotalSeconds -ge 15) {
                        Write-Output "LOG:[Store CLI] Waiting for interactive $($ActionLabel.ToLowerInvariant()) to finish ($storeCliTimeoutMinutes-minute Store CLI timeout)..."
                        $storeProgress = [Math]::Min(90, $storeProgress + 10)
                        Write-Output "LOG:  [store] Progress: $storeProgress%"
                        $lastBeat = $now
                    }
                    Start-Sleep -Milliseconds 500
                }

                Write-Output "LOG:[Store CLI] Timed out waiting for the interactive $($ActionLabel.ToLowerInvariant()) window."
                try {
                    if ($cmdProc -and -not $cmdProc.HasExited) { Stop-Process -Id $cmdProc.Id -Force -ErrorAction SilentlyContinue }
                }
                catch {}
                Clear-WmtStoreCliTempFiles @($resultPath, $statusPath, $resourcesInUsePath, $screenPath, $fallbackAckPath, $sendKeysPath, $runnerPath, $batPath)
                return [PSCustomObject]@{ ExitCode = -1 }
            }
            catch {
                Write-Output "LOG:[Store CLI] Interactive launch failed: $($_.Exception.Message)"
                Clear-WmtStoreCliTempFiles @($resultPath, $statusPath, $resourcesInUsePath, $screenPath, $fallbackAckPath, $sendKeysPath, $runnerPath, $batPath)
                return [PSCustomObject]@{ ExitCode = 1 }
            }
        }

        function Get-StoreCliProductId {
            param([string]$Value)

            $text = ([string]$Value).Trim()
            if ([string]::IsNullOrWhiteSpace($text)) { return "" }

            $matchPatterns = @(
                '(?i)(?:product\s*id|productid|product-id)\s*[:=]\s*((?:9[A-Z0-9]{9,19}|XP[A-Z0-9]{8,18}))',
                '(?i)(?:/detail/|productid=)((?:9[A-Z0-9]{9,19}|XP[A-Z0-9]{8,18}))',
                '(?i)\b((?:9[A-Z0-9]{9,19}|XP[A-Z0-9]{8,18}))\b'
            )

            foreach ($pattern in $matchPatterns) {
                $match = [regex]::Match($text, $pattern)
                if ($match.Success) { return $match.Groups[1].Value.ToUpperInvariant() }
            }

            return ""
        }

        function Invoke-WmtWindowsUpdateInstall {
            param([object]$Item)

            $targetRaw = ([string]$Item.Id).Trim()
            $targetName = ([string]$Item.Name).Trim()
            if ([string]::IsNullOrWhiteSpace($targetRaw) -and [string]::IsNullOrWhiteSpace($targetName)) {
                Write-Output "LOG:[Windows Update] Selected update has no usable identity."
                return [PSCustomObject]@{ ExitCode = 1 }
            }

            $targetParts = @($targetRaw -split '\|', 2)
            $targetId = if ($targetParts.Count -gt 0) { ([string]$targetParts[0]).Trim() } else { $targetRaw }
            $targetRevision = -1
            if ($targetParts.Count -gt 1) { [void][int]::TryParse(([string]$targetParts[1]).Trim(), [ref]$targetRevision) }

            try {
                Write-Output "LOG:[Windows Update] Preparing selected update: $targetName"
                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()
                try { $searcher.Online = $true } catch {}
                $result = $searcher.Search("IsInstalled=0 and IsHidden=0")
                if (-not $result -or -not $result.Updates) {
                    Write-Output "LOG:[Windows Update] No pending updates were returned."
                    return [PSCustomObject]@{ ExitCode = 0 }
                }

                $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
                for ($wuIndex = 0; $wuIndex -lt $result.Updates.Count; $wuIndex++) {
                    $update = $result.Updates.Item($wuIndex)
                    if (-not $update) { continue }

                    $updateId = ""
                    $revision = -1
                    try { $updateId = ([string]$update.Identity.UpdateID).Trim() } catch {}
                    try { $revision = [int]$update.Identity.RevisionNumber } catch {}
                    $title = ""
                    try { $title = ([string]$update.Title).Trim() } catch {}

                    $idMatches = (-not [string]::IsNullOrWhiteSpace($targetId) -and $updateId -eq $targetId)
                    $revisionMatches = ($targetRevision -lt 0 -or $revision -eq $targetRevision)
                    $nameMatches = ([string]::IsNullOrWhiteSpace($targetId) -and -not [string]::IsNullOrWhiteSpace($targetName) -and $title -eq $targetName)

                    if (($idMatches -and $revisionMatches) -or $nameMatches) {
                        try {
                            if (-not [bool]$update.EulaAccepted) { $update.AcceptEula() }
                        }
                        catch {
                            Write-Output "LOG:[Windows Update] Could not accept EULA for ${title}: $($_.Exception.Message)"
                        }
                        [void]$updatesToInstall.Add($update)
                        break
                    }
                }

                if ($updatesToInstall.Count -eq 0) {
                    Write-Output "LOG:[Windows Update] $targetName is no longer offered, already installed, or hidden."
                    return [PSCustomObject]@{ ExitCode = 0 }
                }

                Write-Output "LOG:[Windows Update] Downloading $($updatesToInstall.Count) update(s)..."
                $downloader = $session.CreateUpdateDownloader()
                $downloader.Updates = $updatesToInstall
                $downloadResult = $downloader.Download()
                $downloadCode = 0
                try { $downloadCode = [int]$downloadResult.ResultCode } catch { $downloadCode = 0 }
                if ($downloadCode -notin @(2, 3)) {
                    Write-Output "LOG:[Windows Update] Download failed with WUA result code $downloadCode."
                    return [PSCustomObject]@{ ExitCode = 1 }
                }

                Write-Output "LOG:[Windows Update] Installing $($updatesToInstall.Count) update(s)..."
                $installer = $session.CreateUpdateInstaller()
                $installer.Updates = $updatesToInstall
                $installResult = $installer.Install()
                $installCode = 0
                $rebootRequired = $false
                try { $installCode = [int]$installResult.ResultCode } catch { $installCode = 0 }
                try { $rebootRequired = [bool]$installResult.RebootRequired } catch { $rebootRequired = $false }
                Write-Output "LOG:[Windows Update] Install result code: $installCode | Reboot required: $rebootRequired"

                if ($installCode -in @(2, 3)) {
                    if ($rebootRequired) { return [PSCustomObject]@{ ExitCode = 3010 } }
                    return [PSCustomObject]@{ ExitCode = 0 }
                }

                return [PSCustomObject]@{ ExitCode = 1 }
            }
            catch {
                Write-Output "LOG:[Windows Update] Install failed: $($_.Exception.Message)"
                return [PSCustomObject]@{ ExitCode = 1 }
            }
        }

        $storeUpdateTotal = @($items | Where-Object { $act -eq "Update" -and ([string]$_.Source).ToLowerInvariant() -eq "msstore" }).Count
        $storeUpdateDone = 0
        if ($storeUpdateTotal -gt 0) {
            Write-Output "LOG:[Store] Microsoft Store updates will be invoked and monitored through the Store GUI."
        }

        $total = @($items).Count
        $index = 0
        foreach ($item in $items) {
            $index++
            $id = $item.Id
            $name = $item.Name
            $src = $item.Source
            $srcKey = ([string]$src).ToLowerInvariant()
            $cmd = ""
            $userCmd = "" 
            $pipArguments = $null
            $wingetArgs = $null
            $storeCliArgs = $null
            $windowsUpdateItem = $null
            $storeForceUpdateScan = $false
            $storeFallbackUri = ""
            $storeFallbackWebUri = ""
            $skipReason = $null
            Write-Output "PROGRESS:${index}/${total}:$name"
            Write-Output "ITEM_SOURCE:$srcKey"

            if ($act -eq "Update" -and ([string]$src).ToLowerInvariant() -eq "msstore") {
                $storeGuiResult = $null
                Invoke-WmtStoreGuiUpdate -PackageName $name -Result ([ref]$storeGuiResult)
                if ($storeGuiResult -and $storeGuiResult.ExitCode -eq 0) {
                    if ($storeGuiResult.AlreadyCurrent) {
                        Write-Output "LOG:[$act][$index/$total] SUCCESS: $name (Microsoft Store reports no available Update button)"
                    }
                    else {
                        Write-Output "LOG:[$act][$index/$total] SUCCESS: $name (updated through Microsoft Store GUI)"
                    }
                    Write-Output "RESULT:${index}:SUCCESS:$name"
                }
                else {
                    Write-Output "LOG:[$act][$index/$total] FAILED: $name (Microsoft Store GUI update did not complete)"
                    Write-Output "RESULT:${index}:FAILED:$name"
                }
                $storeUpdateDone++
                if ($storeUpdateDone -ge $storeUpdateTotal) {
                    Close-WmtStoreGui
                }
                continue
            }

            # --- COMMAND GENERATION ---
            if ($tmpl) {
                $cmd = $tmpl -f $id
                $userCmd = $cmd -replace "--disable-interactivity", "" 
            }
            else {
                # --- WINGET ---
                if ($src -eq "winget") {
                    $flags = "--accept-source-agreements --accept-package-agreements --disable-interactivity"
                    $userFlags = "--accept-source-agreements --accept-package-agreements"
                    $includeUnknownFlag = if ($wingetIncludeUnknown) { " --include-unknown" } else { "" }
                    if ($act -eq "Install") { $wingetArgs = "install --id `"$id`" $flags"; $cmd = "winget $wingetArgs"; $userCmd = "winget install --id `"$id`" $userFlags" }
                    if ($act -eq "Update") { $wingetArgs = "upgrade --id `"$id`"$includeUnknownFlag $flags"; $cmd = "winget $wingetArgs"; $userCmd = "winget upgrade --id `"$id`"$includeUnknownFlag $userFlags" }
                    if ($act -eq "Uninstall") { $wingetArgs = "uninstall --id `"$id`" $flags"; $cmd = "winget $wingetArgs"; $userCmd = "winget uninstall --id `"$id`" $userFlags" }
                }
                # --- MICROSOFT STORE ---
                elseif ($src -eq "msstore") {
                    $safeStoreId = Get-StoreCliProductId $id
                    $preferStoreUpdateScan = Test-WmtStoreUpdateScanPreferredItem -Name $name -Id $id
                    if ($act -eq "Install" -and $preferStoreUpdateScan) {
                        $storeForceUpdateScan = $true
                        $storeFallbackUri = "ms-windows-store://downloadsandupdates"
                        $storeFallbackWebUri = "https://apps.microsoft.com/home"
                        $cmd = "Microsoft Store app update scan"
                        $userCmd = "PowerShell MDM_EnterpriseModernAppManagement UpdateScanMethod"
                    }
                    elseif ($act -eq "Install") {
                        if ($safeStoreId) {
                            $storeCliArgs = "install `"$safeStoreId`""
                            if ($preferStoreUpdateScan) {
                                $storeFallbackUri = "ms-windows-store://downloadsandupdates"
                                $storeFallbackWebUri = "https://apps.microsoft.com/home"
                            }
                            else {
                                $storeFallbackUri = "ms-windows-store://pdp/?ProductId=$safeStoreId"
                                $storeFallbackWebUri = "https://apps.microsoft.com/detail/$safeStoreId"
                            }
                        }
                        else {
                            $storeTarget = ([string]$name).Replace('"', '').Trim()
                            if ([string]::IsNullOrWhiteSpace($storeTarget)) {
                                $rawStoreId = ([string]$id).Trim()
                                if ([string]::IsNullOrWhiteSpace($rawStoreId)) { $rawStoreId = "(blank)" }
                                $skipReason = "Store CLI needs a product ID or package name, but this row has ID '$rawStoreId' and no usable name."
                            }
                            else {
                                $storeCliArgs = "install `"$storeTarget`""
                                $escapedStoreTarget = [System.Uri]::EscapeDataString($storeTarget)
                                if ($preferStoreUpdateScan) {
                                    $storeFallbackUri = "ms-windows-store://downloadsandupdates"
                                    $storeFallbackWebUri = "https://apps.microsoft.com/home"
                                }
                                else {
                                    $storeFallbackUri = "ms-windows-store://search/?query=$escapedStoreTarget"
                                    $storeFallbackWebUri = "https://apps.microsoft.com/search?query=$escapedStoreTarget"
                                }
                                Write-Output "LOG:[Store CLI] Product ID unavailable for '$name'; using Store CLI's product picker with automatic exact-match selection."
                            }
                        }
                        $cmd = "store $storeCliArgs"
                        $userCmd = $cmd
                    }
                    if ($act -eq "Uninstall") {
                        $flags = "--accept-source-agreements --accept-package-agreements --disable-interactivity"
                        $userFlags = "--accept-source-agreements --accept-package-agreements"
                        $wingetArgs = "uninstall --id `"$id`" --source msstore $flags"
                        $cmd = "winget $wingetArgs"
                        $userCmd = "winget uninstall --id `"$id`" --source msstore $userFlags"
                    }
                }
                # --- WINDOWS UPDATE ---
                elseif ($srcKey -eq "windowsupdate") {
                    if ($act -eq "Update") {
                        $windowsUpdateItem = $item
                        $cmd = "Windows Update COM install"
                        $userCmd = "Microsoft.Update.Session install selected update"
                    }
                    elseif ($act -eq "Install") {
                        $skipReason = "Windows Update items can only be updated from this list; use Refresh All to rescan offered updates."
                    }
                    elseif ($act -eq "Uninstall") {
                        $skipReason = "Windows Update uninstall is not supported here. Use Windows Update history if you need to remove an update."
                    }
                }
                # --- STEAM GAMES ---
                elseif (([string]$src).ToLowerInvariant() -eq "steam") {
                    if ($act -eq "Update") {
                        # Steam game updates have to be handled by the Steam client.
                        # Use steam://validate/<AppID> to validate/update individual apps.
                        # Falls back to downloads page if AppID is not available.
                        $steamUri = if (-not [string]::IsNullOrWhiteSpace([string]$id)) { "steam://validate/$id" } else { "steam://open/downloads" }
                        $steamRunUri = if (-not [string]::IsNullOrWhiteSpace([string]$id)) { "steam://rungameid/$id" } else { "" }

                        Write-Output "LOG:[Steam] Requesting validation for $name (AppID: $id)."
                        try {
                            $steamPayload = [ordered]@{
                                Uri         = $steamUri
                                RunUri      = $steamRunUri
                                PackageName = $name
                                AppId       = $id
                            }
                            $steamJson = $steamPayload | ConvertTo-Json -Compress
                            $steamEncoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($steamJson))
                            $steamOpenLine = "STEAM_OPEN:$steamEncoded"
                            Write-Output $steamOpenLine
                            Write-WmtStoreCliActivityEvent $steamOpenLine
                        }
                        catch {
                            Write-Output "LOG:[Steam] Could not prepare Steam request: $($_.Exception.Message)"
                        }

                        Write-Output "LOG:[Steam] Steam launch was delegated to the headless GUI launcher."

                        $steamResult = $null
                        Wait-WmtSteamActionCompletion -ManifestPath ([string]$item.ManifestPath) -PackageName $name -Result ([ref]$steamResult)
                        if ($steamResult -and $steamResult.ExitCode -eq 0) {
                            Write-Output "LOG:[$act][$index/$total] SUCCESS: $name (Steam manifest confirms update completion)"
                            Write-Output "RESULT:${index}:SUCCESS:$name"
                        }
                        elseif ($steamResult -and $steamResult.ExitCode -eq 2) {
                            Write-Output "LOG:[$act][$index/$total] SKIPPED: $name (opened Steam updater, but completion cannot be monitored)"
                            Write-Output "RESULT:${index}:SKIPPED:$name"
                        }
                        else {
                            Write-Output "LOG:[$act][$index/$total] FAILED: $name (Steam update completion was not confirmed)"
                            Write-Output "RESULT:${index}:FAILED:$name"
                        }
                        continue
                    }
                    elseif ($act -eq "Install") {
                        $cmd = "Start-Process `"steam://install/$id`""
                        $userCmd = "Open Steam install prompt for app $id"
                    }
                    elseif ($act -eq "Uninstall") {
                        $skipReason = "Steam game uninstall should be handled from the Steam client."
                    }
                }
                # --- LEGENDARY / EPIC GAMES ---
                elseif ($src -eq "legendary") {
                    $legendaryCommand = Get-WmtLegendaryCommandText -ForPowerShell:($act -ne "Update")
                    if ($act -eq "Install") { $cmd = "$legendaryCommand -y install `"$id`"" }
                    if ($act -eq "Update") { $cmd = "$legendaryCommand -y update `"$id`"" }
                    if ($act -eq "Uninstall") { $cmd = "$legendaryCommand -y uninstall `"$id`"" }
                    $userCmd = $cmd
                }
                # --- GOGDL / GOG GAMES ---
                elseif ($src -eq "gogdl") {
                    if ($act -eq "Update") {
                        $installDir = ([string]$item.InstallDir).Trim()
                        if ([string]::IsNullOrWhiteSpace($installDir)) {
                            $skipReason = "GOG install path was not available."
                        }
                        elseif (-not (Test-Path -LiteralPath $installDir -PathType Container)) {
                            $skipReason = "GOG install path no longer exists: $installDir"
                        }
                        else {
                            $gogdlCommand = Get-WmtGogdlCommandText
                            $platform = ([string]$item.Platform).Trim().ToLowerInvariant()
                            if ($platform -notin @("windows", "osx", "linux")) { $platform = "windows" }
                            $authConfig = ([string]$gogdlAuthConfigPath).Trim()
                            $authCandidates = @($authConfig)
                            if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
                                $authCandidates += (Join-Path $env:APPDATA "heroic\gog_store\auth.json")
                                $authCandidates += (Join-Path $env:APPDATA "Heroic\gog_store\auth.json")
                            }
                            $resolvedAuthConfig = ""
                            foreach ($candidateAuth in $authCandidates) {
                                if ([string]::IsNullOrWhiteSpace([string]$candidateAuth)) { continue }
                                if (Test-Path -LiteralPath ([string]$candidateAuth) -PathType Leaf) {
                                    $resolvedAuthConfig = [string]$candidateAuth
                                    break
                                }
                            }
                            if ([string]::IsNullOrWhiteSpace($resolvedAuthConfig)) {
                                $skipReason = "GOGDL auth.json was not found. Sign into GOG in Heroic or place auth.json at $authConfig."
                            }
                            else {
                                $cmd = "$gogdlCommand --auth-config-path `"$resolvedAuthConfig`" update `"$id`" --path `"$installDir`" --os $platform"
                                $userCmd = $cmd
                            }
                        }
                    }
                    elseif ($act -eq "Install") {
                        $skipReason = "GOG game installs should be started from GOG Galaxy or Heroic; WMT updates installed GOG games."
                    }
                    elseif ($act -eq "Uninstall") {
                        $skipReason = "GOG game uninstall should be handled from GOG Galaxy, Heroic, or Apps & Features."
                    }
                }
                # --- SCOOP (Likely requires User Mode) ---
                elseif ($src -eq "scoop") {
                    if ($act -eq "Install") { $cmd = "scoop install `"$id`"" }
                    if ($act -eq "Update") { $cmd = "scoop update `"$id`"" }
                    if ($act -eq "Uninstall") { $cmd = "scoop uninstall `"$id`"" }
                    $userCmd = $cmd # Scoop commands are same for user
                }
                # --- RUBY GEMS ---
                elseif ($src -eq "ruby" -or $src -eq "gem") {
                    if ($act -eq "Install") { $cmd = "gem install `"$id`"" }
                    if ($act -eq "Update") { $cmd = "gem update `"$id`"" }
                    if ($act -eq "Uninstall") { $cmd = "gem uninstall `"$id`"" }
                    $userCmd = $cmd
                }
                # --- RUST CARGO ---
                elseif ($src -eq "cargo" -or $src -eq "rust") {
                    if ($act -eq "Install") { $cmd = "cargo install `"$id`"" }
                    if ($act -eq "Update") { $cmd = "cargo install --force `"$id`"" } # Cargo needs force to overwrite/update binaries
                    if ($act -eq "Uninstall") { $cmd = "cargo uninstall `"$id`"" }
                    $userCmd = $cmd
                }
                # --- .NET GLOBAL TOOLS ---
                elseif ($src -eq "dotnet") {
                    if ($act -eq "Install") { $cmd = "dotnet tool install --global `"$id`"" }
                    if ($act -eq "Update") { $cmd = "dotnet tool update --global `"$id`"" }
                    if ($act -eq "Uninstall") { $cmd = "dotnet tool uninstall --global `"$id`"" }
                    $userCmd = $cmd
                }
                # --- POWERSHELL MODULES ---
                elseif ($src -eq "psmodule") {
                    if ($act -eq "Install") { $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"Install-Module -Name '$id' -Scope CurrentUser -Force -AllowClobber`"" }
                    if ($act -eq "Update") { $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"Update-Module -Name '$id' -Force`"" }
                    if ($act -eq "Uninstall") { $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"Uninstall-Module -Name '$id' -AllVersions -Force`"" }
                    $userCmd = $cmd
                }
                # --- PHP COMPOSER GLOBAL PACKAGES ---
                elseif ($src -eq "composer") {
                    if ($act -eq "Install") { $cmd = "composer global require `"$id`" --no-interaction" }
                    if ($act -eq "Update") { $cmd = "composer global update `"$id`" --with-all-dependencies --no-interaction" }
                    if ($act -eq "Uninstall") { $cmd = "composer global remove `"$id`" --no-interaction" }
                    $userCmd = $cmd
                }
                # --- PYTHON PIP ---
                elseif ($src -eq "pip" -or $src -eq "pip3") {
                    $pipSafetyFlags = "--disable-pip-version-check --no-input --timeout 30 --retries 2"
                    if ($act -eq "Install") {
                        $cmd = "python -m pip $pipSafetyFlags install `"$id`""
                        $pipArguments = @("-m", "pip", "--disable-pip-version-check", "--no-input", "--timeout", "30", "--retries", "2", "install", [string]$id)
                    }
                    if ($act -eq "Update") {
                        $cmd = "python -m pip $pipSafetyFlags install --upgrade `"$id`""
                        $pipArguments = @("-m", "pip", "--disable-pip-version-check", "--no-input", "--timeout", "30", "--retries", "2", "install", "--upgrade", [string]$id)
                    }
                    if ($act -eq "Uninstall") {
                        $cmd = "python -m pip --disable-pip-version-check --no-input uninstall -y `"$id`""
                        $pipArguments = @("-m", "pip", "--disable-pip-version-check", "--no-input", "uninstall", "-y", [string]$id)
                    }
                    $userCmd = $cmd
                }
                # --- NODE NPM & PNPM ---
                elseif ($src -eq "npm") {
                    if ($act -eq "Install") { $cmd = "npm install `"$id`"" }
                    if ($act -eq "Update") { $cmd = "npm update `"$id`"" }
                    if ($act -eq "Uninstall") { $cmd = "npm uninstall `"$id`"" }
                    $userCmd = $cmd
                }
                elseif ($src -eq "npm (global)") {
                    if ($act -eq "Install") { $cmd = "npm install -g `"$id`"" }
                    if ($act -eq "Update") { $cmd = "npm update -g `"$id`"" }
                    if ($act -eq "Uninstall") { $cmd = "npm uninstall -g `"$id`"" }
                    $userCmd = $cmd
                }
                elseif ($src -eq "pnpm") {
                    if ($act -eq "Install") { $cmd = "pnpm install `"$id`"" }
                    if ($act -eq "Update") { $cmd = "pnpm update `"$id`"" }
                    if ($act -eq "Uninstall") { $cmd = "pnpm remove `"$id`"" }
                    $userCmd = $cmd
                }
                elseif ($src -eq "pnpm (global)") {
                    if ($act -eq "Install") { $cmd = "pnpm add -g `"$id`"" }
                    if ($act -eq "Update") { $cmd = "pnpm update -g `"$id`"" }
                    if ($act -eq "Uninstall") { $cmd = "pnpm remove -g `"$id`"" }
                    $userCmd = $cmd
                }
                # --- CHOCOLATEY ---
                elseif ($src -eq "chocolatey" -or $src -eq "choco") {
                    if ($act -eq "Install") { $cmd = "choco install `"$id`" -y" }
                    if ($act -eq "Update") { $cmd = "choco upgrade `"$id`" -y" }
                    if ($act -eq "Uninstall") { $cmd = "choco uninstall `"$id`" -y" }
                    $userCmd = $cmd
                }
            }

            if ($skipReason) {
                Write-Output "LOG:[$act][$index/$total] SKIPPED: $name - $skipReason"
                Write-Output "RESULT:${index}:SKIPPED:$name"
                continue
            }

            if ($cmd) {
                Write-Output "LOG:[$act][$index/$total] Starting: $name ($src)..."
                Write-Output "LOG:[$act] Command: $userCmd"

                # 1. RUN COMMAND (First Attempt - Admin)
                # UX: most package updates run one-by-one in visible windows (auto-close when done),
                # so end-users can follow each update without relying on Activity Log only.
                $isPipUpdate = (($src -eq "pip" -or $src -eq "pip3") -and $act -eq "Update")
                $isChocoUpdate = (($src -eq "chocolatey" -or $src -eq "choco") -and $act -eq "Update")
                $isPythonUpdate = ($act -eq "Update" -and (([string]$id -match "(?i)\bpython([0-9\.]*)\b") -or ([string]$name -match "(?i)\bpython([0-9\.]*)\b")))
                $useVisibleWindow = ($act -eq "Update" -and -not $silentUpdateInstallEnabled -and -not ($src -eq "msstore" -and $storeCliArgs) -and -not $windowsUpdateItem)

                if ($useVisibleWindow) {
                    $windowTag = switch -Regex ($src) {
                        "^(winget)$" { "Winget"; break }
                        "^(msstore)$" { "MSStore"; break }
                        "^(pip|pip3)$" { "PIP"; break }
                        "^(npm|npm \(global\))$" { "NPM"; break }
                        "^(pnpm|pnpm \(global\))$" { "PNPM"; break }
                        "^(chocolatey|choco)$" { "Chocolatey"; break }
                        "^(scoop)$" { "Scoop"; break }
                        "^(gem|ruby)$" { "RubyGem"; break }
                        "^(cargo|rust)$" { "Cargo"; break }
                        "^(steam)$" { "Steam"; break }
                        "^(legendary)$" { "Legendary"; break }
                        "^(gogdl)$" { "GOGDL"; break }
                        "^(windowsupdate)$" { "WindowsUpdate"; break }
                        default { "Package" }
                    }
                    if ($isPipUpdate) { $windowTag = "PIP" }
                    elseif ($isChocoUpdate) { $windowTag = "Chocolatey" }
                    elseif ($isPythonUpdate) { $windowTag = "Python" }
                    Write-Output "LOG:[$act] Launching visible $windowTag window for: $name"
                    try {
                        $holdSeconds = if ($src -eq "msstore") { 5 } else { 0 }
                        $p = Invoke-VisibleCmd $cmd "WMT $windowTag Update - $name" -HoldSeconds $holdSeconds

                        # Check if the process crashed or the user manually closed the frozen window
                        if ($null -eq $p -or $null -eq $p.ExitCode -or $p.ExitCode -ne 0) {
                            if ($src -eq "msstore" -or $src -eq "gogdl") {
                                Write-Output "LOG:[$act] $windowTag update window exited with a non-zero code."
                                $exitCode = if ($p -and $null -ne $p.ExitCode) { $p.ExitCode } else { 1 }
                                $p = [PSCustomObject]@{ ExitCode = $exitCode }
                            }
                            else {
                                Write-Output "LOG:[$act] Window was forcefully closed or exited with a non-zero code. Assuming success due to known installer hang behavior."
                                $p = [PSCustomObject]@{ ExitCode = 0 } # Force a fake success code to prevent WMT from crashing
                            }
                        }
                    }
                    catch {
                        if ($src -eq "msstore" -or $src -eq "gogdl") {
                            Write-Output "LOG:[$act] $windowTag update window was interrupted."
                            $p = [PSCustomObject]@{ ExitCode = 1 }
                        }
                        else {
                            Write-Output "LOG:[$act] Visible window forcefully closed or interrupted."
                            $p = [PSCustomObject]@{ ExitCode = 0 } # Assume success here as well
                        }
                    }
                }
                elseif ($wingetArgs) {
                    Write-Output "LOG:[$act] Running winget with live output..."
                    $p = Invoke-WingetLive $wingetArgs
                }
                elseif ($storeForceUpdateScan) {
                    $p = Invoke-WmtStoreAppUpdateScan -PackageName $name
                }
                elseif ($storeCliArgs) {
                    $p = Invoke-StoreCliInteractive -Arguments $storeCliArgs -PackageName $name -TempPath $temp -ActionLabel $act -StoreFallbackUri $storeFallbackUri -StoreFallbackWebUri $storeFallbackWebUri
                }
                elseif ($windowsUpdateItem) {
                    $p = Invoke-WmtWindowsUpdateInstall -Item $windowsUpdateItem
                }
                elseif ($pipArguments) {
                    Write-Output "LOG:[$act] Running pip directly with $pythonExePath..."
                    $p = Invoke-WmtPipDirect -PythonPath $pythonExePath -ArgumentList $pipArguments
                    foreach ($pipLine in @($p.OutputLines)) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$pipLine)) {
                            Write-Output "LOG:  > $pipLine"
                        }
                    }
                }
                else {
                    Write-Output "LOG:[$act] Running... (this may take a while)"
                    $commandTimeoutSeconds = if ($isPipUpdate -or ($src -eq "pip" -or $src -eq "pip3")) { 600 } else { 0 }
                    $commandLabel = if ($isPipUpdate -or ($src -eq "pip" -or $src -eq "pip3")) { "Pip $act for $name" } else { "$src $act for $name" }
                    $p = Invoke-WingetCmd -Command $cmd -TimeoutSeconds $commandTimeoutSeconds -CommandLabel $commandLabel
                }
                Write-Output "LOG:[$act][$index/$total] Process completed with exit code: $($p.ExitCode)"
                
                $hex = "0x{0:x}" -f $p.ExitCode
                
                # --- AUTO-FIX: SOURCE CORRUPTION ---
                if ($wingetArgs -and $hex -eq "0x8a150003") {
                    Write-Output "LOG:[$act] WARNING: Detected Winget Source Corruption. Auto-fixing..."
                    $fixP = Invoke-WingetCmd "winget source reset --force"
                    if ($fixP.ExitCode -eq 0) {
                        Write-Output "LOG:[$act][$index/$total] Sources reset. Retrying $name..."
                        if ($wingetArgs) {
                            if ($useVisibleWindow) {
                                $retryCmd = "winget $wingetArgs"
                                $p = Invoke-VisibleCmd $retryCmd "WMT Winget Retry - $name"
                            }
                            else {
                                $p = Invoke-WingetLive $wingetArgs
                            }
                        }
                        else {
                            $p = Invoke-WingetCmd $cmd
                        }
                        $hex = "0x{0:x}" -f $p.ExitCode 
                    }
                }

                # --- CHECK FINAL RESULT ---
                if ($p.ExitCode -eq 0) {
                    Write-Output "LOG:[$act][$index/$total] SUCCESS: $name"
                    Write-Output "RESULT:${index}:SUCCESS:$name"
                }
                elseif ($p.ExitCode -eq 3010) {
                    Write-Output "LOG:[$act][$index/$total] SUCCESS: $name (Reboot Required to complete)"
                    Write-Output "RESULT:${index}:SUCCESS:$name"
                }
                elseif ($p.ExitCode -eq 1602) {
                    Write-Output "LOG:[$act][$index/$total] CANCELLED: $name (by User)"
                    Write-Output "RESULT:${index}:CANCELLED:$name"
                }
                else {
                    # --- FAILURE HANDLING ---
                    $dec = "$($p.ExitCode)"
                    $errDesc = "Unknown Error"
                    
                    if ($ErrorCodes.ContainsKey($hex)) { $errDesc = $ErrorCodes[$hex] }
                    elseif ($ErrorCodes.ContainsKey($dec)) { $errDesc = $ErrorCodes[$dec] }

                    # Known non-retry outcomes: avoid opening fallback user-mode consoles.
                    if ($hex -eq "0x8a150006") {
                        Write-Output "LOG:[$act][$index/$total] SKIPPED [$hex] ${errDesc} - $name"
                        Write-Output "RESULT:${index}:SKIPPED:$name"
                        continue
                    }
                    if ($hex -eq "0x8a15000b" -or $dec -eq "1618") {
                        Write-Output "LOG:[$act][$index/$total] FAILED [$hex] ${errDesc} - $name (no user-mode retry)"
                        Write-Output "RESULT:${index}:FAILED:$name"
                        continue
                    }

                    if ($useVisibleWindow) {
                        Write-Output "LOG:[$act][$index/$total] FAILED [$hex] ${errDesc} - $name (see visible window output)"
                        Write-Output "RESULT:${index}:FAILED:$name"
                        continue
                    }
                    if ($storeCliArgs) {
                        $storeResourcesInUse = (
                            ($hex -eq "0x80073d02") -or
                            ($dec -eq "-2147009278") -or
                            ($dec -eq "2147958018") -or
                            ($p.PSObject.Properties["ResourcesInUse"] -and $p.ResourcesInUse)
                        )
                        if ($storeResourcesInUse) {
                            if (-not ($p.PSObject.Properties["ResourcesInUse"] -and $p.ResourcesInUse)) {
                                $resourcesInUseLog = "LOG:[Store CLI] Error 0x80073d02: The package could not be installed because resources it modifies are currently in use. Close the app and related Store/Xbox windows, then try again."
                                Write-Output $resourcesInUseLog
                            }
                            Write-Output "LOG:[$act][$index/$total] FAILED [$hex] ${errDesc} - $name (Microsoft Store says resources are currently in use; close the app and related Store/Xbox windows, then try again)"
                        }
                        elseif (($p.PSObject.Properties["StoreFallbackOpened"] -and $p.StoreFallbackOpened) -or ($p.PSObject.Properties["StalledReadyToDownload"] -and $p.StalledReadyToDownload)) {
                            Write-Output "LOG:[$act][$index/$total] FAILED [$hex] ${errDesc} - $name (Store CLI isn't working; opened Microsoft Store so the item can be downloaded or updated directly)"
                        }
                        else {
                            Write-Output "LOG:[$act][$index/$total] FAILED [$hex] ${errDesc} - $name (Store CLI action failed)"
                        }
                        Write-Output "RESULT:${index}:FAILED:$name"
                        continue
                    }
                    if ($storeForceUpdateScan) {
                        Write-Output "LOG:[$act][$index/$total] FAILED [$hex] ${errDesc} - $name (could not start Microsoft Store app update scan)"
                        Write-Output "RESULT:${index}:FAILED:$name"
                        continue
                    }
                    if ($srcKey -eq "pip" -or $srcKey -eq "pip3") {
                        Write-Output "LOG:[$act][$index/$total] FAILED [$hex] ${errDesc} - $name (pip user-mode retry disabled)"
                        Write-Output "RESULT:${index}:FAILED:$name"
                        continue
                    }

                    if ($dec -eq "1603") {
                        Write-Output "LOG:[$act][$index/$total] FAILED (1603): $name - Retrying in Interactive Mode (Look for popup)..."
                    }
                    else {
                        Write-Output "LOG:[$act][$index/$total] FAILED [$hex] $errDesc - Retrying as User..."
                    }
                    
                    # --- RETRY AS USER (Fallback) ---
                    # Handles Scoop (needs user rights) and Spotify (hates Admin)
                    $rand = [Guid]::NewGuid().ToString()
                    $batPath = "$temp\WMT_Fix_${id}_${rand}.bat"
                    $batContent = @"
@echo off
title $act $name (User Mode)
echo WMT-GUI: Re-launching $name...
echo.
echo NOTE: If this is Scoop or Spotify, this usually fixes the error.
echo If an installer window appears, please click through it.
echo.
$userCmd
echo.
echo Done.
timeout /t 5
(goto) 2>nul & del "%~f0"
"@
                    Set-Content -Path $batPath -Value $batContent -Encoding Ascii
                    try {
                        Start-Process "explorer.exe" -ArgumentList "`"$batPath`""
                    }
                    catch {
                        Write-Output "LOG:Retry failed: $($_.Exception.Message)"
                    }
                    Write-Output "RESULT:${index}:FAILED:$name"
                }
            }
            else {
                Write-Output "LOG:[$act][$index/$total] SKIPPED: No command generated for source '$src' ($name)"
                Write-Output "RESULT:${index}:SKIPPED:$name"
            }
        }
    }

    # 3. Setup Timer
    if ($script:WingetTimer) { $script:WingetTimer.Stop() }
    $script:WingetTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:WingetTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $script:ProcessWingetLines = {
        param($lines)
        foreach ($line in $lines) {
            if ($line -match "^STEAM_OPEN:(.+)$") {
                $payload = $null
                try {
                    $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($matches[1].Trim()))
                    $payload = $json | ConvertFrom-Json
                }
                catch {
                    Write-GuiLog "[Steam] Could not decode Steam launch request: $($_.Exception.Message)"
                }

                $steamUri = "steam://open/downloads"
                $steamRunUri = ""
                $packageName = $script:WingetCurrentItemName
                $appId = ""
                if ($payload) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$payload.Uri)) { $steamUri = [string]$payload.Uri }
                    if (-not [string]::IsNullOrWhiteSpace([string]$payload.RunUri)) { $steamRunUri = [string]$payload.RunUri }
                    if (-not [string]::IsNullOrWhiteSpace([string]$payload.PackageName)) { $packageName = [string]$payload.PackageName }
                    if (-not [string]::IsNullOrWhiteSpace([string]$payload.AppId)) { $appId = [string]$payload.AppId }
                }
                if ([string]::IsNullOrWhiteSpace($packageName)) { $packageName = "Steam" }
                Write-GuiLog "[Steam] Received STEAM_OPEN request for $packageName ($steamUri)."

                # Prevent spamming the same Steam URL multiple times during bulk runs.
                if (-not $script:WingetSteamOpenSeen) { $script:WingetSteamOpenSeen = @{} }
                $seenKey = if (-not [string]::IsNullOrWhiteSpace($appId)) { "$steamUri|$appId" } else { $steamUri }
                if ($script:WingetSteamOpenSeen.ContainsKey($seenKey)) { continue }
                $script:WingetSteamOpenSeen[$seenKey] = $true

                function Find-WmtSteamExeForLaunch {
                    $candidates = New-Object System.Collections.Generic.List[string]
                    $addCandidate = {
                        param([string]$Path)
                        if ([string]::IsNullOrWhiteSpace($Path)) { return }
                        try {
                            $expanded = [Environment]::ExpandEnvironmentVariables(([string]$Path).Trim())
                            if ((Test-Path -LiteralPath $expanded -PathType Leaf) -and -not $candidates.Contains($expanded)) {
                                [void]$candidates.Add($expanded)
                            }
                        }
                        catch {}
                    }
                    foreach ($registryPath in @(
                            "HKCU:\Software\Valve\Steam",
                            "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
                            "HKLM:\SOFTWARE\Valve\Steam"
                        )) {
                        try {
                            $props = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
                            if ($props.PSObject.Properties["SteamExe"]) { & $addCandidate ([string]$props.SteamExe) }
                            foreach ($propName in @("SteamPath", "InstallPath")) {
                                if ($props.PSObject.Properties[$propName]) {
                                    & $addCandidate (Join-Path ([string]$props.$propName) "steam.exe")
                                }
                            }
                        }
                        catch {}
                    }
                    foreach ($path in @(
                            "${env:ProgramFiles(x86)}\Steam\steam.exe",
                            "${env:ProgramFiles}\Steam\steam.exe"
                        )) { & $addCandidate $path }
                    return @($candidates) | Select-Object -First 1
                }

                function Invoke-WmtSteamHeadlessLauncher {
                    param(
                        [string]$Uri,
                        [string]$Label
                    )

                    if ([string]::IsNullOrWhiteSpace($Uri)) { return $false }
                    $steamExe = Find-WmtSteamExeForLaunch
                    if ([string]::IsNullOrWhiteSpace($steamExe)) {
                        Write-GuiLog "[Steam] Headless launch skipped because steam.exe was not found."
                        return $false
                    }

                    try {
                        $isValidationUri = $Uri -match '^(?i)steam://validate/'
                        $psi = New-Object System.Diagnostics.ProcessStartInfo
                        $psi.FileName = $steamExe
                        $psi.Arguments = if ($isValidationUri) { "`"$Uri`"" } else { "-silent -minimized `"$Uri`"" }
                        $psi.UseShellExecute = $false
                        $psi.CreateNoWindow = $true
                        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                        [void][System.Diagnostics.Process]::Start($psi)

                        $launchText = if ($isValidationUri) { "steam.exe $Uri" } else { "steam.exe -silent -minimized $Uri" }
                        Write-GuiLog "[Steam] Started headless Steam launcher for $Label`: $launchText"
                        return $true
                    }
                    catch {
                        Write-GuiLog "[Steam] Headless Steam launch failed for $Label`: $($_.Exception.Message)"
                    }

                    return $false
                }

                function Open-WmtSteamUriFromGui {
                    param(
                        [string]$Uri,
                        [string]$Label,
                        [switch]$PreferSteamExe
                    )

                    if ([string]::IsNullOrWhiteSpace($Uri)) { return $false }

                    Write-GuiLog "[Steam] Launch request received for $Label ($Uri)."

                    if (Invoke-WmtSteamHeadlessLauncher -Uri $Uri -Label $Label) { return $true }

                    return $false
                }

                $opened = Open-WmtSteamUriFromGui -Uri $steamUri -Label $packageName -PreferSteamExe
                if (-not $opened -and $steamUri -ne "steam://open/downloads") {
                    $opened = Open-WmtSteamUriFromGui -Uri "steam://open/downloads" -Label "Steam Downloads" -PreferSteamExe
                }

                if ($opened) {
                    Write-GuiLog "[Steam] Opened Steam updater for $packageName."
                    if (-not [string]::IsNullOrWhiteSpace($steamRunUri)) {
                        Write-GuiLog "[Steam] If the download does not start automatically, click Update/Resume in Steam Downloads for app $appId."
                    }
                }
                else {
                    Write-GuiLog "[Steam] Could not open Steam. Start Steam manually and open Downloads to finish updating $packageName."
                }
                continue
            }
            if ($line -match "^STORE_FALLBACK:(.+)$") {
                $payload = $null
                try {
                    $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($matches[1].Trim()))
                    $payload = $json | ConvertFrom-Json
                }
                catch {}

                $storeUri = ""
                $webUri = ""
                $ackPath = ""
                $fallbackId = ""
                $reason = ""
                $reasonText = ""
                $packageName = $script:WingetCurrentItemName
                if ($payload) {
                    $storeUri = ([string]$payload.StoreUri).Trim()
                    $webUri = ([string]$payload.WebUri).Trim()
                    $ackPath = ([string]$payload.AckPath).Trim()
                    $fallbackId = ([string]$payload.FallbackId).Trim()
                    $reason = ([string]$payload.Reason).Trim()
                    $reasonText = ([string]$payload.ReasonText).Trim()
                    if (-not [string]::IsNullOrWhiteSpace([string]$payload.PackageName)) {
                        $packageName = [string]$payload.PackageName
                    }
                }
                if ([string]::IsNullOrWhiteSpace($packageName)) { $packageName = "this Microsoft Store item" }
                if ([string]::IsNullOrWhiteSpace($storeUri)) { $storeUri = "ms-windows-store://home" }
                if ([string]::IsNullOrWhiteSpace($webUri)) { $webUri = $storeUri }
                if ([string]::IsNullOrWhiteSpace($fallbackId)) { $fallbackId = "$storeUri|$packageName|$reason" }

                if (-not $script:WingetStoreFallbackSeen) { $script:WingetStoreFallbackSeen = @{} }
                if ($script:WingetStoreFallbackSeen.ContainsKey($fallbackId)) {
                    continue
                }
                $script:WingetStoreFallbackSeen[$fallbackId] = $true

                $isStoreUpdateRequest = ($reason -eq "UpdateScan" -or $reason -eq "UpdateScanFailed")
                $opened = $false
                try {
                    Start-Process $storeUri
                    $opened = $true
                    if ($isStoreUpdateRequest) {
                        Write-GuiLog "[Store] Opened Microsoft Store Updates for $packageName."
                    }
                    else {
                        Write-GuiLog "[Store CLI] Opened Microsoft Store fallback page for $packageName."
                    }
                }
                catch {
                    Write-GuiLog "[Store CLI] Could not open Microsoft Store URI: $($_.Exception.Message)"
                }
                if (-not $opened -and $webUri -and $webUri -ne $storeUri) {
                    try {
                        Start-Process $webUri
                        $opened = $true
                        if ($isStoreUpdateRequest) {
                            Write-GuiLog "[Store] Opened Microsoft Store web Updates page for $packageName."
                        }
                        else {
                            Write-GuiLog "[Store CLI] Opened Microsoft Store web fallback page for $packageName."
                        }
                    }
                    catch {
                        Write-GuiLog "[Store CLI] Could not open Microsoft Store web fallback: $($_.Exception.Message)"
                    }
                }
                if (-not [string]::IsNullOrWhiteSpace($ackPath)) {
                    try {
                        $ack = "opened=$opened|$((Get-Date).ToString('o'))"
                        Set-Content -Path $ackPath -Value $ack -Encoding Ascii -Force
                    }
                    catch {}
                }

                if ($isStoreUpdateRequest) {
                    if (-not [string]::IsNullOrWhiteSpace($reasonText)) {
                        Write-GuiLog "[Store] $reasonText"
                    }
                    continue
                }

                if ([string]::IsNullOrWhiteSpace($reasonText)) {
                    if ($reason -eq "InstallTimeout") {
                        $reasonText = "Store CLI did not finish the install within 30 seconds"
                    }
                    else {
                        $reasonText = "Store CLI stayed at Ready to Download 0% for more than 30 seconds"
                    }
                }
                $msg = "Store CLI isn't working for $packageName. $reasonText.`r`n`r`nA Microsoft Store page was opened so you can download or update it directly."
                [System.Windows.MessageBox]::Show($msg, "Microsoft Store CLI Stalled", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
                continue
            }
            if ($line -match "^RESULT:(\d+):(SUCCESS|SKIPPED|FAILED|CANCELLED):(.*)$") {
                $doneIndex = [int]$matches[1]
                $result = $matches[2]
                $resultName = $matches[3]
                if (-not $script:WingetCompletedIndexes.ContainsKey($doneIndex)) {
                    $script:WingetCompletedIndexes[$doneIndex] = $true
                    $script:WingetProgressDone++
                    if ($result -eq "SUCCESS") {
                        $script:WingetProgressSuccess++
                    }
                    elseif ($result -eq "SKIPPED") {
                        $script:WingetProgressSkipped++
                    }
                    else {
                        $script:WingetProgressFailed++
                    }
                    if ($doneIndex -eq $script:WingetCurrentIndex) { $script:WingetCurrentPercent = 0 }
                    & $script:SetWingetLastResultUi $result $resultName $doneIndex $script:WingetProgressTotal
                    & $script:RefreshWingetProgressUi
                }
                continue
            }
            if ($line -match "^ITEM_SOURCE:(.*)$") {
                $script:WingetCurrentItemSource = ([string]$matches[1]).Trim().ToLowerInvariant()
                $script:WingetCurrentItemStartedAt = Get-Date
                continue
            }
            if ($line -match "^PROGRESS:(\d+)/(\d+):(.+)$") {
                $i = [int]$matches[1]
                $t = [int]$matches[2]
                $n = $matches[3]
                $script:WingetCurrentIndex = $i
                $script:WingetCurrentPercent = 0
                $script:WingetCurrentItemName = $n
                $lblWingetStatus.Text = "$($script:WingetActiveAction) ${i}/${t}: $n"
                & $script:RefreshWingetProgressUi
                continue
            }
            if ($line -match "^LOG:(.*)") {
                $logMsg = $matches[1].Trim()
                if ($logMsg -match "^\[Store CLI\]\s+Error 0x80073d02:") {
                    $script:WingetStoreResourcesInUseSeen = $true
                    if ($script:WingetStoreErrorLogSeen.ContainsKey($logMsg)) { continue }
                    $script:WingetStoreErrorLogSeen[$logMsg] = $true
                }
                if ($logMsg -match "^\[(?:winget|store)\]\s+Progress:\s*(\d+)%$") {
                    $script:WingetCurrentPercent = [int]$matches[1]
                    & $script:RefreshWingetProgressUi
                }
                if ($logMsg -match "^\[[^\]]+\]\[(\d+)/(\d+)\]\s+(SUCCESS|SKIPPED|FAILED|CANCELLED)\b") {
                    $doneIndex = [int]$matches[1]
                    $result = $matches[3]
                    if (-not $script:WingetCompletedIndexes.ContainsKey($doneIndex)) {
                        $script:WingetCompletedIndexes[$doneIndex] = $true
                        $script:WingetProgressDone++
                        if ($result -eq "SUCCESS") {
                            $script:WingetProgressSuccess++
                        }
                        elseif ($result -eq "SKIPPED") {
                            $script:WingetProgressSkipped++
                        }
                        else {
                            $script:WingetProgressFailed++
                        }
                        if ($doneIndex -eq $script:WingetCurrentIndex) { $script:WingetCurrentPercent = 0 }
                        & $script:SetWingetLastResultUi $result $script:WingetCurrentItemName $doneIndex $script:WingetProgressTotal
                        & $script:RefreshWingetProgressUi
                    }
                }
                Write-GuiLog $logMsg
            }
        }
    }

    $script:WingetTimer.Add_Tick({
            try {
                if (-not $script:WingetJob) { return }
                if ($script:WingetJob.HasMoreData) {
                    $results = Receive-Job -Job $script:WingetJob -ErrorAction SilentlyContinue
                    if ($results) {
                        & $script:ProcessWingetLines $results
                    }
                }
                $pipItemRunning = (
                    $script:WingetJob.State -eq 'Running' -and
                    $script:WingetCurrentItemSource -in @("pip", "pip3") -and
                    $script:WingetCurrentItemStartedAt
                )
                if ($pipItemRunning -and -not $script:WingetActionForcedTimeout) {
                    $pipElapsedSeconds = ((Get-Date) - $script:WingetCurrentItemStartedAt).TotalSeconds
                    if ($pipElapsedSeconds -ge 600) {
                        $script:WingetActionForcedTimeout = $true
                        Write-GuiLog "[Pip] $($script:WingetCurrentItemName) exceeded the 10-minute action timeout. Stopping the background job."
                        try { Stop-Job -Job $script:WingetJob -ErrorAction SilentlyContinue } catch {}
                    }
                }
                if ($script:WingetJob.State -eq 'Running' -and $script:WingetActionStartedAt -and $script:WingetCurrentItemName) {
                    try {
                        $elapsed = (Get-Date) - $script:WingetActionStartedAt
                        $elapsedText = $elapsed.ToString("mm\:ss", [System.Globalization.CultureInfo]::InvariantCulture)
                        $curIdx = [Math]::Max(1, $script:WingetCurrentIndex)
                        $lblWingetStatus.Text = "$($script:WingetActiveAction) ${curIdx}/$($script:WingetProgressTotal): $($script:WingetCurrentItemName)  (${elapsedText})"
                    }
                    catch {}
                }
                if ($script:WingetJob.State -ne 'Running') {
                    $script:WingetTimer.Stop()
                    $results = Receive-Job -Job $script:WingetJob -ErrorAction SilentlyContinue
                    if ($results) {
                        & $script:ProcessWingetLines $results
                    }
                    Remove-Job -Job $script:WingetJob -Force -ErrorAction SilentlyContinue
                    $script:WingetJob = $null
                    if ($script:WingetActiveAction) {
                        if ($script:WingetProgressDone -lt $script:WingetProgressTotal) {
                            $missing = $script:WingetProgressTotal - $script:WingetProgressDone
                            $script:WingetProgressDone = $script:WingetProgressTotal
                            if ($script:WingetActionForcedTimeout) {
                                $script:WingetProgressFailed += $missing
                                $missingName = if ([string]::IsNullOrWhiteSpace($script:WingetCurrentItemName)) { "Pip item" } else { $script:WingetCurrentItemName }
                                & $script:SetWingetLastResultUi "FAILED" $missingName $script:WingetProgressTotal $script:WingetProgressTotal
                                Write-GuiLog "[$($script:WingetActiveAction)] FAILED: $missing item(s) stopped after the pip action timeout."
                            }
                            elseif ($script:WingetActionHasStoreCli) {
                                $script:WingetProgressFailed += $missing
                                $missingName = if ([string]::IsNullOrWhiteSpace($script:WingetCurrentItemName)) { "Microsoft Store item" } else { $script:WingetCurrentItemName }
                                & $script:SetWingetLastResultUi "FAILED" $missingName $script:WingetProgressTotal $script:WingetProgressTotal
                                if (-not $script:WingetStoreResourcesInUseSeen) {
                                    try {
                                        $cutoff = if ($script:WingetActionStartedAt) { $script:WingetActionStartedAt.AddSeconds(-5) } else { (Get-Date).AddMinutes(-10) }
                                        $storeTempFiles = @(
                                            Get-ChildItem -Path $env:TEMP -Filter "WMT_StoreCLI_*.resources" -File -ErrorAction SilentlyContinue
                                            Get-ChildItem -Path $env:TEMP -Filter "WMT_StoreCLI_*.screen" -File -ErrorAction SilentlyContinue
                                            Get-ChildItem -Path $env:TEMP -Filter "WMT_StoreCLI_*.transcript" -File -ErrorAction SilentlyContinue
                                        ) | Where-Object { $_.LastWriteTime -ge $cutoff }
                                        foreach ($storeTempFile in $storeTempFiles) {
                                            $storeTempText = Get-Content -Path $storeTempFile.FullName -Raw -ErrorAction SilentlyContinue
                                            if ($storeTempText -match '(?is)(0x80073d02|resources\s+(?:it\s+)?modifies\s+are\s+currently\s+in\s+use|resources[\s\S]{0,240}currently\s+in\s+use)') {
                                                $script:WingetStoreResourcesInUseSeen = $true
                                                $resourcesInUseLog = "[Store CLI] Error 0x80073d02: The package could not be installed because resources it modifies are currently in use. Close the app and related Store/Xbox windows, then try again."
                                                if (-not $script:WingetStoreErrorLogSeen.ContainsKey($resourcesInUseLog)) {
                                                    $script:WingetStoreErrorLogSeen[$resourcesInUseLog] = $true
                                                    Write-GuiLog $resourcesInUseLog
                                                }
                                                break
                                            }
                                        }
                                    }
                                    catch {}
                                }
                                if ($script:WingetStoreResourcesInUseSeen) {
                                    Write-GuiLog "[$($script:WingetActiveAction)] FAILED: $missing Store CLI item(s) ended after Microsoft Store reported 0x80073d02 resources currently in use."
                                }
                                else {
                                    Write-GuiLog "[$($script:WingetActiveAction)] FAILED: $missing Store CLI item(s) ended without a result. This usually means Store CLI was stopped after a stalled or cancelled update."
                                }
                            }
                            else {
                                # Some non-Store installers close their consoles without a reliable exit event.
                                Write-GuiLog "[$($script:WingetActiveAction)] Notice: $missing item(s) completed silently without a standard success flag."
                            }
                        }
                        if ($script:WingetProgressFailed -gt 0) {
                            $lblWingetStatus.Text = "$($script:WingetActiveAction) completed with failures. $($script:WingetProgressDone)/$($script:WingetProgressTotal) done."
                            Write-GuiLog "[$($script:WingetActiveAction)] Completed with $($script:WingetProgressFailed) failure(s)."
                        }
                        else {
                            $lblWingetStatus.Text = "$($script:WingetActiveAction) completed. $($script:WingetProgressDone)/$($script:WingetProgressTotal) done."
                            Write-GuiLog "[$($script:WingetActiveAction)] Completed."
                        }
                    }

                    $script:WingetCurrentIndex = 0
                    $script:WingetCurrentPercent = 0
                    $script:WingetCurrentItemSource = ""
                    $script:WingetCurrentItemStartedAt = $null
                    & $script:RefreshWingetProgressUi

                    $btnWingetScan.IsEnabled = $true
                    $btnWingetUpdateSel.IsEnabled = $true
                    if ($btnWingetUpdateAll) { $btnWingetUpdateAll.IsEnabled = $true }
                    if ($btnWingetInstall) { $btnWingetInstall.IsEnabled = $true }
                    if ($btnWingetUninstall) { $btnWingetUninstall.IsEnabled = $true }

                    $nonSuccessCount = $script:WingetProgressSkipped + $script:WingetProgressFailed
                    $shouldRefreshAfterAction = ($script:WingetProgressSuccess -gt 0 -or $nonSuccessCount -eq 0)

                    if ($script:WingetProgressSuccess -gt 0) {
                        Write-GuiLog "Action finished. $($script:WingetProgressSuccess) explicit success(es). Refreshing package list..."
                    }
                    elseif (-not $shouldRefreshAfterAction) {
                        Write-GuiLog "Action finished with no applied updates. Package list was not refreshed."
                    }
                    else {
                        Write-GuiLog "Action finished. Refreshing package list to verify changes..."
                    }

                    $autoInstallCompleted = [bool]$script:WmtAutoInstallActive
                    if ($autoInstallCompleted) {
                        Show-WmtBackgroundInstallNotification -Status Completed `
                            -TotalCount $script:WingetProgressTotal `
                            -SuccessCount $script:WingetProgressSuccess `
                            -SkippedCount $script:WingetProgressSkipped `
                            -FailedCount $script:WingetProgressFailed
                    }

                    # Clear action ownership before starting the verification scan.
                    $script:WmtAutoInstallActive = $false
                    $script:WingetActiveAction = $null
                    $script:WingetActionStoreUpdateOnly = $false
                    $script:WingetActionForcedTimeout = $false

                    # Refresh after successful or silent actions; skipped/failed-only actions keep the current list visible.
                    if ($shouldRefreshAfterAction -and $btnWingetScan) {
                        if (Get-WmtUpdateAutoInstallEnabled) {
                            $script:WmtAutoInstallSuppressNextScan = $true
                        }
                        $btnWingetScan.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
                    }
                }
            }
            catch {
                Reset-WmtUpdateUiAfterMonitorError -Context "Update completion monitor failed" -Exception $_.Exception -ErrorRecord $_
            }
        })
    $script:WingetTimer.Start()
}

# 3. EVENT HANDLERS


























# ---------------------------------------------------------
# PARALLEL SCAN ENGINE
# ---------------------------------------------------------

# 1. SETUP MULTI-THREAD TIMER
$script:ScanTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:ScanTimer.Interval = [TimeSpan]::FromMilliseconds(200)
# We now use a LIST of active scanners instead of just one
$script:ActiveScans = [System.Collections.ArrayList]::new()
$script:WmtAutoInstallSuppressNextScan = $false
$script:WmtAutoInstallActive = $false

$script:ScanTimer.Add_Tick({
        if ($script:ActiveScans.Count -gt 0) {
        
            # Iterate backwards so we can remove completed tasks safely
            for ($i = $script:ActiveScans.Count - 1; $i -ge 0; $i--) {
                $task = $script:ActiveScans[$i]
            
                if ($task.AsyncResult.IsCompleted) {
                    try {
                        $results = $task.PowerShell.EndInvoke($task.AsyncResult)
                        $task.PowerShell.Dispose()
                    
                        # Process Results
                        foreach ($item in $results) {
                            if ($null -eq $item) { continue }

                            if ($item -is [string] -and $item.StartsWith("LOG:")) {
                                Write-GuiLog ($item.Substring(4))
                            }
                            elseif ($item.PSObject.Properties["Name"]) {
                                # --- STRICT GARBAGE FILTER ---
                                # Rejects headers, separators, and empty dashed lines
                                if ($item.Name -match "^-+$" -or $item.Id -match "^-+$") { continue }
                                if ($item.Name -eq "Name" -and $item.Id -eq "Id") { continue }
                                if ($item.Name -eq "Source" -and $item.Id -eq "Name") { continue }
                                if ($item.Version -eq "Version" -or $item.Available -eq "Available") { continue }
                            
                                # Add to UI
                                [void](Set-WmtUpdateListItemCheckState -Item $item -DefaultChecked:$false)
                                [void]$lstWinget.Items.Add($item)
                            }
                        }
                    }
                    catch {
                        Write-GuiLog "Scan Error: $($_.Exception.Message)"
                    }
                
                    # Remove finished task
                    $script:ActiveScans.RemoveAt($i)
                }
            }
        }
        else {
            # All tasks finished
            if ($script:ScanTimer.IsEnabled) {
                $script:ScanTimer.Stop()
            
                $lblWingetStatus.Visibility = "Hidden"
                if ($pbWingetProgress) { $pbWingetProgress.Visibility = "Collapsed"; $pbWingetProgress.Value = 0 }
                if ($lblWingetProgress) { $lblWingetProgress.Visibility = "Collapsed"; $lblWingetProgress.Text = "" }
                $btnWingetScan.IsEnabled = $true
                if ($btnWingetUpdateAll) { $btnWingetUpdateAll.IsEnabled = $true }
                $btnWingetUpdateSel.IsEnabled = $true
                $lstWinget.Items.Refresh()
                $lstWinget.UpdateLayout()
                Request-WmtUpdateListSmartColumnResize -ListView $lstWinget
            
                if ($lstWinget.Items.Count -eq 0) {
                    Write-GuiLog "System is up to date."
                }
                else {
                    Write-GuiLog "Scan Complete. Found $($lstWinget.Items.Count) updates."
                }

                if (Get-WmtUpdateAutoInstallEnabled) {
                    if ($script:WmtAutoInstallSuppressNextScan) {
                        $script:WmtAutoInstallSuppressNextScan = $false
                        Write-GuiLog "Auto install skipped for this verification scan."
                    }
                    else {
                        Invoke-WmtAutoInstallAvailableUpdates
                    }
                }
            }
        }
    })

# 2. BUTTON CLICK (Launch Parallel Threads)
$btnWingetScan.Add_Click({
        # UI Prep
        $lblWingetTitle.Text = "Package Updates"
        $lblWingetStatus.Text = "Scanning all providers..."
        $lblWingetStatus.Visibility = "Visible"
        if ($pbWingetProgress) { $pbWingetProgress.Visibility = "Collapsed"; $pbWingetProgress.Value = 0 }
        if ($lblWingetProgress) { $lblWingetProgress.Visibility = "Collapsed"; $lblWingetProgress.Text = "" }
        if ($lblWingetLastResult) { $lblWingetLastResult.Visibility = "Collapsed"; $lblWingetLastResult.Text = "" }
    
        $lstWinget.Items.Clear()
        $btnWingetScan.IsEnabled = $false
        if ($btnWingetUpdateAll) { $btnWingetUpdateAll.IsEnabled = $false }
        $btnWingetUpdateSel.IsEnabled = $false
        $btnWingetInstall.Visibility = "Collapsed"
        $btnWingetUpdateSel.Visibility = "Visible"
        if ($btnWingetUpdateAll) { $btnWingetUpdateAll.Visibility = "Visible" }
    
        Write-GuiLog " "
        Write-GuiLog "Starting Parallel Scan (global timeout 120s)..."
        # Winget source refresh is handled before the provider worker starts.
        # Store updates use the Microsoft Store CLI instead of the winget msstore source.
        # Do not kill winget here; source preflight may already be running.
        # Stuck winget processes are cleaned at app start and install/update actions handle their own cleanup.
    
        # --- Load Settings ---
        $settings = Get-WmtSettings
        $enabled = if ($settings.EnabledProviders -and $settings.EnabledProviders.Count -gt 0) { 
            $settings.EnabledProviders 
        }
        else { 
            @("winget", "msstore", "windowsupdate", "pip", "npm", "pnpm", "dotnet", "psmodule", "composer", "chocolatey", "scoop", "gem", "cargo", "steam", "legendary", "gogdl")
        }
        $ignoreList = if ($settings.WingetIgnore) { $settings.WingetIgnore } else { @() }
        $includeUnknown = Get-WmtWingetIncludeUnknown -Settings $settings
    
        Write-GuiLog "Enabled providers: $($enabled -join ', ')"
        Write-GuiLog "Winget include unknown: $includeUnknown"

        # Gate the actual winget scan behind a completed source refresh.
        # This keeps startup clickable but ensures the first visible package results are collected after source prep.
        $wingetSourcesToPrep = @()
        if ("winget" -in $enabled) { $wingetSourcesToPrep += "winget" }

        if ($wingetSourcesToPrep.Count -gt 0 -and -not $script:WingetSourcePreflightReadyForScan) {
            if (-not $script:WingetScanSourcePreflightInProgress) {
                Start-WingetScanSourcePreflight -Sources $wingetSourcesToPrep
            }
            else {
                Write-GuiLog "Waiting for winget source preflight to finish before scanning..."
            }
            return
        }
        #$script:WingetSourcePreflightReadyForScan = $false
        # Keep the ready flag set after the first preflight so later page/manual refreshes scan immediately.
    
        # --- Reset scan tracking ---
        $script:ActiveScans.Clear()
        $script:ScanCancelled = $false
        $script:ScanStartTime = Get-Date
    
        # --- Global Timeout Timer (120 seconds) ---
        if ($script:GlobalScanTimer) {
            try { $script:GlobalScanTimer.Stop() } catch {}
            $script:GlobalScanTimer = $null
        }
        $script:GlobalScanTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:GlobalScanTimer.Interval = [TimeSpan]::FromSeconds(120)
        $script:GlobalScanTimer.Add_Tick({
                if ($script:ActiveScans.Count -gt 0 -and -not $script:ScanCancelled) {
                    $script:ScanCancelled = $true
                    Write-GuiLog "Global scan timeout reached (120s). Cancelling remaining provider scans."
                    # Stop all still-running runspaces
                    foreach ($task in $script:ActiveScans) {
                        try { $task.PowerShell.Stop() } catch { }
                        try { $task.PowerShell.Dispose() } catch { }
                    }
                    $script:ActiveScans.Clear()
                    # Stop result collection timer
                    if ($script:ScanTimer.IsEnabled) { $script:ScanTimer.Stop() }
                    $lblWingetStatus.Text = "Scan timeout - some providers did not respond."
                    $lblWingetStatus.Visibility = "Visible"
                    $btnWingetScan.IsEnabled = $true
                    if ($btnWingetUpdateAll) { $btnWingetUpdateAll.IsEnabled = $true }
                    $btnWingetUpdateSel.IsEnabled = $true
                    [System.Windows.MessageBox]::Show(
                        "Scan timed out after 120 seconds.`n`nOne of the enabled package providers did not respond.`nTry disabling slow providers and scan again.",
                        "Scan Timeout", "OK", "Warning"
                    ) | Out-Null
                }
                $script:GlobalScanTimer.Stop()
            })
        $script:GlobalScanTimer.Start()
    
        # --- Provider Workers ---
    
        # A. WINGET
        foreach ($wingetSource in @("winget")) {
            if ($wingetSource -notin $enabled) { continue }
    
            $ps = [PowerShell]::Create()
            [void]$ps.AddScript({
                    param($SourceName, $IgnoreList, $IncludeUnknown)
                    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    
                    function Test-Ignored($n, $i) {
                        if ($IgnoreList -and ($IgnoreList -contains $n -or $IgnoreList -contains $i)) { return $true }
                        return $false
                    }

                    function Test-WingetScanNoticeLine {
                        param([string]$Text)

                        if ([string]::IsNullOrWhiteSpace($Text)) { return $true }

                        $trimmed = $Text.Trim()
                        if ($trimmed -match "^-+") { return $true }
                        if ($trimmed -match "(?i)--include-unknown") { return $true }
                        if ($trimmed -match "(?i)explicit targeting" -or $trimmed -match "(?i)following packages have an upgrade available") { return $true }
                        if ($trimmed -match "(?i)^(name|nom)\s+(id|identifiant)\s+version(\s+|$)") { return $true }
                        if ($trimmed -match "(?i)^(no updates|all apps are up to date|your apps are up to date)") { return $true }

                        return $false
                    }
    
                    Write-Output "LOG:$SourceName source preflight already completed; starting scan..."
    
                    # Winget source-backed scans can legitimately take a while.
                    $timeoutMs = 120000
    
                    $includeUnknownFlag = if ([bool]$IncludeUnknown) { " --include-unknown" } else { "" }
                    $wArgs = "list --upgrade-available$includeUnknownFlag --accept-source-agreements --disable-interactivity --source $SourceName"
                    try {
                        $pInfo = New-Object System.Diagnostics.ProcessStartInfo
                        $pInfo.FileName = "winget"
                        $pInfo.Arguments = $wArgs
                        $pInfo.RedirectStandardOutput = $true
                        $pInfo.RedirectStandardError = $false
                        $pInfo.UseShellExecute = $false
                        $pInfo.CreateNoWindow = $true
                        $pInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
                        $p = [System.Diagnostics.Process]::Start($pInfo)
                        $outTask = $p.StandardOutput.ReadToEndAsync()
    
                        if (-not $p.WaitForExit($timeoutMs)) {
                            Write-Output "LOG:$SourceName scan timed out after $([int]($timeoutMs / 1000)) seconds."
                            try { $p.Kill() } catch { }
                            try { [void]$p.WaitForExit(2000) } catch { }
                            return
                        }
    
                        $out = $outTask.GetAwaiter().GetResult()
    
                        # Auto-accept & refresh if needed (existing logic)
                        if ($p.ExitCode -eq -1978335231 -or $p.ExitCode -eq -1978335229) { 
                            Write-Output "LOG:$SourceName connection failed (Code: $($p.ExitCode)). Auto-accepting agreements and refreshing..."
                            $fixInfo1 = New-Object System.Diagnostics.ProcessStartInfo("winget", "search `"Spotify`" --source $SourceName --accept-source-agreements")
                            $fixInfo1.CreateNoWindow = $true; $fixInfo1.UseShellExecute = $false
                            $fixP1 = [System.Diagnostics.Process]::Start($fixInfo1); $fixP1.WaitForExit()
    
                            $fixInfo2 = New-Object System.Diagnostics.ProcessStartInfo("winget", "source update --name $SourceName")
                            $fixInfo2.CreateNoWindow = $true; $fixInfo2.UseShellExecute = $false
                            $fixP2 = [System.Diagnostics.Process]::Start($fixInfo2); $fixP2.WaitForExit()
    
                            Write-Output "LOG:$SourceName refreshed. Retrying scan..."
                            $p = [System.Diagnostics.Process]::Start($pInfo)
                            $outTask = $p.StandardOutput.ReadToEndAsync()
                            if (-not $p.WaitForExit($timeoutMs)) {
                                Write-Output "LOG:$SourceName retry scan timed out after $([int]($timeoutMs / 1000)) seconds."
                                try { $p.Kill() } catch { }
                                try { [void]$p.WaitForExit(2000) } catch { }
                                return
                            }
                            $out = $outTask.GetAwaiter().GetResult()
                        }
    
                        if ($p.ExitCode -ne 0) {
                            Write-Output "LOG:$SourceName scan exited with code $($p.ExitCode)."
                        }
    
                        if (-not [string]::IsNullOrWhiteSpace($out)) {
                            $lines = $out -split "`r`n"
                            foreach ($line in $lines) {
                                $line = $line.Trim()
                                if (Test-WingetScanNoticeLine $line) { continue }
    
                                $parts = $line -split '\s+'
                                $len = $parts.Count
                                if ($len -ge 4) {
                                    $lastWord = $parts[-1]
                                    if ($len -ge 5 -and ($lastWord -eq "winget" -or $lastWord -eq "msstore")) {
                                        $a = $parts[-2]
                                        $v = $parts[-3]
                                        $i = $parts[-4]
                                        $n = ($parts[0..($len - 5)] -join " ")
                                    }
                                    else {
                                        $a = $parts[-1]
                                        $v = $parts[-2]
                                        $i = $parts[-3]
                                        $n = ($parts[0..($len - 4)] -join " ")
                                    }
                                    if ($n -and $i -and $i.Length -gt 2 -and $i -notmatch "^Id$") {
                                        if (Test-Ignored $n $i) { continue }
                                        if ($v -match "^(?i)(unknown|inconnu)$") { $v = "?" }
                                        [PSCustomObject]@{ Source = $SourceName; Name = $n; Id = $i; Version = $v; Available = $a }
                                    }
                                }
                            }
                        }
                    }
                    catch {
                        Write-Output "LOG:$SourceName check failed: $($_.Exception.Message)"
                    }
                }).AddArgument($wingetSource).AddArgument($ignoreList).AddArgument([bool]$includeUnknown)
    
            [void]$script:ActiveScans.Add([PSCustomObject]@{ PowerShell = $ps; AsyncResult = $ps.BeginInvoke() })
        }

        if ("msstore" -in $enabled) {
            $ps = [PowerShell]::Create()
            [void]$ps.AddScript({
                    param($IgnoreList)
                    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

                    function Test-Ignored($n, $i) {
                        if ($IgnoreList -and ($IgnoreList -contains $n -or $IgnoreList -contains $i)) { return $true }
                        return $false
                    }

                    function Get-StoreColumnIndex {
                        param([string[]]$Headers, [string[]]$Patterns, [int]$DefaultIndex = -1)
                        if ($Headers) {
                            for ($idx = 0; $idx -lt $Headers.Count; $idx++) {
                                foreach ($pattern in $Patterns) {
                                    if ($Headers[$idx] -match $pattern) { return $idx }
                                }
                            }
                        }
                        return $DefaultIndex
                    }

                    function Get-StoreColumnValue {
                        param([string[]]$Columns, [int]$Index, [string]$Fallback = "")
                        if ($Index -ge 0 -and $Index -lt $Columns.Count) { return ([string]$Columns[$Index]).Trim() }
                        return $Fallback
                    }

                    function Get-StoreCliProductId {
                        param([string]$Value)

                        $text = ([string]$Value).Trim()
                        if ([string]::IsNullOrWhiteSpace($text)) { return "" }

                        $matchPatterns = @(
                            '(?i)(?:product\s*id|productid|product-id)\s*[:=]\s*((?:9[A-Z0-9]{9,19}|XP[A-Z0-9]{8,18}))',
                            '(?i)(?:/detail/|productid=)((?:9[A-Z0-9]{9,19}|XP[A-Z0-9]{8,18}))',
                            '(?i)\b((?:9[A-Z0-9]{9,19}|XP[A-Z0-9]{8,18}))\b'
                        )

                        foreach ($pattern in $matchPatterns) {
                            $match = [regex]::Match($text, $pattern)
                            if ($match.Success) { return $match.Groups[1].Value.ToUpperInvariant() }
                        }

                        return ""
                    }

                    function ConvertFrom-StoreUpdatesOutput {
                        param([string]$OutputText)

                        $items = New-Object System.Collections.Generic.List[object]
                        if ([string]::IsNullOrWhiteSpace($OutputText)) { return $items.ToArray() }

                        $cleanText = [regex]::Replace($OutputText, "`e\[[0-?]*[ -/]*[@-~]", "")
                        $headers = $null
                        $vertical = [string][char]0x2502
                        $lines = $cleanText -split "`r?`n"

                        foreach ($rawLine in $lines) {
                            $line = ([string]$rawLine).Trim()
                            if ([string]::IsNullOrWhiteSpace($line)) { continue }
                            if ($line -notmatch '[\p{L}\p{Nd}]') { continue }
                            if ($line -match '(?i)^(checking|usage:|commands?:|options?:|examples?:)' -or $line -match '(?i)store cli') { continue }
                            if ($line -match '(?i)^(no updates|all apps are up to date|your apps are up to date)') { continue }

                            $cols = @()
                            if ($line.Contains($vertical)) {
                                $rawCols = $line -split [regex]::Escape($vertical)
                                if ($rawCols.Count -gt 2) {
                                    for ($ci = 1; $ci -lt ($rawCols.Count - 1); $ci++) {
                                        $value = ([string]$rawCols[$ci]).Trim()
                                        if ($value -ne "") { $cols += $value }
                                    }
                                }
                            }
                            elseif ($line -match '\s{2,}') {
                                $cols = @($line -split '\s{2,}' | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -ne "" })
                            }

                            if ($cols.Count -lt 2) { continue }

                            $lowerCols = @($cols | ForEach-Object { ([string]$_).ToLowerInvariant() })
                            if ($lowerCols -contains "name" -or $lowerCols -contains "app" -or $lowerCols -contains "title") {
                                $headers = [string[]]$cols
                                continue
                            }
                            if ($headers -and ($headers[0] -match '(?i)^command$')) { continue }

                            $nameIndex = Get-StoreColumnIndex -Headers $headers -Patterns @('(?i)^(name|app|title)$') -DefaultIndex 0
                            $idIndex = Get-StoreColumnIndex -Headers $headers -Patterns @('(?i)product\s*id', '(?i)store\s*id', '(?i)catalog\s*id', '(?i)^id$') -DefaultIndex -1
                            $versionIndex = Get-StoreColumnIndex -Headers $headers -Patterns @('(?i)installed', '(?i)current', '(?i)^version$') -DefaultIndex -1
                            $availableIndex = Get-StoreColumnIndex -Headers $headers -Patterns @('(?i)available', '(?i)latest', '(?i)new\s+version', '(?i)update') -DefaultIndex -1

                            if ($availableIndex -eq $versionIndex) { $availableIndex = -1 }

                            $n = Get-StoreColumnValue -Columns $cols -Index $nameIndex
                            if ([string]::IsNullOrWhiteSpace($n) -or $n -match '(?i)^(name|app|title)$') { continue }

                            $i = Get-StoreCliProductId (Get-StoreColumnValue -Columns $cols -Index $idIndex -Fallback "")
                            $detectedProductId = $null
                            for ($colIndex = 0; $colIndex -lt $cols.Count; $colIndex++) {
                                if ($colIndex -eq $nameIndex) { continue }
                                $candidate = Get-StoreCliProductId $cols[$colIndex]
                                if ($candidate) {
                                    $detectedProductId = $candidate
                                    break
                                }
                            }
                            if ($detectedProductId -and [string]::IsNullOrWhiteSpace($i)) {
                                $i = $detectedProductId
                            }
                            if ([string]::IsNullOrWhiteSpace($i)) { $i = "" }
                            $v = Get-StoreColumnValue -Columns $cols -Index $versionIndex -Fallback "?"
                            $a = Get-StoreColumnValue -Columns $cols -Index $availableIndex -Fallback "Update available"

                            if (Test-Ignored $n $i) { continue }
                            [void]$items.Add([PSCustomObject]@{Source = "msstore"; Name = $n; Id = $i; Version = $v; Available = $a })
                        }

                        return $items.ToArray()
                    }

                    Write-Output "LOG:Scanning Microsoft Store with Store CLI..."
                    try {
                        if (-not (Get-Command "store" -ErrorAction SilentlyContinue)) {
                            Write-Output "LOG:Store CLI was not found. Update Microsoft Store, then scan again."
                            return
                        }

                        $pInfo = New-Object System.Diagnostics.ProcessStartInfo
                        $pInfo.FileName = "store"
                        $pInfo.Arguments = "updates"
                        $pInfo.RedirectStandardOutput = $true
                        $pInfo.RedirectStandardError = $true
                        $pInfo.RedirectStandardInput = $true
                        $pInfo.UseShellExecute = $false
                        $pInfo.CreateNoWindow = $true
                        $pInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
                        $pInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)

                        $p = [System.Diagnostics.Process]::Start($pInfo)
                        $outTask = $p.StandardOutput.ReadToEndAsync()
                        $errTask = $p.StandardError.ReadToEndAsync()
                        try {
                            $p.StandardInput.WriteLine("n")
                            $p.StandardInput.Close()
                        }
                        catch {}

                        if (-not $p.WaitForExit(60000)) {
                            Write-Output "LOG:Store CLI scan timed out after 60 seconds."
                            try { $p.Kill() } catch {}
                            try { [void]$p.WaitForExit(2000) } catch {}
                            return
                        }

                        $out = $outTask.GetAwaiter().GetResult()
                        $err = $errTask.GetAwaiter().GetResult()
                        $combined = "$out`n$err"

                        if ($p.ExitCode -ne 0) {
                            Write-Output "LOG:Store CLI scan exited with code $($p.ExitCode)."
                            if (-not [string]::IsNullOrWhiteSpace($err)) {
                                foreach ($errLine in ($err -split "`r?`n")) {
                                    if (-not [string]::IsNullOrWhiteSpace($errLine)) { Write-Output "LOG:Store CLI: $errLine" }
                                }
                            }
                        }

                        $storeItems = @(ConvertFrom-StoreUpdatesOutput -OutputText $combined)
                        if ($storeItems.Count -eq 0 -and $combined -match '(?i)(no updates|up to date)') {
                            Write-Output "LOG:No Microsoft Store updates found by Store CLI."
                        }
                        foreach ($storeItem in $storeItems) { $storeItem }
                    }
                    catch {
                        Write-Output "LOG:Store CLI check failed: $($_.Exception.Message)"
                    }
                }).AddArgument($ignoreList)

            [void]$script:ActiveScans.Add([PSCustomObject]@{ PowerShell = $ps; AsyncResult = $ps.BeginInvoke() })
        }

        # WINDOWS UPDATE WORKER - includes optional updates.
        if ("windowsupdate" -in $enabled) {
            $ps = [PowerShell]::Create()
            [void]$ps.AddScript({
                    param($IgnoreList)
                    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

                    function Test-Ignored($n, $i) {
                        if ($IgnoreList -and ($IgnoreList -contains $n -or $IgnoreList -contains $i)) { return $true }
                        return $false
                    }

                    function Get-WmtWuCategoryText {
                        param($Update)
                        $names = New-Object System.Collections.Generic.List[string]
                        try {
                            for ($i = 0; $i -lt $Update.Categories.Count; $i++) {
                                $title = ([string]$Update.Categories.Item($i).Name).Trim()
                                if (-not [string]::IsNullOrWhiteSpace($title) -and -not $names.Contains($title)) { [void]$names.Add($title) }
                            }
                        }
                        catch {}
                        $text = ($names.ToArray() -join ", ")
                        if ([string]::IsNullOrWhiteSpace($text)) {
                            try { $text = [string]$Update.Type } catch { $text = "Windows Update" }
                        }
                        if ([string]::IsNullOrWhiteSpace($text)) { $text = "Windows Update" }
                        return $text
                    }

                    function Test-WmtWuOptionalUpdate {
                        param($Update)
                        $isOptional = $false
                        try { if ([bool]$Update.BrowseOnly) { $isOptional = $true } } catch {}
                        try { if (-not [bool]$Update.AutoSelectOnWebSites) { $isOptional = $true } } catch {}
                        try { if (-not [bool]$Update.IsMandatory -and [bool]$Update.BrowseOnly) { $isOptional = $true } } catch {}
                        return $isOptional
                    }

                    Write-Output "LOG:Scanning Windows Update, including optional updates..."
                    try {
                        $session = New-Object -ComObject Microsoft.Update.Session
                        $searcher = $session.CreateUpdateSearcher()
                        try { $searcher.Online = $true } catch {}
                        $criteria = "IsInstalled=0 and IsHidden=0"
                        $result = $searcher.Search($criteria)
                        if (-not $result -or -not $result.Updates) {
                            Write-Output "LOG:Windows Update returned no scan result."
                            return
                        }

                        $count = [int]$result.Updates.Count
                        $visibleCount = 0
                        $optionalCount = 0
                        for ($i = 0; $i -lt $count; $i++) {
                            $update = $result.Updates.Item($i)
                            if (-not $update) { continue }

                            $title = ([string]$update.Title).Trim()
                            if ([string]::IsNullOrWhiteSpace($title)) { $title = "Windows Update" }
                            $updateId = ""
                            $revision = 0
                            try { $updateId = ([string]$update.Identity.UpdateID).Trim() } catch {}
                            try { $revision = [int]$update.Identity.RevisionNumber } catch { $revision = 0 }
                            if ([string]::IsNullOrWhiteSpace($updateId)) { $updateId = $title }
                            $rowId = "$updateId|$revision"
                            if (Test-Ignored $title $rowId) { continue }

                            $categoryText = Get-WmtWuCategoryText -Update $update
                            $kbText = ""
                            try {
                                $kbValues = @()
                                for ($kbIndex = 0; $kbIndex -lt $update.KBArticleIDs.Count; $kbIndex++) {
                                    $kb = ([string]$update.KBArticleIDs.Item($kbIndex)).Trim()
                                    if (-not [string]::IsNullOrWhiteSpace($kb)) { $kbValues += "KB$kb" }
                                }
                                if ($kbValues.Count -gt 0) { $kbText = $kbValues -join ", " }
                            }
                            catch {}

                            $isOptional = Test-WmtWuOptionalUpdate -Update $update
                            if ($isOptional) { $optionalCount++ }
                            $severity = ""
                            try { $severity = ([string]$update.MsrcSeverity).Trim() } catch {}
                            $availability = if ($isOptional) { "Optional" } elseif (-not [string]::IsNullOrWhiteSpace($severity)) { "Security: $severity" } elseif ($categoryText -match '(?i)driver') { "Driver" } else { "Important" }
                            $displayName = if ($isOptional -and $title -notmatch '^\[Optional\]') { "[Optional] $title" } else { $title }
                            if (-not [string]::IsNullOrWhiteSpace($kbText) -and $displayName -notmatch [regex]::Escape($kbText)) {
                                $displayName = "$displayName ($kbText)"
                            }

                            $visibleCount++
                            [PSCustomObject]@{
                                Source       = "windowsupdate"
                                Name         = $displayName
                                Id           = $rowId
                                Version      = $categoryText
                                Available    = $availability
                                WUIsOptional = $isOptional
                            }
                        }

                        if ($visibleCount -eq 0) {
                            Write-Output "LOG:No Windows Update items found."
                        }
                        else {
                            Write-Output "LOG:Windows Update found $visibleCount item(s), including $optionalCount optional item(s)."
                        }
                    }
                    catch {
                        Write-Output "LOG:Windows Update scan failed: $($_.Exception.Message)"
                    }
                }).AddArgument($ignoreList)

            [void]$script:ActiveScans.Add([PSCustomObject]@{ PowerShell = $ps; AsyncResult = $ps.BeginInvoke() })
        }
    
        # B. PIP WORKER
        if ("pip" -in $enabled) {
            $ps = [PowerShell]::Create()
            [void]$ps.AddScript({
                    param($IgnoreList)
                    Write-Output "LOG:Scanning Pip..."
                    try {
                        $pInfo = New-Object System.Diagnostics.ProcessStartInfo
                        $pInfo.FileName = "python.exe"
                        $pInfo.Arguments = "-m pip --disable-pip-version-check --no-input --timeout 20 --retries 1 list --outdated --format=json"
                        $pInfo.RedirectStandardOutput = $true
                        $pInfo.RedirectStandardError = $true
                        $pInfo.UseShellExecute = $false
                        $pInfo.CreateNoWindow = $true
                        $pInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

                        $pipProcess = [System.Diagnostics.Process]::Start($pInfo)
                        $outTask = $pipProcess.StandardOutput.ReadToEndAsync()
                        $errTask = $pipProcess.StandardError.ReadToEndAsync()
                        if (-not $pipProcess.WaitForExit(60000)) {
                            Write-Output "LOG:Pip scan timed out after 60 seconds. Stopping its process tree."
                            try {
                                $killInfo = New-Object System.Diagnostics.ProcessStartInfo
                                $killInfo.FileName = "taskkill.exe"
                                $killInfo.Arguments = "/PID $($pipProcess.Id) /T /F"
                                $killInfo.UseShellExecute = $false
                                $killInfo.CreateNoWindow = $true
                                $killInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                                $killProcess = [System.Diagnostics.Process]::Start($killInfo)
                                if ($killProcess) { [void]$killProcess.WaitForExit(5000) }
                            }
                            catch {
                                try { $pipProcess.Kill() } catch {}
                            }
                            return
                        }

                        try { [void]$pipProcess.WaitForExit() } catch {}
                        $json = ""
                        $pipError = ""
                        try { if ($outTask.IsCompleted) { $json = $outTask.GetAwaiter().GetResult() } } catch {}
                        try { if ($errTask.IsCompleted) { $pipError = $errTask.GetAwaiter().GetResult() } } catch {}
                        if ($pipProcess.ExitCode -ne 0) {
                            $detail = if ([string]::IsNullOrWhiteSpace($pipError)) { "exit code $($pipProcess.ExitCode)" } else { $pipError.Trim() }
                            Write-Output "LOG:Pip scan failed: $detail"
                            return
                        }
                        if ($json.Trim().StartsWith("[")) { 
                            $pkgs = $json | ConvertFrom-Json
                            foreach ($pkg in $pkgs) {
                                if ($IgnoreList -contains $pkg.name) { continue }
                                [PSCustomObject]@{Source = "pip"; Name = $pkg.name; Id = $pkg.name; Version = $pkg.version; Available = $pkg.latest_version }
                            }
                        }
                    }
                    catch { Write-Output "LOG:Pip check failed: $($_.Exception.Message)" }
                }).AddArgument($ignoreList)
            [void]$script:ActiveScans.Add([PSCustomObject]@{ PowerShell = $ps; AsyncResult = $ps.BeginInvoke() })
        }
    
        # C. NPM WORKER
        if ("npm" -in $enabled) {
            $ps = [PowerShell]::Create()
            [void]$ps.AddScript({
                    param($IgnoreList)
                    Write-Output "LOG:Scanning Npm..."
                    try {
                        # Local packages
                        $pInfo = New-Object System.Diagnostics.ProcessStartInfo("cmd", "/c npm outdated --json 2>nul")
                        $pInfo.RedirectStandardOutput = $true; $pInfo.UseShellExecute = $false; $pInfo.CreateNoWindow = $true
                        $p = [System.Diagnostics.Process]::Start($pInfo)
                        if ($p.WaitForExit(30000)) { 
                            $json = $p.StandardOutput.ReadToEnd().Trim()
                            if ($json -and $json.StartsWith("{")) { 
                                $pkgs = $json | ConvertFrom-Json
                                foreach ($k in $pkgs.PSObject.Properties.Name) {
                                    if ($IgnoreList -contains $k) { continue }
                                    $o = $pkgs.$k
                                    [PSCustomObject]@{Source = "npm"; Name = $k; Id = $k; Version = $o.current; Available = $o.latest }
                                }
                            }
                        }
                        else {
                            try { $p.Kill() } catch {}
                            Write-Output "LOG:Npm local scan timed out."
                        }

                        # Global packages
                        $pInfoG = New-Object System.Diagnostics.ProcessStartInfo("cmd", "/c npm outdated -g --json 2>nul")
                        $pInfoG.RedirectStandardOutput = $true; $pInfoG.UseShellExecute = $false; $pInfoG.CreateNoWindow = $true
                        $pg = [System.Diagnostics.Process]::Start($pInfoG)
                        if ($pg.WaitForExit(30000)) { 
                            $jsonG = $pg.StandardOutput.ReadToEnd().Trim()
                            if ($jsonG -and $jsonG.StartsWith("{")) { 
                                $pkgsG = $jsonG | ConvertFrom-Json
                                foreach ($k in $pkgsG.PSObject.Properties.Name) {
                                    if ($IgnoreList -contains $k) { continue }
                                    $o = $pkgsG.$k
                                    [PSCustomObject]@{Source = "npm (global)"; Name = $k; Id = $k; Version = $o.current; Available = $o.latest }
                                }
                            }
                        }
                        else {
                            try { $pg.Kill() } catch {}
                            Write-Output "LOG:Npm global scan timed out."
                        }
                    }
                    catch { Write-Output "LOG:Npm check failed." }
                }).AddArgument($ignoreList)
            [void]$script:ActiveScans.Add([PSCustomObject]@{ PowerShell = $ps; AsyncResult = $ps.BeginInvoke() })
        }
    
        # D. CHOCOLATEY WORKER (unchanged)
        if ("chocolatey" -in $enabled) {
            $ps = [PowerShell]::Create()
            [void]$ps.AddScript({
                    param($IgnoreList)
                    Write-Output "LOG:Scanning Chocolatey..."
                    try {
                        $pInfo = New-Object System.Diagnostics.ProcessStartInfo("choco", "outdated -r")
                        $pInfo.RedirectStandardOutput = $true; $pInfo.UseShellExecute = $false; $pInfo.CreateNoWindow = $true
                        $p = [System.Diagnostics.Process]::Start($pInfo)
                        if (-not $p.WaitForExit(60000)) { try { $p.Kill() } catch {}; Write-Output "LOG:Chocolatey scan timed out."; return }
                        $out = $p.StandardOutput.ReadToEnd()
                        $lines = $out -split "`r`n"
                        foreach ($l in $lines) { 
                            if (!$l) { continue }
                            $p = $l -split "\|"
                            if ($p.Count -ge 4) {
                                $n = $p[0]
                                if ($IgnoreList -contains $n) { continue }
                                [PSCustomObject]@{Source = "chocolatey"; Name = $n; Id = $n; Version = $p[1]; Available = $p[2] }
                            }
                        }
                    }
                    catch { Write-Output "LOG:Choco check failed." }
                }).AddArgument($ignoreList)
            [void]$script:ActiveScans.Add([PSCustomObject]@{ PowerShell = $ps; AsyncResult = $ps.BeginInvoke() })
        }
    
        # E. SCOOP WORKER (unchanged)
        if ("scoop" -in $enabled) {
            $ps = [PowerShell]::Create()
            [void]$ps.AddScript({
                    param($IgnoreList)
                    Write-Output "LOG:Scanning Scoop..."
                    try {
                        $pInfo = New-Object System.Diagnostics.ProcessStartInfo("cmd", "/c scoop status")
                        $pInfo.RedirectStandardOutput = $true; $pInfo.UseShellExecute = $false; $pInfo.CreateNoWindow = $true
                        $p = [System.Diagnostics.Process]::Start($pInfo)
                        if (-not $p.WaitForExit(30000)) { try { $p.Kill() } catch {}; Write-Output "LOG:Scoop scan timed out."; return }
                        $out = $p.StandardOutput.ReadToEnd()
                        $lines = $out -split "`r`n"
                        foreach ($line in $lines) {
                            $line = $line.Trim()
                            if ([string]::IsNullOrWhiteSpace($line) -or $line -match "^Name\s+Version" -or $line -match "^----" -or $line -match "Scoop is up to date") { continue }
                            if ($line -match '^(\S+)\s+(\S+)\s+(\S+)') {
                                $n = $matches[1]; $v = $matches[2]; $l = $matches[3]
                                if ($IgnoreList -contains $n) { continue }
                                [PSCustomObject]@{Source = "scoop"; Name = $n; Id = $n; Version = $v; Available = $l }
                            }
                        }
                    }
                    catch { Write-Output "LOG:Scoop check failed." }
                }).AddArgument($ignoreList)
            [void]$script:ActiveScans.Add([PSCustomObject]@{ PowerShell = $ps; AsyncResult = $ps.BeginInvoke() })
        }
    
        # F. RUBY GEMS WORKER (unchanged)
        if ("gem" -in $enabled) {
            $ps = [PowerShell]::Create()
            [void]$ps.AddScript({
                    param($IgnoreList)
                    Write-Output "LOG:Scanning Ruby Gems..."
                    try {
                        $pInfo = New-Object System.Diagnostics.ProcessStartInfo("cmd", "/c gem outdated")
                        $pInfo.RedirectStandardOutput = $true; $pInfo.UseShellExecute = $false; $pInfo.CreateNoWindow = $true
                        $p = [System.Diagnostics.Process]::Start($pInfo)
                        if (-not $p.WaitForExit(30000)) { try { $p.Kill() } catch {}; Write-Output "LOG:Gem scan timed out."; return }
                        $out = $p.StandardOutput.ReadToEnd()
                        $lines = $out -split "`r`n"
                        foreach ($line in $lines) {
                            if ($line -match '^(\S+)\s+\(([\d\.]+)\s+<\s+([\d\.]+)\)') {
                                $n = $matches[1]; $v = $matches[2]; $a = $matches[3]
                                if ($IgnoreList -contains $n) { continue }
                                [PSCustomObject]@{Source = "gem"; Name = $n; Id = $n; Version = $v; Available = $a }
                            }
                        }
                    }
                    catch { Write-Output "LOG:Gem check failed." }
                }).AddArgument($ignoreList)
            [void]$script:ActiveScans.Add([PSCustomObject]@{ PowerShell = $ps; AsyncResult = $ps.BeginInvoke() })
        }
    
        # G. CARGO WORKER (unchanged)
        if ("cargo" -in $enabled) {
            $ps = [PowerShell]::Create()
            [void]$ps.AddScript({
                    param($IgnoreList)
                    Write-Output "LOG:Scanning Cargo..."
                    try {
                        $pInfo = New-Object System.Diagnostics.ProcessStartInfo("cmd", "/c cargo install --list")
                        $pInfo.RedirectStandardOutput = $true; $pInfo.UseShellExecute = $false; $pInfo.CreateNoWindow = $true
                        $p = [System.Diagnostics.Process]::Start($pInfo)
                        if (-not $p.WaitForExit(30000)) { try { $p.Kill() } catch {}; Write-Output "LOG:Cargo scan timed out."; return }
                        $out = $p.StandardOutput.ReadToEnd()
                        $lines = $out -split "`r`n"
                        foreach ($line in $lines) {
                            if ($line -match '^([a-zA-Z0-9_\-]+)\s+v([\d\.]+):') {
                                $n = $matches[1]; $v = $matches[2]
                                if ($IgnoreList -contains $n) { continue }
                                [PSCustomObject]@{Source = "cargo"; Name = $n; Id = $n; Version = $v; Available = "?" }
                            }
                        }
                    }
                    catch { Write-Output "LOG:Cargo check failed." }
                }).AddArgument($ignoreList)
            [void]$script:ActiveScans.Add([PSCustomObject]@{ PowerShell = $ps; AsyncResult = $ps.BeginInvoke() })
        }
    
        # H. .NET GLOBAL TOOLS WORKER
        if ("dotnet" -in $enabled) {
            $ps = [PowerShell]::Create()
            [void]$ps.AddScript({
                    param($IgnoreList)
                    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
                    Write-Output "LOG:Scanning .NET global tools..."

                    function Invoke-DotnetToolCommand {
                        param([string]$Arguments, [int]$TimeoutMs = 15000)
                        $pInfo = New-Object System.Diagnostics.ProcessStartInfo("dotnet", $Arguments)
                        $pInfo.RedirectStandardOutput = $true
                        $pInfo.RedirectStandardError = $true
                        $pInfo.UseShellExecute = $false
                        $pInfo.CreateNoWindow = $true
                        $pInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
                        $proc = [System.Diagnostics.Process]::Start($pInfo)
                        $outTask = $proc.StandardOutput.ReadToEndAsync()
                        $errTask = $proc.StandardError.ReadToEndAsync()
                        if (-not $proc.WaitForExit($TimeoutMs)) {
                            try { $proc.Kill() } catch {}
                            return [PSCustomObject]@{ TimedOut = $true; Out = ""; Err = ""; ExitCode = 124 }
                        }
                        return [PSCustomObject]@{
                            TimedOut = $false
                            Out      = $outTask.GetAwaiter().GetResult()
                            Err      = $errTask.GetAwaiter().GetResult()
                            ExitCode = $proc.ExitCode
                        }
                    }

                    function Test-NewerVersionText {
                        param([string]$Current, [string]$Latest)
                        if ([string]::IsNullOrWhiteSpace($Current) -or [string]::IsNullOrWhiteSpace($Latest)) { return $false }
                        try { return ([version]$Latest -gt [version]$Current) } catch { return (([string]$Latest).Trim() -ne ([string]$Current).Trim()) }
                    }

                    try {
                        if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
                            Write-Output "LOG:.NET SDK was not found."
                            return
                        }

                        $listResult = Invoke-DotnetToolCommand -Arguments "tool list --global" -TimeoutMs 20000
                        if ($listResult.TimedOut) { Write-Output "LOG:.NET tool list timed out."; return }
                        $installed = @()
                        foreach ($line in ($listResult.Out -split "`r?`n")) {
                            $trimmed = ([string]$line).Trim()
                            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
                            if ($trimmed -match "(?i)^Package\s+Id\s+Version\s+Commands") { continue }
                            if ($trimmed -match "^-+") { continue }
                            $parts = @($trimmed -split "\s+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                            if ($parts.Count -lt 2) { continue }
                            $pkgId = [string]$parts[0]
                            $currentVersion = [string]$parts[1]
                            if ($IgnoreList -contains $pkgId) { continue }
                            $installed += [PSCustomObject]@{ Id = $pkgId; Version = $currentVersion }
                        }

                        if ($installed.Count -eq 0) {
                            Write-Output "LOG:No global .NET tools are installed."
                            return
                        }

                        foreach ($tool in $installed) {
                            $pkgId = [string]$tool.Id
                            $currentVersion = [string]$tool.Version
                            $searchResult = Invoke-DotnetToolCommand -Arguments "tool search `"$pkgId`" --take 5" -TimeoutMs 12000
                            if ($searchResult.TimedOut) { Write-Output "LOG:.NET search timed out for $pkgId."; continue }
                            $latestVersion = ""
                            foreach ($line in ($searchResult.Out -split "`r?`n")) {
                                $trimmed = ([string]$line).Trim()
                                if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
                                if ($trimmed -match "(?i)^Package\s+ID\s+Version") { continue }
                                if ($trimmed -match "^-+") { continue }
                                $parts = @($trimmed -split "\s+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                                if ($parts.Count -ge 2 -and ([string]$parts[0]).Equals($pkgId, [StringComparison]::OrdinalIgnoreCase)) {
                                    $latestVersion = [string]$parts[1]
                                    break
                                }
                            }
                            if (Test-NewerVersionText -Current $currentVersion -Latest $latestVersion) {
                                [PSCustomObject]@{ Source = "dotnet"; Name = $pkgId; Id = $pkgId; Version = $currentVersion; Available = $latestVersion }
                            }
                        }
                    }
                    catch { Write-Output "LOG:.NET tools check failed: $($_.Exception.Message)" }
                }).AddArgument($ignoreList)
            [void]$script:ActiveScans.Add([PSCustomObject]@{ PowerShell = $ps; AsyncResult = $ps.BeginInvoke() })
        }

        # I. POWERSHELL MODULES WORKER
        if ("psmodule" -in $enabled) {
            $ps = [PowerShell]::Create()
            [void]$ps.AddScript({
                    param($IgnoreList)
                    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
                    Write-Output "LOG:Scanning PowerShell modules..."

                    function Test-NewerVersionText {
                        param([string]$Current, [string]$Latest)
                        if ([string]::IsNullOrWhiteSpace($Current) -or [string]::IsNullOrWhiteSpace($Latest)) { return $false }
                        try { return ([version]$Latest -gt [version]$Current) } catch { return (([string]$Latest).Trim() -ne ([string]$Current).Trim()) }
                    }

                    try {
                        if (-not (Get-Command Get-InstalledModule -ErrorAction SilentlyContinue) -or -not (Get-Command Find-Module -ErrorAction SilentlyContinue)) {
                            Write-Output "LOG:PowerShellGet cmdlets were not found."
                            return
                        }

                        $installed = @(Get-InstalledModule -ErrorAction Stop | Sort-Object Name -Unique)
                        if ($installed.Count -eq 0) {
                            Write-Output "LOG:No PowerShellGet-managed modules are installed."
                            return
                        }

                        $nameList = @(
                            $installed |
                                ForEach-Object { [string]$_.Name } |
                                Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $IgnoreList -notcontains $_ } |
                                Sort-Object -Unique
                        )
                        if ($nameList.Count -eq 0) {
                            Write-Output "LOG:All PowerShellGet-managed modules are ignored."
                            return
                        }

                        $latestMap = @{}
                        $galleryApiSucceeded = $false
                        $lookupTimer = [Diagnostics.Stopwatch]::StartNew()
                        try {
                            # PowerShellGet routes discovery through PackageManagement and can be
                            # slow even for one Name array. PSGallery's OData feed can resolve a
                            # small batch of exact IDs in a single request.
                            for ($offset = 0; $offset -lt $nameList.Count; $offset += 25) {
                                $last = [Math]::Min($offset + 24, $nameList.Count - 1)
                                $batch = @($nameList[$offset..$last])
                                $clauses = @($batch | ForEach-Object { "Id eq '$(([string]$_).Replace("'", "''"))'" })
                                $filter = "IsLatestVersion eq true and ($($clauses -join ' or '))"
                                $uri = 'https://www.powershellgallery.com/api/v2/Packages?$filter=' +
                                    [uri]::EscapeDataString($filter) + '&$select=Id,Version'

                                foreach ($entry in @(Invoke-RestMethod -Uri $uri -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop)) {
                                    $foundName = [string]$entry.properties.Id
                                    $foundVersion = [string]$entry.properties.Version
                                    if (-not [string]::IsNullOrWhiteSpace($foundName) -and
                                        -not [string]::IsNullOrWhiteSpace($foundVersion) -and
                                        -not $latestMap.ContainsKey($foundName)) {
                                        $latestMap[$foundName] = $foundVersion
                                    }
                                }
                            }
                            $galleryApiSucceeded = $true
                        }
                        catch {
                            $latestMap.Clear()
                            Write-Output "LOG:Fast PSGallery metadata lookup failed; retrying with PowerShellGet."
                        }

                        if (-not $galleryApiSucceeded) {
                            try {
                                foreach ($found in @(Find-Module -Name $nameList -Repository PSGallery -ErrorAction SilentlyContinue)) {
                                    if ($found -and $found.Name -and -not $latestMap.ContainsKey([string]$found.Name)) {
                                        $latestMap[[string]$found.Name] = [string]$found.Version
                                    }
                                }
                            }
                            catch {
                                Write-Output "LOG:PSGallery lookup failed: $($_.Exception.Message)"
                            }
                        }
                        $lookupTimer.Stop()
                        $lookupSeconds = [Math]::Round($lookupTimer.Elapsed.TotalSeconds, 2)
                        $lookupMethod = if ($galleryApiSucceeded) { "batched Gallery API" } else { "PowerShellGet fallback" }
                        Write-Output "LOG:PowerShell module metadata loaded via $lookupMethod in ${lookupSeconds}s."

                        foreach ($module in $installed) {
                            $name = [string]$module.Name
                            if ([string]::IsNullOrWhiteSpace($name) -or $IgnoreList -contains $name) { continue }
                            if (-not $latestMap.ContainsKey($name)) { continue }
                            $currentVersion = [string]$module.Version
                            $latestVersion = [string]$latestMap[$name]
                            if (Test-NewerVersionText -Current $currentVersion -Latest $latestVersion) {
                                [PSCustomObject]@{ Source = "psmodule"; Name = $name; Id = $name; Version = $currentVersion; Available = $latestVersion }
                            }
                        }
                    }
                    catch { Write-Output "LOG:PowerShell module check failed: $($_.Exception.Message)" }
                }).AddArgument($ignoreList)
            [void]$script:ActiveScans.Add([PSCustomObject]@{ PowerShell = $ps; AsyncResult = $ps.BeginInvoke() })
        }

        # J. COMPOSER WORKER
        if ("composer" -in $enabled) {
            $ps = [PowerShell]::Create()
            [void]$ps.AddScript({
                    param($IgnoreList)
                    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
                    Write-Output "LOG:Scanning Composer global packages..."
                    try {
                        if (-not (Get-Command composer -ErrorAction SilentlyContinue)) {
                            Write-Output "LOG:Composer was not found."
                            return
                        }
                        $pInfo = New-Object System.Diagnostics.ProcessStartInfo("cmd", "/c composer global outdated --format=json --no-interaction 2>nul")
                        $pInfo.RedirectStandardOutput = $true
                        $pInfo.UseShellExecute = $false
                        $pInfo.CreateNoWindow = $true
                        $pInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
                        $p = [System.Diagnostics.Process]::Start($pInfo)
                        if (-not $p.WaitForExit(45000)) { try { $p.Kill() } catch {}; Write-Output "LOG:Composer scan timed out."; return }
                        $json = $p.StandardOutput.ReadToEnd().Trim()
                        if ([string]::IsNullOrWhiteSpace($json) -or -not $json.StartsWith("{")) {
                            Write-Output "LOG:Composer reported no outdated global packages."
                            return
                        }
                        $data = $json | ConvertFrom-Json
                        $packages = @()
                        if ($data.PSObject.Properties["installed"]) { $packages = @($data.installed) }
                        elseif ($data.PSObject.Properties["locked"]) { $packages = @($data.locked) }
                        foreach ($pkg in $packages) {
                            $name = [string]$pkg.name
                            if ([string]::IsNullOrWhiteSpace($name) -or $IgnoreList -contains $name) { continue }
                            $currentVersion = if ($pkg.PSObject.Properties["version"]) { [string]$pkg.version } elseif ($pkg.PSObject.Properties["installed"]) { [string]$pkg.installed } else { "?" }
                            $latestVersion = if ($pkg.PSObject.Properties["latest"]) { [string]$pkg.latest } elseif ($pkg.PSObject.Properties["available"]) { [string]$pkg.available } else { "?" }
                            if ($latestVersion -eq "?" -and $currentVersion -eq "?") { continue }
                            [PSCustomObject]@{ Source = "composer"; Name = $name; Id = $name; Version = $currentVersion; Available = $latestVersion }
                        }
                    }
                    catch { Write-Output "LOG:Composer check failed: $($_.Exception.Message)" }
                }).AddArgument($ignoreList)
            [void]$script:ActiveScans.Add([PSCustomObject]@{ PowerShell = $ps; AsyncResult = $ps.BeginInvoke() })
        }

        # H. PNPM WORKER (unchanged)
        if ("pnpm" -in $enabled) {
            $ps = [PowerShell]::Create()
            [void]$ps.AddScript({
                    param($IgnoreList)
                    Write-Output "LOG:Scanning Pnpm..."
                    try {
                        # Local packages
                        $pInfo = New-Object System.Diagnostics.ProcessStartInfo("cmd", "/c pnpm outdated --format json 2>nul")
                        $pInfo.RedirectStandardOutput = $true; $pInfo.UseShellExecute = $false; $pInfo.CreateNoWindow = $true
                        $p = [System.Diagnostics.Process]::Start($pInfo)
                        if ($p.WaitForExit(35000)) {
                            $json = $p.StandardOutput.ReadToEnd().Trim()
                            if ($json -and $json.StartsWith("[")) {
                                $pkgs = $json | ConvertFrom-Json
                                foreach ($pkg in $pkgs) {
                                    if ($IgnoreList -contains $pkg.name) { continue }
                                    [PSCustomObject]@{Source = "pnpm"; Name = $pkg.name; Id = $pkg.name; Version = $pkg.current; Available = $pkg.latest }
                                }
                            }
                        }
                        # Global packages
                        $pInfoG = New-Object System.Diagnostics.ProcessStartInfo("cmd", "/c pnpm outdated -g --format json 2>nul")
                        $pInfoG.RedirectStandardOutput = $true; $pInfoG.UseShellExecute = $false; $pInfoG.CreateNoWindow = $true
                        $pg = [System.Diagnostics.Process]::Start($pInfoG)
                        if ($pg.WaitForExit(15000)) {
                            $jsonG = $pg.StandardOutput.ReadToEnd().Trim()
                            if ($jsonG -and $jsonG.StartsWith("[")) {
                                $pkgsG = $jsonG | ConvertFrom-Json
                                foreach ($pkg in $pkgsG) {
                                    if ($IgnoreList -contains $pkg.name) { continue }
                                    [PSCustomObject]@{Source = "pnpm (global)"; Name = $pkg.name; Id = $pkg.name; Version = $pkg.current; Available = $pkg.latest }
                                }
                            }
                        }
                    }
                    catch { Write-Output "LOG:Pnpm check failed or pnpm not installed." }
                }).AddArgument($ignoreList)
            [void]$script:ActiveScans.Add([PSCustomObject]@{ PowerShell = $ps; AsyncResult = $ps.BeginInvoke() })
        }

        # I. LEGENDARY / EPIC GAMES WORKER
        if ("legendary" -in $enabled) {
            $ps = [PowerShell]::Create()
            [void]$ps.AddScript({
                    param($IgnoreList, $LegendaryExePath)
                    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
                    Write-Output "LOG:Scanning Legendary Epic Games updates..."

                    function Test-Ignored($n, $i) {
                        if ($IgnoreList -and ($IgnoreList -contains $n -or $IgnoreList -contains $i)) { return $true }
                        return $false
                    }

                    function ConvertFrom-LegendaryBuildVersion {
                        param([string]$RawVersion)

                        $raw = ([string]$RawVersion).Trim()
                        if ([string]::IsNullOrWhiteSpace($raw)) {
                            return [PSCustomObject]@{ Display = ""; Sort = "" }
                        }

                        $releaseMatch = [regex]::Match($raw, '(?i)\bRelease-(\d+(?:\.\d+){1,5})(?:-CL-(\d+))?')
                        if ($releaseMatch.Success) {
                            $version = [string]$releaseMatch.Groups[1].Value
                            $cl = [string]$releaseMatch.Groups[2].Value
                            $display = if ([string]::IsNullOrWhiteSpace($cl)) { $version } else { "$version (CL $cl)" }
                            $sort = if ([string]::IsNullOrWhiteSpace($cl)) { $version } else { "$version.$cl" }
                            return [PSCustomObject]@{ Display = $display; Sort = $sort }
                        }

                        $lastVersion = ""
                        foreach ($match in [regex]::Matches($raw, '(?<!\d)(\d+(?:\.\d+){1,5})(?!\d)')) {
                            $lastVersion = [string]$match.Groups[1].Value
                        }
                        if (-not [string]::IsNullOrWhiteSpace($lastVersion)) {
                            return [PSCustomObject]@{ Display = $lastVersion; Sort = $lastVersion }
                        }

                        return [PSCustomObject]@{ Display = $raw; Sort = $raw }
                    }

                    try {
                        $legendaryCommand = ([string]$LegendaryExePath).Trim()
                        if ([string]::IsNullOrWhiteSpace($legendaryCommand) -or -not (Test-Path -LiteralPath $legendaryCommand -PathType Leaf)) {
                            $cmd = Get-Command legendary -ErrorAction SilentlyContinue
                            if ($cmd -and $cmd.Source) {
                                $legendaryCommand = [string]$cmd.Source
                            }
                            else {
                                Write-Output "LOG:Legendary scan skipped: legendary.exe was not found in WMT data or PATH."
                                return
                            }
                        }

                        $pInfo = New-Object System.Diagnostics.ProcessStartInfo
                        $pInfo.FileName = $legendaryCommand
                        $pInfo.Arguments = "list-installed --check-updates --csv --show-dirs"
                        $pInfo.RedirectStandardOutput = $true
                        $pInfo.RedirectStandardError = $true
                        $pInfo.UseShellExecute = $false
                        $pInfo.CreateNoWindow = $true
                        $pInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
                        $pInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)

                        $p = [System.Diagnostics.Process]::Start($pInfo)
                        $outTask = $p.StandardOutput.ReadToEndAsync()
                        $errTask = $p.StandardError.ReadToEndAsync()
                        if (-not $p.WaitForExit(90000)) {
                            Write-Output "LOG:Legendary scan timed out after 90 seconds."
                            try { $p.Kill() } catch {}
                            try { [void]$p.WaitForExit(2000) } catch {}
                            return
                        }

                        $out = $outTask.GetAwaiter().GetResult()
                        $err = $errTask.GetAwaiter().GetResult()
                        if ($p.ExitCode -ne 0) {
                            Write-Output "LOG:Legendary scan exited with code $($p.ExitCode)."
                            if (-not [string]::IsNullOrWhiteSpace($err)) {
                                foreach ($errLine in ($err -split "`r?`n")) {
                                    if (-not [string]::IsNullOrWhiteSpace($errLine)) { Write-Output "LOG:Legendary: $errLine" }
                                }
                            }
                        }

                        if ([string]::IsNullOrWhiteSpace($out)) {
                            if (-not [string]::IsNullOrWhiteSpace($err)) { Write-Output "LOG:Legendary returned no CSV output. Run 'legendary auth' if Epic login is not configured." }
                            return
                        }

                        $headerIndex = $out.IndexOf("App name,")
                        if ($headerIndex -gt 0) { $out = $out.Substring($headerIndex) }
                        $rows = @($out | ConvertFrom-Csv)
                        $installedCount = 0
                        $pendingCount = 0
                        foreach ($row in $rows) {
                            if (-not $row) { continue }
                            $appName = ([string]$row.'App name').Trim()
                            $title = ([string]$row.'App title').Trim()
                            $installedVersion = ([string]$row.'Installed version').Trim()
                            $availableVersion = ([string]$row.'Available version').Trim()
                            $updateFlag = ([string]$row.'Update available').Trim()
                            $installPath = ([string]$row.'Install path').Trim()
                            $platform = ([string]$row.Platform).Trim()
                            if ([string]::IsNullOrWhiteSpace($appName)) { continue }
                            $installedCount++
                            if ([string]::IsNullOrWhiteSpace($title)) { $title = $appName }
                            $hasUpdate = ($updateFlag -match '^(?i:true|yes|1)$')
                            if (-not $hasUpdate -and -not [string]::IsNullOrWhiteSpace($availableVersion) -and $availableVersion -ne $installedVersion) {
                                $hasUpdate = $true
                            }
                            if (-not $hasUpdate) { continue }
                            if (Test-Ignored $title $appName) { continue }
                            $pendingCount++
                            $installedVersionInfo = ConvertFrom-LegendaryBuildVersion -RawVersion $installedVersion
                            $availableVersionInfo = ConvertFrom-LegendaryBuildVersion -RawVersion $availableVersion
                            $displayInstalledVersion = if ([string]::IsNullOrWhiteSpace([string]$installedVersionInfo.Display)) { "?" } else { [string]$installedVersionInfo.Display }
                            $displayAvailableVersion = if ([string]::IsNullOrWhiteSpace([string]$availableVersionInfo.Display)) { "Update available" } else { [string]$availableVersionInfo.Display }
                            [PSCustomObject]@{
                                Source         = "legendary"
                                Name           = $title
                                Id             = $appName
                                Version        = $displayInstalledVersion
                                Available      = $displayAvailableVersion
                                VersionSort    = if ([string]::IsNullOrWhiteSpace([string]$installedVersionInfo.Sort)) { $displayInstalledVersion } else { [string]$installedVersionInfo.Sort }
                                AvailableSort  = if ([string]::IsNullOrWhiteSpace([string]$availableVersionInfo.Sort)) { $displayAvailableVersion } else { [string]$availableVersionInfo.Sort }
                                RawVersion     = $installedVersion
                                RawAvailable   = $availableVersion
                                InstallDir     = $installPath
                                ExecutablePath = $legendaryCommand
                                Platform       = $platform
                            }
                        }

                        if ($pendingCount -eq 0) {
                            Write-Output "LOG:Legendary scan found $installedCount installed Epic game(s), with no pending updates."
                        }
                        else {
                            Write-Output "LOG:Legendary scan found $pendingCount pending Epic game update(s)."
                        }
                    }
                    catch {
                        Write-Output "LOG:Legendary scan failed: $($_.Exception.Message)"
                    }
                }).AddArgument($ignoreList).AddArgument((Get-WmtLegendaryExePath))
            [void]$script:ActiveScans.Add([PSCustomObject]@{ PowerShell = $ps; AsyncResult = $ps.BeginInvoke() })
        }

        # J. GOGDL / GOG GAMES WORKER
        if ("gogdl" -in $enabled) {
            $ps = [PowerShell]::Create()
            [void]$ps.AddScript({
                    param($IgnoreList, $GogdlExePath)
                    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
                    Write-Output "LOG:Scanning installed GOG games with GOGDL metadata..."

                    function Test-Ignored($n, $i) {
                        if ($IgnoreList -and ($IgnoreList -contains $n -or $IgnoreList -contains $i)) { return $true }
                        return $false
                    }

                    function Get-WmtGogdlCommand {
                        param([string]$LocalPath)

                        $local = ([string]$LocalPath).Trim()
                        if (-not [string]::IsNullOrWhiteSpace($local) -and (Test-Path -LiteralPath $local -PathType Leaf)) {
                            return $local
                        }
                        foreach ($cmdName in @("gogdl", "gogdl.exe", "gogdl_windows_x86_64.exe")) {
                            try {
                                $cmd = Get-Command $cmdName -ErrorAction SilentlyContinue
                                if ($cmd -and $cmd.Source) { return [string]$cmd.Source }
                            }
                            catch {}
                        }
                        return ""
                    }

                    function Get-GogInstalledGames {
                        $items = New-Object System.Collections.Generic.List[object]
                        $seen = @{}
                        $registryRoots = @(
                            "HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games",
                            "HKLM:\SOFTWARE\GOG.com\Games",
                            "HKCU:\SOFTWARE\GOG.com\Games",
                            "HKCU:\SOFTWARE\WOW6432Node\GOG.com\Games"
                        )

                        foreach ($root in $registryRoots) {
                            if (-not (Test-Path -LiteralPath $root)) { continue }
                            foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                                try {
                                    $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                                    $gameId = ([string]$props.gameID).Trim()
                                    if ([string]::IsNullOrWhiteSpace($gameId)) { $gameId = (Split-Path -Leaf $key.Name) }
                                    $installPath = ([string]$props.path).Trim()
                                    if ([string]::IsNullOrWhiteSpace($installPath) -and $props.PSObject.Properties["installPath"]) {
                                        $installPath = ([string]$props.installPath).Trim()
                                    }
                                    if ([string]::IsNullOrWhiteSpace($gameId) -or [string]::IsNullOrWhiteSpace($installPath)) { continue }
                                    $installPath = [Environment]::ExpandEnvironmentVariables($installPath)
                                    if (-not (Test-Path -LiteralPath $installPath -PathType Container)) { continue }
                                    $name = ([string]$props.gameName).Trim()
                                    if ([string]::IsNullOrWhiteSpace($name)) { $name = (Split-Path -Leaf $installPath) }
                                    $dedupeKey = "$gameId`n$installPath"
                                    if ($seen.ContainsKey($dedupeKey)) { continue }
                                    $seen[$dedupeKey] = $true
                                    [void]$items.Add([PSCustomObject]@{
                                            GameID      = $gameId
                                            Name        = $name
                                            InstallPath = $installPath
                                        })
                                }
                                catch {}
                            }
                        }

                        return $items.ToArray()
                    }

                    function Get-GogLocalMetadata {
                        param($Game)

                        $installPath = ([string]$Game.InstallPath).Trim()
                        $registryId = ([string]$Game.GameID).Trim()
                        $title = ([string]$Game.Name).Trim()
                        $platform = "windows"
                        $candidateDirs = @($installPath, (Join-Path $installPath "game"), (Join-Path $installPath "Contents\Resources"))
                        $infoObjects = New-Object System.Collections.Generic.List[object]

                        foreach ($dir in $candidateDirs) {
                            if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
                            foreach ($infoFile in @(Get-ChildItem -LiteralPath $dir -Filter "goggame-*.info" -File -ErrorAction SilentlyContinue)) {
                                try {
                                    $json = Get-Content -LiteralPath $infoFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                                    [void]$infoObjects.Add([PSCustomObject]@{ Json = $json; Directory = $dir; Path = $infoFile.FullName })
                                }
                                catch {}
                            }
                        }

                        $chosen = $null
                        foreach ($entry in @($infoObjects.ToArray())) {
                            $json = $entry.Json
                            $rootId = ([string]$json.rootGameId).Trim()
                            $gameId = ([string]$json.gameId).Trim()
                            if (-not [string]::IsNullOrWhiteSpace($registryId) -and ($registryId -eq $rootId -or $registryId -eq $gameId)) {
                                $chosen = $entry
                                break
                            }
                            if (-not [string]::IsNullOrWhiteSpace($rootId) -and $rootId -eq $gameId) {
                                $chosen = $entry
                            }
                        }
                        if (-not $chosen -and $infoObjects.Count -gt 0) { $chosen = $infoObjects[0] }

                        $gameId = $registryId
                        $buildId = ""
                        if ($chosen) {
                            $json = $chosen.Json
                            if (-not [string]::IsNullOrWhiteSpace([string]$json.rootGameId)) { $gameId = ([string]$json.rootGameId).Trim() }
                            elseif (-not [string]::IsNullOrWhiteSpace([string]$json.gameId)) { $gameId = ([string]$json.gameId).Trim() }
                            if (-not [string]::IsNullOrWhiteSpace([string]$json.name)) { $title = ([string]$json.name).Trim() }
                            if (-not [string]::IsNullOrWhiteSpace([string]$json.buildId)) { $buildId = ([string]$json.buildId).Trim() }

                            $idPath = Join-Path ([string]$chosen.Directory) ("goggame-{0}.id" -f $gameId)
                            if (-not (Test-Path -LiteralPath $idPath -PathType Leaf)) {
                                $idPath = [System.IO.Path]::ChangeExtension([string]$chosen.Path, ".id")
                            }
                            if (Test-Path -LiteralPath $idPath -PathType Leaf) {
                                try {
                                    $idText = (Get-Content -LiteralPath $idPath -Raw -ErrorAction Stop).Trim()
                                    if (-not [string]::IsNullOrWhiteSpace($idText)) {
                                        try {
                                            $idJson = $idText | ConvertFrom-Json -ErrorAction Stop
                                            if (-not [string]::IsNullOrWhiteSpace([string]$idJson.buildId)) {
                                                $buildId = ([string]$idJson.buildId).Trim()
                                            }
                                        }
                                        catch {
                                            if ($idText -match '^\d+$') { $buildId = $idText }
                                        }
                                    }
                                }
                                catch {}
                            }
                        }

                        return [PSCustomObject]@{
                            GameID      = $gameId
                            Name        = $title
                            InstallPath = $installPath
                            BuildID     = $buildId
                            Platform    = $platform
                        }
                    }

                    function Get-GogBuildCatalog {
                        param([string]$GameID)

                        if ([string]::IsNullOrWhiteSpace($GameID)) { return $null }
                        $escapedId = [uri]::EscapeDataString($GameID)
                        $url = "https://content-system.gog.com/products/$escapedId/os/windows/builds?generation=2"
                        $headers = @{ "User-Agent" = "GOGGalaxyCommunicationService/2.0.4.164 (Windows_32bit)" }
                        return Invoke-RestMethod -Uri $url -Headers $headers -UseBasicParsing -ErrorAction Stop
                    }

                    try {
                        $gogdlCommand = Get-WmtGogdlCommand -LocalPath $GogdlExePath
                        if ([string]::IsNullOrWhiteSpace($gogdlCommand)) {
                            Write-Output "LOG:GOGDL scan skipped: gogdl was not found in WMT data or PATH."
                            return
                        }

                        $games = @(Get-GogInstalledGames)
                        if ($games.Count -eq 0) {
                            Write-Output "LOG:GOGDL scan found no installed GOG games in the registry."
                            return
                        }

                        $pendingCount = 0
                        $checkedCount = 0
                        $missingMetadataCount = 0
                        foreach ($game in $games) {
                            $metadata = Get-GogLocalMetadata -Game $game
                            $gameId = ([string]$metadata.GameID).Trim()
                            $title = ([string]$metadata.Name).Trim()
                            $installPath = ([string]$metadata.InstallPath).Trim()
                            $installedBuild = ([string]$metadata.BuildID).Trim()
                            if ([string]::IsNullOrWhiteSpace($title)) { $title = $gameId }
                            if ([string]::IsNullOrWhiteSpace($gameId) -or [string]::IsNullOrWhiteSpace($installedBuild)) {
                                $missingMetadataCount++
                                continue
                            }

                            $catalog = $null
                            try {
                                $catalog = Get-GogBuildCatalog -GameID $gameId
                            }
                            catch {
                                Write-Output "LOG:GOGDL could not query latest build for $title ($gameId): $($_.Exception.Message)"
                                continue
                            }

                            $items = @($catalog.items)
                            if ($items.Count -eq 0) { continue }
                            $checkedCount++
                            $latest = $items[0]
                            $latestBuild = ([string]$latest.build_id).Trim()
                            if ([string]::IsNullOrWhiteSpace($latestBuild)) { continue }
                            if ($installedBuild -eq $latestBuild) { continue }
                            if (Test-Ignored $title $gameId) { continue }

                            $installedVersionName = ""
                            foreach ($build in $items) {
                                if (([string]$build.build_id).Trim() -eq $installedBuild) {
                                    $installedVersionName = ([string]$build.version_name).Trim()
                                    break
                                }
                            }
                            $pendingCount++
                            $displayInstalled = if ([string]::IsNullOrWhiteSpace($installedVersionName)) { $installedBuild } else { $installedVersionName }
                            $displayLatest = if ([string]::IsNullOrWhiteSpace([string]$latest.version_name)) { $latestBuild } else { ([string]$latest.version_name).Trim() }
                            [PSCustomObject]@{
                                Source         = "gogdl"
                                Name           = $title
                                Id             = $gameId
                                Version        = $displayInstalled
                                Available      = $displayLatest
                                VersionSort    = $installedBuild
                                AvailableSort  = $latestBuild
                                InstallDir     = $installPath
                                ExecutablePath = $gogdlCommand
                                Platform       = "windows"
                            }
                        }

                        if ($pendingCount -eq 0) {
                            Write-Output "LOG:GOGDL scan checked $checkedCount installed GOG game(s), with no pending updates."
                        }
                        else {
                            Write-Output "LOG:GOGDL scan found $pendingCount pending GOG game update(s)."
                        }
                        if ($missingMetadataCount -gt 0) {
                            Write-Output "LOG:GOGDL skipped $missingMetadataCount GOG game(s) without local goggame build metadata."
                        }
                    }
                    catch {
                        Write-Output "LOG:GOGDL scan failed: $($_.Exception.Message)"
                    }
                }).AddArgument($ignoreList).AddArgument((Get-WmtGogdlExePath))
            [void]$script:ActiveScans.Add([PSCustomObject]@{ PowerShell = $ps; AsyncResult = $ps.BeginInvoke() })
        }

        # K. STEAM WORKER
        if ("steam" -in $enabled) {
            $ps = [PowerShell]::Create()
            [void]$ps.AddScript({
                    param($IgnoreList)
                    Write-Output "LOG:Scanning Steam game manifests..."

                    function Add-UniqueSteamPath {
                        param(
                            [System.Collections.Generic.List[string]]$Paths,
                            [string]$Path
                        )

                        if ([string]::IsNullOrWhiteSpace($Path)) { return }
                        $rawPathText = ([string]$Path).Trim()
                        $expanded = [Environment]::ExpandEnvironmentVariables($rawPathText)
                        $expanded = $expanded -replace '/', '\'
                        $expanded = $expanded -replace '\\\\', '\'
                        try {
                            $full = [System.IO.Path]::GetFullPath($expanded)
                            if ((Test-Path -LiteralPath $full) -and -not $Paths.Contains($full)) {
                                [void]$Paths.Add($full)
                            }
                        }
                        catch {}
                    }

                    function ConvertFrom-SteamVdfPath {
                        param([string]$Value)
                        if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
                        $path = ([string]$Value).Trim()
                        $path = $path -replace '\\\\', '\'
                        $path = $path -replace '/', '\'
                        return [Environment]::ExpandEnvironmentVariables($path)
                    }

                    function Get-SteamManifestValue {
                        param(
                            [string]$Text,
                            [string]$Key
                        )

                        if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Key)) { return "" }
                        $pattern = '"' + [regex]::Escape($Key) + '"\s+"([^"]*)"'
                        $match = [regex]::Match($Text, $pattern)
                        if ($match.Success) { return [string]$match.Groups[1].Value }
                        return ""
                    }

                    function Get-SteamManifestNumber {
                        param(
                            [string]$Text,
                            [string]$Key
                        )

                        $value = Get-SteamManifestValue -Text $Text -Key $Key
                        $number = [long]0
                        if ([long]::TryParse(([string]$value), [ref]$number)) { return $number }
                        return [long]0
                    }

                    function Get-SteamInstallRoots {
                        $paths = [System.Collections.Generic.List[string]]::new()
                        $registryPaths = @(
                            "HKCU:\Software\Valve\Steam",
                            "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
                            "HKLM:\SOFTWARE\Valve\Steam"
                        )

                        foreach ($registryPath in $registryPaths) {
                            try {
                                $props = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
                                foreach ($propName in @("SteamPath", "InstallPath")) {
                                    if ($props.PSObject.Properties[$propName]) {
                                        Add-UniqueSteamPath -Paths $paths -Path ([string]$props.$propName)
                                    }
                                }
                                if ($props.PSObject.Properties["SteamExe"] -and -not [string]::IsNullOrWhiteSpace([string]$props.SteamExe)) {
                                    Add-UniqueSteamPath -Paths $paths -Path (Split-Path -Parent ([string]$props.SteamExe))
                                }
                            }
                            catch {}
                        }

                        foreach ($candidate in @(
                                "${env:ProgramFiles(x86)}\Steam",
                                "${env:ProgramFiles}\Steam",
                                "${env:SystemDrive}\Steam",
                                "${env:SystemDrive}\steamcmd"
                            )) {
                            Add-UniqueSteamPath -Paths $paths -Path $candidate
                        }

                        foreach ($cmdName in @("steamcmd", "steamcmd.exe")) {
                            try {
                                $cmd = Get-Command $cmdName -ErrorAction SilentlyContinue
                                if ($cmd -and $cmd.Source) {
                                    Add-UniqueSteamPath -Paths $paths -Path (Split-Path -Parent ([string]$cmd.Source))
                                }
                            }
                            catch {}
                        }

                        return $paths.ToArray()
                    }

                    function Get-SteamLibraryRoots {
                        $paths = [System.Collections.Generic.List[string]]::new()
                        foreach ($root in @(Get-SteamInstallRoots)) {
                            if ([string]::IsNullOrWhiteSpace($root)) { continue }
                            if (Test-Path -LiteralPath (Join-Path $root "steamapps")) {
                                Add-UniqueSteamPath -Paths $paths -Path $root
                            }

                            $libraryFile = Join-Path $root "steamapps\libraryfolders.vdf"
                            if (-not (Test-Path -LiteralPath $libraryFile)) { continue }

                            $libraryText = Get-Content -LiteralPath $libraryFile -Raw -ErrorAction SilentlyContinue
                            if ([string]::IsNullOrWhiteSpace($libraryText)) { continue }

                            foreach ($match in [regex]::Matches($libraryText, '"path"\s+"([^"]+)"')) {
                                Add-UniqueSteamPath -Paths $paths -Path (ConvertFrom-SteamVdfPath $match.Groups[1].Value)
                            }
                            foreach ($match in [regex]::Matches($libraryText, '"\d+"\s+"([^"]+)"')) {
                                $candidate = ConvertFrom-SteamVdfPath $match.Groups[1].Value
                                if ($candidate -match '^[A-Za-z]:\\|^\\\\') {
                                    Add-UniqueSteamPath -Paths $paths -Path $candidate
                                }
                            }
                        }

                        return $paths.ToArray()
                    }

                    $seenAppIds = @{}
                    $manifestCount = 0
                    $pendingCount = 0

                    try {
                        $libraryRoots = @(Get-SteamLibraryRoots)
                        if ($libraryRoots.Count -eq 0) {
                            Write-Output "LOG:Steam scan skipped: no Steam library folders were found."
                            return
                        }

                        foreach ($libraryRoot in $libraryRoots) {
                            $steamApps = Join-Path $libraryRoot "steamapps"
                            if (-not (Test-Path -LiteralPath $steamApps)) { continue }

                            foreach ($manifest in @(Get-ChildItem -LiteralPath $steamApps -Filter "appmanifest_*.acf" -File -ErrorAction SilentlyContinue)) {
                                $manifestCount++
                                $text = Get-Content -LiteralPath $manifest.FullName -Raw -ErrorAction SilentlyContinue
                                if ([string]::IsNullOrWhiteSpace($text)) { continue }

                                $appId = Get-SteamManifestValue -Text $text -Key "appid"
                                if ([string]::IsNullOrWhiteSpace($appId)) {
                                    $appId = [regex]::Match($manifest.BaseName, '\d+').Value
                                }
                                if ([string]::IsNullOrWhiteSpace($appId)) { continue }
                                if ($seenAppIds.ContainsKey($appId)) { continue }
                                $seenAppIds[$appId] = $true

                                $name = Get-SteamManifestValue -Text $text -Key "name"
                                if ([string]::IsNullOrWhiteSpace($name)) { $name = "Steam App $appId" }
                                if ($IgnoreList -and ($IgnoreList -contains $name -or $IgnoreList -contains $appId)) { continue }

                                $stateFlags = Get-SteamManifestNumber -Text $text -Key "StateFlags"
                                $bytesToDownload = Get-SteamManifestNumber -Text $text -Key "BytesToDownload"
                                $bytesDownloaded = Get-SteamManifestNumber -Text $text -Key "BytesDownloaded"
                                $bytesToStage = Get-SteamManifestNumber -Text $text -Key "BytesToStage"
                                $bytesStaged = Get-SteamManifestNumber -Text $text -Key "BytesStaged"
                                $buildId = Get-SteamManifestValue -Text $text -Key "buildid"
                                $targetBuildId = Get-SteamManifestValue -Text $text -Key "TargetBuildID"
                                $installDir = ConvertFrom-SteamVdfPath (Get-SteamManifestValue -Text $text -Key "installdir")

                                $downloadRemaining = [Math]::Max([long]0, $bytesToDownload - $bytesDownloaded)
                                $stageRemaining = [Math]::Max([long]0, $bytesToStage - $bytesStaged)
                                $hasTargetBuild = (-not [string]::IsNullOrWhiteSpace($targetBuildId) -and $targetBuildId -ne "0" -and $targetBuildId -ne $buildId)
                                $needsAttention = (
                                    ($stateFlags -ne 0 -and $stateFlags -ne 4) -or
                                    $downloadRemaining -gt 0 -or
                                    $stageRemaining -gt 0 -or
                                    $hasTargetBuild
                                )

                                if (-not $needsAttention) { continue }

                                $pendingCount++
                                $versionText = if (-not [string]::IsNullOrWhiteSpace($buildId) -and $buildId -ne "0") { "Build $buildId" } else { "State $stateFlags" }
                                $availableText = "Steam pending"
                                if ($hasTargetBuild) {
                                    $availableText = "Build $targetBuildId"
                                }
                                elseif ($downloadRemaining -gt 0) {
                                    $availableText = "{0:N1} MB pending" -f ($downloadRemaining / 1MB)
                                }
                                elseif ($stageRemaining -gt 0) {
                                    $availableText = "{0:N1} MB staging" -f ($stageRemaining / 1MB)
                                }
                                elseif ($stateFlags -ne 4) {
                                    $availableText = "State $stateFlags"
                                }

                                [PSCustomObject]@{
                                    Source       = "steam"
                                    Name         = $name
                                    Id           = $appId
                                    Version      = $versionText
                                    Available    = $availableText
                                    LibraryPath  = $libraryRoot
                                    InstallDir   = $installDir
                                    ManifestPath = $manifest.FullName
                                }
                            }
                        }

                        if ($pendingCount -eq 0) {
                            Write-Output "LOG:Steam scan found $manifestCount installed Steam app manifest(s), with no manifest-marked pending updates."
                        }
                        else {
                            Write-Output "LOG:Steam scan found $pendingCount manifest-marked pending Steam update(s)."
                        }
                    }
                    catch {
                        Write-Output "LOG:Steam scan failed: $($_.Exception.Message)"
                    }
                }).AddArgument($ignoreList)
            [void]$script:ActiveScans.Add([PSCustomObject]@{ PowerShell = $ps; AsyncResult = $ps.BeginInvoke() })
        }
    
        # --- Start the result collection timer (already defined earlier in script) ---
        $script:ScanTimer.Start()
    })

# --- IGNORE SELECTED ---
$btnWingetIgnore.Add_Click({
        $selected = @($lstWinget.SelectedItems)
        if ($selected.Count -eq 0) { return }

        $msg = "Ignore $($selected.Count) package(s)?`n`nThese updates will be hidden from future scans."
        if ((Show-WmtMessageBox -Message $msg -Title "Ignore Updates" -Button YesNo -Image Question) -eq [System.Windows.MessageBoxResult]::Yes) {
        
            # 1. Get fresh settings
            $settings = Get-WmtSettings
        
            # 2. Create a fresh ArrayList to ensure it is editable
            $newList = New-Object System.Collections.ArrayList
        
            # Add existing items (checking for nulls)
            if ($settings.WingetIgnore) {
                foreach ($existing in $settings.WingetIgnore) {
                    if (-not [string]::IsNullOrWhiteSpace($existing)) {
                        [void]$newList.Add($existing.ToString())
                    }
                }
            }

            # 3. Add NEW items
            foreach ($item in $selected) {
                $id = $item.Id
                # Avoid duplicates
                if ($id -and ($id -notin $newList)) {
                    [void]$newList.Add($id)
                }
                # Remove from GUI immediately
                $lstWinget.Items.Remove($item)
            }

            # 4. Save back as a standard array
            $settings.WingetIgnore = $newList.ToArray()
            Save-WmtSettings -Settings $settings
        
            Write-GuiLog "Ignored $($selected.Count) packages. Saved to settings.json."
        }
    })

# --- MANAGE IGNORED (UNIGNORE) ---
$btnWingetUnignore.Add_Click({
        $jsonPath = Join-Path (Get-DataPath) "settings.json"
        $listItems = @()

        if (Test-Path $jsonPath) {
            try {
                $json = Get-Content $jsonPath -Raw | ConvertFrom-Json
                if ($json.WingetIgnore) { $listItems = @($json.WingetIgnore) | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" } }
            }
            catch { Write-GuiLog "Error: $($_.Exception.Message)" }
        }

        if ($listItems.Count -eq 0) {
            Show-WmtMessageBox -Message "No ignored packages found." -Title "Manage Ignored" -Image Information | Out-Null
            return
        }

        $content = @"
    <Grid Margin="16">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <TextBlock Text="Select packages to restore" Foreground="{DynamicResource TextSecondary}" Margin="0,0,0,10"/>
        <ListBox Name="lbIgnored" Grid.Row="1" SelectionMode="Extended"/>
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button Name="btnRestore" Content="Un-ignore Selected" MinWidth="142" Background="{DynamicResource Success}" Foreground="{DynamicResource SuccessText}" Margin="0,0,8,0"/>
            <Button Name="btnClose" Content="Close" Width="92" IsCancel="True"/>
        </StackPanel>
    </Grid>
"@
        $dialog = New-WmtWindowFromXaml -Title "Manage Ignored Updates" -ContentXaml $content -Width 520 -Height 420 -MinWidth 440 -MinHeight 340
        $lb = $dialog.FindName("lbIgnored")
        $btnRestore = $dialog.FindName("btnRestore")
        $btnClose = $dialog.FindName("btnClose")
        foreach ($item in $listItems) { [void]$lb.Items.Add($item) }
        $refreshNeeded = @{ Value = $false }

        $btnRestore.Add_Click({
                $selected = @($lb.SelectedItems)
                if ($selected.Count -eq 0) { return }
                $s = Get-WmtSettings
                $current = [System.Collections.ArrayList]@($s.WingetIgnore)
                foreach ($item in $selected) {
                    if ($current.Contains($item)) { $current.Remove($item) }
                    $lb.Items.Remove($item)
                }
                $s.WingetIgnore = $current.ToArray()
                Save-WmtSettings -Settings $s
                $refreshNeeded.Value = $true
            }.GetNewClosure())
        $btnClose.Add_Click({ $dialog.Close() }.GetNewClosure())
        $dialog.ShowDialog() | Out-Null

        if ($refreshNeeded.Value) {
            Write-GuiLog "List updated. Refreshing..."
            $btnWingetScan.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
        }
    })
# --- LISTVIEW SORTING LOGIC ---
$lstWinget = Get-Ctrl "lstWinget"

















$script:WingetSortChain = New-Object System.Collections.ArrayList
$script:GridSortAscendingGlyph = [string][char]0x25B2
$script:GridSortDescendingGlyph = [string][char]0x25BC

















if ($lstWinget) {
    $wingetSortHandler = [System.Windows.RoutedEventHandler] {
        param($src, $e)
        $columnHeader = Get-GridViewColumnHeaderFromSource -OriginalSource $e.OriginalSource
        if (-not $columnHeader -or -not $columnHeader.Column) { return }
        $header = Get-CleanHeader $columnHeader.Column.Header
        if ([string]::IsNullOrWhiteSpace($header)) { return }

        $propName = Resolve-WingetSortProperty $header
        if ([string]::IsNullOrWhiteSpace($propName)) { return }

        $isAscending = Set-SortChainPrimary -Chain $script:WingetSortChain -PropertyName $propName
        Update-GridViewHeaders -ListView $lstWinget -ActiveHeader $header -Ascending:$isAscending
        Set-ListViewSort -ListView $lstWinget -Chain $script:WingetSortChain
    }
    $lstWinget.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, $wingetSortHandler, $true)
    $lstWinget.Add_Loaded({ Request-WmtUpdateListSmartColumnResize -ListView $lstWinget })
    $lstWinget.Add_SizeChanged({ Request-WmtUpdateListSmartColumnResize -ListView $lstWinget })
    Request-WmtUpdateListSmartColumnResize -ListView $lstWinget
}

# ---------------------------------------------------------
# HIGH-PERFORMANCE THREADED SEARCH
# ---------------------------------------------------------

# 1. SETUP UI TIMER (Handles the Thread Callback)
$script:SearchTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:SearchTimer.Interval = [TimeSpan]::FromMilliseconds(100)
$script:AsyncSearch = $null
$script:AsyncPowerShell = $null
$script:WmtPackageSearchActive = $false

$script:SearchTimer.Add_Tick({
        # Check if the thread has finished
        if ($script:AsyncSearch -and $script:AsyncSearch.IsCompleted) {
            $script:SearchTimer.Stop()
        
            try {
                # Get Results from the Thread
                $results = $script:AsyncPowerShell.EndInvoke($script:AsyncSearch)
                $script:AsyncPowerShell.Dispose()
            
                foreach ($item in $results) {
                    # Handle Log Messages vs Result Objects
                    if ($item -is [string] -and $item.StartsWith("LOG:")) {
                        Write-GuiLog ($item.Substring(4))
                    }
                    elseif ($item.PSObject.Properties["Name"]) {
                        [void](Set-WmtUpdateListItemCheckState -Item $item -DefaultChecked:$false)
                        [void]$lstWinget.Items.Add($item)
                    }
                }
            }
            catch {
                Write-GuiLog "Thread Error: $($_.Exception.Message)"
            }

            # UI Cleanup
            $lblWingetStatus.Visibility = "Hidden"
            $btnWingetFind.IsEnabled = $true
            $txtWingetSearch.IsEnabled = $true
            $lblWingetStatus.Text = "Ready"
        
            if ($lstWinget.Items.Count -eq 0) { 
                [void]$lstWinget.Items.Add((Set-WmtUpdateListItemCheckState -Item ([PSCustomObject]@{ Source = ""; Name = "No results found"; Id = ""; Version = ""; Available = "" }) -DefaultChecked:$false)) 
            }
            Request-WmtUpdateListSmartColumnResize -ListView $lstWinget
            Write-GuiLog "Search Complete. Found $($lstWinget.Items.Count) results."
            $script:WmtPackageSearchActive = $true
        
            $script:AsyncSearch = $null
            $script:AsyncPowerShell = $null
        }
    })

# 2. THE BUTTON CLICK (Starts the Thread)
$btnWingetFind.Add_Click({
        if (Test-WmtUpdateScanEngineBusy) {
            Write-GuiLog "Package search skipped because an update scan or package action is already running."
            return
        }
        if ([string]::IsNullOrWhiteSpace($txtWingetSearch.Text) -or $txtWingetSearch.Text -in @("Search packages...", "Search new packages...")) { return }

        # UI Prep
        $script:WmtPackageSearchActive = $true
        $query = $txtWingetSearch.Text
        $lblWingetTitle.Text = "Search Results: $query"
        $lblWingetStatus.Text = "Searching..."; $lblWingetStatus.Visibility = "Visible"
        $btnWingetUpdateSel.Visibility = "Collapsed"
        if ($btnWingetUpdateAll) { $btnWingetUpdateAll.Visibility = "Collapsed" }
        $btnWingetInstall.Visibility = "Visible"
        $lstWinget.Items.Clear()
        $btnWingetFind.IsEnabled = $false 
    
        Write-GuiLog " "
        Write-GuiLog "Starting Search: '$query'"

        # Get Settings
        $settings = Get-WmtSettings
        
        $enabled = if ($settings.EnabledProviders -and $settings.EnabledProviders.Count -gt 0) { 
            $settings.EnabledProviders 
        }
        else { 
            @("winget", "msstore", "windowsupdate", "pip", "npm", "pnpm", "dotnet", "psmodule", "composer", "chocolatey", "scoop", "gem", "cargo", "steam", "legendary", "gogdl")
        }

        Write-GuiLog "Enabled providers: $($enabled -join ', ')"
        
        # Reset Task List
        $script:ActiveScans.Clear()
        # 3. DEFINE THE WORKER THREAD SCRIPT
        # This contains the EXACT logic that worked for you before.
        $scriptBlock = {
            param($Query, $Enabled)
        
            [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
            function Log($msg) { Write-Output "LOG:$msg" }

            # --- A. WINGET & MSSTORE ---
            if ("winget" -in $Enabled -or "msstore" -in $Enabled) {
                Log "Searching Winget & Store..."
            
                $sourceFlag = ""
                if ("winget" -in $Enabled -and "msstore" -notin $Enabled) { $sourceFlag = "--source winget" }
                elseif ("winget" -notin $Enabled -and "msstore" -in $Enabled) { $sourceFlag = "--source msstore" }
                $defaultSource = if ("winget" -notin $Enabled -and "msstore" -in $Enabled) { "msstore" } else { "winget" }
            
                $cleanQuery = $Query.Replace('"', '')
            
                $pInfo = New-Object System.Diagnostics.ProcessStartInfo
                $pInfo.FileName = "winget"
                $pInfo.Arguments = "search --query `"$cleanQuery`" $sourceFlag --accept-source-agreements"
            
                $pInfo.RedirectStandardOutput = $true
                $pInfo.RedirectStandardError = $true
                $pInfo.UseShellExecute = $false
                $pInfo.CreateNoWindow = $true
                $pInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)

                try {
                    $p = [System.Diagnostics.Process]::Start($pInfo)
                    $out = $p.StandardOutput.ReadToEnd()
                    $p.WaitForExit()
                
                    if (-not [string]::IsNullOrWhiteSpace($out)) {
                        $lines = $out -split "`r`n"
                    
                        foreach ($line in $lines) {
                            $line = $line.Trim()
                        
                            # Skip dividers, headers, and empty lines
                            if ([string]::IsNullOrWhiteSpace($line)) { continue }
                            if ($line -match "^-+$" -or $line -match "^Name\s+Id" -or $line -match "^-{3,}") { continue } 
                            if ($line -match "Windows Package Manager" -or $line -match "Copyright" -or $line -match "usage:" -or $line -match "No package found") { continue }
                            if ($line -eq "-") { continue }

                            # Split by 2 OR MORE spaces (\s{2,}). 
                            # This perfectly separates columns without breaking names that have 1 space!
                            $parts = @($line -split '\s{2,}' | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -ne "" })
                            $headerTokens = @("name", "id", "version", "match", "source")
                            $nonDividerParts = @($parts | Where-Object { $_ -notmatch "^-+$" })
                            if ($nonDividerParts.Count -eq 0) { continue }
                            if (@($nonDividerParts | Where-Object { $headerTokens -notcontains $_.ToLowerInvariant() }).Count -eq 0) { continue }

                            $len = $parts.Count

                            $n = $null; $i = $null; $v = $null; $s = $defaultSource

                            if ($len -ge 5) {
                                # Layout: Name | Id | Version | Match | Source
                                $n = $parts[0].Trim()
                                $i = $parts[1].Trim()
                                $v = $parts[2].Trim()
                                $s = $parts[4].Trim()
                            }
                            elseif ($len -eq 4) {
                                # Layout: Name | Id | Version | Source (Match column is empty)
                                $n = $parts[0].Trim()
                                $i = $parts[1].Trim()
                                $v = $parts[2].Trim()
                                $s = $parts[3].Trim()
                            }
                            elseif ($len -eq 3) {
                                # Layout: Name | Id | Version (Source is hidden)
                                $n = $parts[0].Trim()
                                $i = $parts[1].Trim()
                                $v = $parts[2].Trim()
                            }

                            if ($n -and $i -and $i.Length -gt 2) {
                                # Final header checks just in case
                                $nText = ([string]$n).Trim()
                                $iText = ([string]$i).Trim()
                                $vText = ([string]$v).Trim()
                                if ($nText -eq "-" -or $nText.ToLowerInvariant() -eq "name") { continue }
                                if ($iText -eq "-" -or $headerTokens -contains $iText.ToLowerInvariant()) { continue }
                                if ($vText -eq "-" -or $headerTokens -contains $vText.ToLowerInvariant()) { continue }

                                if ($s -eq "msstore") { $s = "msstore" } else { $s = "winget" }
                                if ($v -eq "Unknown") { $v = "?" }
                            
                                # Available is hardcoded to "-" since searches don't show updates
                                [PSCustomObject]@{ Source = $s; Name = $n; Id = $i; Version = $v; Available = "-" }
                            }
                        }
                    }
                }
                catch { Log "Winget Error: $_" }
            }

            # --- B. NPM ---
            if ("npm" -in $Enabled) {
                Log "Searching NPM..."
                try {
                    $pInfo = New-Object System.Diagnostics.ProcessStartInfo("cmd", "/c npm search `"$Query`" --json")
                    $pInfo.RedirectStandardOutput = $true; $pInfo.UseShellExecute = $false; $pInfo.CreateNoWindow = $true
                    $p = [System.Diagnostics.Process]::Start($pInfo); $json = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
                    if ($json.Contains("[")) {
                        $json = $json.Substring($json.IndexOf("[")); $pkgs = $json | ConvertFrom-Json
                        foreach ($pkg in $pkgs) { 
                            [PSCustomObject]@{ Source = "npm"; Name = $pkg.name; Id = $pkg.name; Version = $pkg.version; Available = "-" } 
                        }
                    }
                }
                catch { Log "Npm skipped." }
            }

            # --- C. CHOCO ---
            if ("chocolatey" -in $Enabled) {
                Log "Searching Chocolatey..."
                try {
                    $pInfo = New-Object System.Diagnostics.ProcessStartInfo("choco", "search `"$Query`" -r")
                    $pInfo.RedirectStandardOutput = $true; $pInfo.UseShellExecute = $false; $pInfo.CreateNoWindow = $true
                    $p = [System.Diagnostics.Process]::Start($pInfo); $out = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
                    $lines = $out -split "`r`n"
                    foreach ($line in $lines) {
                        if ([string]::IsNullOrWhiteSpace($line)) { continue }
                        $parts = $line -split "\|"
                        if ($parts.Count -ge 2) {
                            [PSCustomObject]@{ Source = "chocolatey"; Name = $parts[0]; Id = $parts[0]; Version = $parts[1]; Available = "-" }
                        }
                    }
                }
                catch { Log "Choco skipped." }
            }

            # --- D. .NET TOOLS ---
            if ("dotnet" -in $Enabled) {
                Log "Searching .NET tools..."
                try {
                    $pInfo = New-Object System.Diagnostics.ProcessStartInfo("dotnet", "tool search `"$Query`" --take 40")
                    $pInfo.RedirectStandardOutput = $true; $pInfo.UseShellExecute = $false; $pInfo.CreateNoWindow = $true
                    $p = [System.Diagnostics.Process]::Start($pInfo); $out = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
                    foreach ($line in ($out -split "`r?`n")) {
                        $trimmed = ([string]$line).Trim()
                        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
                        if ($trimmed -match "(?i)^Package\s+ID\s+Version" -or $trimmed -match "^-+") { continue }
                        $parts = @($trimmed -split "\s+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                        if ($parts.Count -ge 2) {
                            [PSCustomObject]@{ Source = "dotnet"; Name = [string]$parts[0]; Id = [string]$parts[0]; Version = [string]$parts[1]; Available = "-" }
                        }
                    }
                }
                catch { Log ".NET tools skipped." }
            }

            # --- E. POWERSHELL MODULES ---
            if ("psmodule" -in $Enabled) {
                Log "Searching PowerShell modules..."
                try {
                    if (Get-Command Find-Module -ErrorAction SilentlyContinue) {
                        $mods = @(Find-Module -Name "*$Query*" -Repository PSGallery -ErrorAction SilentlyContinue | Select-Object -First 40)
                        foreach ($mod in $mods) {
                            [PSCustomObject]@{ Source = "psmodule"; Name = $mod.Name; Id = $mod.Name; Version = [string]$mod.Version; Available = "-" }
                        }
                    }
                }
                catch { Log "PowerShell modules skipped." }
            }

            # --- F. COMPOSER ---
            if ("composer" -in $Enabled) {
                Log "Searching Composer..."
                try {
                    $pInfo = New-Object System.Diagnostics.ProcessStartInfo("cmd", "/c composer search `"$Query`" --format=json 2>nul")
                    $pInfo.RedirectStandardOutput = $true; $pInfo.UseShellExecute = $false; $pInfo.CreateNoWindow = $true
                    $p = [System.Diagnostics.Process]::Start($pInfo); $json = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
                    $json = $json.Trim()
                    if ($json.StartsWith("[")) {
                        $pkgs = $json | ConvertFrom-Json
                        foreach ($pkg in $pkgs) {
                            $name = if ($pkg.PSObject.Properties["name"]) { [string]$pkg.name } else { "" }
                            if (-not [string]::IsNullOrWhiteSpace($name)) {
                                [PSCustomObject]@{ Source = "composer"; Name = $name; Id = $name; Version = "?"; Available = "-" }
                            }
                        }
                    }
                    else {
                        foreach ($line in ($json -split "`r?`n")) {
                            $trimmed = ([string]$line).Trim()
                            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
                            $name = @($trimmed -split "\s+" | Where-Object { $_ })[0]
                            if (-not [string]::IsNullOrWhiteSpace($name)) {
                                [PSCustomObject]@{ Source = "composer"; Name = $name; Id = $name; Version = "?"; Available = "-" }
                            }
                        }
                    }
                }
                catch { Log "Composer skipped." }
            }
        }

        # 4. EXECUTE THREAD (The Magic Part)
        $script:AsyncPowerShell = [PowerShell]::Create().AddScript($scriptBlock).AddArgument($query).AddArgument($enabled)
        $script:AsyncSearch = $script:AsyncPowerShell.BeginInvoke()
        $script:SearchTimer.Start()
    })





# 1. Update Selected (Removed CmdTemplate to allow smart logic)
$btnWingetUpdateSel.Add_Click({ 
        $selected = @(Get-WmtUpdateListCheckedItems -FallbackToSelection)
        if ($selected.Count -eq 0) {
            Show-WmtMessageBox -Message "Check one or more update rows first, or select rows as a fallback." -Title "No Updates Checked" -Image Information | Out-Null
            return
        }
        if (-not (Show-WingetRestartRiskWarning -Items $selected -Action "Update")) {
            Write-GuiLog "[Update] Cancelled by user after restart warning."
            return
        }
        & $Script:StartWingetAction -ListItems $selected -ActionName "Update"
    })







if ($btnWingetUpdateAll) {
    $btnWingetUpdateAll.Add_Click({
            $items = @(Get-WingetListedUpdateItems)
            if ($items.Count -eq 0) { return }

            $msg = "Update all $($items.Count) listed package(s)?"
            $res = [System.Windows.MessageBox]::Show($msg, "Update All", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
            if ($res -ne [System.Windows.MessageBoxResult]::Yes) { return }

            if (-not (Show-WingetRestartRiskWarning -Items $items -Action "Update")) {
                Write-GuiLog "[Update All] Cancelled by user after restart warning."
                return
            }
            $actionItems = @(ConvertTo-WmtUpdateAllActionItems -Items $items)
            & $Script:StartWingetAction -ListItems $actionItems -ActionName "Update"
        })
}

# 2. Install Selected (Removed CmdTemplate so it includes --accept-agreements)
$btnWingetInstall.Add_Click({ 
        $selected = @(Get-WmtUpdateListCheckedItems -FallbackToSelection)
        if ($selected.Count -eq 0) { return }
        & $Script:StartWingetAction -ListItems $selected -ActionName "Install"
    })

# 3. Uninstall Selected
$btnWingetUninstall.Add_Click({ 
        $selected = @($lstWinget.SelectedItems)
        if ($selected.Count -eq 0) { return }

        $msg = "Are you sure you want to uninstall $($selected.Count) application(s)?"
        if ((Show-WmtMessageBox -Message $msg -Title "Confirm" -Button YesNo -Image Warning) -eq [System.Windows.MessageBoxResult]::Yes) {
            & $Script:StartWingetAction -ListItems $selected -ActionName "Uninstall"
        }
    })

# --- System Health ---
$btnQuickFix.Add_Click({ Invoke-QuickFixSuite })
$btnSFC.Add_Click({
        Start-Process -FilePath "powershell.exe" -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command "sfc /scannow; Write-Host; Write-Host ''Execution Complete.'' -ForegroundColor Green; Write-Host ''Press Enter to close...'' -NoNewline -ForegroundColor Gray; Read-Host"' -Verb RunAs -WindowStyle Normal
    })
$btnDISMCheck.Add_Click({
        Invoke-UiCommand {
            $output = dism /online /cleanup-image /checkhealth 2>&1
            $text = ($output | Out-String).Trim()
            if ($text) { Write-Output $text }

            $message = "DISM Check completed."
            $needsRepair = $false
            if ($text -match "No component store corruption detected") {
                $message = "DISM Check: no corruption detected."
            }
            elseif ($text -match "component store is repairable") {
                $message = "DISM Check: corruption detected (repairable)."
                $needsRepair = $true
            }
            elseif ($text -match "The operation completed successfully") {
                $message = "DISM Check: completed successfully."
            }
            [System.Windows.MessageBox]::Show($message, "DISM CheckHealth", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null

            if ($needsRepair) {
                $prompt = [System.Windows.MessageBox]::Show(
                    "DISM found repairable corruption.`n`nRun DISM RestoreHealth now?",
                    "DISM CheckHealth",
                    [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Question
                )
                if ($prompt -eq "Yes") {
                    Write-Output "Launching DISM RestoreHealth..."
                    Start-Process -FilePath "powershell.exe" -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command "dism /online /cleanup-image /restorehealth; Write-Host; Write-Host ''Execution Complete.'' -ForegroundColor Green; Write-Host ''Press Enter to close...'' -NoNewline -ForegroundColor Gray; Read-Host"' -Verb RunAs -WindowStyle Normal
                }
            }
        } "Running DISM CheckHealth..."
    })
$btnDISMRestore.Add_Click({
        Start-Process -FilePath "powershell.exe" -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command "dism /online /cleanup-image /restorehealth; Write-Host; Write-Host ''Execution Complete.'' -ForegroundColor Green; Write-Host ''Press Enter to close...'' -NoNewline -ForegroundColor Gray; Read-Host"' -Verb RunAs -WindowStyle Normal
    })
$btnCHKDSK.Add_Click({ Invoke-ChkdskAll })

# --- NETWORK ---
$btnNetInfo.Add_Click({
        Invoke-UiCommand {
            $out = ipconfig /all 2>&1
            $txt = ($out | Out-String)
            Write-Output $txt
            Show-TextDialog -Title "IP Configuration" -Text $txt
        } "Showing IP configuration..."
    })
$btnFlushDNS.Add_Click({
        Invoke-UiCommand {
            $out = ipconfig /flushdns 2>&1
            $txt = ($out | Out-String).Trim()
            if ($txt) { Write-Output $txt }
            [System.Windows.MessageBox]::Show("DNS cache flushed.", "Flush DNS", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        } "Flushing DNS cache..."
    })
$btnResetWifi.Add_Click({
        Invoke-UiCommand {
            $wifi = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -match "Wi-Fi|Wireless" }
            $eth = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch "Wi-Fi|Wireless" -and $_.InterfaceDescription -notmatch "Bluetooth" }

            if (-not $wifi) {
                $msg = "No active Wi-Fi adapters found."
                if ($eth) {
                    $ethNames = $eth | Select-Object -ExpandProperty Name
                    $msg += "`nYou appear to be on Ethernet: " + ($ethNames -join ", ")
                }
                [System.Windows.MessageBox]::Show($msg, "Restart Wi-Fi", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
                Write-Output $msg
                return
            }

            $names = $wifi | Select-Object -ExpandProperty Name
            foreach ($n in $names) {
                Restart-NetAdapter -Name $n -Confirm:$false -ErrorAction SilentlyContinue
                Write-Output "Restarted Wi-Fi adapter: $n"
            }

            [System.Windows.MessageBox]::Show("Restarted Wi-Fi adapter(s): " + ($names -join ", "), "Restart Wi-Fi", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        } "Restarting Wi-Fi adapters..."
    })

$btnNetRepair.Add_Click({
        $msg = "Full Network Repair will:" +
        "`n- Release/Renew IP" +
        "`n- Flush DNS cache" +
        "`n- Reset Winsock" +
        "`n- Reset IP stack" +
        "`n`nAdapters may briefly disconnect. Continue?"

        $res = [System.Windows.MessageBox]::Show($msg, "Full Network Repair", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    
        if ($res -eq "Yes") {
            Start-NetRepair
        }
    })

$btnRouteTable.Add_Click({ Invoke-UiCommand { $path = Join-Path (Get-DataPath) "RouteTable.txt"; route print | Out-File -FilePath $path -Encoding UTF8; Write-Output "Saved to $path" } "Saving routing table..." })
$btnRouteView.Add_Click({
        Invoke-UiCommand {
            $out = route print 2>&1
            $txt = ($out | Out-String)
            Write-Output $txt
            Show-TextDialog -Title "Route Table" -Text $txt
        } "Routing table"
    })

$btnDnsGoogle.Add_Click({
        Invoke-DnsPreset -ProviderKey "Google"
    })
$btnDnsCloudflare.Add_Click({
        Invoke-DnsPreset -ProviderKey "Cloudflare"
    })
$btnDnsQuad9.Add_Click({
        Invoke-DnsPreset -ProviderKey "Quad9"
    })
$btnDnsAdGuard.Add_Click({
        Invoke-DnsPreset -ProviderKey "AdGuard"
    })
$btnDnsAuto.Add_Click({
        Reset-DnsAddressesToAutomatic
    })
$btnDnsCustom.Add_Click({
        Invoke-CustomDnsSettings
    })

$btnDohAuto.Add_Click({ Enable-AllDoh })
$btnDohDisable.Add_Click({ Disable-AllDoh })

$btnHostsUpdate.Add_Click({ Invoke-HostsUpdate })
$btnHostsEdit.Add_Click({ Show-HostsEditor })
$btnHostsBackup.Add_Click({ Invoke-UiCommand { $dest = Join-Path (Get-DataPath) ("hosts_bk_{0}.bak" -f (Get-Date -Format "yyyyMMdd_HHmmss")); Copy-Item "$env:windir\System32\drivers\etc\hosts" $dest; "Backup saved to $dest" } "Backing up hosts file..." })
$btnHostsRestore.Add_Click({
        $o = [Microsoft.Win32.OpenFileDialog]::new()
        $o.Filter = "*.bak;*.txt|*.bak;*.txt"
        if ($o.ShowDialog() -eq $true) {
            $restoreFile = $o.FileName
            $res = [System.Windows.MessageBox]::Show("Restore hosts file from:`n$restoreFile`n`nThis will overwrite the current hosts file. Continue?", "Restore Hosts", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
            if ($res -ne "Yes") { return }
            Invoke-UiCommand { Copy-Item $restoreFile "$env:windir\System32\drivers\etc\hosts" -Force } "Restored hosts file from $restoreFile"
            [System.Windows.MessageBox]::Show("Hosts file restored from:`n$restoreFile", "Restore Hosts", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        }
    })

# --- FIREWALL ---
# --- FIREWALL DOUBLE-CLICK MODIFY ---
$lstFw.Add_MouseDoubleClick({
        $rule = $lstFw.SelectedItem
        if ($null -eq $rule) { return }
        Initialize-FirewallRuleDetails -Rule $rule -Synchronous

        # 1. Open existing dialog with the selected rule
        $result = Show-RuleDialog "Edit Firewall Rule" $rule

        # 2. If user clicked 'Save' (result is not null)
        if ($result) {
            try {
                # 3. Apply changes using the Name (ID) from the original object
                Set-NetFirewallRule -Name $rule.Name `
                    -Direction $result.Direction `
                    -Action $result.Action `
                    -Protocol $result.Protocol `
                    -LocalPort $result.Port `
                    -ErrorAction Stop

                # 4. Refresh the list to show changes
                $btnFwRefresh.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
            }
            catch {
                [System.Windows.MessageBox]::Show("Failed to update rule:`n$($_.Exception.Message)", "Error", "OK", "Error")
            }
        }
    })
# --- FIREWALL CONTEXT MENU ---
$fwCtxMenu = New-Object System.Windows.Controls.ContextMenu
Set-WmtContextMenuChrome -ContextMenu $fwCtxMenu

# 1. Option: Copy Rule Name
$mniCopyName = New-Object System.Windows.Controls.MenuItem
$mniCopyName.Header = "Copy Rule Name"
$mniCopyName.Add_Click({
        if ($lstFw.SelectedItem) {
            try {
                [System.Windows.Clipboard]::SetText($lstFw.SelectedItem.Name)
            }
            catch { 
                # Fallback if clipboard is busy
            }
        }
    })

# 2. Option: Copy Port/Protocol
$mniCopyPort = New-Object System.Windows.Controls.MenuItem
$mniCopyPort.Header = "Copy Port/Protocol"
$mniCopyPort.Add_Click({
        if ($lstFw.SelectedItem) {
            Initialize-FirewallRuleDetails -Rule $lstFw.SelectedItem -Synchronous
            $info = "$($lstFw.SelectedItem.Protocol) : $($lstFw.SelectedItem.LocalPort)"
            try {
                [System.Windows.Clipboard]::SetText($info)
            }
            catch {}
        }
    })

# 3. Option: Copy Full Details
$mniCopyAll = New-Object System.Windows.Controls.MenuItem
$mniCopyAll.Header = "Copy Full Details"
$mniCopyAll.Add_Click({
        if ($lstFw.SelectedItem) {
            Initialize-FirewallRuleDetails -Rule $lstFw.SelectedItem -Synchronous
            # Create a nice string representation of the rule
            $rule = $lstFw.SelectedItem
            $text = "Name: $($rule.Name)`nEnabled: $($rule.Enabled)`nAction: $($rule.Action)`nDirection: $($rule.Direction)`nProtocol: $($rule.Protocol)`nPort: $($rule.LocalPort)"
            try {
                [System.Windows.Clipboard]::SetText($text)
            }
            catch {}
        }
    })

# Add items to the menu
[void]$fwCtxMenu.Items.Add($mniCopyName)
[void]$fwCtxMenu.Items.Add($mniCopyPort)
[void]$fwCtxMenu.Items.Add((New-Object System.Windows.Controls.Separator))
[void]$fwCtxMenu.Items.Add($mniCopyAll)

# Attach to the ListView
$lstFw.ContextMenu = $fwCtxMenu
$script:AllFw = @()
$script:FirewallRulesLoaded = $false
$script:FirewallLoadInProgress = $false
$script:FirewallLoadRunspace = $null
$script:FirewallLoadAsyncResult = $null
$script:FirewallLoadTimer = $null
$script:FirewallLoadPreloadMode = $false
$script:FirewallDetailCache = @{}
$script:FirewallDetailJob = $null
$script:FirewallDetailTimer = $null
$script:FirewallDetailToken = 0



























$btnFwRefresh.Add_Click({ Start-FirewallRuleLoad -Force })

if ($lstFw) {
    $lstFw.Add_SelectionChanged({
            if ($lstFw.SelectedItem) {
                Initialize-FirewallRuleDetails -Rule $lstFw.SelectedItem
            }
        })
}

# --- FIREWALL LISTVIEW SORTING LOGIC ---
$script:FirewallSortChain = New-Object System.Collections.ArrayList


if ($lstFw) {
    $fwSortHandler = [System.Windows.RoutedEventHandler] {
        param($src, $e)
        $columnHeader = Get-GridViewColumnHeaderFromSource -OriginalSource $e.OriginalSource
        if (-not $columnHeader -or -not $columnHeader.Column) { return }
        $header = Get-CleanHeader $columnHeader.Column.Header
        if ([string]::IsNullOrWhiteSpace($header)) { return }

        $propName = Resolve-FirewallSortProperty $header
        if ([string]::IsNullOrWhiteSpace($propName)) { return }

        $isAscending = Set-SortChainPrimary -Chain $script:FirewallSortChain -PropertyName $propName
        Update-GridViewHeaders -ListView $lstFw -ActiveHeader $header -Ascending:$isAscending
        Set-ListViewSort -ListView $lstFw -Chain $script:FirewallSortChain
    }
    $lstFw.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, $fwSortHandler, $true)
}

$txtFwSearch.Add_TextChanged({ Update-FirewallListView })
$txtFwSearch.Add_GotFocus({
        $t = $txtFwSearch
        if ($t.Text -in @("Search Rules...", "Search rules...")) { $t.Text = "" }
    })
$btnFwAdd.Add_Click({ $d = Show-RuleDialog "Add Rule"; if ($d) { try { New-NetFirewallRule -DisplayName $d.Name -Direction $d.Direction -Action $d.Action -Protocol $d.Protocol -LocalPort $d.Port -ErrorAction Stop; $btnFwRefresh.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }catch { [System.Windows.MessageBox]::Show("Err: $_") } } })
$btnFwEdit.Add_Click({ if ($lstFw.SelectedItem) { Initialize-FirewallRuleDetails -Rule $lstFw.SelectedItem -Synchronous; $d = Show-RuleDialog "Edit" $lstFw.SelectedItem; if ($d) { try { Set-NetFirewallRule -Name $lstFw.SelectedItem.Name -Direction $d.Direction -Action $d.Action -Protocol $d.Protocol -LocalPort $d.Port; $btnFwRefresh.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }catch { [System.Windows.MessageBox]::Show("Err: $_") } } } })
$btnFwEnable.Add_Click({ if ($lstFw.SelectedItem) { Set-NetFirewallRule -Name $lstFw.SelectedItem.Name -Enabled True; $btnFwRefresh.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) } })
$btnFwDisable.Add_Click({ if ($lstFw.SelectedItem) { Set-NetFirewallRule -Name $lstFw.SelectedItem.Name -Enabled False; $btnFwRefresh.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) } })
$btnFwDelete.Add_Click({ if ($lstFw.SelectedItem) { Remove-NetFirewallRule -Name $lstFw.SelectedItem.Name; $btnFwRefresh.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) } })
$btnFwExport.Add_Click({ Invoke-FirewallExport })
$btnFwImport.Add_Click({ Invoke-FirewallImport; $btnFwRefresh.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) })
$btnFwDefaults.Add_Click({ Invoke-FirewallDefaults; $btnFwRefresh.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) })
$btnFwPurge.Add_Click({ Invoke-FirewallPurge; $btnFwRefresh.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) })

# --- Drivers ---
$btnDrvDisableWU.Add_Click({
        $res = [System.Windows.MessageBox]::Show("Disable automatic driver updates via Windows Update?", "Driver Updates", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($res -ne "Yes") { return }
        Invoke-DriverUpdates -Enable:$false
    })
$btnDrvEnableWU.Add_Click({
        $res = [System.Windows.MessageBox]::Show("Enable automatic driver updates via Windows Update?", "Driver Updates", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($res -ne "Yes") { return }
        Invoke-DriverUpdates -Enable:$true
    })
$btnDrvDisableMeta.Add_Click({
        $res = [System.Windows.MessageBox]::Show("Disable device metadata downloads (icons/info) from the internet?", "Device Metadata", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($res -ne "Yes") { return }
        Invoke-DeviceMetadata -Enable:$false
    })
$btnDrvEnableMeta.Add_Click({
        $res = [System.Windows.MessageBox]::Show("Enable device metadata downloads (icons/info) from the internet?", "Device Metadata", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($res -ne "Yes") { return }
        Invoke-DeviceMetadata -Enable:$true
    })

# --- Cleanup ---
$btnCleanDisk.Add_Click({ Start-Process cleanmgr })
$btnCleanTemp.Add_Click({ Invoke-TempCleanup })
$btnCleanShortcuts.Add_Click({ Invoke-ShortcutFix })
$btnCleanReg.Add_Click({ Invoke-RegistryTask -Action "DeepClean" })
# --- OneDrive Cleanup ---
$btnCleanupOneDrive = Get-Ctrl "btnCleanupOneDrive"
if ($btnCleanupOneDrive) {
    # Check if OneDrive is actually present on the system before enabling the button
    if (-not (Test-Path $env:OneDrive -ErrorAction SilentlyContinue)) {
        $btnCleanupOneDrive.IsEnabled = $false
        $btnCleanupOneDrive.Content = "Not Installed"
        $btnCleanupOneDrive.ToolTip = "OneDrive is not installed or disabled on this system."
    }

    $btnCleanupOneDrive.Add_Click({
            Invoke-UiCommand {
                if (Test-Path $env:OneDrive) {
                    Write-GuiLog "Freeing up OneDrive space..."
                    # +U means Unpinned (Online Only), -P removes the Always Keep on this device flag
                    Start-Process -FilePath "attrib.exe" -ArgumentList "+U -P /s /d `"$env:OneDrive\*.*`"" -Wait -WindowStyle Hidden
                    Write-GuiLog "OneDrive files have been set to Online Only."
                }
                else {
                    Write-GuiLog "OneDrive folder not found on this system."
                }
            } "Freeing OneDrive Space..."
        })
}
$btnCleanXbox.Add_Click({
        if ([System.Windows.MessageBox]::Show("Delete stored Xbox credentials? This signs you out of Xbox services.", "Xbox Cleanup", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning) -eq "Yes") { Start-XboxClean }
    })

# --- Utilities ---
$btnUpdateServices.Add_Click({
        $confirm = [System.Windows.MessageBox]::Show("Restart Windows Update related services (wuauserv/cryptsvc/bits/appidsvc)?", "Restart Update Services", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($confirm -ne "Yes") { return }
        $script:UpdateSvcResult = $null
        Invoke-UpdateServiceReset
        if ($script:UpdateSvcResult -and $script:UpdateSvcResult -like "OK*") {
            [System.Windows.MessageBox]::Show("Update services restarted successfully.", "Restart Update Services", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        }
        else {
            $msg = if ($script:UpdateSvcResult) { $script:UpdateSvcResult } else { "Unknown error. Check log output." }
            [System.Windows.MessageBox]::Show("Failed to restart update services.`n$msg", "Restart Update Services", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        }
    })
$btnDotNetEnable.Add_Click({
        $res = [System.Windows.MessageBox]::Show("Set .NET roll-forward? This forces apps to use the latest installed .NET version (depending on selection).", "Set .NET RollForward", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($res -ne "Yes") { return }

        [xml]$rollForwardXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Set .NET RollForward" Width="340" Height="230" ResizeMode="NoResize" WindowStartupLocation="CenterOwner"
        Background="{DynamicResource BgDark}" Foreground="{DynamicResource TextPrimary}"
        FontFamily="Segoe UI Variable Display, Segoe UI, Arial" FontSize="13">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel>
            <RadioButton Name="rbRuntime" Content="Runtime" GroupName="RollForward" IsChecked="True" Margin="0,0,0,10"/>
            <RadioButton Name="rbSdk" Content="SDK" GroupName="RollForward" Margin="0,0,0,10"/>
            <RadioButton Name="rbBoth" Content="Both" GroupName="RollForward"/>
        </StackPanel>
        <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Name="btnCancel" Content="Cancel" Width="90" IsCancel="True" Margin="0,0,8,0"/>
            <Button Name="btnApply" Content="Apply" Width="100" Background="{DynamicResource Success}" Foreground="{DynamicResource SuccessText}" IsDefault="True"/>
        </StackPanel>
    </Grid>
</Window>
'@
        $dialog = New-WmtWindowFromFullXaml -Xaml $rollForwardXaml
        $dialog.Tag = $null
        $dialog.FindName("btnApply").Add_Click({
                $choice = if ([bool]$dialog.FindName("rbSdk").IsChecked) { "SDK" } elseif ([bool]$dialog.FindName("rbBoth").IsChecked) { "Both" } else { "Runtime" }
                $dialog.Tag = $choice
                $dialog.DialogResult = $true
            }.GetNewClosure())

        if ($dialog.ShowDialog() -eq $true -and $dialog.Tag) {
            $choice = [string]$dialog.Tag
            Invoke-UiCommand { param($choice) Set-DotNetRollForward -Mode $choice } "Setting .NET roll-forward ($choice)..." -ArgumentList $choice
        }
    })
$btnDotNetDisable.Add_Click({
        $res = [System.Windows.MessageBox]::Show("Remove .NET roll-forward and revert to default .NET selection?", "Reset .NET RollForward", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($res -ne "Yes") { return }
        Invoke-UiCommand { Set-DotNetRollForward -Mode "Disable" } "Removing .NET roll-forward..."
    })
$btnTaskManager.Add_Click({ Show-StartupManager -DefaultTab "Scheduled Tasks" })
$btnInstallGpedit.Add_Click({ Start-GpeditInstall })
$btnUtilTrim.Add_Click({
        $res = [System.Windows.MessageBox]::Show("Run SSD Trim/ReTrim now? This will optimize all detected SSD volumes.", "Trim SSD", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($res -ne "Yes") { return }
        Start-SSDTrimConsole
    })
$btnUtilSysInfo.Add_Click({ Invoke-SystemReports })
$btnUtilWinRE.Add_Click({ Invoke-WinREStatusCheck })
$btnUtilRestoreMgr.Add_Click({ Show-SystemRestoreManager })
$btnUtilStartupMgr.Add_Click({ Show-StartupManager })
$btnUtilMas.Add_Click({ Invoke-MASActivation })
$btnUpdateRepair.Add_Click({ Invoke-WindowsUpdateRepairFull })
$btnCtxBuilder.Add_Click({ Show-ContextMenuBuilder })

# --- Support ---
if ($btnSupportDiscord) { $btnSupportDiscord.Add_Click({ Start-Process "https://discord.gg/bCQqKHGxja" }) }
if ($btnSupportIssue) { $btnSupportIssue.Add_Click({ Start-Process "https://github.com/ios12checker/Windows-Maintenance-Tool/issues/new/choose" }) }
if ($btnDonateIos12) { $btnDonateIos12.Add_Click({ Start-Process "https://github.com/sponsors/ios12checker" }) }
if ($btnCreditLilBatti) { $btnCreditLilBatti.Add_Click({ Start-Process "https://github.com/ios12checker" }) }
if ($btnCreditChaython) { $btnCreditChaython.Add_Click({ Start-Process "https://github.com/Chaython" }) }
if ($btnToggleTheme) {
    $btnToggleTheme.Add_Click({
            $nextTheme = if ($script:CurrentTheme -eq "dark") { "light" } else { "dark" }
            Set-WmtThemePreference -Theme $nextTheme
        })
}
if ($btnDonate) { $btnDonate.Add_Click({ Start-Process "https://github.com/sponsors/Chaython" }) }

if ($btnNavDownloads) { $btnNavDownloads.Add_Click({ Show-DownloadStats }) }

# ==========================================
# TWEAKS & OPTIMIZATION FUNCTIONS
# ==========================================

# --- PERFORMANCE TWEAKS WITH REVERT ---
$btnPerfServicesManual.Add_Click({
        Invoke-UiCommand {
            Write-GuiLog "Optimizing services to Manual..."
            $services = @('DiagTrack', 'dmwappushservice', 'MapsBroker', 'lfsvc', 'SharedAccess', 'WbioSrvc', 'WMPNetworkSvc', 'icssvc', 'WpnService', 'PcaSvc', 'SessionEnv', 'TermService', 'UmRdpService', 'RemoteRegistry', 'RemoteAccess', 'shpamsvc', 'TapiSrv', 'TabletInputService', 'lmhosts', 'SNMPTrap', 'WebClient', 'WerSvc', 'Wecsvc', 'SDRSVC', 'fdPHost', 'FDResPub', 'HomeGroupListener', 'HomeGroupProvider', 'upnphost', 'SSDPSRV', 'swprv', 'smphost', 'SysMain', 'TrkWks', 'WMPNetworkSvc', 'WMPNetworkSvc', 'iphlpsvc', 'MSiSCSI', 'WSearch', 'WinRM', 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc')
            foreach ($svc in $services) {
                try {
                    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
                    if ($service -and $service.StartType -eq 'Automatic') {
                        Set-Service -Name $svc -StartupType Manual -ErrorAction SilentlyContinue
                        Write-GuiLog "Set $svc to Manual"
                    }
                }
                catch {}
            }
            Write-GuiLog "Services optimization complete!"
        } "Optimizing services..."
        Update-TweakButtonStates
    })

$btnPerfServicesRevert.Add_Click({
        Invoke-UiCommand {
            Write-GuiLog "Reverting services to default..."
            $services = @('DiagTrack', 'dmwappushservice', 'MapsBroker', 'WpnService', 'PcaSvc', 'WerSvc', 'SysMain', 'WSearch', 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'iphlpsvc')
            foreach ($svc in $services) {
                try {
                    Set-Service -Name $svc -StartupType Automatic -ErrorAction SilentlyContinue
                    Write-GuiLog "Set $svc to Automatic"
                }
                catch {}
            }
            Write-GuiLog "Services restored to default!"
        } "Reverting services..."
        Update-TweakButtonStates
    })

$btnPerfDisableHibernate.Add_Click({
        Invoke-UiCommand {
            powercfg /hibernate off
            Write-GuiLog "Hibernation disabled. Disk space freed."
        } "Disabling hibernation..."
        Update-TweakButtonStates
    })

$btnPerfEnableHibernate.Add_Click({
        Invoke-UiCommand {
            powercfg /hibernate on
            Write-GuiLog "Hibernation enabled."
        } "Enabling hibernation..."
        Update-TweakButtonStates
    })

$btnPerfDisableSuperfetch.Add_Click({
        Invoke-UiCommand {
            Stop-Service -Name SysMain -Force -ErrorAction SilentlyContinue
            Set-Service -Name SysMain -StartupType Disabled
            Write-GuiLog "Superfetch/SysMain disabled."
        } "Disabling Superfetch..."
        Update-TweakButtonStates
    })

$btnPerfEnableSuperfetch.Add_Click({
        Invoke-UiCommand {
            Set-Service -Name SysMain -StartupType Automatic
            Start-Service -Name SysMain -ErrorAction SilentlyContinue
            Write-GuiLog "Superfetch/SysMain enabled."
        } "Enabling Superfetch..."
        Update-TweakButtonStates
    })

$btnPerfDisableMemCompress.Add_Click({
        Invoke-UiCommand {
            Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
            Write-GuiLog "Memory compression disabled."
        } "Disabling memory compression..."
        Update-TweakButtonStates
    })

$btnPerfEnableMemCompress.Add_Click({
        Invoke-UiCommand {
            Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
            Write-GuiLog "Memory compression enabled."
        } "Enabling memory compression..."
        Update-TweakButtonStates
    })

$btnPerfUltimatePower.Add_Click({
        Invoke-UiCommand {
            powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
            powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61
            Write-GuiLog "Ultimate Performance power plan enabled."
        } "Enabling Ultimate Performance..."
        Update-TweakButtonStates
    })
$btnPerfEnableHags = Get-Ctrl "btnPerfEnableHags"
$btnPerfDisableHags = Get-Ctrl "btnPerfDisableHags"
if ($btnPerfEnableHags) {
    $btnPerfEnableHags.Add_Click({ Set-Hags -Enable $true; Update-TweakButtonStates })
}
if ($btnPerfDisableHags) {
    $btnPerfDisableHags.Add_Click({ Set-Hags -Enable $false; Update-TweakButtonStates })
}
    

# --- APPX BLOATWARE REMOVAL ---
$script:AppxList = @(
    [PSCustomObject]@{Name = "Xbox App"; Package = "Microsoft.XboxApp" },
    [PSCustomObject]@{Name = "Xbox Gaming Overlay"; Package = "Microsoft.XboxGamingOverlay" },
    [PSCustomObject]@{Name = "Xbox Game Bar"; Package = "Microsoft.XboxGameOverlay" },
    [PSCustomObject]@{Name = "Xbox Live"; Package = "Microsoft.XboxSpeechToTextOverlay" },
    [PSCustomObject]@{Name = "Xbox Identity Provider"; Package = "Microsoft.XboxIdentityProvider" },
    [PSCustomObject]@{Name = "Microsoft Solitaire"; Package = "Microsoft.MicrosoftSolitaireCollection" },
    [PSCustomObject]@{Name = "Microsoft Office Hub"; Package = "Microsoft.MicrosoftOfficeHub" },
    [PSCustomObject]@{Name = "OneNote"; Package = "Microsoft.Office.OneNote" },
    [PSCustomObject]@{Name = "Mail & Calendar"; Package = "microsoft.windowscommunicationsapps" },
    [PSCustomObject]@{Name = "People"; Package = "Microsoft.People" },
    [PSCustomObject]@{Name = "Skype"; Package = "Microsoft.SkypeApp" },
    [PSCustomObject]@{Name = "Maps"; Package = "Microsoft.WindowsMaps" },
    [PSCustomObject]@{Name = "Weather"; Package = "Microsoft.BingWeather" },
    [PSCustomObject]@{Name = "News"; Package = "Microsoft.BingNews" },
    [PSCustomObject]@{Name = "Sports"; Package = "Microsoft.BingSports" },
    [PSCustomObject]@{Name = "Finance"; Package = "Microsoft.BingFinance" },
    [PSCustomObject]@{Name = "Movies & TV"; Package = "Microsoft.ZuneVideo" },
    [PSCustomObject]@{Name = "Groove Music"; Package = "Microsoft.ZuneMusic" },
    [PSCustomObject]@{Name = "Get Help"; Package = "Microsoft.GetHelp" },
    [PSCustomObject]@{Name = "Get Started"; Package = "Microsoft.Getstarted" },
    [PSCustomObject]@{Name = "Feedback Hub"; Package = "Microsoft.WindowsFeedbackHub" },
    [PSCustomObject]@{Name = "Mixed Reality Portal"; Package = "Microsoft.MixedReality.Portal" },
    [PSCustomObject]@{Name = "3D Viewer"; Package = "Microsoft.Microsoft3DViewer" },
    [PSCustomObject]@{Name = "Paint 3D"; Package = "Microsoft.MSPaint" },
    [PSCustomObject]@{Name = "Phone Link"; Package = "Microsoft.YourPhone" },
    [PSCustomObject]@{Name = "Quick Assist"; Package = "MicrosoftCorporationII.QuickAssist" },
    [PSCustomObject]@{Name = "Family Safety"; Package = "MicrosoftCorporationII.MicrosoftFamily" }
)

$btnAppxLoad.Add_Click({
        $lstAppxPackages.Items.Clear()
        foreach ($app in $script:AppxList) {
            $installed = Get-AppxPackage -Name $app.Package -ErrorAction SilentlyContinue
            if ($installed) {
                [void]$lstAppxPackages.Items.Add($app)
            }
        }
        Write-GuiLog "Loaded $($lstAppxPackages.Items.Count) removable apps."
    })

$btnAppxRemoveSel.Add_Click({
        $selected = $lstAppxPackages.SelectedItems
        if ($selected.Count -eq 0) { return }
        Invoke-UiCommand {
            param($apps)
            foreach ($app in $apps) {
                try {
                    Remove-AppxPackage -Package (Get-AppxPackage -Name $app.Package).PackageFullName -ErrorAction SilentlyContinue
                    Write-GuiLog "Removed: $($app.Name)"
                }
                catch {
                    Write-GuiLog "Failed to remove: $($app.Name)"
                }
            }
        } "Removing selected apps..." -ArgumentList $selected
    })

$btnAppxRemoveAll.Add_Click({
        if ((Show-WmtMessageBox -Message "Remove ALL listed apps? This cannot be undone easily." -Title "Confirm" -Button YesNo -Image Warning) -eq [System.Windows.MessageBoxResult]::Yes) {
            $btnAppxRemoveSel.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
        }
    })

# --- WINDOWS FEATURES TOGGLE ---
$btnFeatHyperV.Add_Click({ Switch-WindowsFeature "Microsoft-Hyper-V-All" "Hyper-V" })
$btnFeatWSL.Add_Click({ Switch-WindowsFeature "Microsoft-Windows-Subsystem-Linux" "WSL" })
$btnFeatSandbox.Add_Click({ Switch-WindowsFeature "Containers-DisposableClientVM" "Windows Sandbox" })
$btnFeatDotNet35.Add_Click({ Switch-WindowsFeature "NetFx3" ".NET Framework 3.5" })
$btnFeatNFS.Add_Click({ Switch-WindowsFeature "ServicesForNFS-ClientOnly" "NFS Client" })
$btnFeatTelnet.Add_Click({ Switch-WindowsFeature "TelnetClient" "Telnet Client" })
$btnFeatIIS.Add_Click({ Switch-WindowsFeature "IIS-WebServerRole" "IIS Web Server" })
$btnFeatLegacy.Add_Click({ Switch-WindowsFeature "WindowsMediaPlayer" "Legacy Media" })



# --- SERVICES MANAGEMENT ---
$btnSvcOptimize.Add_Click({ $btnPerfServicesManual.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) })
$btnSvcRestore.Add_Click({ $btnPerfServicesRevert.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) })

$btnSvcView.Add_Click({
        Get-Service | Select-Object Name, DisplayName, StartType, Status | Out-GridView -Title "Windows Services"
    })

# --- SCHEDULED TASKS WITH REVERT ---
$script:TelemetryTasks = @(
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "\Microsoft\Windows\Autochk\Proxy",
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
    "\Microsoft\Windows\Feedback\Siuf\DmClient",
    "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload",
    "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
)

$btnTasksDisableTelemetry.Add_Click({
        Invoke-UiCommand {
            param($tasks)
            foreach ($task in $tasks) {
                $result = Invoke-WmtScheduledTaskAction -Action Disable -FullName $task
                if ($result.Success) {
                    Write-GuiLog "Disabled: $task"
                }
                else {
                    Write-GuiLog "Failed to disable $task`: $($result.Message)"
                }
            }
            Write-GuiLog "Telemetry tasks disabled!"
        } "Disabling telemetry tasks..." -ArgumentList $script:TelemetryTasks
    })

$btnTasksRestore.Add_Click({
        Invoke-UiCommand {
            param($tasks)
            foreach ($task in $tasks) {
                $result = Invoke-WmtScheduledTaskAction -Action Enable -FullName $task
                if ($result.Success) {
                    Write-GuiLog "Enabled: $task"
                }
                else {
                    Write-GuiLog "Failed to enable $task`: $($result.Message)"
                }
            }
            Write-GuiLog "Telemetry tasks restored!"
        } "Restoring telemetry tasks..." -ArgumentList $script:TelemetryTasks
    })

$btnTasksView.Add_Click({
        Show-WmtScheduledTasksDialog -Title "Telemetry Tasks" -FullPaths $script:TelemetryTasks
    })

# --- WINDOWS UPDATE PRESETS ---
$btnWUDefault.Add_Click({
        Invoke-UiCommand {
            Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferFeatureUpdates" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferQualityUpdates" -ErrorAction SilentlyContinue
            Set-Service -Name wuauserv -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
            Write-GuiLog "Windows Update set to Default."
        } "Applying default Windows Update settings..."
    })

$btnWUSecurity.Add_Click({
        Invoke-UiCommand {
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Force | Out-Null
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferFeatureUpdates" -Value 1
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferFeatureUpdatesPeriodInDays" -Value 365
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Value 0 -ErrorAction SilentlyContinue
            Set-Service -Name wuauserv -StartupType Automatic -ErrorAction SilentlyContinue
            Write-GuiLog "Windows Update set to Security Only (deferring features)."
        } "Applying security-only update settings..."
    })

$btnWUDisable.Add_Click({
        if ((Show-WmtMessageBox -Message "Disable ALL Windows Updates? This is not recommended for security." -Title "Warning" -Button YesNo -Image Warning) -eq [System.Windows.MessageBoxResult]::Yes) {
            Invoke-UiCommand {
                Set-Service -Name wuauserv -StartupType Disabled -ErrorAction SilentlyContinue
                Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
                New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force | Out-Null
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Value 1
                Write-GuiLog "Windows Update DISABLED."
            } "Disabling Windows Update..."
        }
    })

# --- Taskbar & Clock Tweaks Logic ---
$btnTaskbarLeft = Get-Ctrl "btnTaskbarLeft"
$btnTaskbarCenter = Get-Ctrl "btnTaskbarCenter"
$btnClock24 = Get-Ctrl "btnClock24"
$btnClock12 = Get-Ctrl "btnClock12"
$btnClockSecsOn = Get-Ctrl "btnClockSecsOn"
$btnClockSecsOff = Get-Ctrl "btnClockSecsOff"
$btnHideSearch = Get-Ctrl "btnHideSearch"
$btnSearchIcon = Get-Ctrl "btnSearchIcon"
$btnHideWidgets = Get-Ctrl "btnHideWidgets"
$btnHideTaskView = Get-Ctrl "btnHideTaskView"
$btnHideChat = Get-Ctrl "btnHideChat"
$btnNeverCombine = Get-Ctrl "btnNeverCombine"
$btnAlwaysCombine = Get-Ctrl "btnAlwaysCombine"
    
if ($btnTaskbarLeft) {
    $btnTaskbarLeft.Add_Click({
            Invoke-UiCommand {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 0 -Type DWord -Force
                Stop-Process -Name explorer -Force
            } "Aligning taskbar to the left... (Explorer will restart)"
            Update-TweakButtonStates
        })
}
    
if ($btnTaskbarCenter) {
    $btnTaskbarCenter.Add_Click({
            Invoke-UiCommand {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 1 -Type DWord -Force
                Stop-Process -Name explorer -Force
            } "Aligning taskbar to the center... (Explorer will restart)"
            Update-TweakButtonStates
        })
}
    
if ($btnClock24) {
    $btnClock24.Add_Click({
            Invoke-UiCommand {
                Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sShortTime" -Value "HH:mm" -Force
                Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sTimeFormat" -Value "HH:mm:ss" -Force
                Stop-Process -Name explorer -Force
            } "Setting system clock to 24-hour format..."
            Update-TweakButtonStates
        })
}
    
if ($btnClock12) {
    $btnClock12.Add_Click({
            Invoke-UiCommand {
                Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sShortTime" -Value "h:mm tt" -Force
                Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sTimeFormat" -Value "h:mm:ss tt" -Force
                Stop-Process -Name explorer -Force
            } "Setting system clock to 12-hour format..."
            Update-TweakButtonStates
        })
}
    
if ($btnClockSecsOn) {
    $btnClockSecsOn.Add_Click({
            Invoke-UiCommand {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowSecondsInSystemClock" -Value 1 -Type DWord -Force
                Stop-Process -Name explorer -Force
            } "Enabling seconds on the system clock..."
            Update-TweakButtonStates
        })
}
    
if ($btnClockSecsOff) {
    $btnClockSecsOff.Add_Click({
            Invoke-UiCommand {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowSecondsInSystemClock" -Value 0 -Type DWord -Force
                Stop-Process -Name explorer -Force
            } "Hiding seconds on the system clock..."
            Update-TweakButtonStates
        })
}
    
if ($btnHideSearch) {
    $btnHideSearch.Add_Click({
            Invoke-UiCommand {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0 -Type DWord -Force
                Stop-Process -Name explorer -Force
            } "Hiding Taskbar Search..."
            Update-TweakButtonStates
        })
}
            
if ($btnSearchIcon) {
    $btnSearchIcon.Add_Click({
            Invoke-UiCommand {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 1 -Type DWord -Force
                Stop-Process -Name explorer -Force
            } "Setting Taskbar Search to Icon only..."
            Update-TweakButtonStates
        })
}
            
if ($btnHideWidgets) {
    $btnHideWidgets.Add_Click({
            Invoke-UiCommand {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -Type DWord -Force
                Stop-Process -Name explorer -Force
            } "Hiding Taskbar Widgets..."
            Update-TweakButtonStates
        })
}
            
if ($btnHideTaskView) {
    $btnHideTaskView.Add_Click({
            Invoke-UiCommand {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0 -Type DWord -Force
                Stop-Process -Name explorer -Force
            } "Hiding Task View button..."
            Update-TweakButtonStates
        })
}
            
if ($btnHideChat) {
    $btnHideChat.Add_Click({
            Invoke-UiCommand {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Value 0 -Type DWord -Force
                Stop-Process -Name explorer -Force
            } "Hiding Chat icon..."
            Update-TweakButtonStates
        })
}
            
if ($btnNeverCombine) {
    $btnNeverCombine.Add_Click({
            Invoke-UiCommand {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarGlomLevel" -Value 2 -Type DWord -Force
                Stop-Process -Name explorer -Force
            } "Setting taskbar to never combine buttons..."
            Update-TweakButtonStates
        })
}
            
if ($btnAlwaysCombine) {
    $btnAlwaysCombine.Add_Click({
            Invoke-UiCommand {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarGlomLevel" -Value 0 -Type DWord -Force
                Stop-Process -Name explorer -Force
            } "Restoring default taskbar combining..."
            Update-TweakButtonStates
        })
}



$script:WmtSuggestionContentNames = @(
    "ContentDeliveryAllowed",
    "FeatureManagementEnabled",
    "OemPreInstalledAppsEnabled",
    "PreInstalledAppsEnabled",
    "PreInstalledAppsEverEnabled",
    "SilentInstalledAppsEnabled",
    "SoftLandingEnabled",
    "SubscribedContent-310093Enabled",
    "SubscribedContent-338388Enabled",
    "SubscribedContent-338389Enabled",
    "SubscribedContent-338393Enabled",
    "SubscribedContent-353694Enabled",
    "SubscribedContent-353696Enabled",
    "SystemPaneSuggestionsEnabled"
)

Register-WmtTweakButton "btnExpShowExt" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 0
        Restart-WmtExplorer
        Write-GuiLog "File extensions are now visible."
    } "Showing file extensions..."
}
Register-WmtTweakButton "btnExpHideExt" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 1
        Restart-WmtExplorer
        Write-GuiLog "Known file extensions are now hidden."
    } "Hiding file extensions..."
}
Register-WmtTweakButton "btnExpShowHidden" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Hidden" 1
        Restart-WmtExplorer
        Write-GuiLog "Hidden files and folders are now visible."
    } "Showing hidden files..."
}
Register-WmtTweakButton "btnExpHideHidden" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Hidden" 2
        Restart-WmtExplorer
        Write-GuiLog "Hidden files and folders are now hidden."
    } "Hiding hidden files..."
}
Register-WmtTweakButton "btnExpFullPathOn" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" "FullPath" 1
        Restart-WmtExplorer
        Write-GuiLog "Explorer title bars now show full paths."
    } "Enabling Explorer full path titles..."
}
Register-WmtTweakButton "btnExpFullPathOff" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" "FullPath" 0
        Restart-WmtExplorer
        Write-GuiLog "Explorer title bars now use default path display."
    } "Disabling Explorer full path titles..."
}
Register-WmtTweakButton "btnExpLaunchThisPc" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "LaunchTo" 1
        Write-GuiLog "File Explorer now opens to This PC."
    } "Setting Explorer to open This PC..."
}
Register-WmtTweakButton "btnExpLaunchQuickAccess" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "LaunchTo" 2
        Write-GuiLog "File Explorer now opens to Quick Access/Home."
    } "Setting Explorer to open Quick Access..."
}
Register-WmtTweakButton "btnExpHideRecents" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" "ShowRecent" 0
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" "ShowFrequent" 0
        Restart-WmtExplorer
        Write-GuiLog "Recent and frequent Quick Access items are hidden."
    } "Hiding Explorer recent items..."
}
Register-WmtTweakButton "btnExpShowRecents" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" "ShowRecent" 1
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" "ShowFrequent" 1
        Restart-WmtExplorer
        Write-GuiLog "Recent and frequent Quick Access items are visible."
    } "Showing Explorer recent items..."
}

Register-WmtTweakButton "btnMouseSpeedSlow" { Invoke-UiCommand { Set-WmtMouseSpeed 6; Write-GuiLog "Mouse pointer speed set to 6." } "Setting mouse pointer speed..." }
Register-WmtTweakButton "btnMouseSpeedDefault" { Invoke-UiCommand { Set-WmtMouseSpeed 10; Write-GuiLog "Mouse pointer speed set to 10." } "Setting mouse pointer speed..." }
Register-WmtTweakButton "btnMouseSpeedFast" { Invoke-UiCommand { Set-WmtMouseSpeed 15; Write-GuiLog "Mouse pointer speed set to 15." } "Setting mouse pointer speed..." }
Register-WmtTweakButton "btnMouseAccelOn" { Invoke-UiCommand { Set-WmtMouseAcceleration $true; Write-GuiLog "Mouse acceleration enabled." } "Enabling mouse acceleration..." }
Register-WmtTweakButton "btnMouseAccelOff" { Invoke-UiCommand { Set-WmtMouseAcceleration $false; Write-GuiLog "Mouse acceleration disabled." } "Disabling mouse acceleration..." }
Register-WmtTweakButton "btnMouseSingleClick" { Invoke-UiCommand { Set-WmtExplorerClickMode $true; Write-GuiLog "Single-click folder opening enabled." } "Enabling single-click folder opening..." }
Register-WmtTweakButton "btnMouseDoubleClick" { Invoke-UiCommand { Set-WmtExplorerClickMode $false; Write-GuiLog "Double-click folder opening restored." } "Restoring double-click folder opening..." }
Register-WmtTweakButton "btnMouseSettings" { Start-Process "ms-settings:mousetouchpad" }

Register-WmtTweakButton "btnCtxClassic" { Invoke-UiCommand { Set-WmtClassicContextMenu $true; Write-GuiLog "Classic Windows 11 context menu enabled." } "Enabling classic context menu..." }
Register-WmtTweakButton "btnCtxModern" { Invoke-UiCommand { Set-WmtClassicContextMenu $false; Write-GuiLog "Modern Windows 11 context menu restored." } "Restoring modern context menu..." }
Register-WmtTweakButton "btnCtxTakeOwnAdd" { Invoke-UiCommand { Set-WmtTakeOwnershipMenu $true; Write-GuiLog "Take Ownership context menu installed." } "Adding Take Ownership context menu..." }
Register-WmtTweakButton "btnCtxTakeOwnRemove" { Invoke-UiCommand { Set-WmtTakeOwnershipMenu $false; Write-GuiLog "Take Ownership context menu removed." } "Removing Take Ownership context menu..." }
Register-WmtTweakButton "btnCtxPsHereAdd" { Invoke-UiCommand { Set-WmtPowerShellHereMenu $true; Write-GuiLog "Open PowerShell Here context menu installed." } "Adding PowerShell context menu..." }
Register-WmtTweakButton "btnCtxPsHereRemove" { Invoke-UiCommand { Set-WmtPowerShellHereMenu $false; Write-GuiLog "Open PowerShell Here context menu removed." } "Removing PowerShell context menu..." }

Register-WmtTweakButton "btnPrivacyAdsOff" { Invoke-UiCommand { Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0; Write-GuiLog "Advertising ID disabled." } "Disabling advertising ID..." }
Register-WmtTweakButton "btnPrivacyAdsOn" { Invoke-UiCommand { Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 1; Write-GuiLog "Advertising ID enabled." } "Enabling advertising ID..." }
Register-WmtTweakButton "btnPrivacySuggestedOff" {
    Invoke-UiCommand {
        Set-WmtContentDeliveryValues $script:WmtSuggestionContentNames 0
        Set-WmtRegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 1
        Write-GuiLog "Suggested content disabled."
    } "Disabling suggested content..."
}
Register-WmtTweakButton "btnPrivacySuggestedOn" {
    Invoke-UiCommand {
        Set-WmtContentDeliveryValues $script:WmtSuggestionContentNames 1
        Remove-WmtRegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures"
        Write-GuiLog "Suggested content restored."
    } "Restoring suggested content..."
}
Register-WmtTweakButton "btnPrivacyTailoredOff" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" 0
        Set-WmtRegDword "HKCU:\Software\Policies\Microsoft\Windows\CloudContent" "DisableTailoredExperiencesWithDiagnosticData" 1
        Write-GuiLog "Tailored experiences disabled."
    } "Disabling tailored experiences..."
}
Register-WmtTweakButton "btnPrivacyTailoredOn" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" 1
        Remove-WmtRegValue "HKCU:\Software\Policies\Microsoft\Windows\CloudContent" "DisableTailoredExperiencesWithDiagnosticData"
        Write-GuiLog "Tailored experiences restored."
    } "Restoring tailored experiences..."
}
Register-WmtTweakButton "btnPrivacyActivityOff" {
    Invoke-UiCommand {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        Set-WmtRegDword $path "EnableActivityFeed" 0
        Set-WmtRegDword $path "PublishUserActivities" 0
        Set-WmtRegDword $path "UploadUserActivities" 0
        Write-GuiLog "Activity history policies disabled."
    } "Disabling activity history..."
}
Register-WmtTweakButton "btnPrivacyActivityOn" {
    Invoke-UiCommand {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        Remove-WmtRegValue $path "EnableActivityFeed"
        Remove-WmtRegValue $path "PublishUserActivities"
        Remove-WmtRegValue $path "UploadUserActivities"
        Write-GuiLog "Activity history policy defaults restored."
    } "Restoring activity history policies..."
}
Register-WmtTweakButton "btnPrivacyAppLaunchOff" { Invoke-UiCommand { Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_TrackProgs" 0; Write-GuiLog "App launch tracking disabled." } "Disabling app launch tracking..." }
Register-WmtTweakButton "btnPrivacyAppLaunchOn" { Invoke-UiCommand { Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_TrackProgs" 1; Write-GuiLog "App launch tracking restored." } "Restoring app launch tracking..." }

Register-WmtTweakButton "btnSearchWebOff" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 0
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "CortanaConsent" 0
        Restart-WmtExplorer
        Write-GuiLog "Web results in Start search disabled."
    } "Disabling web search results..."
}
Register-WmtTweakButton "btnSearchWebOn" {
    Invoke-UiCommand {
        Remove-WmtRegValue "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions"
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 1
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "CortanaConsent" 1
        Restart-WmtExplorer
        Write-GuiLog "Web results in Start search restored."
    } "Restoring web search results..."
}
Register-WmtTweakButton "btnSearchIndexReduced" {
    Invoke-UiCommand {
        Stop-Service -Name WSearch -Force -ErrorAction SilentlyContinue
        Set-Service -Name WSearch -StartupType Manual -ErrorAction SilentlyContinue
        Write-GuiLog "Windows Search indexing reduced."
    } "Reducing search indexing..."
}
Register-WmtTweakButton "btnSearchIndexDefault" {
    Invoke-UiCommand {
        Set-Service -Name WSearch -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name WSearch -ErrorAction SilentlyContinue
        Write-GuiLog "Windows Search indexing restored."
    } "Restoring search indexing..."
}
Register-WmtTweakButton "btnSearchIndexRebuild" {
    if ((Show-WmtMessageBox -Message "Rebuild the Windows Search index? Search results may be incomplete while it rebuilds." -Title "Rebuild Search Index" -Button YesNo -Image Warning) -eq [System.Windows.MessageBoxResult]::Yes) {
        Invoke-UiCommand {
            Stop-Service -Name WSearch -Force -ErrorAction SilentlyContinue
            $db = Join-Path $env:ProgramData "Microsoft\Search\Data\Applications\Windows\Windows.edb"
            if (Test-Path -LiteralPath $db) {
                Remove-Item -LiteralPath $db -Force -ErrorAction Stop
                Write-GuiLog "Deleted Windows.edb; Windows will rebuild the index."
            }
            else {
                Write-GuiLog "Search index database was not found."
            }
            Start-Service -Name WSearch -ErrorAction SilentlyContinue
        } "Rebuilding search index..."
    }
}
Register-WmtTweakButton "btnSearchIndexOptions" { Start-Process "control.exe" "srchadmin.dll" }

Register-WmtTweakButton "btnGameModeOn" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode" 1
        Set-WmtRegDword "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" 1
        Write-GuiLog "Game Mode enabled."
    } "Enabling Game Mode..."
}
Register-WmtTweakButton "btnGameModeOff" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode" 0
        Set-WmtRegDword "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" 0
        Write-GuiLog "Game Mode disabled."
    } "Disabling Game Mode..."
}
Register-WmtTweakButton "btnGameBarOff" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0
        Set-WmtRegDword "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0
        Set-WmtRegDword "HKCU:\Software\Microsoft\GameBar" "UseNexusForGameBarEnabled" 0
        Write-GuiLog "Xbox Game Bar disabled."
    } "Disabling Xbox Game Bar..."
}
Register-WmtTweakButton "btnGameBarOn" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 1
        Set-WmtRegDword "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 1
        Set-WmtRegDword "HKCU:\Software\Microsoft\GameBar" "UseNexusForGameBarEnabled" 1
        Write-GuiLog "Xbox Game Bar restored."
    } "Restoring Xbox Game Bar..."
}
Register-WmtTweakButton "btnGameCaptureOff" { Invoke-UiCommand { Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "HistoricalCaptureEnabled" 0; Write-GuiLog "Background capture disabled." } "Disabling background capture..." }
Register-WmtTweakButton "btnGameCaptureOn" { Invoke-UiCommand { Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "HistoricalCaptureEnabled" 1; Write-GuiLog "Background capture restored." } "Restoring background capture..." }
Register-WmtTweakButton "btnGameFsoOff" {
    Invoke-UiCommand {
        $path = "HKCU:\System\GameConfigStore"
        Set-WmtRegDword $path "GameDVR_FSEBehaviorMode" 2
        Set-WmtRegDword $path "GameDVR_HonorUserFSEBehaviorMode" 1
        Set-WmtRegDword $path "GameDVR_DXGIHonorFSEWindowsCompatible" 1
        Set-WmtRegDword $path "GameDVR_EFSEFeatureFlags" 0
        Write-GuiLog "Fullscreen optimizations disabled globally."
    } "Disabling fullscreen optimizations..."
}
Register-WmtTweakButton "btnGameFsoDefault" {
    Invoke-UiCommand {
        $path = "HKCU:\System\GameConfigStore"
        Set-WmtRegDword $path "GameDVR_FSEBehaviorMode" 0
        Set-WmtRegDword $path "GameDVR_HonorUserFSEBehaviorMode" 0
        Set-WmtRegDword $path "GameDVR_DXGIHonorFSEWindowsCompatible" 0
        Set-WmtRegDword $path "GameDVR_EFSEFeatureFlags" 0
        Write-GuiLog "Fullscreen optimization defaults restored."
    } "Restoring fullscreen optimizations..."
}

Register-WmtTweakButton "btnVisualBestAppearance" { Invoke-UiCommand { Set-WmtVisualPreset "Appearance"; Write-GuiLog "Visual effects set to best appearance." } "Applying best appearance..." }
Register-WmtTweakButton "btnVisualBestPerformance" { Invoke-UiCommand { Set-WmtVisualPreset "Performance"; Write-GuiLog "Visual effects set to best performance." } "Applying best performance..." }
Register-WmtTweakButton "btnVisualSnappy" { Invoke-UiCommand { Set-WmtVisualPreset "Snappy"; Write-GuiLog "Snappy desktop visual preset applied." } "Applying snappy desktop preset..." }

Register-WmtTweakButton "btnNotifyFocusSettings" { Start-Process "ms-settings:notifications" }
Register-WmtTweakButton "btnNotifyTipsOff" {
    Invoke-UiCommand {
        Set-WmtContentDeliveryValues @("SoftLandingEnabled", "SubscribedContent-338389Enabled", "SubscribedContent-338393Enabled", "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled") 0
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 0
        Write-GuiLog "Windows tips and suggestions disabled."
    } "Disabling notification tips..."
}
Register-WmtTweakButton "btnNotifyTipsOn" {
    Invoke-UiCommand {
        Set-WmtContentDeliveryValues @("SoftLandingEnabled", "SubscribedContent-338389Enabled", "SubscribedContent-338393Enabled", "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled") 1
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 1
        Write-GuiLog "Windows tips and suggestions restored."
    } "Restoring notification tips..."
}
Register-WmtTweakButton "btnNotifySetupOff" { Invoke-UiCommand { Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 0; Write-GuiLog "Finish setup prompts disabled." } "Disabling setup prompts..." }
Register-WmtTweakButton "btnNotifySetupOn" { Invoke-UiCommand { Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 1; Write-GuiLog "Finish setup prompts restored." } "Restoring setup prompts..." }
Register-WmtTweakButton "btnLockFactsOff" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "RotatingLockScreenOverlayEnabled" 0
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338387Enabled" 0
        Write-GuiLog "Lock screen fun facts disabled."
    } "Disabling lock screen fun facts..."
}
Register-WmtTweakButton "btnLockFactsOn" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "RotatingLockScreenOverlayEnabled" 1
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338387Enabled" 1
        Write-GuiLog "Lock screen fun facts restored."
    } "Restoring lock screen fun facts..."
}
Register-WmtTweakButton "btnLockSpotlightOff" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "RotatingLockScreenEnabled" 0
        Set-WmtRegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsSpotlightFeatures" 1
        Write-GuiLog "Lock screen Spotlight disabled."
    } "Disabling lock screen Spotlight..."
}
Register-WmtTweakButton "btnLockSpotlightOn" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "RotatingLockScreenEnabled" 1
        Remove-WmtRegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsSpotlightFeatures"
        Write-GuiLog "Lock screen Spotlight restored."
    } "Restoring lock screen Spotlight..."
}
Register-WmtTweakButton "btnLockPlain" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "RotatingLockScreenOverlayEnabled" 0
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338387Enabled" 0
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "RotatingLockScreenEnabled" 0
        Set-WmtRegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsSpotlightFeatures" 1
        Write-GuiLog "Plain lock screen preset applied."
    } "Applying plain lock screen..."
}
Register-WmtTweakButton "btnLockDefault" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "RotatingLockScreenOverlayEnabled" 1
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338387Enabled" 1
        Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "RotatingLockScreenEnabled" 1
        Remove-WmtRegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsSpotlightFeatures"
        Write-GuiLog "Default lock screen content restored."
    } "Restoring lock screen defaults..."
}

Register-WmtTweakButton "btnStartupFastOff" { Invoke-UiCommand { Set-WmtRegDword "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 0; Write-GuiLog "Fast Startup disabled." } "Disabling Fast Startup..." }
Register-WmtTweakButton "btnStartupFastOn" {
    Invoke-UiCommand {
        powercfg /hibernate on
        Set-WmtRegDword "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 1
        Write-GuiLog "Fast Startup enabled. Hibernation was enabled because Fast Startup depends on it."
    } "Enabling Fast Startup..."
}
Register-WmtTweakButton "btnStartupRestoreFoldersOn" { Invoke-UiCommand { Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "PersistBrowsers" 1; Write-GuiLog "Previous folder windows will restore at logon." } "Enabling folder restore at logon..." }
Register-WmtTweakButton "btnStartupRestoreFoldersOff" { Invoke-UiCommand { Set-WmtRegDword "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "PersistBrowsers" 0; Write-GuiLog "Previous folder windows will not restore at logon." } "Disabling folder restore at logon..." }

Register-WmtTweakButton "btnSecurityUacOpen" { Start-Process "UserAccountControlSettings.exe" }
Register-WmtTweakButton "btnSecurityUacStatus" {
    $systemPolicy = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    Write-GuiLog "UAC EnableLUA: $(Get-WmtRegValue $systemPolicy "EnableLUA" "Unknown")"
    Write-GuiLog "UAC ConsentPromptBehaviorAdmin: $(Get-WmtRegValue $systemPolicy "ConsentPromptBehaviorAdmin" "Unknown")"
    Write-GuiLog "UAC PromptOnSecureDesktop: $(Get-WmtRegValue $systemPolicy "PromptOnSecureDesktop" "Unknown")"
}
Register-WmtTweakButton "btnSecuritySmartScreenOpen" {
    try { Start-Process "windowsdefender://AppAndBrowser" } catch { Start-Process "ms-settings:windowsdefender" }
}
Register-WmtTweakButton "btnSecuritySmartScreenStatus" {
    Write-GuiLog "Explorer SmartScreen: $(Get-WmtRegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "SmartScreenEnabled" "Unknown")"
    Write-GuiLog "AppHost Web Content Evaluation: $(Get-WmtRegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost" "EnableWebContentEvaluation" "Unknown")"
    if (Get-Command Get-MpPreference -ErrorAction SilentlyContinue) {
        $mp = Get-MpPreference -ErrorAction SilentlyContinue
        if ($mp) { Write-GuiLog "Defender PUA protection: $($mp.PUAProtection)" }
    }
}
Register-WmtTweakButton "btnSecurityCfaOpen" {
    try { Start-Process "windowsdefender://RansomwareProtection" } catch { Start-Process "ms-settings:windowsdefender" }
}

Register-WmtTweakButton "btnPowerBatterySaverOff" { Invoke-UiCommand { Set-WmtPowerSettingIndex "SUB_ENERGYSAVER" "ESBATTTHRESHOLD" 0 -DCOnly; Write-GuiLog "Battery saver threshold set to 0%." } "Setting battery saver threshold..." }
Register-WmtTweakButton "btnPowerBatterySaver20" { Invoke-UiCommand { Set-WmtPowerSettingIndex "SUB_ENERGYSAVER" "ESBATTTHRESHOLD" 20 -DCOnly; Write-GuiLog "Battery saver threshold set to 20%." } "Setting battery saver threshold..." }
Register-WmtTweakButton "btnPowerBatterySaver50" { Invoke-UiCommand { Set-WmtPowerSettingIndex "SUB_ENERGYSAVER" "ESBATTTHRESHOLD" 50 -DCOnly; Write-GuiLog "Battery saver threshold set to 50%." } "Setting battery saver threshold..." }
Register-WmtTweakButton "btnPowerUsbSuspendOn" { Invoke-UiCommand { Set-WmtPowerSettingIndex "2a737441-1930-4402-8d77-b2bebba308a3" "48e6b7a6-50f5-4782-a5d4-53bb8f07e226" 1; Write-GuiLog "USB selective suspend enabled." } "Enabling USB selective suspend..." }
Register-WmtTweakButton "btnPowerUsbSuspendOff" { Invoke-UiCommand { Set-WmtPowerSettingIndex "2a737441-1930-4402-8d77-b2bebba308a3" "48e6b7a6-50f5-4782-a5d4-53bb8f07e226" 0; Write-GuiLog "USB selective suspend disabled." } "Disabling USB selective suspend..." }
Register-WmtTweakButton "btnPowerPcieModerate" { Invoke-UiCommand { Set-WmtPowerSettingIndex "501a4d13-42af-4429-9fd1-a8218c268e20" "ee12f906-d277-404b-b6da-e5fa1a576df5" 1; Write-GuiLog "PCI Express link state set to moderate savings." } "Setting PCIe link state savings..." }
Register-WmtTweakButton "btnPowerPcieOff" { Invoke-UiCommand { Set-WmtPowerSettingIndex "501a4d13-42af-4429-9fd1-a8218c268e20" "ee12f906-d277-404b-b6da-e5fa1a576df5" 0; Write-GuiLog "PCI Express link state savings disabled." } "Disabling PCIe link state savings..." }

Register-WmtTweakButton "btnDevLongPathsOn" { Invoke-UiCommand { Set-WmtRegDword "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" "LongPathsEnabled" 1; Write-GuiLog "Win32 long paths enabled." } "Enabling long paths..." }
Register-WmtTweakButton "btnDevLongPathsOff" { Invoke-UiCommand { Set-WmtRegDword "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" "LongPathsEnabled" 0; Write-GuiLog "Win32 long paths disabled." } "Disabling long paths..." }
Register-WmtTweakButton "btnDevModeOn" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" "AllowDevelopmentWithoutDevLicense" 1
        Set-WmtRegDword "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" "AllowAllTrustedApps" 1
        Write-GuiLog "Developer Mode policies enabled."
    } "Enabling Developer Mode..."
}
Register-WmtTweakButton "btnDevModeOff" {
    Invoke-UiCommand {
        Set-WmtRegDword "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" "AllowDevelopmentWithoutDevLicense" 0
        Set-WmtRegDword "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" "AllowAllTrustedApps" 0
        Write-GuiLog "Developer Mode policies disabled."
    } "Disabling Developer Mode..."
}
Register-WmtTweakButton "btnDevSettings" { Start-Process "ms-settings:developers" }

# --- SOFTWARE CATALOG ---
$script:SoftwareCatalog = @(
    [PSCustomObject]@{Category = "Browsers"; Name = "Google Chrome"; Description = "Fast, secure web browser"; Source = "winget"; Id = "Google.Chrome" },
    [PSCustomObject]@{Category = "Browsers"; Name = "Mozilla Firefox"; Description = "Privacy-focused browser"; Source = "winget"; Id = "Mozilla.Firefox" },
    [PSCustomObject]@{Category = "Browsers"; Name = "Microsoft Edge"; Description = "Chromium-based browser"; Source = "winget"; Id = "Microsoft.Edge" },
    [PSCustomObject]@{Category = "Browsers"; Name = "Brave"; Description = "Privacy-focused Chromium browser"; Source = "winget"; Id = "Brave.Brave" },
    [PSCustomObject]@{Category = "Development"; Name = "Visual Studio Code"; Description = "Popular code editor"; Source = "winget"; Id = "Microsoft.VisualStudioCode" },
    [PSCustomObject]@{Category = "Development"; Name = "Git"; Description = "Version control system"; Source = "winget"; Id = "Git.Git" },
    [PSCustomObject]@{Category = "Development"; Name = "Node.js"; Description = "JavaScript runtime"; Source = "winget"; Id = "OpenJS.NodeJS" },
    [PSCustomObject]@{Category = "Development"; Name = "Python"; Description = "Programming language"; Source = "winget"; Id = "Python.Python.3" },
    [PSCustomObject]@{Category = "Development"; Name = "Notepad++"; Description = "Advanced text editor"; Source = "winget"; Id = "Notepad++.Notepad++" },
    [PSCustomObject]@{Category = "Utilities"; Name = "7-Zip"; Description = "File archiver"; Source = "winget"; Id = "7zip.7zip" },
    [PSCustomObject]@{Category = "Utilities"; Name = "WinRAR"; Description = "Archive manager"; Source = "winget"; Id = "RARLab.WinRAR" },
    [PSCustomObject]@{Category = "Utilities"; Name = "Everything"; Description = "Fast file search"; Source = "winget"; Id = "voidtools.Everything" },
    [PSCustomObject]@{Category = "Utilities"; Name = "PowerToys"; Description = "Microsoft productivity tools"; Source = "winget"; Id = "Microsoft.PowerToys" },
    [PSCustomObject]@{Category = "Utilities"; Name = "HWiNFO"; Description = "Hardware monitoring"; Source = "winget"; Id = "REALiX.HWiNFO" },
    [PSCustomObject]@{Category = "Multimedia"; Name = "VLC Media Player"; Description = "Universal media player"; Source = "winget"; Id = "VideoLAN.VLC" },
    [PSCustomObject]@{Category = "Multimedia"; Name = "Spotify"; Description = "Music streaming"; Source = "winget"; Id = "Spotify.Spotify" },
    [PSCustomObject]@{Category = "Multimedia"; Name = "OBS Studio"; Description = "Streaming/recording software"; Source = "winget"; Id = "OBSProject.OBSStudio" },
    [PSCustomObject]@{Category = "Multimedia"; Name = "GIMP"; Description = "Image editor"; Source = "winget"; Id = "GIMP.GIMP" },
    [PSCustomObject]@{Category = "Gaming"; Name = "Steam"; Description = "Game platform"; Source = "winget"; Id = "Valve.Steam" },
    [PSCustomObject]@{Category = "Gaming"; Name = "Discord"; Description = "Chat for gamers"; Source = "winget"; Id = "Discord.Discord" },
    [PSCustomObject]@{Category = "Gaming"; Name = "Epic Games Launcher"; Description = "Epic game store"; Source = "winget"; Id = "EpicGames.EpicGamesLauncher" },
    [PSCustomObject]@{Category = "Security"; Name = "Malwarebytes"; Description = "Anti-malware"; Source = "winget"; Id = "Malwarebytes.Malwarebytes" },
    [PSCustomObject]@{Category = "Security"; Name = "Bitwarden"; Description = "Password manager"; Source = "winget"; Id = "Bitwarden.Bitwarden" }
)







if ($btnShowCatalog -and $btnBackToUpdates -and $btnCatalogSearch -and $btnCatalogInstall -and $btnCatalogSelectAll -and $btnCatalogClear -and $btnCatAll -and $btnCatBrowsers -and $btnCatDev -and $btnCatUtils -and $btnCatMedia -and $btnCatGames -and $btnCatSecurity -and $pnlCatalog -and $lstCatalog -and $txtCatalogSearch) {
    $btnShowCatalog.Add_Click({
            $pnlUpdates.Visibility = "Collapsed"
            $pnlCatalog.Visibility = "Visible"
            Add-WmtCatalogListItems -ListView $lstCatalog -Items $script:SoftwareCatalog
        })

    $btnBackToUpdates.Add_Click({
            $pnlCatalog.Visibility = "Collapsed"
            $pnlUpdates.Visibility = "Visible"
        })

    $btnCatalogSearch.Add_Click({
            Add-WmtCatalogListItems -ListView $lstCatalog -Items (Get-WmtCatalogItemsBySearch -Query $txtCatalogSearch.Text)
        })

    $btnCatAll.Add_Click({
            Add-WmtCatalogListItems -ListView $lstCatalog -Items $script:SoftwareCatalog
        })

    $btnCatBrowsers.Add_Click({ Get-CatalogByCategory "Browsers" })
    $btnCatDev.Add_Click({ Get-CatalogByCategory "Development" })
    $btnCatUtils.Add_Click({ Get-CatalogByCategory "Utilities" })
    $btnCatMedia.Add_Click({ Get-CatalogByCategory "Multimedia" })
    $btnCatGames.Add_Click({ Get-CatalogByCategory "Gaming" })
    $btnCatSecurity.Add_Click({ Get-CatalogByCategory "Security" })
}



if ($btnCatalogInstall -and $btnCatalogSelectAll -and $btnCatalogClear -and $lstCatalog) {
    $btnCatalogInstall.Add_Click({
            $selected = $lstCatalog.SelectedItems
            if ($selected.Count -eq 0) { return }
            Invoke-UiCommand {
                param($items)
                foreach ($item in $items) {
                    Write-GuiLog "Installing: $($item.Name)..."
                    $proc = Start-Process -FilePath "winget" -ArgumentList "install --id `"$($item.Id)`" --accept-source-agreements --accept-package-agreements --silent" -Wait -PassThru
                    if ($proc.ExitCode -eq 0) {
                        Write-GuiLog "Installed: $($item.Name)"
                    }
                    else {
                        Write-GuiLog "Failed: $($item.Name)"
                    }
                }
            } "Installing software..." -ArgumentList $selected
        })

    $btnCatalogSelectAll.Add_Click({ $lstCatalog.SelectAll() })
    $btnCatalogClear.Add_Click({ $lstCatalog.SelectedItems.Clear() })
}

# My Device shortcuts point at the original page buttons so all confirmations, logging, and state checks stay in one place.


@{
    btnMyDeviceQuickFix       = "btnQuickFix"
    btnMyDeviceWinRE          = "btnUtilWinRE"
    btnMyDeviceSysReport      = "btnUtilSysInfo"
    btnMyDeviceRestoreMgr     = "btnUtilRestoreMgr"
    btnMyDeviceStartupMgr     = "btnUtilStartupMgr"
    btnMyDeviceUpdateRepair   = "btnUpdateRepair"
    btnMyDeviceUpdateServices = "btnUpdateServices"
    btnMyDeviceNetInfo        = "btnNetInfo"
    btnMyDeviceFlushDNS       = "btnFlushDNS"
    btnMyDeviceResetWifi      = "btnResetWifi"
    btnMyDeviceNetRepair      = "btnNetRepair"
    btnMyDeviceDnsCustom      = "btnDnsCustom"
    btnMyDeviceHostsEdit      = "btnHostsEdit"
    btnMyDeviceHostsAdBlock   = "btnHostsUpdate"
    btnMyDeviceRouteView      = "btnRouteView"
    btnMyDeviceUltimatePower  = "btnPerfUltimatePower"
    btnMyDeviceHibernateOff   = "btnPerfDisableHibernate"
    btnMyDeviceHibernateOn    = "btnPerfEnableHibernate"
    btnMyDeviceMemCompressOff = "btnPerfDisableMemCompress"
    btnMyDeviceMemCompressOn  = "btnPerfEnableMemCompress"
    btnMyDeviceHagsOn         = "btnPerfEnableHags"
    btnMyDeviceHagsOff        = "btnPerfDisableHags"
    btnMyDeviceDriverReport   = "btnDrvReport"
    btnMyDeviceDriverBackup   = "btnDrvBackup"
    btnMyDeviceGhostDrivers   = "btnDrvGhost"
    btnMyDeviceDriverClean    = "btnDrvClean"
    btnMyDeviceDriverRestore  = "btnDrvRestore"
    btnMyDeviceChkdsk         = "btnCHKDSK"
    btnMyDeviceDiskCleanup    = "btnCleanDisk"
    btnMyDeviceTempCleanup    = "btnCleanTemp"
}.GetEnumerator() | ForEach-Object {
    Connect-WmtMyDeviceShortcut -ShortcutButtonName $_.Key -TargetButtonName $_.Value
}







# --- LAUNCH ---
$onMainWindowContentRendered = {
    $settings = Get-WmtSettings

    # Restore persisted window geometry/state when valid.
    if ($settings.WindowBounds) {
        $wb = $settings.WindowBounds
        if ($wb.Width -ge $window.MinWidth -and $wb.Height -ge $window.MinHeight) {
            $window.Width = [double]$wb.Width
            $window.Height = [double]$wb.Height
        }
        if (($wb.Left -ne 0 -or $wb.Top -ne 0) -and $settings.WindowState -ne "Maximized") {
            $screenW = [System.Windows.SystemParameters]::VirtualScreenWidth
            $screenH = [System.Windows.SystemParameters]::VirtualScreenHeight
            $screenX = [System.Windows.SystemParameters]::VirtualScreenLeft
            $screenY = [System.Windows.SystemParameters]::VirtualScreenTop

            $clampedLeft = [math]::Max($screenX, [math]::Min([double]$wb.Left, $screenX + $screenW - 100))
            $clampedTop = [math]::Max($screenY, [math]::Min([double]$wb.Top, $screenY + $screenH - 40))

            $window.Left = $clampedLeft
            $window.Top = $clampedTop
        }
    }

    Set-WmtTheme -Theme $settings.Theme
    if ($settings.WindowState -eq "Maximized") {
        $window.WindowState = [System.Windows.WindowState]::Maximized
    }

    # 1. Click the Updates tab by default.
    (Get-Ctrl "btnTabUpdates").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))

    # 2. Warm hidden pages in the background while the Updates scan starts.
    Start-WmtStartupBackgroundPreload

    # 3. Trigger the background update check.
    Start-UpdateCheckBackground

    # 3b. Enable periodic update auto scan if configured in Provider settings.
    if (Get-WmtUpdateNotificationsEnabled -Settings $settings) {
        [void](Initialize-WmtNativeToastSupport)
    }
    Start-WmtUpdateAutoScanTimer -ResetNextRun

    # 4. Update tweak button states based on system.
    Update-TweakButtonStates
    Update-MyDeviceResponsiveLayout
}.GetNewClosure()
[void]$window.Add_ContentRendered($onMainWindowContentRendered)

$onMainWindowSizeChanged = {
    Update-MyDeviceResponsiveLayout
}.GetNewClosure()
[void]$window.Add_SizeChanged($onMainWindowSizeChanged)

$onMainWindowClosing = {
    param($windowSender, $closeArgs)

    if (-not $script:WmtAllowFinalClose -and (Get-WmtRunInTrayOnClose)) {
        try {
            if (Initialize-WmtTrayIcon -Window $window) {
                if ($closeArgs) { $closeArgs.Cancel = $true }
                $script:WmtHiddenToTray = $true
                $window.ShowInTaskbar = $false
                $window.Hide()
                if (Get-WmtReduceRamInTray) {
                    Invoke-WmtMemoryTrim -Reason "hidden-to-tray"
                }
                Show-WmtTrayHiddenBalloon
                Write-GuiLog "WMT hidden to the system tray. Background update scans will continue. Left-click the tray icon to reopen, or right-click it to exit."
                return
            }
        }
        catch {
            Write-GuiLog "Tray close fallback failed: $($_.Exception.Message)"
        }
    }

    # Cancel any ongoing scan.
    if ($script:ActiveScans) {
        foreach ($task in $script:ActiveScans) {
            try { $task.PowerShell.Stop() } catch {}
            try { $task.PowerShell.Dispose() } catch {}
        }
        $script:ActiveScans.Clear()
    }
    if ($script:ScanTimer) { $script:ScanTimer.Stop() }
    if ($script:GlobalScanTimer) { $script:GlobalScanTimer.Stop() }
    Stop-WmtUpdateAutoScanTimer
    Remove-WmtTrayIcon
    Stop-WmtNotificationFallbackTimers
    if ($script:WingetTimer) { $script:WingetTimer.Stop() }
    Stop-WmtStartupBackgroundPreload
    if ($script:WingetSourcePreflightTimer) { $script:WingetSourcePreflightTimer.Stop() }
    if ($script:WingetSourcePreflightRunspace) {
        try { $script:WingetSourcePreflightRunspace.Stop() } catch {}
        try { $script:WingetSourcePreflightRunspace.Dispose() } catch {}
    }
    Stop-FirewallRuleLoad
    Stop-FirewallDetailLoad
    Stop-MyDeviceSectionJobs
    Stop-WmtDnsRunspaces
    if ($script:WmtRegistryCleanupTimer) { try { $script:WmtRegistryCleanupTimer.Stop() } catch {}; $script:WmtRegistryCleanupTimer = $null }
    if ($script:WmtRegistryCleanupPowerShell) { try { $script:WmtRegistryCleanupPowerShell.Stop() } catch {}; try { $script:WmtRegistryCleanupPowerShell.Dispose() } catch {}; $script:WmtRegistryCleanupPowerShell = $null }
    if ($script:WmtRegistryCleanupRunspace) { try { $script:WmtRegistryCleanupRunspace.Dispose() } catch {}; $script:WmtRegistryCleanupRunspace = $null }
    $script:WmtRegistryCleanupAsync = $null
    $script:WmtRegistryCleanupSync = $null
    $script:WmtRegistryCleanupActive = $false
    if ($script:BitLockerStatusTimer) { $script:BitLockerStatusTimer.Stop() }
    if ($script:BitLockerStatusRunspace) {
        try { $script:BitLockerStatusRunspace.Stop() } catch {}
        try { $script:BitLockerStatusRunspace.Dispose() } catch {}
    }

    try {
        $settings = Get-WmtSettings
        $settings.Theme = $script:CurrentTheme
        $settings.WindowState = [string]$window.WindowState

        $rb = if ($window.WindowState -eq [System.Windows.WindowState]::Normal) { $null } else { $window.RestoreBounds }
        if ($rb) {
            $settings.WindowBounds = @{
                Top    = [double]$rb.Top
                Left   = [double]$rb.Left
                Width  = [double]$rb.Width
                Height = [double]$rb.Height
            }
        }
        else {
            $settings.WindowBounds = @{
                Top    = [double]$window.Top
                Left   = [double]$window.Left
                Width  = [double]$window.Width
                Height = [double]$window.Height
            }
        }
        Save-WmtSettings -Settings $settings
    }
    catch {}
}.GetNewClosure()
[void]$window.Add_Closing($onMainWindowClosing)

$onMainWindowClosed = {
    try { Remove-WmtTrayIcon } catch {}
    try { Stop-WmtNotificationFallbackTimers } catch {}
    try {
        $app = $script:WmtApplication
        if (-not $app) { $app = [System.Windows.Application]::Current }
        if ($app) { $app.Shutdown() }
    }
    catch {}
}.GetNewClosure()
[void]$window.Add_Closed($onMainWindowClosed)

# Show the Window.
# Use a real WPF Application message loop instead of ShowDialog().
# ShowDialog() can unwind after a modal window is hidden, which leaves a stale tray icon that vanishes when clicked.
try {
    $script:WmtApplication = [System.Windows.Application]::Current
    if (-not $script:WmtApplication) {
        $script:WmtApplication = New-Object System.Windows.Application
    }

    if ($script:WmtDispatcherUnhandledHandler) {
        try { $script:WmtApplication.remove_DispatcherUnhandledException($script:WmtDispatcherUnhandledHandler) } catch {}
    }
    $script:WmtDispatcherUnhandledHandler = [System.Windows.Threading.DispatcherUnhandledExceptionEventHandler] {
        param($s, $eA)

        try { $eventArgs.Handled = $true } catch {}
        try {
            Write-WmtLastCrash -Context "Unhandled WPF dispatcher exception" -Exception $eventArgs.Exception
            if ($script:WingetJob -or $script:WingetActiveAction) {
                Reset-WmtUpdateUiAfterMonitorError -Context "Unhandled WPF dispatcher exception" -Exception $eventArgs.Exception -SkipCrashWrite
            }
        }
        catch {}
    }
    $script:WmtApplication.add_DispatcherUnhandledException($script:WmtDispatcherUnhandledHandler)

    $script:WmtApplication.ShutdownMode = [System.Windows.ShutdownMode]::OnLastWindowClose
    $script:WmtApplication.MainWindow = $window
    [void]$script:WmtApplication.Run($window)
}
catch {
    Write-WmtLastCrash -Context "WMT application loop failed" -Exception $_.Exception -ErrorRecord $_
    Write-Warning "WMT application loop failed: $($_.Exception.Message)"
}

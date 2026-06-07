# Functional block generated from WMT-GUI.ps1.
# Dot-source this file; it intentionally shares WMT's script scope.

function Get-DataPath {
    if (-not [string]::IsNullOrWhiteSpace($script:DataDir) -and [System.IO.Directory]::Exists($script:DataDir)) {
        return $script:DataDir
    }

    $root = $script:WmtRootPath
    if ([string]::IsNullOrWhiteSpace($root)) {
        foreach ($candidate in @($script:WmtLaunchPath, $script:WmtScriptPath, $PSCommandPath)) {
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                try {
                    $root = Split-Path -Parent $candidate
                    if (-not [string]::IsNullOrWhiteSpace($root)) { break }
                }
                catch {}
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = (Get-Location).Path
    }
    $dataPath = Join-Path $root "data"
    try {
        if (-not [System.IO.Directory]::Exists($dataPath)) {
            [void][System.IO.Directory]::CreateDirectory($dataPath)
        }
    }
    catch {}
    $script:DataDir = $dataPath
    return $dataPath
}

function Save-WmtSettings {
    param($Settings)
    $path = Join-Path (Get-DataPath) "settings.json"
    try {
        # Update the memory cache immediately
        $script:WmtSettingsCache = $Settings

        # Convert Hashtable/OrderedDictionary to generic Object for cleaner JSON
        $saveObj = [PSCustomObject]@{
            TempCleanup                = $Settings.TempCleanup
            RegistryScan               = $Settings.RegistryScan
            WingetIgnore               = $Settings.WingetIgnore
            WingetIncludeUnknown       = [bool](Get-WmtWingetIncludeUnknown -Settings $Settings)
            UpdateAutoScanMinutes      = [int](Get-WmtUpdateAutoScanMinutes -Settings $Settings)
            UpdateNotificationsEnabled = [bool](Get-WmtUpdateNotificationsEnabled -Settings $Settings)
            UpdateSilentInstallEnabled = [bool](Get-WmtUpdateSilentInstallEnabled -Settings $Settings)
            UpdateAutoInstallEnabled   = [bool](Get-WmtUpdateAutoInstallEnabled -Settings $Settings)
            RunInTrayOnClose           = [bool](Get-WmtRunInTrayOnClose -Settings $Settings)
            ReduceRamInTray            = [bool](Get-WmtReduceRamInTray -Settings $Settings)
            LoadWinapp2                = [bool]$Settings.LoadWinapp2
            LoadCleanerML              = [bool]$Settings.LoadCleanerML
            EnabledProviders           = $Settings.EnabledProviders
            CustomDnsServers           = if ($Settings.CustomDnsServers) { @($Settings.CustomDnsServers) } else { @() }
            CustomDohTemplate          = if ($Settings.CustomDohTemplate) { [string]$Settings.CustomDohTemplate } else { "" }
            CustomDohEnabled           = [bool]$Settings.CustomDohEnabled
            Theme                      = if ($Settings.Theme) { [string]$Settings.Theme } else { "dark" }
            WindowState                = if ($Settings.WindowState) { [string]$Settings.WindowState } else { "Normal" }
            WindowBounds               = if ($Settings.WindowBounds) { $Settings.WindowBounds } else { $null }
        }
        $saveObj | ConvertTo-Json -Depth 5 | Set-Content $path -Force
    }
    catch {
        Write-Warning "Failed to save settings: $_"
    }
}

function Get-WmtSettings {
    # OPTIMIZATION: Return cached settings if available to avoid disk I/O
    if ($script:WmtSettingsCache) { return $script:WmtSettingsCache }

    $path = Join-Path (Get-DataPath) "settings.json"
    
    # Default Structure
    $defaults = @{
        TempCleanup                = @{}
        RegistryScan               = @{}
        WingetIgnore               = @("228980") # Filter false positive updates for Steamworks Redist
        WingetIncludeUnknown       = $true
        UpdateAutoScanMinutes      = 0
        UpdateNotificationsEnabled = $true
        UpdateSilentInstallEnabled = $false
        UpdateAutoInstallEnabled   = $false
        RunInTrayOnClose           = $false
        ReduceRamInTray            = $true
        LoadWinapp2                = $false 
        LoadCleanerML              = $false
        EnabledProviders           = @("winget", "msstore", "windowsupdate", "pip", "npm", "pnpm", "dotnet", "psmodule", "composer", "chocolatey", "scoop", "gem", "cargo", "steam", "legendary", "gogdl")
        CustomDnsServers           = @()
        CustomDohTemplate          = ""
        CustomDohEnabled           = $false
        Theme                      = "dark"
        WindowState                = "Normal"
        WindowBounds               = @{
            Top    = 0
            Left   = 0
            Width  = 1280
            Height = 820
        }
    }
    
    if (Test-Path $path) {
        try {
            $json = Get-Content $path -Raw | ConvertFrom-Json
            
            if ($json.TempCleanup) { 
                foreach ($p in $json.TempCleanup.PSObject.Properties) { $defaults.TempCleanup[$p.Name] = $p.Value } 
            }
            if ($json.RegistryScan) { 
                foreach ($p in $json.RegistryScan.PSObject.Properties) { $defaults.RegistryScan[$p.Name] = $p.Value } 
            }
            if ($json.PSObject.Properties["WingetIgnore"]) {
                $raw = $json.WingetIgnore
                $clean = New-Object System.Collections.ArrayList
                if ($raw) { foreach ($item in $raw) { [void]$clean.Add("$item".Trim()) } }
                $defaults.WingetIgnore = $clean.ToArray()
            }
            if ($json.PSObject.Properties["WingetIncludeUnknown"]) { $defaults.WingetIncludeUnknown = [bool]$json.WingetIncludeUnknown }
            if ($json.PSObject.Properties["UpdateAutoScanMinutes"]) {
                try { $defaults.UpdateAutoScanMinutes = [int]$json.UpdateAutoScanMinutes } catch { $defaults.UpdateAutoScanMinutes = 0 }
                if ($defaults.UpdateAutoScanMinutes -lt 0) { $defaults.UpdateAutoScanMinutes = 0 }
            }
            if ($json.PSObject.Properties["UpdateNotificationsEnabled"]) { $defaults.UpdateNotificationsEnabled = [bool]$json.UpdateNotificationsEnabled }
            if ($json.PSObject.Properties["UpdateSilentInstallEnabled"]) { $defaults.UpdateSilentInstallEnabled = [bool]$json.UpdateSilentInstallEnabled }
            if ($json.PSObject.Properties["UpdateAutoInstallEnabled"]) { $defaults.UpdateAutoInstallEnabled = [bool]$json.UpdateAutoInstallEnabled }
            if ($json.PSObject.Properties["RunInTrayOnClose"]) { $defaults.RunInTrayOnClose = [bool]$json.RunInTrayOnClose }
            if ($json.PSObject.Properties["ReduceRamInTray"]) { $defaults.ReduceRamInTray = [bool]$json.ReduceRamInTray }
            if ($json.PSObject.Properties["LoadWinapp2"]) { $defaults.LoadWinapp2 = [bool]$json.LoadWinapp2 }
            if ($json.PSObject.Properties["LoadCleanerML"]) { $defaults.LoadCleanerML = [bool]$json.LoadCleanerML }
            if ($json.PSObject.Properties["EnabledProviders"]) { $defaults.EnabledProviders = $json.EnabledProviders }
            if ($json.PSObject.Properties["CustomDnsServers"]) {
                $customDnsServers = @()
                foreach ($server in @($json.CustomDnsServers)) {
                    $serverText = ([string]$server).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($serverText)) { $customDnsServers += $serverText }
                }
                $defaults.CustomDnsServers = $customDnsServers
            }
            if ($json.PSObject.Properties["CustomDohTemplate"]) { $defaults.CustomDohTemplate = [string]$json.CustomDohTemplate }
            if ($json.PSObject.Properties["CustomDohEnabled"]) { $defaults.CustomDohEnabled = [bool]$json.CustomDohEnabled }
            if ($json.PSObject.Properties["Theme"] -and $json.Theme) { $defaults.Theme = [string]$json.Theme }
            if ($json.PSObject.Properties["WindowState"] -and $json.WindowState) { $defaults.WindowState = [string]$json.WindowState }
            if ($json.PSObject.Properties["WindowBounds"] -and $json.WindowBounds) {
                $defaults.WindowBounds = @{
                    Top    = [double]$json.WindowBounds.Top
                    Left   = [double]$json.WindowBounds.Left
                    Width  = [double]$json.WindowBounds.Width
                    Height = [double]$json.WindowBounds.Height
                }
            }
        }
        catch { 
            Write-GuiLog "Error loading settings: $($_.Exception.Message)" 
        }
    }
    $normalizedProviders = New-Object System.Collections.Generic.List[string]
    foreach ($provider in @($defaults.EnabledProviders)) {
        $providerKey = ([string]$provider).Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($providerKey)) { continue }
        if ($providerKey -eq "comet") { $providerKey = "gogdl" }
        if (-not $normalizedProviders.Contains($providerKey)) {
            [void]$normalizedProviders.Add($providerKey)
        }
    }
    if ($normalizedProviders.Count -eq 0) {
        [void]$normalizedProviders.Add("winget")
    }
    $defaults.EnabledProviders = $normalizedProviders.ToArray()

    # Cache the result
    $script:WmtSettingsCache = $defaults
    return $defaults
}

function Get-WmtWingetIncludeUnknown {
    param($Settings)

    if (-not $Settings) { $Settings = Get-WmtSettings }

    if ($Settings -is [System.Collections.IDictionary] -and $Settings.Contains("WingetIncludeUnknown")) {
        return [bool]$Settings["WingetIncludeUnknown"]
    }
    if ($Settings.PSObject.Properties["WingetIncludeUnknown"]) {
        return [bool]$Settings.WingetIncludeUnknown
    }

    return $true
}

function Set-WmtWingetIncludeUnknown {
    param([bool]$IncludeUnknown)

    $settings = Get-WmtSettings
    if ($settings -is [System.Collections.IDictionary]) {
        $settings["WingetIncludeUnknown"] = $IncludeUnknown
    }
    elseif ($settings.PSObject.Properties["WingetIncludeUnknown"]) {
        $settings.WingetIncludeUnknown = $IncludeUnknown
    }
    else {
        $settings | Add-Member -MemberType NoteProperty -Name "WingetIncludeUnknown" -Value $IncludeUnknown -Force
    }
    Save-WmtSettings -Settings $settings
}

function Get-WmtUpdateAutoScanMinutes {
    param($Settings)

    if (-not $Settings) { $Settings = Get-WmtSettings }

    $value = 0
    try {
        if ($Settings -is [System.Collections.IDictionary] -and $Settings.Contains("UpdateAutoScanMinutes")) {
            $value = [int]$Settings["UpdateAutoScanMinutes"]
        }
        elseif ($Settings.PSObject.Properties["UpdateAutoScanMinutes"]) {
            $value = [int]$Settings.UpdateAutoScanMinutes
        }
    }
    catch {
        $value = 0
    }

    if ($value -lt 0) { return 0 }
    if ($value -gt 1440) { return 1440 }
    return $value
}

function Set-WmtUpdateAutoScanMinutes {
    param([int]$Minutes)

    if ($Minutes -lt 0) { $Minutes = 0 }
    if ($Minutes -gt 1440) { $Minutes = 1440 }

    $settings = Get-WmtSettings
    if ($settings -is [System.Collections.IDictionary]) {
        $settings["UpdateAutoScanMinutes"] = $Minutes
    }
    elseif ($settings.PSObject.Properties["UpdateAutoScanMinutes"]) {
        $settings.UpdateAutoScanMinutes = $Minutes
    }
    else {
        $settings | Add-Member -MemberType NoteProperty -Name "UpdateAutoScanMinutes" -Value $Minutes -Force
    }
    Save-WmtSettings -Settings $settings
}

function Get-WmtUpdateNotificationsEnabled {
    param($Settings)

    if (-not $Settings) { $Settings = Get-WmtSettings }

    try {
        if ($Settings -is [System.Collections.IDictionary] -and $Settings.Contains("UpdateNotificationsEnabled")) {
            return [bool]$Settings["UpdateNotificationsEnabled"]
        }
        if ($Settings.PSObject.Properties["UpdateNotificationsEnabled"]) {
            return [bool]$Settings.UpdateNotificationsEnabled
        }
    }
    catch {}

    return $true
}

function Set-WmtUpdateNotificationsEnabled {
    param([bool]$Enabled)

    $settings = Get-WmtSettings
    if ($settings -is [System.Collections.IDictionary]) {
        $settings["UpdateNotificationsEnabled"] = $Enabled
    }
    elseif ($settings.PSObject.Properties["UpdateNotificationsEnabled"]) {
        $settings.UpdateNotificationsEnabled = $Enabled
    }
    else {
        $settings | Add-Member -MemberType NoteProperty -Name "UpdateNotificationsEnabled" -Value $Enabled -Force
    }
    Save-WmtSettings -Settings $settings
}

function Get-WmtUpdateSilentInstallEnabled {
    param($Settings)

    if (-not $Settings) { $Settings = Get-WmtSettings }

    try {
        if ($Settings -is [System.Collections.IDictionary] -and $Settings.Contains("UpdateSilentInstallEnabled")) {
            return [bool]$Settings["UpdateSilentInstallEnabled"]
        }
        if ($Settings.PSObject.Properties["UpdateSilentInstallEnabled"]) {
            return [bool]$Settings.UpdateSilentInstallEnabled
        }
    }
    catch {}

    return $false
}

function Set-WmtUpdateSilentInstallEnabled {
    param([bool]$Enabled)

    $settings = Get-WmtSettings
    if ($settings -is [System.Collections.IDictionary]) {
        $settings["UpdateSilentInstallEnabled"] = $Enabled
    }
    elseif ($settings.PSObject.Properties["UpdateSilentInstallEnabled"]) {
        $settings.UpdateSilentInstallEnabled = $Enabled
    }
    else {
        $settings | Add-Member -MemberType NoteProperty -Name "UpdateSilentInstallEnabled" -Value $Enabled -Force
    }
    Save-WmtSettings -Settings $settings
}

function Get-WmtUpdateAutoInstallEnabled {
    param($Settings)

    if (-not $Settings) { $Settings = Get-WmtSettings }

    try {
        if ($Settings -is [System.Collections.IDictionary] -and $Settings.Contains("UpdateAutoInstallEnabled")) {
            return [bool]$Settings["UpdateAutoInstallEnabled"]
        }
        if ($Settings.PSObject.Properties["UpdateAutoInstallEnabled"]) {
            return [bool]$Settings.UpdateAutoInstallEnabled
        }
    }
    catch {}

    return $false
}

function Set-WmtUpdateAutoInstallEnabled {
    param([bool]$Enabled)

    $settings = Get-WmtSettings
    if ($settings -is [System.Collections.IDictionary]) {
        $settings["UpdateAutoInstallEnabled"] = $Enabled
    }
    elseif ($settings.PSObject.Properties["UpdateAutoInstallEnabled"]) {
        $settings.UpdateAutoInstallEnabled = $Enabled
    }
    else {
        $settings | Add-Member -MemberType NoteProperty -Name "UpdateAutoInstallEnabled" -Value $Enabled -Force
    }
    Save-WmtSettings -Settings $settings
}

function Get-WmtRunInTrayOnClose {
    param($Settings)

    if (-not $Settings) { $Settings = Get-WmtSettings }

    try {
        if ($Settings -is [System.Collections.IDictionary] -and $Settings.Contains("RunInTrayOnClose")) {
            return [bool]$Settings["RunInTrayOnClose"]
        }
        if ($Settings.PSObject.Properties["RunInTrayOnClose"]) {
            return [bool]$Settings.RunInTrayOnClose
        }
    }
    catch {}

    return $false
}

function Set-WmtRunInTrayOnClose {
    param([bool]$Enabled)

    $settings = Get-WmtSettings
    if ($settings -is [System.Collections.IDictionary]) {
        $settings["RunInTrayOnClose"] = $Enabled
    }
    elseif ($settings.PSObject.Properties["RunInTrayOnClose"]) {
        $settings.RunInTrayOnClose = $Enabled
    }
    else {
        $settings | Add-Member -MemberType NoteProperty -Name "RunInTrayOnClose" -Value $Enabled -Force
    }
    Save-WmtSettings -Settings $settings
}

function Get-WmtReduceRamInTray {
    param($Settings)

    if (-not $Settings) { $Settings = Get-WmtSettings }

    try {
        if ($Settings -is [System.Collections.IDictionary] -and $Settings.Contains("ReduceRamInTray")) {
            return [bool]$Settings["ReduceRamInTray"]
        }
        if ($Settings.PSObject.Properties["ReduceRamInTray"]) {
            return [bool]$Settings.ReduceRamInTray
        }
    }
    catch {}

    return $true
}

function Set-WmtReduceRamInTray {
    param([bool]$Enabled)

    $settings = Get-WmtSettings
    if ($settings -is [System.Collections.IDictionary]) {
        $settings["ReduceRamInTray"] = $Enabled
    }
    elseif ($settings.PSObject.Properties["ReduceRamInTray"]) {
        $settings.ReduceRamInTray = $Enabled
    }
    else {
        $settings | Add-Member -MemberType NoteProperty -Name "ReduceRamInTray" -Value $Enabled -Force
    }
    Save-WmtSettings -Settings $settings
}

# Functional block generated from WMT-GUI.ps1.
# Dot-source this file; it intentionally shares WMT's script scope.

function Show-ContextMenuBuilder {
    $content = @"
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="This replaces the 'Set as desktop background' command with your custom top-level Windows 11 context menu action." Foreground="{DynamicResource Warning}" TextWrapping="Wrap" Margin="0,0,0,12"/>
        <StackPanel Grid.Row="1" Margin="0,0,0,10">
            <TextBlock Text="Menu Name" Foreground="{DynamicResource TextSecondary}" Margin="0,0,0,4"/>
            <TextBox Name="txtName" Height="34" VerticalContentAlignment="Center"/>
        </StackPanel>
        <Grid Grid.Row="2" Margin="0,0,0,10">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel>
                <TextBlock Text="Command" Foreground="{DynamicResource TextSecondary}" Margin="0,0,0,4"/>
                <TextBox Name="txtCmd" Height="34" VerticalContentAlignment="Center"/>
            </StackPanel>
            <Button Name="btnBrowseCmd" Grid.Column="1" Content="Browse" Width="88" Margin="8,22,0,0"/>
        </Grid>
        <Grid Grid.Row="3" Margin="0,0,0,10">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel>
                <TextBlock Text="Icon Path" Foreground="{DynamicResource TextSecondary}" Margin="0,0,0,4"/>
                <TextBox Name="txtIcon" Height="34" VerticalContentAlignment="Center"/>
            </StackPanel>
            <Button Name="btnBrowseIcon" Grid.Column="1" Content="Browse" Width="88" Margin="8,22,0,0"/>
        </Grid>
        <TextBlock Grid.Row="4" Text="Hint: use &quot;%1&quot; for the selected file." Foreground="{DynamicResource TextMuted}" Margin="0,0,0,16"/>
        <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Name="btnRemove" Content="Remove from Menu" MinWidth="142" Background="{DynamicResource Danger}" Foreground="{DynamicResource DangerText}" Margin="0,0,8,0"/>
            <Button Name="btnClose" Content="Cancel" Width="92" IsCancel="True" Margin="0,0,8,0"/>
            <Button Name="btnApply" Content="Apply to Menu" MinWidth="124" IsDefault="True" Background="{DynamicResource Success}" Foreground="{DynamicResource SuccessText}"/>
        </StackPanel>
    </Grid>
"@
    $dialog = New-WmtWindowFromXaml -Title "Custom Context Menu Builder" -ContentXaml $content -Width 640 -Height 430 -MinWidth 560 -MinHeight 390 -NoResize
    $txtName = $dialog.FindName("txtName")
    $txtCmd = $dialog.FindName("txtCmd")
    $txtIcon = $dialog.FindName("txtIcon")
    $btnBrowseCmd = $dialog.FindName("btnBrowseCmd")
    $btnBrowseIcon = $dialog.FindName("btnBrowseIcon")
    $btnApply = $dialog.FindName("btnApply")
    $btnRemove = $dialog.FindName("btnRemove")
    $btnClose = $dialog.FindName("btnClose")

    $txtName.Text = "Take Ownership"
    $txtCmd.Text = 'powershell -windowstyle hidden -command "Start-Process cmd -ArgumentList ''/c takeown /f \"%1\" /r /d y && icacls \"%1\" /grant administrators:F /t'' -Verb runAs"'
    $txtIcon.Text = "imageres.dll,-78"

    $btnBrowseCmd.Add_Click({
            $dlg = [Microsoft.Win32.OpenFileDialog]::new()
            $dlg.Filter = "Programs|*.exe;*.bat;*.cmd|All Files|*.*"
            if ($dlg.ShowDialog() -eq $true) { $txtCmd.Text = "`"$($dlg.FileName)`" `"%1`"" }
        }.GetNewClosure())
    $btnBrowseIcon.Add_Click({
            $dlg = [Microsoft.Win32.OpenFileDialog]::new()
            $dlg.Filter = "Icons|*.ico;*.exe;*.dll|All Files|*.*"
            if ($dlg.ShowDialog() -eq $true) { $txtIcon.Text = $dlg.FileName }
        }.GetNewClosure())

    $btnApply.Add_Click({
            if ([string]::IsNullOrWhiteSpace($txtName.Text) -or [string]::IsNullOrWhiteSpace($txtCmd.Text)) {
                Show-WmtMessageBox -Owner $dialog -Message "Name and Command are required." -Title "Custom Context Menu" -Image Warning | Out-Null
                return
            }
            $targets = @("HKCU:\Software\Classes\*\shell\SetDesktopWallpaper", "HKCU:\Software\Classes\Directory\shell\SetDesktopWallpaper")
            try {
                foreach ($key in $targets) {
                    if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
                    Set-ItemProperty -LiteralPath $key -Name "MUIVerb" -Value $txtName.Text
                    Set-ItemProperty -LiteralPath $key -Name "MultiSelectModel" -Value "Player"
                    if (-not [string]::IsNullOrWhiteSpace($txtIcon.Text)) { Set-ItemProperty -LiteralPath $key -Name "Icon" -Value $txtIcon.Text }
                    $cmdKey = Join-Path $key "command"
                    if (-not (Test-Path -LiteralPath $cmdKey)) { New-Item -Path $cmdKey -Force | Out-Null }
                    Set-Item -LiteralPath $cmdKey -Value $txtCmd.Text
                }
                Show-WmtMessageBox -Owner $dialog -Message "Context Menu updated successfully!" -Title "Success" -Image Information | Out-Null
                $dialog.Close()
            }
            catch { Show-WmtMessageBox -Owner $dialog -Message $_.Exception.Message -Title "Context Menu Error" -Image Error | Out-Null }
        }.GetNewClosure())

    $btnRemove.Add_Click({
            if ((Show-WmtMessageBox -Owner $dialog -Message "Remove the custom menu item?" -Title "Confirm" -Button YesNo -Image Warning) -ne [System.Windows.MessageBoxResult]::Yes) { return }
            $targets = @("HKCU:\Software\Classes\*\shell\SetDesktopWallpaper", "HKCU:\Software\Classes\Directory\shell\SetDesktopWallpaper")
            foreach ($key in $targets) { if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue } }
            Show-WmtMessageBox -Owner $dialog -Message "Item removed." -Title "Success" -Image Information | Out-Null
            $dialog.Close()
        }.GetNewClosure())
    $btnClose.Add_Click({ $dialog.Close() }.GetNewClosure())
    $dialog.ShowDialog() | Out-Null
}

function Update-TweakButtonStates {
    try {
        $regCache = @{}
        $getRegValue = {
            param(
                [string]$Path,
                [string]$Name,
                $Default = $null
            )

            if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Name)) { return $Default }
            if (-not $regCache.ContainsKey($Path)) {
                try { $regCache[$Path] = Get-ItemProperty -Path $Path -ErrorAction Stop }
                catch { $regCache[$Path] = $null }
            }

            $item = $regCache[$Path]
            if ($item -and $item.PSObject.Properties[$Name]) { return $item.$Name }
            return $Default
        }.GetNewClosure()

        $setButtonEnabled = {
            param(
                [string]$Name,
                [bool]$Enabled
            )

            $button = Get-Ctrl $Name
            if ($button) { $button.IsEnabled = [bool]$Enabled }
        }

        $h = & $getRegValue "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode"
        & $setButtonEnabled "btnPerfEnableHags" ($h -ne 2); & $setButtonEnabled "btnPerfDisableHags" ($h -eq 2)

        $sm = Get-Service "SysMain" -EA Ignore
        if ($sm) {
            $d = ($sm.StartType -eq 'Disabled')
            & $setButtonEnabled "btnPerfDisableSuperfetch" (-not $d); & $setButtonEnabled "btnPerfEnableSuperfetch" $d
        }

        $hibernate = & $getRegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "HibernateEnabled"
        if ($null -ne $hibernate) {
            $hibernateEnabled = ([int]$hibernate -ne 0)
            & $setButtonEnabled "btnPerfDisableHibernate" $hibernateEnabled; & $setButtonEnabled "btnPerfEnableHibernate" (-not $hibernateEnabled)
        }

        if (Get-Command Get-MMAgent -ErrorAction Ignore) {
            $mma = Get-MMAgent -ErrorAction Ignore
            if ($mma -and $null -ne $mma.MemoryCompression) {
                $memoryCompressionEnabled = [bool]$mma.MemoryCompression
                & $setButtonEnabled "btnPerfDisableMemCompress" $memoryCompressionEnabled; & $setButtonEnabled "btnPerfEnableMemCompress" (-not $memoryCompressionEnabled)
            }
        }

        $ap = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        $ta = & $getRegValue $ap "TaskbarAl"; & $setButtonEnabled "btnTaskbarLeft" ($ta -ne 0); & $setButtonEnabled "btnTaskbarCenter" ($ta -eq 0 -or $null -eq $ta)
        $tc = & $getRegValue $ap "TaskbarGlomLevel"; & $setButtonEnabled "btnNeverCombine" ($tc -ne 2); & $setButtonEnabled "btnAlwaysCombine" ($tc -eq 2 -or $null -eq $tc)
        $is24 = ([string](& $getRegValue "HKCU:\Control Panel\International" "sShortTime") -cmatch "H")
        & $setButtonEnabled "btnClock24" (-not $is24); & $setButtonEnabled "btnClock12" $is24
        $cs = & $getRegValue $ap "ShowSecondsInSystemClock"; & $setButtonEnabled "btnClockSecsOn" ($cs -ne 1); & $setButtonEnabled "btnClockSecsOff" ($cs -eq 1 -or $null -eq $cs)
        $smode = & $getRegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "SearchboxTaskbarMode"
        & $setButtonEnabled "btnHideSearch" ($smode -ne 0); & $setButtonEnabled "btnSearchIcon" ($smode -ne 1)
        & $setButtonEnabled "btnHideWidgets" ((& $getRegValue $ap "TaskbarDa") -ne 0)
        & $setButtonEnabled "btnHideTaskView" ((& $getRegValue $ap "ShowTaskViewButton") -ne 0)
        & $setButtonEnabled "btnHideChat" ((& $getRegValue $ap "TaskbarMn") -ne 0)

        $cabinetPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState"
        $explorerPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"
        $hideExt = [int](& $getRegValue $ap "HideFileExt" 1)
        & $setButtonEnabled "btnExpShowExt" ($hideExt -ne 0); & $setButtonEnabled "btnExpHideExt" ($hideExt -eq 0)
        $hidden = [int](& $getRegValue $ap "Hidden" 2)
        & $setButtonEnabled "btnExpShowHidden" ($hidden -ne 1); & $setButtonEnabled "btnExpHideHidden" ($hidden -eq 1)
        $fullPath = [int](& $getRegValue $cabinetPath "FullPath" 0)
        & $setButtonEnabled "btnExpFullPathOn" ($fullPath -ne 1); & $setButtonEnabled "btnExpFullPathOff" ($fullPath -eq 1)
        $launchTo = [int](& $getRegValue $ap "LaunchTo" 2)
        & $setButtonEnabled "btnExpLaunchThisPc" ($launchTo -ne 1); & $setButtonEnabled "btnExpLaunchQuickAccess" ($launchTo -eq 1)
        $recentsHidden = ([int](& $getRegValue $explorerPath "ShowRecent" 1) -eq 0 -and [int](& $getRegValue $explorerPath "ShowFrequent" 1) -eq 0)
        & $setButtonEnabled "btnExpHideRecents" (-not $recentsHidden); & $setButtonEnabled "btnExpShowRecents" $recentsHidden

        $mousePath = "HKCU:\Control Panel\Mouse"
        $mouseSpeed = [int](& $getRegValue $mousePath "MouseSensitivity" 10)
        & $setButtonEnabled "btnMouseSpeedSlow" ($mouseSpeed -ne 6); & $setButtonEnabled "btnMouseSpeedDefault" ($mouseSpeed -ne 10); & $setButtonEnabled "btnMouseSpeedFast" ($mouseSpeed -ne 15)
        $mouseAccelOn = ([string](& $getRegValue $mousePath "MouseSpeed" "1") -ne "0")
        & $setButtonEnabled "btnMouseAccelOn" (-not $mouseAccelOn); & $setButtonEnabled "btnMouseAccelOff" $mouseAccelOn
        $shellState = & $getRegValue $explorerPath "ShellState"
        $singleClick = ($shellState -and $shellState.Length -gt 4 -and [int]$shellState[4] -eq 0x1E)
        & $setButtonEnabled "btnMouseSingleClick" (-not $singleClick); & $setButtonEnabled "btnMouseDoubleClick" $singleClick

        $classicContext = Test-Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
        & $setButtonEnabled "btnCtxClassic" (-not $classicContext); & $setButtonEnabled "btnCtxModern" $classicContext
        $takeOwnInstalled = Test-Path "Registry::HKEY_CLASSES_ROOT\Directory\shell\WMT_TakeOwnership"
        & $setButtonEnabled "btnCtxTakeOwnAdd" (-not $takeOwnInstalled); & $setButtonEnabled "btnCtxTakeOwnRemove" $takeOwnInstalled
        $psHereInstalled = Test-Path "Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\WMT_OpenPowerShell"
        & $setButtonEnabled "btnCtxPsHereAdd" (-not $psHereInstalled); & $setButtonEnabled "btnCtxPsHereRemove" $psHereInstalled

        $adEnabled = [int](& $getRegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 1)
        & $setButtonEnabled "btnPrivacyAdsOff" ($adEnabled -ne 0); & $setButtonEnabled "btnPrivacyAdsOn" ($adEnabled -eq 0)
        $contentDeliveryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        $suggestionNames = @("ContentDeliveryAllowed", "FeatureManagementEnabled", "OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "PreInstalledAppsEverEnabled", "SilentInstalledAppsEnabled", "SoftLandingEnabled", "SubscribedContent-310093Enabled", "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled", "SubscribedContent-338393Enabled", "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled", "SystemPaneSuggestionsEnabled")
        $suggestionsOff = $true
        foreach ($name in $suggestionNames) {
            if ([int](& $getRegValue $contentDeliveryPath $name 1) -ne 0) { $suggestionsOff = $false; break }
        }
        & $setButtonEnabled "btnPrivacySuggestedOff" (-not $suggestionsOff); & $setButtonEnabled "btnPrivacySuggestedOn" $suggestionsOff
        $tailoredOff = ([int](& $getRegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" 1) -eq 0 -or [int](& $getRegValue "HKCU:\Software\Policies\Microsoft\Windows\CloudContent" "DisableTailoredExperiencesWithDiagnosticData" 0) -eq 1)
        & $setButtonEnabled "btnPrivacyTailoredOff" (-not $tailoredOff); & $setButtonEnabled "btnPrivacyTailoredOn" $tailoredOff
        $activityPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        $activityOff = ([int](& $getRegValue $activityPolicy "EnableActivityFeed" 1) -eq 0 -and [int](& $getRegValue $activityPolicy "PublishUserActivities" 1) -eq 0 -and [int](& $getRegValue $activityPolicy "UploadUserActivities" 1) -eq 0)
        & $setButtonEnabled "btnPrivacyActivityOff" (-not $activityOff); & $setButtonEnabled "btnPrivacyActivityOn" $activityOff
        $launchTrackingOff = ([int](& $getRegValue $ap "Start_TrackProgs" 1) -eq 0)
        & $setButtonEnabled "btnPrivacyAppLaunchOff" (-not $launchTrackingOff); & $setButtonEnabled "btnPrivacyAppLaunchOn" $launchTrackingOff

        $webSearchOff = ([int](& $getRegValue "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 0) -eq 1 -or [int](& $getRegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 1) -eq 0)
        & $setButtonEnabled "btnSearchWebOff" (-not $webSearchOff); & $setButtonEnabled "btnSearchWebOn" $webSearchOff
        $searchSvc = Get-Service "WSearch" -ErrorAction Ignore
        if ($searchSvc) {
            $indexReduced = ($searchSvc.StartType -ne "Automatic")
            & $setButtonEnabled "btnSearchIndexReduced" (-not $indexReduced); & $setButtonEnabled "btnSearchIndexDefault" $indexReduced
        }

        $gameBarPath = "HKCU:\Software\Microsoft\GameBar"
        $gameDvrPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR"
        $gameCfgPath = "HKCU:\System\GameConfigStore"
        $gameModeOn = ([int](& $getRegValue $gameBarPath "AutoGameModeEnabled" 0) -eq 1 -or [int](& $getRegValue $gameBarPath "AllowAutoGameMode" 0) -eq 1)
        & $setButtonEnabled "btnGameModeOn" (-not $gameModeOn); & $setButtonEnabled "btnGameModeOff" $gameModeOn
        $gameBarOn = ([int](& $getRegValue $gameDvrPath "AppCaptureEnabled" 1) -ne 0 -and [int](& $getRegValue $gameCfgPath "GameDVR_Enabled" 1) -ne 0)
        & $setButtonEnabled "btnGameBarOff" $gameBarOn; & $setButtonEnabled "btnGameBarOn" (-not $gameBarOn)
        $captureOn = ([int](& $getRegValue $gameDvrPath "HistoricalCaptureEnabled" 1) -ne 0)
        & $setButtonEnabled "btnGameCaptureOff" $captureOn; & $setButtonEnabled "btnGameCaptureOn" (-not $captureOn)
        $fsoOff = ([int](& $getRegValue $gameCfgPath "GameDVR_FSEBehaviorMode" 0) -eq 2 -and [int](& $getRegValue $gameCfgPath "GameDVR_HonorUserFSEBehaviorMode" 0) -eq 1)
        & $setButtonEnabled "btnGameFsoOff" (-not $fsoOff); & $setButtonEnabled "btnGameFsoDefault" $fsoOff

        $visualPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        $visualMode = [int](& $getRegValue $visualPath "VisualFXSetting" 0)
        $snappyOn = ($visualMode -eq 3 -and [string](& $getRegValue "HKCU:\Control Panel\Desktop" "MinAnimate" "1") -eq "0" -and [int](& $getRegValue $ap "TaskbarAnimations" 1) -eq 0 -and [int](& $getRegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 1) -eq 0)
        & $setButtonEnabled "btnVisualBestAppearance" ($visualMode -ne 1); & $setButtonEnabled "btnVisualBestPerformance" ($visualMode -ne 2); & $setButtonEnabled "btnVisualSnappy" (-not $snappyOn)

        $tipsOff = ([int](& $getRegValue $contentDeliveryPath "SoftLandingEnabled" 1) -eq 0 -and [int](& $getRegValue $contentDeliveryPath "SubscribedContent-338389Enabled" 1) -eq 0)
        & $setButtonEnabled "btnNotifyTipsOff" (-not $tipsOff); & $setButtonEnabled "btnNotifyTipsOn" $tipsOff
        $setupOff = ([int](& $getRegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 1) -eq 0)
        & $setButtonEnabled "btnNotifySetupOff" (-not $setupOff); & $setButtonEnabled "btnNotifySetupOn" $setupOff
        $lockFactsOff = ([int](& $getRegValue $contentDeliveryPath "RotatingLockScreenOverlayEnabled" 1) -eq 0 -and [int](& $getRegValue $contentDeliveryPath "SubscribedContent-338387Enabled" 1) -eq 0)
        $spotlightOff = ([int](& $getRegValue $contentDeliveryPath "RotatingLockScreenEnabled" 1) -eq 0 -or [int](& $getRegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsSpotlightFeatures" 0) -eq 1)
        & $setButtonEnabled "btnLockFactsOff" (-not $lockFactsOff); & $setButtonEnabled "btnLockFactsOn" $lockFactsOff
        & $setButtonEnabled "btnLockSpotlightOff" (-not $spotlightOff); & $setButtonEnabled "btnLockSpotlightOn" $spotlightOff
        & $setButtonEnabled "btnLockPlain" (-not ($lockFactsOff -and $spotlightOff)); & $setButtonEnabled "btnLockDefault" ($lockFactsOff -or $spotlightOff)

        $fastStartupOn = ([int](& $getRegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 1) -ne 0)
        & $setButtonEnabled "btnStartupFastOff" $fastStartupOn; & $setButtonEnabled "btnStartupFastOn" (-not $fastStartupOn)
        $restoreFoldersOn = ([int](& $getRegValue $ap "PersistBrowsers" 0) -ne 0)
        & $setButtonEnabled "btnStartupRestoreFoldersOn" (-not $restoreFoldersOn); & $setButtonEnabled "btnStartupRestoreFoldersOff" $restoreFoldersOn

        $batteryThreshold = Get-WmtPowerSettingIndex "SUB_ENERGYSAVER" "ESBATTTHRESHOLD" "DC"
        if ($null -ne $batteryThreshold) {
            & $setButtonEnabled "btnPowerBatterySaverOff" ($batteryThreshold -ne 0); & $setButtonEnabled "btnPowerBatterySaver20" ($batteryThreshold -ne 20); & $setButtonEnabled "btnPowerBatterySaver50" ($batteryThreshold -ne 50)
        }
        $usbSub = "2a737441-1930-4402-8d77-b2bebba308a3"; $usbSetting = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"
        $usbAc = Get-WmtPowerSettingIndex $usbSub $usbSetting "AC"; $usbDc = Get-WmtPowerSettingIndex $usbSub $usbSetting "DC"
        if ($null -ne $usbAc -and $null -ne $usbDc) {
            $usbOn = ($usbAc -eq 1 -and $usbDc -eq 1)
            & $setButtonEnabled "btnPowerUsbSuspendOn" (-not $usbOn); & $setButtonEnabled "btnPowerUsbSuspendOff" ($usbAc -ne 0 -or $usbDc -ne 0)
        }
        $pcieSub = "501a4d13-42af-4429-9fd1-a8218c268e20"; $pcieSetting = "ee12f906-d277-404b-b6da-e5fa1a576df5"
        $pcieAc = Get-WmtPowerSettingIndex $pcieSub $pcieSetting "AC"; $pcieDc = Get-WmtPowerSettingIndex $pcieSub $pcieSetting "DC"
        if ($null -ne $pcieAc -and $null -ne $pcieDc) {
            $pcieModerate = ($pcieAc -eq 1 -and $pcieDc -eq 1)
            & $setButtonEnabled "btnPowerPcieModerate" (-not $pcieModerate); & $setButtonEnabled "btnPowerPcieOff" ($pcieAc -ne 0 -or $pcieDc -ne 0)
        }

        $longPathsOn = ([int](& $getRegValue "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" "LongPathsEnabled" 0) -eq 1)
        & $setButtonEnabled "btnDevLongPathsOn" (-not $longPathsOn); & $setButtonEnabled "btnDevLongPathsOff" $longPathsOn
        $devModeOn = ([int](& $getRegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" "AllowDevelopmentWithoutDevLicense" 0) -eq 1)
        & $setButtonEnabled "btnDevModeOn" (-not $devModeOn); & $setButtonEnabled "btnDevModeOff" $devModeOn
    }
    catch {}
}

function Set-Hags {
    param([bool]$Enable)
    
    if ($Enable) {
        Invoke-UiCommand {
            $path = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
            if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
                
            Set-ItemProperty -Path $path -Name "HwSchMode" -Value 2 -Type DWord
            Write-Output "Hardware-Accelerated GPU Scheduling (HAGS) enabled. Reboot required."
                
            [System.Windows.MessageBox]::Show("HAGS enabled successfully. Please restart your computer to apply the changes.", "HAGS Status", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        } "Enabling HAGS..."
    }
    else {
        Invoke-UiCommand {
            $path = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
            if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
                
            Set-ItemProperty -Path $path -Name "HwSchMode" -Value 1 -Type DWord
            Write-Output "Hardware-Accelerated GPU Scheduling (HAGS) disabled. Reboot required."
                
            [System.Windows.MessageBox]::Show("HAGS disabled successfully. Please restart your computer to apply the changes.", "HAGS Status", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        } "Disabling HAGS..."
    }
}

function Get-WmtRegValue {
    param(
        [string]$Path,
        [string]$Name,
        $Default = $null
    )

    try {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $item.$Name
    }
    catch {
        return $Default
    }
}

function Set-WmtRegDword {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value
    )

    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force
}

function Set-WmtRegString {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Value
    )

    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type String -Force
}

function Remove-WmtRegValue {
    param(
        [string]$Path,
        [string]$Name
    )

    if (Test-Path $Path) {
        Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    }
}

function Restart-WmtExplorer {
    try { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue } catch {}
}

function Invoke-WmtUserSettingRefresh {
    try {
        Start-Process -FilePath "$env:SystemRoot\System32\RUNDLL32.EXE" -ArgumentList "USER32.DLL,UpdatePerUserSystemParameters" -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
    }
    catch {}
}

function Test-WmtExplorerSingleClick {
    $shellState = Get-WmtRegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" "ShellState"
    return ($shellState -and $shellState.Length -gt 4 -and [int]$shellState[4] -eq 0x1E)
}

function Set-WmtExplorerClickMode {
    param([bool]$SingleClick)

    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }

    $shellState = Get-WmtRegValue $path "ShellState"
    if (-not $shellState -or $shellState.Length -lt 5) {
        $shellState = [byte[]](0x24, 0x00, 0x00, 0x00, 0x3E, 0x28, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
    }

    $shellState[4] = if ($SingleClick) { [byte]0x1E } else { [byte]0x3E }
    Set-ItemProperty -Path $path -Name "ShellState" -Value $shellState -Type Binary -Force
    Set-WmtRegDword $path "IconUnderline" $(if ($SingleClick) { 2 } else { 3 })
    Restart-WmtExplorer
}

function Set-WmtMouseSpeed {
    param([int]$Speed)

    $speed = [math]::Max(1, [math]::Min(20, $Speed))
    $path = "HKCU:\Control Panel\Mouse"
    Set-WmtRegString $path "MouseSensitivity" ([string]$speed)
    Invoke-WmtUserSettingRefresh
}

function Set-WmtMouseAcceleration {
    param([bool]$Enable)

    $path = "HKCU:\Control Panel\Mouse"
    if ($Enable) {
        Set-WmtRegString $path "MouseSpeed" "1"
        Set-WmtRegString $path "MouseThreshold1" "6"
        Set-WmtRegString $path "MouseThreshold2" "10"
    }
    else {
        Set-WmtRegString $path "MouseSpeed" "0"
        Set-WmtRegString $path "MouseThreshold1" "0"
        Set-WmtRegString $path "MouseThreshold2" "0"
    }
    Invoke-WmtUserSettingRefresh
}

function Set-WmtContentDeliveryValues {
    param(
        [string[]]$Names,
        [int]$Value
    )

    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    foreach ($name in $Names) {
        Set-WmtRegDword $path $name $Value
    }
}

function Set-WmtClassicContextMenu {
    param([bool]$Enable)

    $clsid = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
    $inproc = Join-Path $clsid "InprocServer32"
    if ($Enable) {
        if (-not (Test-Path $inproc)) { New-Item -Path $inproc -Force | Out-Null }
        Set-Item -Path $inproc -Value "" -Force
    }
    else {
        if (Test-Path $clsid) { Remove-Item -Path $clsid -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Restart-WmtExplorer
}

function Set-WmtTakeOwnershipMenu {
    param([bool]$Enable)

    $targets = @(
        @{Path = "Registry::HKEY_CLASSES_ROOT\*\shell\WMT_TakeOwnership"; Command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -Verb RunAs -ArgumentList ''/c takeown /f ""%1"" /a && icacls ""%1"" /grant *S-1-5-32-544:F /c && pause''"' },
        @{Path = "Registry::HKEY_CLASSES_ROOT\Directory\shell\WMT_TakeOwnership"; Command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -Verb RunAs -ArgumentList ''/c takeown /f ""%1"" /r /d y /a && icacls ""%1"" /grant *S-1-5-32-544:F /t /c && pause''"' },
        @{Path = "Registry::HKEY_CLASSES_ROOT\Drive\shell\WMT_TakeOwnership"; Command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -Verb RunAs -ArgumentList ''/c takeown /f ""%1"" /r /d y /a && icacls ""%1"" /grant *S-1-5-32-544:F /t /c && pause''"' }
    )

    foreach ($target in $targets) {
        $path = $target.Path
        if ($Enable) {
            if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
            Set-Item -Path $path -Value "Take Ownership" -Force
            New-ItemProperty -Path $path -Name "HasLUAShield" -Value "" -PropertyType String -Force | Out-Null
            $cmdPath = Join-Path $path "command"
            if (-not (Test-Path $cmdPath)) { New-Item -Path $cmdPath -Force | Out-Null }
            Set-Item -Path $cmdPath -Value $target.Command -Force
        }
        else {
            if (Test-Path $path) { Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Set-WmtPowerShellHereMenu {
    param([bool]$Enable)

    $targets = @(
        @{Path = "Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\WMT_OpenPowerShell"; Location = "%V" },
        @{Path = "Registry::HKEY_CLASSES_ROOT\Directory\shell\WMT_OpenPowerShell"; Location = "%1" },
        @{Path = "Registry::HKEY_CLASSES_ROOT\Drive\shell\WMT_OpenPowerShell"; Location = "%1" }
    )

    foreach ($target in $targets) {
        $path = $target.Path
        if ($Enable) {
            if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
            Set-Item -Path $path -Value "Open PowerShell Here" -Force
            Set-ItemProperty -Path $path -Name "Icon" -Value "powershell.exe" -Type String -Force
            $cmdPath = Join-Path $path "command"
            if (-not (Test-Path $cmdPath)) { New-Item -Path $cmdPath -Force | Out-Null }
            Set-Item -Path $cmdPath -Value "powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -Command `"Set-Location -LiteralPath '$($target.Location)'`"" -Force
        }
        else {
            if (Test-Path $path) { Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Set-WmtVisualPreset {
    param([ValidateSet("Appearance", "Performance", "Snappy")] [string]$Mode)

    $visualPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    $desktopPath = "HKCU:\Control Panel\Desktop"
    $advancedPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $dwmPath = "HKCU:\Software\Microsoft\Windows\DWM"
    $personalizePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"

    switch ($Mode) {
        "Appearance" {
            Set-WmtRegDword $visualPath "VisualFXSetting" 1
            Set-WmtRegString $desktopPath "MinAnimate" "1"
            Set-WmtRegDword $advancedPath "TaskbarAnimations" 1
            Set-WmtRegDword $dwmPath "EnableAeroPeek" 1
            Set-WmtRegDword $personalizePath "EnableTransparency" 1
        }
        "Performance" {
            Set-WmtRegDword $visualPath "VisualFXSetting" 2
        }
        "Snappy" {
            Set-WmtRegDword $visualPath "VisualFXSetting" 3
            Set-WmtRegString $desktopPath "MinAnimate" "0"
            Set-WmtRegDword $advancedPath "TaskbarAnimations" 0
            Set-WmtRegDword $dwmPath "EnableAeroPeek" 0
            Set-WmtRegDword $personalizePath "EnableTransparency" 0
        }
    }

    Restart-WmtExplorer
}

function Get-WmtPowerSettingIndex {
    param(
        [string]$SubGroup,
        [string]$Setting,
        [ValidateSet("AC", "DC")] [string]$Mode = "AC"
    )

    try {
        $output = powercfg /query SCHEME_CURRENT $SubGroup $Setting 2>$null
        $label = if ($Mode -eq "DC") { "Current DC Power Setting Index" } else { "Current AC Power Setting Index" }
        $pattern = [regex]::Escape($label) + "\s*:\s*0x([0-9a-fA-F]+)"
        foreach ($line in $output) {
            if ($line -match $pattern) { return [Convert]::ToInt32($matches[1], 16) }
        }
        $output = powercfg /qh SCHEME_CURRENT $SubGroup $Setting 2>$null
        foreach ($line in $output) {
            if ($line -match $pattern) { return [Convert]::ToInt32($matches[1], 16) }
        }
    }
    catch {}
    return $null
}

function Set-WmtPowerSettingIndex {
    param(
        [string]$SubGroup,
        [string]$Setting,
        [int]$Value,
        [switch]$DCOnly
    )

    if (-not $DCOnly) { powercfg /setacvalueindex SCHEME_CURRENT $SubGroup $Setting $Value | Out-Null }
    powercfg /setdcvalueindex SCHEME_CURRENT $SubGroup $Setting $Value | Out-Null
    powercfg /S SCHEME_CURRENT | Out-Null
}

function Register-WmtTweakButton {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    $button = Get-Ctrl $Name
    if (-not $button) { return }
    $button.Add_Click({
            & $Action
            Update-TweakButtonStates
        }.GetNewClosure())
}

# Functional block generated from WMT-GUI.ps1.
# Dot-source this file; it intentionally shares WMT's script scope.

function Start-UpdateRepair {
    Invoke-UiCommand {
        Stop-Service -Name wuauserv, bits, cryptsvc, msiserver -Force -ErrorAction SilentlyContinue
        $rnd = Get-Random
        if (Test-Path "$env:windir\SoftwareDistribution") { Rename-Item "$env:windir\SoftwareDistribution" "$env:windir\SoftwareDistribution.bak_$rnd" -ErrorAction SilentlyContinue }
        if (Test-Path "$env:windir\System32\catroot2") { Rename-Item "$env:windir\System32\catroot2" "$env:windir\System32\catroot2.bak_$rnd" -ErrorAction SilentlyContinue }
        netsh winsock reset | Out-Null
        Start-Service -Name wuauserv, bits, cryptsvc, msiserver -ErrorAction SilentlyContinue
    } "Repairing Windows Update..."
}

function Start-NetRepair {
    Invoke-UiCommand {
        ipconfig /release | Out-Null
        ipconfig /renew | Out-Null
        ipconfig /flushdns | Out-Null
        netsh winsock reset | Out-Null
        netsh int ip reset | Out-Null
    } "Running Full Network Repair..."
}

function Start-XboxClean {
    Invoke-UiCommand {
        Write-Output "Stopping Xbox Auth Manager..."
        Stop-Service -Name "XblAuthManager" -Force -ErrorAction SilentlyContinue

        $allCreds = (cmdkey /list) -split "`r?`n"
        $targets = @()
        foreach ($line in $allCreds) {
            if ($line -match '^\s*Target:.*(Xbl.*)$') { $targets += $matches[1] }
        }

        if ($targets.Count -eq 0) {
            Write-Output "No Xbox Live credentials found."
        }
        else {
            foreach ($t in $targets) {
                Write-Output "Deleting credential: $t"
                cmdkey /delete:$t 2>$null
            }
            Write-Output "Deleted $($targets.Count) credential(s)."
        }

        Start-Service -Name "XblAuthManager" -ErrorAction SilentlyContinue
    } "Cleaning Xbox Credentials..."
}

function Start-GpeditInstall {
    # Check for User Confirmation
    $msg = "Install Local Group Policy Editor?`n`nThis enables the Group Policy Editor (gpedit.msc) on Windows Home editions by installing the built-in system packages.`n`nContinue?"
    $res = Show-WmtMessageBox -Message $msg -Title "Confirm Install" -Button YesNo -Image Question
    if ($res -ne [System.Windows.MessageBoxResult]::Yes) { return }

    Invoke-UiCommand {
        $packageRoot = Join-Path $env:SystemRoot "servicing\\Packages"
        
        if (-not (Test-Path $packageRoot)) {
            throw "Package directory not found: $packageRoot"
        }

        Write-Output "Searching packages in $packageRoot..."
        
        $clientTools = @(Get-WmtEnumeratedFiles -Path $packageRoot -Filter "Microsoft-Windows-GroupPolicy-ClientTools-Package~*.mum" | ForEach-Object { [System.IO.FileInfo]::new($_) })
        $clientExtensions = @(Get-WmtEnumeratedFiles -Path $packageRoot -Filter "Microsoft-Windows-GroupPolicy-ClientExtensions-Package~*.mum" | ForEach-Object { [System.IO.FileInfo]::new($_) })
        
        if (-not $clientTools -or -not $clientExtensions) {
            Write-Output "WARNING: Required GroupPolicy packages were not found."
            Write-Output "Ensure you are on a compatible Windows 10/11 version."
            return
        }

        $packages = @($clientTools + $clientExtensions) | Sort-Object Name -Unique
        
        foreach ($pkg in $packages) {
            Write-Output "Installing: $($pkg.Name)..."
            # Using DISM to add package
            $proc = Start-Process dism.exe -ArgumentList "/online", "/norestart", "/add-package:`"$($pkg.FullName)`"" -NoNewWindow -Wait -PassThru
            if ($proc.ExitCode -ne 0) {
                Write-Output " -> Failed (Exit Code: $($proc.ExitCode))"
            }
        }
        Write-Output "`nInstallation Complete. Try running 'gpedit.msc'. (A reboot may be required)."
    } "Installing Group Policy Editor..."
}

function Invoke-ChkdskAll {
    $confirm = [System.Windows.MessageBox]::Show("Run CHKDSK /f /r on all file-system drives in a live console window?`n`nThis can take a long time. System drive repairs may be scheduled for next reboot.", "Confirm CHKDSK", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($confirm -ne "Yes") { return }
    Start-ChkdskConsole
}

function Start-ChkdskConsole {
    $consoleScript = @'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$ErrorActionPreference = "Continue"

Write-Host "WMT: CHKDSK started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host ""

$drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
    Where-Object { $null -ne $_.Free } |
    Select-Object -ExpandProperty Name -Unique |
    Sort-Object

if (-not $drives -or $drives.Count -eq 0) {
    Write-Host "No file-system drives detected."
    Write-Host ""
    [void](Read-Host "Press Enter to close")
    exit
}

$systemDrive = (($env:SystemDrive -replace ":", "")).ToUpperInvariant()
$ok = 0
$fail = 0

foreach ($drive in $drives) {
    $letter = ([string]$drive).TrimEnd(":").ToUpperInvariant()
    $target = "$letter`:"

    Write-Host ""
    Write-Host "[$target] Running CHKDSK..."

    try {
        if ($letter -eq $systemDrive) {
            Write-Host "[$target] System drive detected. Auto-answering schedule prompt with 'Y' if required."
            $out = cmd.exe /c "echo Y|chkdsk $target /f /r" 2>&1
        } else {
            $out = cmd.exe /c "chkdsk $target /f /r /x" 2>&1
        }

        $exitCode = $LASTEXITCODE
        if ($out) { $out | ForEach-Object { if ($null -ne $_) { Write-Host $_ } } }

        if ($exitCode -eq 0) {
            Write-Host "[$target] Completed (exit 0)."
            $ok++
        } else {
            Write-Warning "[$target] Completed with exit code $exitCode."
            if ($letter -eq $systemDrive) {
                Write-Host "[$target] Note: System drive checks commonly require reboot scheduling."
            }
            $fail++
        }
    } catch {
        Write-Warning "[$target] Failed: $($_.Exception.Message)"
        $fail++
    }
}

Write-Host ""
Write-Host "Summary: completed_ok=$ok, completed_with_warnings=$fail"
Write-Host ""
[void](Read-Host "Press Enter to close")
'@

    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($consoleScript))
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" -WindowStyle Normal
    Write-GuiLog "[CHKDSK] Opened live CHKDSK console window."
}

function Invoke-SSDTrim {
    Invoke-UiCommand {
        $log = Join-Path (Get-DataPath) ("SSD_OPTIMIZE_{0}.log" -f (Get-Date -Format "yyyy-MM-dd_HHmmss"))
        $out = @("SSD Optimize Log - $(Get-Date)")

        $volumes = Get-Volume -ErrorAction SilentlyContinue | Where-Object {
            $null -ne $_.DriveLetter -and $_.DriveType -eq 'Fixed'
        }
        if (-not $volumes -or $volumes.Count -eq 0) {
            $out += "No fixed volumes with drive letters were found."
            $out | Out-File -FilePath $log -Encoding UTF8
            Write-Output "SSD optimization skipped. Log: $log"
            return
        }

        $optimized = 0
        $skipped = 0
        $failed = 0

        foreach ($v in $volumes) {
            $driveLetter = [string]$v.DriveLetter
            $mediaType = "Unknown"

            try {
                $part = Get-Partition -DriveLetter $v.DriveLetter -ErrorAction Stop | Select-Object -First 1
                if ($part) {
                    $disk = Get-Disk -Number $part.DiskNumber -ErrorAction Stop
                    if ($disk -and $disk.MediaType) { $mediaType = [string]$disk.MediaType }
                }
            }
            catch {}

            if ($mediaType -notin @("SSD", "SCM", "Unspecified", "Unknown")) {
                $out += "Skipping $driveLetter`: (MediaType=$mediaType)"
                $skipped++
                continue
            }

            $mediaTypeLabel = switch ($mediaType) {
                "Unknown" { "Unknown (treated as SSD)" }
                "Unspecified" { "Unspecified (treated as SSD)" }
                default { $mediaType }
            }
            $out += "Optimizing $driveLetter`: (MediaType=$mediaTypeLabel)"

            try {
                $result = Optimize-Volume -DriveLetter $v.DriveLetter -ReTrim -Verbose -ErrorAction Stop 4>&1 | Out-String
                if (-not [string]::IsNullOrWhiteSpace($result)) { $out += $result.TrimEnd() }
                $optimized++
            }
            catch {
                $out += "Optimize-Volume failed on $driveLetter`: $($_.Exception.Message)"
                try {
                    $fallback = (& defrag "$driveLetter`:" /L 2>&1 | Out-String).TrimEnd()
                    if (-not [string]::IsNullOrWhiteSpace($fallback)) { $out += $fallback }
                    $out += "Fallback completed on $driveLetter`: defrag /L"
                    $optimized++
                }
                catch {
                    $out += "Fallback failed on $driveLetter`: $($_.Exception.Message)"
                    $failed++
                }
            }
        }

        $out += "Summary: optimized=$optimized, skipped=$skipped, failed=$failed"
        $out | Out-File -FilePath $log -Encoding UTF8
        if ($failed -gt 0) {
            Write-Output "SSD optimization completed with some failures. Log: $log"
        }
        else {
            Write-Output "SSD optimization complete. Log: $log"
        }
    } "Running SSD Trim/ReTrim..."
}

function Start-SSDTrimConsole {
    $consoleScript = @'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$ErrorActionPreference = "Continue"

Write-Host "WMT: SSD Trim/ReTrim started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host ""

$volumes = Get-Volume -ErrorAction SilentlyContinue |
    Where-Object { $null -ne $_.DriveLetter -and $_.DriveType -eq "Fixed" } |
    Sort-Object DriveLetter -Unique

if (-not $volumes -or $volumes.Count -eq 0) {
    Write-Host "No fixed volumes with drive letters were found."
    Write-Host ""
    [void](Read-Host "Press Enter to close")
    exit
}

$optimized = 0
$skipped = 0
$failed = 0

foreach ($v in $volumes) {
    $driveLetter = [string]$v.DriveLetter
    $mediaType = "Unknown"

    try {
        $part = Get-Partition -DriveLetter $v.DriveLetter -ErrorAction Stop | Select-Object -First 1
        if ($part) {
            $disk = Get-Disk -Number $part.DiskNumber -ErrorAction Stop
            if ($disk -and $disk.MediaType) { $mediaType = [string]$disk.MediaType }
        }
    } catch {}

    if ($mediaType -notin @("SSD", "SCM", "Unspecified", "Unknown")) {
        Write-Host "Skipping $driveLetter`: (MediaType=$mediaType)"
        $skipped++
        continue
    }

    $mediaTypeLabel = switch ($mediaType) {
        "Unknown" { "Unknown (treated as SSD)" }
        "Unspecified" { "Unspecified (treated as SSD)" }
        default { $mediaType }
    }

    Write-Host ""
    Write-Host "Optimizing $driveLetter`: (MediaType=$mediaTypeLabel)"

    try {
        Optimize-Volume -DriveLetter $v.DriveLetter -ReTrim -Verbose -ErrorAction Stop
        $optimized++
    } catch {
        Write-Warning "Optimize-Volume failed on $driveLetter`: $($_.Exception.Message)"
        try {
            defrag "$driveLetter`:" /L
            Write-Host "Fallback completed on $driveLetter`: defrag /L"
            $optimized++
        } catch {
            Write-Warning "Fallback failed on $driveLetter`: $($_.Exception.Message)"
            $failed++
        }
    }
}

Write-Host ""
Write-Host "Summary: optimized=$optimized, skipped=$skipped, failed=$failed"
Write-Host ""
[void](Read-Host "Press Enter to close")
'@

    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($consoleScript))
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" -WindowStyle Normal
    Write-GuiLog "[Trim] Opened live SSD trim console window."
}

function Start-DiskManagementGui {
    try {
        Start-Process -FilePath "diskmgmt.msc" -WindowStyle Normal
        Write-GuiLog "[Storage] Opened Disk Management."
    }
    catch {
        Write-GuiLog "[Storage] Failed to open Disk Management: $($_.Exception.Message)"
    }
}

function Open-PowerSettings {
    try {
        Start-Process "ms-settings:powersleep"
        Write-GuiLog "[Power] Opened Windows Power settings."
    }
    catch {
        try {
            Start-Process -FilePath "control.exe" -ArgumentList "powercfg.cpl"
            Write-GuiLog "[Power] Opened Control Panel Power Options."
        }
        catch {
            Write-GuiLog "[Power] Failed to open power settings: $($_.Exception.Message)"
        }
    }
}

function Start-DriveBenchmark {
    $launcherButton = Get-Ctrl "btnMyDeviceDriveBenchmark"

    if ($script:DriveBenchmarkWindow) {
        try {
            if ($script:DriveBenchmarkWindow.IsVisible) {
                $script:DriveBenchmarkWindow.Activate() | Out-Null
                return
            }
        }
        catch {}

        $script:DriveBenchmarkWindow = $null
    }

    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
    Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue
    Add-Type -AssemblyName WindowsBase -ErrorAction SilentlyContinue

    if ($launcherButton) {
        $launcherButton.IsEnabled = $false
    }

    Write-GuiLog "[Storage Benchmark] Opening drive benchmark window."


    $BrushHeaderBg = New-WmtBrush "BgPanel"
    $BrushHeaderText = New-WmtBrush "TextPrimary"
    $BrushHeaderBorder = New-WmtBrush "BorderBrush"
    $BrushHeaderSelectBg = New-WmtBrush "BgHover"

    function Set-DbSystemColors {
        param([System.Windows.FrameworkElement]$Element)

        $Element.Resources[[System.Windows.SystemColors]::WindowBrushKey] = New-WmtBrush "BgPanel"
        $Element.Resources[[System.Windows.SystemColors]::WindowTextBrushKey] = New-WmtBrush "TextPrimary"
        $Element.Resources[[System.Windows.SystemColors]::ControlBrushKey] = New-WmtBrush "BgElevated"
        $Element.Resources[[System.Windows.SystemColors]::ControlTextBrushKey] = New-WmtBrush "TextPrimary"
        $Element.Resources[[System.Windows.SystemColors]::HighlightBrushKey] = New-WmtBrush "Accent"
        $Element.Resources[[System.Windows.SystemColors]::HighlightTextBrushKey] = New-WmtBrush "AccentText"
    }

    function Set-DbHeaderSystemColors {
        param([System.Windows.FrameworkElement]$Element)

        $Element.Resources[[System.Windows.SystemColors]::WindowBrushKey] = $BrushHeaderBg
        $Element.Resources[[System.Windows.SystemColors]::WindowTextBrushKey] = $BrushHeaderText
        $Element.Resources[[System.Windows.SystemColors]::ControlBrushKey] = $BrushHeaderBg
        $Element.Resources[[System.Windows.SystemColors]::ControlTextBrushKey] = $BrushHeaderText
        $Element.Resources[[System.Windows.SystemColors]::HighlightBrushKey] = $BrushHeaderSelectBg
        $Element.Resources[[System.Windows.SystemColors]::HighlightTextBrushKey] = $BrushHeaderText
        $Element.Resources[[System.Windows.SystemColors]::GrayTextBrushKey] = $BrushHeaderText
    }

    function New-DbTextBlock {
        param(
            [string]$Text,
            [double]$FontSize = 12,
            [object]$Foreground = "TextPrimary",
            [System.Windows.Thickness]$Margin = (New-Object System.Windows.Thickness(0))
        )

        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $Text
        $tb.FontSize = $FontSize
        if ($Foreground -is [string]) {
            Set-WmtThemedBrush -Object $tb -Property ([System.Windows.Controls.TextBlock]::ForegroundProperty) -ColorOrKey ([string]$Foreground)
        }
        else {
            $tb.Foreground = $Foreground
        }
        $tb.Margin = $Margin
        $tb.VerticalAlignment = "Center"
        $tb.TextWrapping = "Wrap"

        return $tb
    }

    function Set-DbButtonStyle {
        param([System.Windows.Controls.Button]$Button)

        Set-WmtThemedBrush -Object $Button -Property ([System.Windows.Controls.Control]::BackgroundProperty) -ColorOrKey "BgElevated"
        Set-WmtThemedBrush -Object $Button -Property ([System.Windows.Controls.Control]::ForegroundProperty) -ColorOrKey "TextPrimary"
        Set-WmtThemedBrush -Object $Button -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -ColorOrKey "BorderBrush"
        $Button.Padding = New-Object System.Windows.Thickness(8, 3, 8, 3)

        Set-DbSystemColors $Button
    }

    function Set-DbHeaderButtonStyle {
        param([System.Windows.Controls.Button]$Button)

        Set-WmtThemedBrush -Object $Button -Property ([System.Windows.Controls.Control]::BackgroundProperty) -ColorOrKey "BgPanel"
        Set-WmtThemedBrush -Object $Button -Property ([System.Windows.Controls.Control]::ForegroundProperty) -ColorOrKey "TextPrimary"
        Set-WmtThemedBrush -Object $Button -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -ColorOrKey "BorderBrush"
        $Button.Padding = New-Object System.Windows.Thickness(8, 3, 8, 3)

        Set-DbHeaderSystemColors $Button
    }

    function Set-DbHeaderComboStyle {
        param([System.Windows.Controls.ComboBox]$ComboBox)

        Set-WmtThemedBrush -Object $ComboBox -Property ([System.Windows.Controls.Control]::BackgroundProperty) -ColorOrKey "BgPanel"
        Set-WmtThemedBrush -Object $ComboBox -Property ([System.Windows.Controls.Control]::ForegroundProperty) -ColorOrKey "TextPrimary"
        Set-WmtThemedBrush -Object $ComboBox -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -ColorOrKey "BorderBrush"
        $ComboBox.IsEditable = $false

        Set-DbHeaderSystemColors $ComboBox

        $itemStyle = New-Object System.Windows.Style([System.Windows.Controls.ComboBoxItem])

        [void]$itemStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::BackgroundProperty, $BrushHeaderBg)))
        [void]$itemStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::ForegroundProperty, $BrushHeaderText)))
        [void]$itemStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::BorderBrushProperty, $BrushHeaderBorder)))
        [void]$itemStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::PaddingProperty, (New-Object System.Windows.Thickness(8, 3, 8, 3)))))

        $ComboBox.ItemContainerStyle = $itemStyle
    }

    $state = [hashtable]::Synchronized(@{
            Lines       = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
            Status      = "Ready."
            Progress    = 0
            IsRunning   = $false
            IsCompleted = $false
            Error       = ""
            Cancel      = $false
            TargetDrive = "ALL"
            TargetSize  = 1024
            ActiveFiles = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        })

    $worker = @{
        PowerShell = $null
        Runspace   = $null
        Async      = $null
        StartedAt  = $null
    }

    $driveValueMap = @{}
    $sizeValueMap = @{}
    $isWindowCleanupDone = $false

    $benchWindow = New-Object System.Windows.Window
    $benchWindow.Title = "Drive Benchmark"
    $benchWindow.Width = 720
    $benchWindow.Height = 540
    $benchWindow.MinWidth = 620
    $benchWindow.MinHeight = 420
    $benchWindow.WindowStartupLocation = "CenterOwner"
    Add-WmtThemeResources -Element $benchWindow
    Set-WmtThemedBrush -Object $benchWindow -Property ([System.Windows.Controls.Control]::BackgroundProperty) -ColorOrKey "BgDark"
    Set-WmtThemedBrush -Object $benchWindow -Property ([System.Windows.Controls.Control]::ForegroundProperty) -ColorOrKey "TextPrimary"

    if ($window) { $benchWindow.Owner = $window }
    Set-DbSystemColors $benchWindow

    $root = New-Object System.Windows.Controls.Grid
    $root.Margin = New-Object System.Windows.Thickness(18)
    Set-WmtThemedBrush -Object $root -Property ([System.Windows.Controls.Panel]::BackgroundProperty) -ColorOrKey "BgDark"
    Set-DbSystemColors $root

    foreach ($rowHeight in @("Auto", "Auto", "Auto", "*", "Auto")) {
        $row = New-Object System.Windows.Controls.RowDefinition
        if ($rowHeight -eq "*") { $row.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
        else { $row.Height = [System.Windows.GridLength]::Auto }
        [void]$root.RowDefinitions.Add($row)
    }

    $title = New-DbTextBlock -Text "Drive Benchmark" -FontSize 18 -Foreground "TextPrimary" -Margin (New-Object System.Windows.Thickness(0, 0, 0, 8))
    $title.FontWeight = [System.Windows.FontWeights]::SemiBold
    [System.Windows.Controls.Grid]::SetRow($title, 0)
    [void]$root.Children.Add($title)

    $controlsPanel = New-Object System.Windows.Controls.StackPanel
    $controlsPanel.Orientation = "Horizontal"
    $controlsPanel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)
    [System.Windows.Controls.Grid]::SetRow($controlsPanel, 1)

    $lblDrive = New-DbTextBlock -Text "Target:" -Foreground "TextPrimary" -Margin (New-Object System.Windows.Thickness(0, 0, 8, 0))
    [void]$controlsPanel.Children.Add($lblDrive)

    $cmbDrive = New-Object System.Windows.Controls.ComboBox
    $cmbDrive.Width = 180
    $cmbDrive.Height = 30
    $cmbDrive.Margin = New-Object System.Windows.Thickness(0, 0, 16, 0)
    Set-DbHeaderComboStyle $cmbDrive

    [void]$cmbDrive.Items.Add("All Fixed Drives")
    $driveValueMap["All Fixed Drives"] = "ALL"

    foreach ($driveInfo in [System.IO.DriveInfo]::GetDrives()) {
        if ($driveInfo.DriveType -eq [System.IO.DriveType]::Fixed -and $driveInfo.IsReady) {
            $driveLetter = $driveInfo.Name.Substring(0, 1)
            $driveLabel = if ([string]::IsNullOrWhiteSpace($driveInfo.VolumeLabel)) { "Local Disk" } else { $driveInfo.VolumeLabel }
            $displayText = "$driveLetter`: ($driveLabel)"
            [void]$cmbDrive.Items.Add($displayText)
            $driveValueMap[$displayText] = $driveLetter
        }
    }
    $cmbDrive.SelectedIndex = 0
    [void]$controlsPanel.Children.Add($cmbDrive)

    $lblSize = New-DbTextBlock -Text "Test Size:" -Foreground "TextPrimary" -Margin (New-Object System.Windows.Thickness(0, 0, 8, 0))
    [void]$controlsPanel.Children.Add($lblSize)

    $cmbSize = New-Object System.Windows.Controls.ComboBox
    $cmbSize.Width = 110
    $cmbSize.Height = 30
    $cmbSize.Margin = New-Object System.Windows.Thickness(0, 0, 16, 0)
    Set-DbHeaderComboStyle $cmbSize

    foreach ($sizeMb in @(16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192)) {
        $sizeText = "$sizeMb MB"
        [void]$cmbSize.Items.Add($sizeText)
        $sizeValueMap[$sizeText] = $sizeMb
    }
    $cmbSize.SelectedItem = "1024 MB"
    [void]$controlsPanel.Children.Add($cmbSize)

    $btnRun = New-Object System.Windows.Controls.Button
    $btnRun.Content = "Run Benchmark"
    $btnRun.Width = 125
    $btnRun.Height = 30
    Set-DbHeaderButtonStyle $btnRun
    [void]$controlsPanel.Children.Add($btnRun)
    [void]$root.Children.Add($controlsPanel)

    $statusText = New-DbTextBlock -Text "Ready." -Foreground "Warning" -Margin (New-Object System.Windows.Thickness(0, 0, 0, 8))
    [System.Windows.Controls.Grid]::SetRow($statusText, 2)
    [void]$root.Children.Add($statusText)

    $logBox = New-Object System.Windows.Controls.TextBox
    $logBox.IsReadOnly = $true
    $logBox.AcceptsReturn = $true
    $logBox.TextWrapping = "NoWrap"
    $logBox.VerticalScrollBarVisibility = "Auto"
    $logBox.HorizontalScrollBarVisibility = "Auto"
    $logBox.FontFamily = "Cascadia Mono, Consolas"
    $logBox.FontSize = 12
    Set-WmtThemedBrush -Object $logBox -Property ([System.Windows.Controls.Control]::BackgroundProperty) -ColorOrKey "BgPanel"
    Set-WmtThemedBrush -Object $logBox -Property ([System.Windows.Controls.Control]::ForegroundProperty) -ColorOrKey "TextPrimary"
    Set-WmtThemedBrush -Object $logBox -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -ColorOrKey "BorderBrush"
    $logBox.BorderThickness = [System.Windows.Thickness]::new(1)
    $logBox.Padding = [System.Windows.Thickness]::new(10)
    Set-DbSystemColors $logBox
    [System.Windows.Controls.Grid]::SetRow($logBox, 3)
    [void]$root.Children.Add($logBox)

    $bottom = New-Object System.Windows.Controls.Grid
    $bottom.Margin = New-Object System.Windows.Thickness(0, 12, 0, 0)

    $colProgress = New-Object System.Windows.Controls.ColumnDefinition
    $colProgress.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $colExport = New-Object System.Windows.Controls.ColumnDefinition
    $colExport.Width = [System.Windows.GridLength]::Auto
    $colClose = New-Object System.Windows.Controls.ColumnDefinition
    $colClose.Width = [System.Windows.GridLength]::Auto

    [void]$bottom.ColumnDefinitions.Add($colProgress)
    [void]$bottom.ColumnDefinitions.Add($colExport)
    [void]$bottom.ColumnDefinitions.Add($colClose)

    $progress = New-Object System.Windows.Controls.ProgressBar
    $progress.Minimum = 0
    $progress.Maximum = 100
    $progress.Height = 12
    $progress.Margin = New-Object System.Windows.Thickness(0, 8, 12, 0)
    Set-WmtThemedBrush -Object $progress -Property ([System.Windows.Controls.Control]::ForegroundProperty) -ColorOrKey "Accent"
    Set-WmtThemedBrush -Object $progress -Property ([System.Windows.Controls.Control]::BackgroundProperty) -ColorOrKey "BorderBrush"
    [System.Windows.Controls.Grid]::SetColumn($progress, 0)
    [void]$bottom.Children.Add($progress)

    $exportBtn = New-Object System.Windows.Controls.Button
    $exportBtn.Content = "Export"
    $exportBtn.Width = 80
    $exportBtn.Height = 32
    $exportBtn.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    Set-DbButtonStyle $exportBtn

    $exportBtn.Add_Click({
            $dialog = [Microsoft.Win32.SaveFileDialog]::new()
            $dialog.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
            $dialog.FileName = "WMT_DriveBenchmark_Results.txt"

            if ($dialog.ShowDialog() -eq $true) {
                try {
                    [System.IO.File]::WriteAllText($dialog.FileName, $logBox.Text, [System.Text.Encoding]::UTF8)
                    Write-GuiLog "[Storage Benchmark] Exported results to $($dialog.FileName)"
                }
                catch { Write-GuiLog "[Storage Benchmark] Export failed: $($_.Exception.Message)" }
            }
        }.GetNewClosure())

    [System.Windows.Controls.Grid]::SetColumn($exportBtn, 1)
    [void]$bottom.Children.Add($exportBtn)

    $closeBtn = New-Object System.Windows.Controls.Button
    $closeBtn.Content = "Close"
    $closeBtn.Width = 80
    $closeBtn.Height = 32
    Set-DbButtonStyle $closeBtn

    $closeBtn.Add_Click({
            try { $benchWindow.Close() }
            catch { Write-GuiLog "[Storage Benchmark] Close failed: $($_.Exception.Message)" }
        }.GetNewClosure())

    [System.Windows.Controls.Grid]::SetColumn($closeBtn, 2)
    [void]$bottom.Children.Add($closeBtn)

    [System.Windows.Controls.Grid]::SetRow($bottom, 4)
    [void]$root.Children.Add($bottom)

    $benchWindow.Content = $root
    $script:DriveBenchmarkWindow = $benchWindow

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)

    $releaseWindowState = {
        try {
            if ($isWindowCleanupDone) { return }
            $isWindowCleanupDone = $true
            $script:DriveBenchmarkWindow = $null
            if ($launcherButton) { $launcherButton.IsEnabled = $true }
            Write-GuiLog "[Storage Benchmark] Window closed."
        }
        catch {
            try { $script:DriveBenchmarkWindow = $null } catch {}
            try { if ($launcherButton) { $launcherButton.IsEnabled = $true } } catch {}
        }
    }.GetNewClosure()

    $setRunningUi = {
        param([bool]$Running)
        if ($Running) {
            $btnRun.Content = "Stop Benchmark"
            $cmbDrive.IsEnabled = $false
            $cmbSize.IsEnabled = $false
        }
        else {
            $btnRun.Content = "Run Benchmark"
            $cmbDrive.IsEnabled = $true
            $cmbSize.IsEnabled = $true
        }
        $btnRun.IsEnabled = $true

        Set-WmtThemedBrush -Object $cmbDrive -Property ([System.Windows.Controls.Control]::BackgroundProperty) -ColorOrKey "BgPanel"
        Set-WmtThemedBrush -Object $cmbDrive -Property ([System.Windows.Controls.Control]::ForegroundProperty) -ColorOrKey "TextPrimary"
        Set-WmtThemedBrush -Object $cmbDrive -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -ColorOrKey "BorderBrush"
        Set-WmtThemedBrush -Object $cmbSize -Property ([System.Windows.Controls.Control]::BackgroundProperty) -ColorOrKey "BgPanel"
        Set-WmtThemedBrush -Object $cmbSize -Property ([System.Windows.Controls.Control]::ForegroundProperty) -ColorOrKey "TextPrimary"
        Set-WmtThemedBrush -Object $cmbSize -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -ColorOrKey "BorderBrush"
        Set-WmtThemedBrush -Object $btnRun -Property ([System.Windows.Controls.Control]::BackgroundProperty) -ColorOrKey "BgPanel"
        Set-WmtThemedBrush -Object $btnRun -Property ([System.Windows.Controls.Control]::ForegroundProperty) -ColorOrKey "TextPrimary"
        Set-WmtThemedBrush -Object $btnRun -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -ColorOrKey "BorderBrush"

        $exportBtn.IsEnabled = $true
        $closeBtn.IsEnabled = $true
    }.GetNewClosure()

    $disposeWorker = {
        try { if ($worker["PowerShell"]) { $worker["PowerShell"].Dispose() } } catch {}
        try { if ($worker["Runspace"]) { $worker["Runspace"].Close(); $worker["Runspace"].Dispose() } } catch {}
        $worker["PowerShell"] = $null
        $worker["Runspace"] = $null
        $worker["Async"] = $null
        $worker["StartedAt"] = $null
    }.GetNewClosure()

    $cleanupTrackedBenchmarkFiles = {
        try {
            if (-not $state["ActiveFiles"]) { return }
            foreach ($path in @($state["ActiveFiles"])) {
                try {
                    if (-not [string]::IsNullOrWhiteSpace([string]$path) -and [System.IO.File]::Exists([string]$path)) {
                        [System.IO.File]::Delete([string]$path)
                    }
                }
                catch {}
            }
            try { $state["ActiveFiles"].Clear() } catch {}
        }
        catch {}
    }.GetNewClosure()

    $stopBenchmark = {
        try {
            if (-not $state["IsRunning"]) { return }
            $state["Cancel"] = $true
            $state["Status"] = "Stopping benchmark..."
            $btnRun.Content = "Stopping..."
            $btnRun.IsEnabled = $false

            try { [void]$state["Lines"].Add(""); [void]$state["Lines"].Add("Stopping benchmark...") } catch {}
            try { if ($worker["PowerShell"]) { $worker["PowerShell"].Stop() } } catch {}
            Write-GuiLog "[Storage Benchmark] Stop requested."
            & $refreshUi
        }
        catch { Write-GuiLog "[Storage Benchmark] Stop failed: $($_.Exception.Message)" }
    }.GetNewClosure()

    $refreshUi = {
        try {
            $statusText.Text = [string]$state["Status"]
            $progress.Value = [double]$state["Progress"]

            if ($state["Lines"]) {
                $logBox.Text = (@($state["Lines"]) -join "`r`n")
                $logBox.ScrollToEnd()
            }
        }
        catch { Write-GuiLog "[Storage Benchmark] UI refresh failed: $($_.Exception.Message)" }
    }.GetNewClosure()

    $timerTick = {
        try {
            & $refreshUi
            if (-not $worker["Async"]) { return }

            if ($state["IsRunning"] -and $worker["StartedAt"]) {
                $elapsedMinutes = ((Get-Date) - $worker["StartedAt"]).TotalMinutes
                if ($elapsedMinutes -ge 60) {
                    $state["Cancel"] = $true
                    $state["Error"] = "Benchmark timed out after 60 minutes."
                    $state["Status"] = "Benchmark timed out."
                    $state["Progress"] = 100
                    $state["IsRunning"] = $false
                    $state["IsCompleted"] = $true
                    [void]$state["Lines"].Add(""); [void]$state["Lines"].Add("ERROR: Benchmark timed out after 60 minutes.")
                    try { if ($worker["PowerShell"]) { $worker["PowerShell"].Stop() } } catch {}
                }
            }

            if ($worker["Async"].IsCompleted -or $state["IsCompleted"]) {
                $timer.Stop()

                try {
                    if ($worker["Async"] -and $worker["Async"].IsCompleted -and $worker["PowerShell"]) {
                        [void]$worker["PowerShell"].EndInvoke($worker["Async"])
                    }
                }
                catch {
                    if ($state["Cancel"]) {
                        $state["Error"] = ""
                        [void]$state["Lines"].Add("Benchmark stopped by user.")
                    }
                    elseif ([string]::IsNullOrWhiteSpace([string]$state["Error"])) {
                        $state["Error"] = $_.Exception.Message
                        [void]$state["Lines"].Add(""); [void]$state["Lines"].Add("ERROR: $($_.Exception.Message)")
                    }
                    Write-GuiLog "[Storage Benchmark] Runspace failed: $($_.Exception.Message)"
                }

                $state["IsRunning"] = $false
                $state["IsCompleted"] = $true
                $state["Progress"] = 100

                if ($state["Cancel"] -and [string]::IsNullOrWhiteSpace([string]$state["Error"])) {
                    $state["Status"] = "Benchmark stopped."
                    Set-WmtThemedBrush -Object $statusText -Property ([System.Windows.Controls.TextBlock]::ForegroundProperty) -ColorOrKey "Warning"
                }
                elseif ([string]::IsNullOrWhiteSpace([string]$state["Error"])) {
                    $state["Status"] = "Benchmark complete."
                    Set-WmtThemedBrush -Object $statusText -Property ([System.Windows.Controls.TextBlock]::ForegroundProperty) -ColorOrKey "Success"
                }
                else {
                    $state["Status"] = "Benchmark failed: $($state["Error"])"
                    Set-WmtThemedBrush -Object $statusText -Property ([System.Windows.Controls.TextBlock]::ForegroundProperty) -ColorOrKey "Danger"
                }

                & $refreshUi
                foreach ($line in @($state["Lines"])) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$line)) { Write-GuiLog "[Storage Benchmark] $line" }
                }

                & $setRunningUi $false
                & $disposeWorker
                & $cleanupTrackedBenchmarkFiles
            }
        }
        catch {
            $timer.Stop()
            $state["IsRunning"] = $false
            $state["IsCompleted"] = $true
            $state["Error"] = $_.Exception.Message
            $state["Status"] = "Benchmark UI failed."
            $state["Progress"] = 100
            try { [void]$state["Lines"].Add(""); [void]$state["Lines"].Add("TIMER ERROR: $($_.Exception.Message)") } catch {}
            $statusText.Text = "Benchmark UI failed: $($_.Exception.Message)"
            Set-WmtThemedBrush -Object $statusText -Property ([System.Windows.Controls.TextBlock]::ForegroundProperty) -ColorOrKey "Danger"

            & $refreshUi
            & $setRunningUi $false
            & $disposeWorker
            & $cleanupTrackedBenchmarkFiles
            Write-GuiLog "[Storage Benchmark] Timer failed: $($_.Exception.Message)"
        }
    }.GetNewClosure()

    $timer.Add_Tick($timerTick)

    $startBenchmark = {
        if ($state["IsRunning"]) { return }

        & $disposeWorker

        $selectedDrive = "ALL"
        if ($cmbDrive.SelectedItem) {
            $driveKey = [string]$cmbDrive.SelectedItem
            if ($driveValueMap.ContainsKey($driveKey)) { $selectedDrive = [string]$driveValueMap[$driveKey] }
        }

        $selectedSize = 1024
        if ($cmbSize.SelectedItem) {
            $sizeKey = [string]$cmbSize.SelectedItem
            if ($sizeValueMap.ContainsKey($sizeKey)) { $selectedSize = [int]$sizeValueMap[$sizeKey] }
        }

        $state["Lines"].Clear()
        $state["Status"] = "Preparing benchmark..."
        $state["Progress"] = 0
        $state["IsRunning"] = $true
        $state["IsCompleted"] = $false
        $state["Error"] = ""
        $state["Cancel"] = $false
        $state["TargetDrive"] = $selectedDrive
        $state["TargetSize"] = $selectedSize
        try { $state["ActiveFiles"].Clear() } catch {}

        $targetLabel = if ($selectedDrive -eq "ALL") { "All Fixed Drives" } else { "{0}:\" -f $selectedDrive }

        [void]$state["Lines"].Add("Storage Benchmark (Native Direct I/O)")
        [void]$state["Lines"].Add("Target: $targetLabel | Size: $selectedSize MB")
        [void]$state["Lines"].Add("Note: Uses direct volume mappings to test physical capabilities.")
        [void]$state["Lines"].Add("")

        Set-WmtThemedBrush -Object $statusText -Property ([System.Windows.Controls.TextBlock]::ForegroundProperty) -ColorOrKey "Warning"
        & $setRunningUi $true
        & $refreshUi

        try {
            $runspace = [runspacefactory]::CreateRunspace()
            $runspace.ApartmentState = "MTA"
            $runspace.ThreadOptions = "ReuseThread"
            $runspace.Open()

            $ps = [PowerShell]::Create()
            $ps.Runspace = $runspace

            [void]$ps.AddScript({
                    param($State)

                    $ErrorActionPreference = "Stop"

                    function Add-Line([string]$Text) { [void]$State["Lines"].Add($Text) }
                    function Set-BenchmarkStatus([string]$Text, [int]$Progress) {
                        $State["Status"] = $Text
                        $State["Progress"] = [math]::Max(0, [math]::Min(100, $Progress))
                    }
                    function Test-Cancelled { if ($State["Cancel"]) { throw "Benchmark cancelled." } }

                    function Get-BenchmarkDriveHardwareMap {
                        $map = @{}
                        try {
                            $partitionByDriveLetter = @{}
                            $diskByNumber = @{}
                            $cimDiskByIndex = @{}

                            foreach ($p in @(Get-Partition -ErrorAction SilentlyContinue)) {
                                if ($null -ne $p.DriveLetter -and -not [string]::IsNullOrWhiteSpace([string]$p.DriveLetter)) {
                                    $partitionByDriveLetter[[string]$p.DriveLetter] = $p
                                }
                            }
                            foreach ($d in @(Get-Disk -ErrorAction SilentlyContinue)) {
                                if ($null -ne $d.Number) { $diskByNumber[[int]$d.Number] = $d }
                            }
                            foreach ($d in @(Get-CimInstance Win32_DiskDrive -Property Index, Model, InterfaceType -ErrorAction SilentlyContinue)) {
                                if ($null -ne $d.Index) { $cimDiskByIndex[[int]$d.Index] = $d }
                            }

                            foreach ($driveLetter in @($partitionByDriveLetter.Keys)) {
                                $partition = $partitionByDriveLetter[$driveLetter]
                                $disk = $null; $cimDisk = $null

                                if ($partition -and $null -ne $partition.DiskNumber) {
                                    $diskNumber = [int]$partition.DiskNumber
                                    if ($diskByNumber.ContainsKey($diskNumber)) { $disk = $diskByNumber[$diskNumber] }
                                    if ($cimDiskByIndex.ContainsKey($diskNumber)) { $cimDisk = $cimDiskByIndex[$diskNumber] }
                                }

                                $model = $null
                                if ($cimDisk -and -not [string]::IsNullOrWhiteSpace([string]$cimDisk.Model)) { $model = ([string]$cimDisk.Model).Trim() }
                                elseif ($disk -and -not [string]::IsNullOrWhiteSpace([string]$disk.FriendlyName)) { $model = ([string]$disk.FriendlyName).Trim() }

                                $parts = @()
                                if (-not [string]::IsNullOrWhiteSpace($model)) { $parts += $model }
                                if ($partition -and $null -ne $partition.DiskNumber) { $parts += ("Disk {0}" -f $partition.DiskNumber) }
                                if ($disk -and $disk.BusType) { $parts += [string]$disk.BusType }
                                elseif ($cimDisk -and -not [string]::IsNullOrWhiteSpace([string]$cimDisk.InterfaceType)) { $parts += [string]$cimDisk.InterfaceType }

                                if ($parts.Count -gt 0) { $map[[string]$driveLetter] = ($parts -join " | ") }
                            }
                        }
                        catch {}
                        return $map
                    }

                    function Initialize-NativeDiskBenchmark {
                        if (([System.Management.Automation.PSTypeName]'Wmt.NativeDiskBenchmark').Type) { return }

                        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Wmt {
    public static class NativeDiskBenchmark {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern SafeFileHandle CreateFile(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool ReadFile(SafeFileHandle hFile, IntPtr lpBuffer, uint nNumberOfBytesToRead, out uint lpNumberOfBytesRead, IntPtr lpOverlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool WriteFile(SafeFileHandle hFile, IntPtr lpBuffer, uint nNumberOfBytesToWrite, out uint lpNumberOfBytesWritten, IntPtr lpOverlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetFilePointerEx(SafeFileHandle hFile, long liDistanceToMove, out long lpNewFilePointer, uint dwMoveMethod);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool FlushFileBuffers(SafeFileHandle hFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetEndOfFile(SafeFileHandle hFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetFileValidData(SafeFileHandle hFile, long ValidDataLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CloseHandle(IntPtr hObject);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr CreateIoCompletionPort(SafeFileHandle FileHandle, IntPtr ExistingCompletionPort, UIntPtr CompletionKey, uint NumberOfConcurrentThreads);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetQueuedCompletionStatusEx(IntPtr CompletionPort, IntPtr lpCompletionPortEntries, uint ulCount, out uint ulNumEntriesRemoved, uint dwMilliseconds, [MarshalAs(UnmanagedType.Bool)] bool fAlertable);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr VirtualAlloc(IntPtr lpAddress, UIntPtr dwSize, uint flAllocationType, uint flProtect);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool VirtualFree(IntPtr lpAddress, UIntPtr dwSize, uint dwFreeType);

        [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out long lpLuid);

        [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, [MarshalAs(UnmanagedType.Bool)] bool DisableAllPrivileges, ref TokenPrivileges NewState, uint BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

        [DllImport("kernel32.dll", ExactSpelling = true)]
        public static extern IntPtr GetCurrentProcess();

        public const uint GENERIC_READ = 0x80000000;
        public const uint GENERIC_WRITE = 0x40000000;
        public const uint FILE_SHARE_READ = 0x00000001;
        public const uint FILE_SHARE_WRITE = 0x00000002;
        public const uint CREATE_ALWAYS = 2;
        public const uint OPEN_EXISTING = 3;
        public const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;
        public const uint FILE_FLAG_NO_BUFFERING = 0x20000000;
        public const uint FILE_FLAG_OVERLAPPED = 0x40000000;
        public const uint FILE_FLAG_WRITE_THROUGH = 0x80000000;
        public const uint FILE_FLAG_RANDOM_ACCESS = 0x10000000;
        public const uint MEM_COMMIT = 0x1000;
        public const uint MEM_RESERVE = 0x2000;
        public const uint MEM_RELEASE = 0x8000;
        public const uint PAGE_READWRITE = 0x04;
        public const uint FILE_BEGIN = 0;
        public const int ERROR_IO_PENDING = 997;
        public const uint INFINITE = 0xFFFFFFFF;
        public const uint TOKEN_ADJUST_PRIVILEGES = 0x00000020;
        public const uint TOKEN_QUERY = 0x00000008;
        public const uint SE_PRIVILEGE_ENABLED = 0x00000002;

        [StructLayout(LayoutKind.Sequential)]
        private struct NativeOverlapped {
            public IntPtr Internal;
            public IntPtr InternalHigh;
            public uint Offset;
            public uint OffsetHigh;
            public IntPtr hEvent;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        public struct TokenPrivileges {
            public int PrivilegeCount;
            public long Luid;
            public uint Attributes;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct OverlappedEntry {
            public UIntPtr CompletionKey;
            public IntPtr Overlapped;
            public UIntPtr Internal;
            public uint NumberOfBytesTransferred;
        }

        private static readonly int OverlappedInternalOffset = (int)Marshal.OffsetOf(typeof(NativeOverlapped), "Internal");
        private static readonly int OverlappedInternalHighOffset = (int)Marshal.OffsetOf(typeof(NativeOverlapped), "InternalHigh");
        private static readonly int OverlappedOffsetOffset = (int)Marshal.OffsetOf(typeof(NativeOverlapped), "Offset");
        private static readonly int OverlappedOffsetHighOffset = (int)Marshal.OffsetOf(typeof(NativeOverlapped), "OffsetHigh");
        private static readonly int OverlappedEventOffset = (int)Marshal.OffsetOf(typeof(NativeOverlapped), "hEvent");
        private static readonly int CompletionEntryOverlappedOffset = (int)Marshal.OffsetOf(typeof(OverlappedEntry), "Overlapped");
        private static readonly int CompletionEntryBytesOffset = (int)Marshal.OffsetOf(typeof(OverlappedEntry), "NumberOfBytesTransferred");

        public sealed class BenchmarkMeasure {
            public long Bytes { get; set; }
            public int Operations { get; set; }
            public double Seconds { get; set; }
            public double MBps {
                get {
                    if (Seconds <= 0) return 0;
                    return Math.Round((Bytes / 1000000.0) / Seconds, 1);
                }
            }
            public double Iops {
                get {
                    if (Seconds <= 0) return 0;
                    return Math.Round(Operations / Seconds, 0);
                }
            }
        }

        private static Exception LastError(string action) {
            return new Win32Exception(Marshal.GetLastWin32Error(), action + " failed");
        }

        private static long AlignBytes(long bytes, int blockSize) {
            long blocks = bytes / blockSize;
            if (blocks < 1) throw new ArgumentOutOfRangeException("bytes", "Benchmark size is smaller than the I/O block size.");
            return blocks * blockSize;
        }

        private static SafeFileHandle OpenNativeFile(string path, uint access, uint creationDisposition, bool randomAccess, bool writeThrough, uint shareMode, bool overlapped) {
            uint flags = FILE_ATTRIBUTE_NORMAL | FILE_FLAG_NO_BUFFERING;
            if (randomAccess) flags |= FILE_FLAG_RANDOM_ACCESS;
            if (writeThrough) flags |= FILE_FLAG_WRITE_THROUGH;
            if (overlapped) flags |= FILE_FLAG_OVERLAPPED;

            SafeFileHandle handle = CreateFile(path, access, shareMode, IntPtr.Zero, creationDisposition, flags, IntPtr.Zero);
            if (handle.IsInvalid) throw LastError("CreateFile " + path);
            return handle;
        }

        private static void EnablePrivilege(string privilegeName) {
            IntPtr token = IntPtr.Zero;
            try {
                if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out token)) return;
                long luid;
                if (!LookupPrivilegeValue(null, privilegeName, out luid)) return;

                TokenPrivileges privileges = new TokenPrivileges {
                    PrivilegeCount = 1,
                    Luid = luid,
                    Attributes = SE_PRIVILEGE_ENABLED
                };
                AdjustTokenPrivileges(token, false, ref privileges, 0, IntPtr.Zero, IntPtr.Zero);
            }
            finally {
                if (token != IntPtr.Zero) CloseHandle(token);
            }
        }

        public static void PrepareFile(string path, long bytes) {
            EnablePrivilege("SeManageVolumePrivilege");
            SafeFileHandle handle = null;
            bool validDataReady = false;

            try {
                handle = OpenNativeFile(path, GENERIC_READ | GENERIC_WRITE, CREATE_ALWAYS, false, false, FILE_SHARE_READ | FILE_SHARE_WRITE, false);
                long ignored;
                SetFilePointerEx(handle, bytes, out ignored, FILE_BEGIN);
                SetEndOfFile(handle);
                validDataReady = SetFileValidData(handle, bytes);
                FlushFileBuffers(handle);
            }
            finally {
                if (handle != null) handle.Dispose();
            }

            if (!validDataReady) {
                // Modified fallback: Using standard FileStream buffering for non-admins to prevent setup thrashing.
                byte[] buffer = new byte[1048576];
                new Random(Environment.TickCount).NextBytes(buffer);
                using (System.IO.FileStream fs = new System.IO.FileStream(path, System.IO.FileMode.Create, System.IO.FileAccess.Write, System.IO.FileShare.None, 1048576, System.IO.FileOptions.SequentialScan)) {
                    long p = 0;
                    while (p < bytes) {
                        int toWrite = (int)Math.Min(buffer.Length, bytes - p);
                        fs.Write(buffer, 0, toWrite);
                        p += toWrite;
                    }
                    fs.Flush(true);
                }
            }
        }

        private sealed class NativeIoSlot : IDisposable {
            public IntPtr Buffer = IntPtr.Zero;
            public IntPtr Overlapped = IntPtr.Zero;

            public NativeIoSlot(int blockSize, int seed) {
                Buffer = VirtualAlloc(IntPtr.Zero, new UIntPtr((ulong)blockSize), MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
                byte[] managed = new byte[blockSize];
                new Random(seed).NextBytes(managed);
                Marshal.Copy(managed, 0, Buffer, blockSize);
                Overlapped = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(NativeOverlapped)));
            }

            public void Dispose() {
                if (Overlapped != IntPtr.Zero) { Marshal.FreeHGlobal(Overlapped); Overlapped = IntPtr.Zero; }
                if (Buffer != IntPtr.Zero) { VirtualFree(Buffer, UIntPtr.Zero, MEM_RELEASE); Buffer = IntPtr.Zero; }
            }
        }

        public static BenchmarkMeasure MeasureQueued(string path, long totalBytes, int blockSize, int queueDepth, double durationSeconds, bool isWrite, bool isRandom) {
            totalBytes = AlignBytes(totalBytes, blockSize);
            long blockCount = totalBytes / blockSize;
            bool timedRun = durationSeconds > 0;
            int operationLimit = timedRun ? int.MaxValue : (int)blockCount;
            queueDepth = Math.Max(1, Math.Min(queueDepth, operationLimit));

            NativeIoSlot[] slots = new NativeIoSlot[queueDepth];
            SafeFileHandle handle = null;
            IntPtr completionPort = IntPtr.Zero;

            try {
                for (int i = 0; i < queueDepth; i++) {
                    slots[i] = new NativeIoSlot(blockSize, Environment.TickCount + i);
                }

                uint access = isWrite ? (GENERIC_READ | GENERIC_WRITE) : GENERIC_READ;
                uint share = isWrite ? 0 : (FILE_SHARE_READ | FILE_SHARE_WRITE);

                // --- THE BUG FIX IS HERE ---
                // We pass 'false' for writeThrough so the SSD can use its DRAM/SLC hardware caches normally.
                handle = OpenNativeFile(path, access, OPEN_EXISTING, isRandom, false, share, true);

                completionPort = CreateIoCompletionPort(handle, IntPtr.Zero, UIntPtr.Zero, 1);

                Random random = isRandom ? new Random(Environment.TickCount) : null;
                int completed = 0;
                int issued = 0;
                long nextSequentialBlock = 0;
                System.Collections.Generic.Dictionary<IntPtr, NativeIoSlot> slotByOverlapped = new System.Collections.Generic.Dictionary<IntPtr, NativeIoSlot>(queueDepth);

                Stopwatch stopwatch = new Stopwatch();
                stopwatch.Start();

                for (int i = 0; i < queueDepth && issued < operationLimit && (!timedRun || stopwatch.Elapsed.TotalSeconds < durationSeconds); i++) {
                    long blockIndex = isRandom ? random.Next((int)blockCount) : (nextSequentialBlock++ % blockCount);
                    long offset = blockIndex * blockSize;

                    Marshal.WriteIntPtr(slots[i].Overlapped, OverlappedInternalOffset, IntPtr.Zero);
                    Marshal.WriteIntPtr(slots[i].Overlapped, OverlappedInternalHighOffset, IntPtr.Zero);
                    Marshal.WriteInt32(slots[i].Overlapped, OverlappedOffsetOffset, unchecked((int)(offset & 0xFFFFFFFFL)));
                    Marshal.WriteInt32(slots[i].Overlapped, OverlappedOffsetHighOffset, unchecked((int)((offset >> 32) & 0xFFFFFFFFL)));
                    Marshal.WriteIntPtr(slots[i].Overlapped, OverlappedEventOffset, IntPtr.Zero);

                    uint ignored;
                    bool ok = isWrite ? WriteFile(handle, slots[i].Buffer, (uint)blockSize, out ignored, slots[i].Overlapped)
                                      : ReadFile(handle, slots[i].Buffer, (uint)blockSize, out ignored, slots[i].Overlapped);

                    int code = Marshal.GetLastWin32Error();
                    if (!ok && code != ERROR_IO_PENDING) throw new Win32Exception(code, "IO Error");

                    slotByOverlapped[slots[i].Overlapped] = slots[i];
                    issued++;
                }

                int completionEntrySize = Marshal.SizeOf(typeof(OverlappedEntry));
                IntPtr completionEntries = Marshal.AllocHGlobal(completionEntrySize * queueDepth);

                try {
                    while (completed < issued || (issued < operationLimit && (!timedRun || stopwatch.Elapsed.TotalSeconds < durationSeconds))) {
                        uint removed;
                        if (!GetQueuedCompletionStatusEx(completionPort, completionEntries, (uint)queueDepth, out removed, INFINITE, false)) {
                            throw LastError("GetQueuedCompletionStatusEx");
                        }

                        for (int i = 0; i < removed; i++) {
                            IntPtr entryPointer = IntPtr.Add(completionEntries, i * completionEntrySize);
                            IntPtr completedOverlapped = Marshal.ReadIntPtr(entryPointer, CompletionEntryOverlappedOffset);
                            NativeIoSlot slot = slotByOverlapped[completedOverlapped];
                            completed++;

                            if (issued < operationLimit && (!timedRun || stopwatch.Elapsed.TotalSeconds < durationSeconds)) {
                                long blockIndex = isRandom ? random.Next((int)blockCount) : (nextSequentialBlock++ % blockCount);
                                long offset = blockIndex * blockSize;

                                Marshal.WriteIntPtr(slot.Overlapped, OverlappedInternalOffset, IntPtr.Zero);
                                Marshal.WriteIntPtr(slot.Overlapped, OverlappedInternalHighOffset, IntPtr.Zero);
                                Marshal.WriteInt32(slot.Overlapped, OverlappedOffsetOffset, unchecked((int)(offset & 0xFFFFFFFFL)));
                                Marshal.WriteInt32(slot.Overlapped, OverlappedOffsetHighOffset, unchecked((int)((offset >> 32) & 0xFFFFFFFFL)));

                                uint ignored;
                                bool ok = isWrite ? WriteFile(handle, slot.Buffer, (uint)blockSize, out ignored, slot.Overlapped)
                                                  : ReadFile(handle, slot.Buffer, (uint)blockSize, out ignored, slot.Overlapped);

                                int code = Marshal.GetLastWin32Error();
                                if (!ok && code != ERROR_IO_PENDING) throw new Win32Exception(code, "IO Error");
                                issued++;
                            }
                        }
                    }
                }
                finally {
                    if (completionEntries != IntPtr.Zero) Marshal.FreeHGlobal(completionEntries);
                }

                stopwatch.Stop();
                return new BenchmarkMeasure { Bytes = (long)completed * blockSize, Operations = completed, Seconds = stopwatch.Elapsed.TotalSeconds };
            }
            finally {
                if (completionPort != IntPtr.Zero) CloseHandle(completionPort);
                if (handle != null) handle.Dispose();
                for (int i = 0; i < slots.Length; i++) { if (slots[i] != null) slots[i].Dispose(); }
            }
        }
    }
}
'@
                    }

                    function Measure-Drive {
                        param([string]$DriveLetter, [int]$FileSizeMb, [int]$BaseProgress, [int]$StepWeight)

                        $root = "{0}:\" -f $DriveLetter
                        $folder = [System.IO.Path]::Combine($root, "WMT_Benchmark_Data")
                        $file = [System.IO.Path]::Combine($folder, "wmt_io_test_{0}.dat" -f ([guid]::NewGuid().ToString("N")))

                        $seqBufferSize = 2MB
                        $randomBlockSize = 4KB
                        $targetBytes = [int64]$FileSizeMb * 1MB

                        $seqPeakQueueDepth = 8
                        $randomPeakQueueDepth = 32
                        $measureSeconds = 5.0
                        $useTimedMode = $FileSizeMb -lt 512
                        $activeMeasureSeconds = if ($useTimedMode) { $measureSeconds } else { 0.0 }

                        try {
                            try { if ($State["ActiveFiles"]) { [void]$State["ActiveFiles"].Add($file) } } catch {}
                            Initialize-NativeDiskBenchmark
                            Test-Cancelled

                            if (-not [System.IO.Directory]::Exists($folder)) { [void][System.IO.Directory]::CreateDirectory($folder) }

                            try {
                                foreach ($oldFile in [System.IO.Directory]::EnumerateFiles($folder, "wmt_io_test_*.dat")) {
                                    try { [System.IO.File]::Delete($oldFile) } catch {}
                                }
                            }
                            catch {}

                            Add-Line ("  Test file: {0}" -f $file)

                            Set-BenchmarkStatus "Allocating test file on $DriveLetter`..." $BaseProgress
                            [Wmt.NativeDiskBenchmark]::PrepareFile($file, $targetBytes)

                            if ($useTimedMode) { Add-Line ("  Mode: {0:N0}s measured loop per result (decimal MB/s)" -f $measureSeconds) }
                            else { Add-Line "  Mode: one full selected-size pass per result, no timer (decimal MB/s)" }

                            $runMeasure = {
                                param([string]$Label, [int]$Progress, [scriptblock]$Measure)
                                Set-BenchmarkStatus "Testing $DriveLetter`: $Label..." $Progress
                                Test-Cancelled
                                return & $Measure
                            }.GetNewClosure()

                            $seqQ8Write = & $runMeasure "SEQ2M Q8T1 write" $BaseProgress {
                                [Wmt.NativeDiskBenchmark]::MeasureQueued($file, $targetBytes, $seqBufferSize, $seqPeakQueueDepth, $activeMeasureSeconds, $true, $false)
                            }

                            $seqQ8Read = & $runMeasure "SEQ2M Q8T1 read" ($BaseProgress + $StepWeight) {
                                [Wmt.NativeDiskBenchmark]::MeasureQueued($file, $targetBytes, $seqBufferSize, $seqPeakQueueDepth, $activeMeasureSeconds, $false, $false)
                            }
                            Add-Line ("  SEQ2M Q8T1 Read  {0} MB/s | Write {1} MB/s" -f $seqQ8Read.MBps, $seqQ8Write.MBps)

                            $seqQ1Write = & $runMeasure "SEQ2M Q1T1 write" ($BaseProgress + ($StepWeight * 2)) {
                                [Wmt.NativeDiskBenchmark]::MeasureQueued($file, $targetBytes, $seqBufferSize, 1, $activeMeasureSeconds, $true, $false)
                            }

                            $seqQ1Read = & $runMeasure "SEQ2M Q1T1 read" ($BaseProgress + ($StepWeight * 3)) {
                                [Wmt.NativeDiskBenchmark]::MeasureQueued($file, $targetBytes, $seqBufferSize, 1, $activeMeasureSeconds, $false, $false)
                            }
                            Add-Line ("  SEQ2M Q1T1 Read  {0} MB/s | Write {1} MB/s" -f $seqQ1Read.MBps, $seqQ1Write.MBps)

                            $rndQ32Write = & $runMeasure "RND4K Q32T1 write" ($BaseProgress + ($StepWeight * 4)) {
                                [Wmt.NativeDiskBenchmark]::MeasureQueued($file, $targetBytes, $randomBlockSize, $randomPeakQueueDepth, $activeMeasureSeconds, $true, $true)
                            }

                            $rndQ32Read = & $runMeasure "RND4K Q32T1 read" ($BaseProgress + ($StepWeight * 5)) {
                                [Wmt.NativeDiskBenchmark]::MeasureQueued($file, $targetBytes, $randomBlockSize, $randomPeakQueueDepth, $activeMeasureSeconds, $false, $true)
                            }
                            Add-Line ("  RND4K Q32T1 Read  {0} MB/s ({1} IOPS) | Write {2} MB/s ({3} IOPS)" -f $rndQ32Read.MBps, $rndQ32Read.Iops, $rndQ32Write.MBps, $rndQ32Write.Iops)

                            $rndQ1Write = & $runMeasure "RND4K Q1T1 write" ($BaseProgress + ($StepWeight * 6)) {
                                [Wmt.NativeDiskBenchmark]::MeasureQueued($file, $targetBytes, $randomBlockSize, 1, $activeMeasureSeconds, $true, $true)
                            }

                            $rndQ1Read = & $runMeasure "RND4K Q1T1 read" ($BaseProgress + ($StepWeight * 7)) {
                                [Wmt.NativeDiskBenchmark]::MeasureQueued($file, $targetBytes, $randomBlockSize, 1, $activeMeasureSeconds, $false, $true)
                            }
                            Add-Line ("  RND4K Q1T1 Read  {0} MB/s ({1} IOPS) | Write {2} MB/s ({3} IOPS)" -f $rndQ1Read.MBps, $rndQ1Read.Iops, $rndQ1Write.MBps, $rndQ1Write.Iops)

                            Set-BenchmarkStatus "Completed $DriveLetter`." ($BaseProgress + ($StepWeight * 8))
                        }
                        finally {
                            try { if ([System.IO.File]::Exists($file)) { [System.IO.File]::Delete($file) } } catch {}
                            try { if ($State["ActiveFiles"]) { [void]$State["ActiveFiles"].Remove($file) } } catch {}
                            try {
                                if ([System.IO.Directory]::Exists($folder)) {
                                    $hasEntries = $false
                                    foreach ($entry in [System.IO.Directory]::EnumerateFileSystemEntries($folder)) {
                                        $hasEntries = $true
                                        break
                                    }
                                    if (-not $hasEntries) { [System.IO.Directory]::Delete($folder, $false) }
                                }
                            }
                            catch {}
                        }
                    }

                    try {
                        $targetDrive = [string]$State["TargetDrive"]
                        $targetSize = [int]$State["TargetSize"]

                        Set-BenchmarkStatus "Finding fixed drives..." 0
                        $drives = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq [System.IO.DriveType]::Fixed -and $_.IsReady })
                        if ($targetDrive -ne "ALL") {
                            $drives = @($drives | Where-Object { $_.Name.Substring(0, 1).ToUpperInvariant() -eq $targetDrive.ToUpperInvariant() })
                        }
                        if (-not $drives -or $drives.Count -eq 0) { throw "No suitable fixed drives were found." }

                        $driveHardwareMap = Get-BenchmarkDriveHardwareMap
                        $requiredBytes = ([int64]$targetSize * 1MB) + 96MB
                        $testableDrives = @($drives | Where-Object { [int64]$_.AvailableFreeSpace -ge $requiredBytes })

                        if (-not $testableDrives -or $testableDrives.Count -eq 0) { throw "Selected drive(s) do not have enough free space for a $targetSize MB benchmark." }

                        $totalSteps = [math]::Max(1, $testableDrives.Count * 8)
                        $stepWeight = [math]::Max(1, [int](100 / $totalSteps))
                        $stepIndex = 0

                        foreach ($driveInfo in $drives) {
                            Test-Cancelled
                            $driveLetter = $driveInfo.Name.Substring(0, 1)
                            $driveLabel = if ([string]::IsNullOrWhiteSpace($driveInfo.VolumeLabel)) { "(No label)" } else { $driveInfo.VolumeLabel }

                            $driveHardware = $null
                            if ($driveHardwareMap.ContainsKey($driveLetter)) { $driveHardware = [string]$driveHardwareMap[$driveLetter] }
                            $driveDisplayName = if ([string]::IsNullOrWhiteSpace($driveHardware)) { "{0}: {1}" -f $driveLetter, $driveLabel } else { "{0}: {1} - {2}" -f $driveLetter, $driveLabel, $driveHardware }

                            if ([int64]$driveInfo.AvailableFreeSpace -lt $requiredBytes) {
                                Add-Line ("{0} - skipped, not enough free space for a {1} MB test." -f $driveDisplayName, $targetSize)
                                continue
                            }

                            Add-Line ""
                            Add-Line ("{0} ({1} MiB test file)" -f $driveDisplayName, $targetSize)

                            $baseProgress = $stepIndex * $stepWeight
                            try { Measure-Drive -DriveLetter $driveLetter -FileSizeMb $targetSize -BaseProgress $baseProgress -StepWeight $stepWeight }
                            catch {
                                if ($State["Cancel"]) { throw }
                                Add-Line ("{0} - benchmark failed: {1}" -f $driveDisplayName, $_.Exception.Message)
                            }
                            $stepIndex += 8
                        }

                        Add-Line ""
                        Add-Line ("Completed: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
                        Set-BenchmarkStatus "Benchmark complete." 100
                    }
                    catch {
                        if ($State["Cancel"]) {
                            $State["Error"] = ""
                            Add-Line ""; Add-Line "Benchmark stopped by user."
                            Set-BenchmarkStatus "Benchmark stopped." 100
                        }
                        else {
                            $State["Error"] = $_.Exception.Message
                            Add-Line ""; Add-Line ("ERROR: {0}" -f $_.Exception.Message)
                            Set-BenchmarkStatus "Benchmark failed." 100
                        }
                    }
                    finally {
                        $State["IsRunning"] = $false
                        $State["IsCompleted"] = $true
                    }
                }).AddArgument($state)

            $worker["Runspace"] = $runspace
            $worker["PowerShell"] = $ps
            $worker["StartedAt"] = Get-Date
            $worker["Async"] = $ps.BeginInvoke()
            $timer.Start()
        }
        catch {
            $state["IsRunning"] = $false
            $state["IsCompleted"] = $true
            $state["Error"] = $_.Exception.Message
            $state["Status"] = "Failed to start benchmark."
            $state["Progress"] = 100
            [void]$state["Lines"].Add(""); [void]$state["Lines"].Add("START ERROR: $($_.Exception.Message)")
            Set-WmtThemedBrush -Object $statusText -Property ([System.Windows.Controls.TextBlock]::ForegroundProperty) -ColorOrKey "Danger"

            & $refreshUi
            & $setRunningUi $false
            & $disposeWorker
            & $cleanupTrackedBenchmarkFiles
            Write-GuiLog "[Storage Benchmark] Start failed: $($_.Exception.Message)"
        }
    }.GetNewClosure()

    $btnRun.Add_Click({
            if ($state["IsRunning"]) { & $stopBenchmark } else { & $startBenchmark }
        }.GetNewClosure())

    $windowCleanup = {
        $state["Cancel"] = $true
        try { $timer.Stop() } catch {}
        try { if ($worker["PowerShell"] -and $state["IsRunning"]) { $worker["PowerShell"].Stop() } } catch {}
        & $disposeWorker
        & $cleanupTrackedBenchmarkFiles
        & $releaseWindowState
    }.GetNewClosure()

    $benchWindow.Add_Closing({ & $windowCleanup }.GetNewClosure())
    $benchWindow.Add_Closed({ & $releaseWindowState }.GetNewClosure())
    $benchWindow.Show() | Out-Null
}

function Invoke-WindowsUpdateRepairFull {
    Invoke-UiCommand {
        $services = @('wuauserv', 'bits', 'cryptsvc', 'msiserver', 'usosvc', 'trustedinstaller')
        foreach ($svc in $services) { try { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue } catch {} }
        try { Get-BitsTransfer -AllUsers | Remove-BitsTransfer -Confirm:$false } catch {}
        $suffix = ".bak_{0}" -f (Get-Random -Maximum 99999)
        if (Test-Path "$env:windir\\SoftwareDistribution") { try { Rename-Item "$env:windir\\SoftwareDistribution" ("SoftwareDistribution" + $suffix) -ErrorAction SilentlyContinue; Write-Output "Renamed SoftwareDistribution$suffix" } catch {} }
        if (Test-Path "$env:windir\\System32\\catroot2") { try { Rename-Item "$env:windir\\System32\\catroot2" ("catroot2" + $suffix) -ErrorAction SilentlyContinue; Write-Output "Renamed catroot2$suffix" } catch {} }
        $dlls = @("atl.dll", "urlmon.dll", "mshtml.dll", "shdocvw.dll", "browseui.dll", "jscript.dll", "vbscript.dll", "scrrun.dll", "msxml.dll", "msxml3.dll", "msxml6.dll", "actxprxy.dll", "softpub.dll", "wintrust.dll", "dssenh.dll", "rsaenh.dll", "gpkcsp.dll", "sccbase.dll", "slbcsp.dll", "cryptdlg.dll", "oleaut32.dll", "ole32.dll", "shell32.dll", "initpki.dll", "wuapi.dll", "wuaueng.dll", "wuaueng1.dll", "wucltui.dll", "wups.dll", "wups2.dll", "wuweb.dll", "qmgr.dll", "qmgrprxy.dll", "wucltux.dll", "muweb.dll", "wuwebv.dll")
        foreach ($dll in $dlls) { try { regsvr32.exe /s $dll } catch {} }
        try { netsh winsock reset | Out-Null } catch {}
        try { netsh winhttp reset proxy | Out-Null } catch {}
        foreach ($svc in $services) { try { Start-Service -Name $svc -ErrorAction SilentlyContinue } catch {} }
        Write-Output "Windows Update repair completed."
    } "Running full Windows Update repair..."
}

function Invoke-SystemReports {
    $selectedFolder = Select-WmtFolder -Description "Select output folder for system reports" -InitialDirectory (Get-DataPath)
    if ([string]::IsNullOrWhiteSpace($selectedFolder)) { return }
    $outdir = Join-Path $selectedFolder ("SystemReports_{0}" -f (Get-Date -Format "yyyy-MM-dd_HHmm"))
    if (-not (Test-Path $outdir)) { New-Item -ItemType Directory -Path $outdir | Out-Null }
    
    Invoke-UiCommand {
        param($outdir)
        $date = Get-Date -Format "yyyy-MM-dd"
        $sys = Join-Path $outdir "System_Info_$date.txt"
        $net = Join-Path $outdir "Network_Info_$date.txt"
        $drv = Join-Path $outdir "Driver_List_$date.txt"
        systeminfo | Out-File -FilePath $sys -Encoding UTF8
        ipconfig /all | Out-File -FilePath $net -Encoding UTF8
        driverquery | Out-File -FilePath $drv -Encoding UTF8
        Write-Output "Reports saved to $outdir"
        # CHANGE IS HERE: Passing the argument explicitly
    } "Generating system reports..." -ArgumentList $outdir
}

function Invoke-UpdateServiceReset {
    Invoke-UiCommand {
        try {
            $script:UpdateSvcResult = "OK"
            Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
            Stop-Service -Name cryptsvc -Force -ErrorAction SilentlyContinue
            Start-Service -Name appidsvc -ErrorAction SilentlyContinue
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
            Start-Service -Name cryptsvc -ErrorAction SilentlyContinue
            Start-Service -Name bits -ErrorAction SilentlyContinue
            Write-Output "Restarted Windows Update related services."
        }
        catch {
            $script:UpdateSvcResult = "ERR: $($_.Exception.Message)"
            throw
        }
    } "Restarting Windows Update services..."
}

function Set-DotNetRollForward {
    param([string]$Mode)
    switch ($Mode) {
        "Runtime" { [System.Environment]::SetEnvironmentVariable("DOTNET_ROLL_FORWARD", "LatestMajor", "Machine"); Write-Output "Runtime roll-forward enabled (LatestMajor)." }
        "SDK" {
            $latestSdk = & dotnet --list-sdks | Sort-Object -Descending | Select-Object -First 1
            if ($latestSdk) {
                $version = $latestSdk.Split()[0]
                $globalJsonPath = "$env:USERPROFILE\global.json"
                @{
                    sdk = @{
                        version     = $version
                        rollForward = "latestMajor"
                    }
                } | ConvertTo-Json -Depth 3 | Out-File -Encoding UTF8 $globalJsonPath
                Write-Output "SDK roll-forward set to $version (global.json at $globalJsonPath)."
            }
            else { Write-Output "No SDK detected." }
        }
        "Both" {
            [System.Environment]::SetEnvironmentVariable("DOTNET_ROLL_FORWARD", "LatestMajor", "Machine")
            $latestSdk = & dotnet --list-sdks | Sort-Object -Descending | Select-Object -First 1
            if ($latestSdk) {
                $version = $latestSdk.Split()[0]
                $globalJsonPath = "$env:USERPROFILE\global.json"
                @{
                    sdk = @{
                        version     = $version
                        rollForward = "latestMajor"
                    }
                } | ConvertTo-Json -Depth 3 | Out-File -Encoding UTF8 $globalJsonPath
            }
            Write-Output "Runtime + SDK roll-forward configured."
        }
        "Disable" {
            [System.Environment]::SetEnvironmentVariable("DOTNET_ROLL_FORWARD", $null, "Machine")
            $globalJsonPath = "$env:USERPROFILE\global.json"
            if (Test-Path $globalJsonPath) {
                try {
                    $json = Get-Content $globalJsonPath -Raw | ConvertFrom-Json
                    if ($json.sdk.rollForward) { $json.sdk.PSObject.Properties.Remove("rollForward"); $json | ConvertTo-Json -Depth 3 | Out-File -Encoding UTF8 $globalJsonPath }
                }
                catch {}
            }
            Write-Output ".NET roll-forward disabled."
        }
    }
}

function Invoke-MASActivation {
    $masInput = Show-WmtInputDialog -Title "MAS Activation Confirmation" -Prompt "Type YES, I UNDERSTAND to download and run MAS from massgrave.dev"
    if ($masInput -ne "YES, I UNDERSTAND") { return }
    Invoke-UiCommand {
        $scriptContent = Invoke-RestMethod -Uri "https://get.activated.win"
        Invoke-Expression -Command $scriptContent
        Write-Output "MAS script executed."
    } "Running MAS activation..."
}

function Invoke-WinREStatusCheck {
    Invoke-UiCommand {
        # 1. FIX THE ENCODING
        $oldEnc = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
        
        $raw = & reagentc.exe /info 2>&1
        $exitCode = $LASTEXITCODE
        
        [Console]::OutputEncoding = $oldEnc

        $text = ($raw | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            $text = "No output returned from reagentc /info."
        }

        $status = "Unknown"
        $location = "Unknown"
        
        # 2. UNIVERSAL EXTRACTION (Indentation-based)
        # We only grab lines that are INDENTED with spaces and contain a colon.
        # This perfectly ignores unindented header lines that might have colons!
        $colonLines = $text -split "`r`n" | Where-Object { $_ -match '^\s+[^:]+:' }
        
        if ($colonLines.Count -ge 2) {
            # The 1st indented line is ALWAYS the Status
            $status = ($colonLines[0] -split ":", 2)[1].Trim()
            # The 2nd indented line is ALWAYS the Location
            $location = ($colonLines[1] -split ":", 2)[1].Trim()
        }

        $warnings = New-Object System.Collections.Generic.List[string]
        if ($exitCode -ne 0) { [void]$warnings.Add("reagentc returned exit code: $exitCode") }
        
        # 3. UNIVERSAL HEALTH CHECK & AUTO-CORRECT
        if ([string]::IsNullOrWhiteSpace($location) -or $location.Length -lt 5) { 
            [void]$warnings.Add("Windows RE is not enabled or recovery location is missing.") 
            
            if ([string]::IsNullOrWhiteSpace($status) -or $status -eq "Unknown") {
                $status = "Disabled (Inferred)"
            }
        }
        else {
            if ([string]::IsNullOrWhiteSpace($status) -or $status -eq "Unknown") {
                $status = "Enabled (Inferred)"
            }
        }

        $health = if ($warnings.Count -eq 0) { "OK" } else { "Needs Attention" }
        $headline = if ($warnings.Count -eq 0) { "WinRE looks healthy." } else { "WinRE needs attention." }

        $summary = @(
            "Windows Recovery Environment (WinRE)",
            "Checked: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "",
            "Health: $health",
            "Status: $status",
            "Location: $location",
            ""
        )

        if ($warnings.Count -gt 0) {
            $summary += "What to check next:"
            foreach ($w in $warnings) { $summary += " - $w" }
            $summary += ""
            $summary += "Tip: You can usually fix this with:"
            $summary += " - reagentc /disable"
            $summary += " - reagentc /enable"
        }
        else {
            $summary += "No immediate issues found."
        }

        $msg = ($summary -join "`r`n")
        Write-Output $msg

        $icon = if ($warnings.Count -eq 0) {
            [System.Windows.MessageBoxImage]::Information
        }
        else {
            [System.Windows.MessageBoxImage]::Warning
        }

        $res = Show-WmtMessageBox -Message "$headline`r`n`r`n$msg`r`n`r`nShow technical details?" -Title "WinRE Status" -Button YesNo -Image $icon

        if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
            Show-TextDialog -Title "WinRE Technical Details" -Text $text
        }
    } "Checking WinRE status..."
}

function Invoke-QuickFixSuite {
    $confirmMsg = @"
Run Quick Fix now?

This will run:
1) SFC /SCANNOW
2) DISM /CheckHealth
3) DISM /RestoreHealth
4) Temp cleanup (User + Windows Temp)


It can take a while.
"@
    $res = [System.Windows.MessageBox]::Show(
        $confirmMsg,
        "Quick Fix",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    if ($res -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $runner = @'
$ErrorActionPreference = "Continue"
$ProgressPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

Write-Host ("WMT Quick Fix started at {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/4] Running SFC /SCANNOW..." -ForegroundColor Yellow
sfc /scannow
$sfcCode = $LASTEXITCODE

Write-Host ""
Write-Host "[2/4] Running DISM /Online /Cleanup-Image /CheckHealth..." -ForegroundColor Yellow
dism /online /cleanup-image /checkhealth
$dismCheckCode = $LASTEXITCODE

Write-Host ""
Write-Host "[3/4] Running DISM /Online /Cleanup-Image /RestoreHealth..." -ForegroundColor Yellow
dism /online /cleanup-image /restorehealth
$dismRestoreCode = $LASTEXITCODE

Write-Host ""
Write-Host "[4/4] Cleaning temporary files..." -ForegroundColor Yellow
function Get-TempFilesStreamed {
    param([string]$Root)
    if (-not $Root -or -not [System.IO.Directory]::Exists($Root)) { return }
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($Root)
    while ($pending.Count -gt 0) {
        $dir = $pending.Pop()
        try {
            foreach ($file in [System.IO.Directory]::EnumerateFiles($dir, "*", [System.IO.SearchOption]::TopDirectoryOnly)) { $file }
        } catch {}
        try {
            foreach ($child in [System.IO.Directory]::EnumerateDirectories($dir, "*", [System.IO.SearchOption]::TopDirectoryOnly)) { $pending.Push($child) }
        } catch {}
    }
}
function Remove-EmptyTempDirs {
    param([string]$Root)
    if (-not $Root -or -not [System.IO.Directory]::Exists($Root)) { return }
    try {
        foreach ($dir in [System.IO.Directory]::EnumerateDirectories($Root, "*", [System.IO.SearchOption]::TopDirectoryOnly)) {
            Remove-EmptyTempDirs $dir
            try { [System.IO.Directory]::Delete($dir, $false) } catch {}
        }
    } catch {}
}
$targets = @($env:TEMP, "$env:SystemRoot\Temp")
$deletedCount = 0
$deletedBytes = 0
foreach ($path in $targets) {
    if (-not $path -or -not [System.IO.Directory]::Exists($path)) { continue }
    foreach ($file in Get-TempFilesStreamed $path) {
        try {
            $info = [System.IO.FileInfo]::new($file)
            $deletedBytes += $info.Length
            try { [System.IO.File]::SetAttributes($file, [System.IO.FileAttributes]::Normal) } catch {}
            [System.IO.File]::Delete($file)
            $deletedCount++
        } catch {}
    }
    Remove-EmptyTempDirs $path
}
$tempMb = [math]::Round(($deletedBytes / 1MB), 2)
Write-Host ("Temp cleanup done: {0} item(s), ~{1} MB reclaimed." -f $deletedCount, $tempMb) -ForegroundColor Gray

Write-Host ""
Write-Host "Quick Fix finished." -ForegroundColor Green
Write-Host ("Exit codes -> SFC: {0} | DISM Check: {1} | DISM Restore: {2}" -f $sfcCode, $dismCheckCode, $dismRestoreCode) -ForegroundColor Gray
Write-Host ""
Write-Host ""
Write-Host "Tip: If needed, run CHKDSK separately from the CHKDSK button in System Health." -ForegroundColor DarkGray
Write-Host "Closing in 8 seconds..." -ForegroundColor Gray
Start-Sleep -Seconds 8
'@

    try {
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($runner))
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" -Verb RunAs -WindowStyle Normal
        Write-GuiLog "Quick Fix launched (SFC + DISM + Temp cleanup)."
    }
    catch {
        Write-GuiLog "Quick Fix launch failed: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show(
            "Could not start Quick Fix: $($_.Exception.Message)",
            "Quick Fix",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
}

function Show-SystemRestoreManager {
    try {
        if ($script:WmtRestoreManagerWindow -and $script:WmtRestoreManagerWindow.IsVisible) {
            $script:WmtRestoreManagerWindow.Activate() | Out-Null
            return
        }
    }
    catch {
        $script:WmtRestoreManagerWindow = $null
    }

    $content = @"
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <DataGrid Name="dgRestore" IsReadOnly="True" SelectionMode="Extended" SelectionUnit="FullRow" CanUserAddRows="False" CanUserDeleteRows="False" AlternationCount="2"/>
        <Grid Grid.Row="1" Margin="0,12,0,0">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <TextBlock Name="lblStatus" Text="Restore points: loading..." Foreground="{DynamicResource TextSecondary}"/>
            <WrapPanel Grid.Row="1" Margin="0,10,0,0">
                <Button Name="btnRefresh" Content="Refresh" MinWidth="104" Margin="0,0,8,8"/>
                <Button Name="btnEnable" Content="Enable Protection" MinWidth="136" Margin="0,0,8,8" Background="{DynamicResource Accent}" Foreground="{DynamicResource AccentText}"/>
                <Button Name="btnDisable" Content="Disable Protection" MinWidth="140" Margin="0,0,8,8" Background="{DynamicResource Warning}" Foreground="{DynamicResource WarningText}"/>
                <Button Name="btnCreate" Content="Create Point" MinWidth="116" Margin="0,0,8,8" Background="{DynamicResource Success}" Foreground="{DynamicResource SuccessText}"/>
                <Button Name="btnDelete" Content="Delete Selected" MinWidth="132" Margin="0,0,8,8" Background="{DynamicResource Danger}" Foreground="{DynamicResource DangerText}"/>
                <Button Name="btnRestore" Content="Restore Selected" MinWidth="138" Margin="0,0,8,8" Background="{DynamicResource Warning}" Foreground="{DynamicResource WarningText}"/>
                <Button Name="btnOpenUi" Content="Open Restore UI" MinWidth="128" Margin="0,0,8,8"/>
                <Button Name="btnClose" Content="Close" Width="92" IsCancel="True" Margin="0,0,8,8"/>
            </WrapPanel>
        </Grid>
    </Grid>
"@
    $dialog = New-WmtWindowFromXaml -Title "System Restore Manager" -ContentXaml $content -Width 1000 -Height 640 -MinWidth 780 -MinHeight 520
    $dg = $dialog.FindName("dgRestore")
    $lblStatus = $dialog.FindName("lblStatus")
    $btnRefresh = $dialog.FindName("btnRefresh")
    $btnEnable = $dialog.FindName("btnEnable")
    $btnDisable = $dialog.FindName("btnDisable")
    $btnCreate = $dialog.FindName("btnCreate")
    $btnDelete = $dialog.FindName("btnDelete")
    $btnRestore = $dialog.FindName("btnRestore")
    $btnOpenUi = $dialog.FindName("btnOpenUi")
    $btnClose = $dialog.FindName("btnClose")

    Set-WmtDataGridColumns -DataGrid $dg -Columns @("Description", "Type", "Created") -Widths @{ Description = "*"; Type = 120; Created = 170 }

    $toRestoreCellText = {
        param([object]$Value)

        if ($null -eq $Value) { return "" }
        try { $text = [string]$Value }
        catch { $text = "" }
        if ($null -eq $text) { return "" }
        $text = $text -replace '[\r\n\t]+', ' '
        $text = $text -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ' '
        return ([string]$text).Trim()
    }.GetNewClosure()

    $getRestorePointValue = {
        param(
            [object]$Item,
            [string[]]$Names
        )

        if ($null -eq $Item) { return $null }
        foreach ($name in @($Names)) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            try {
                $prop = $null
                try { $prop = $Item.PSObject.Properties[$name] } catch {}
                if ($prop) {
                    $value = $null
                    try { $value = $prop.Value } catch {}
                    if ($null -ne $value) { return $value }
                }
            }
            catch {}

            try {
                if ($Item -is [System.Management.ManagementBaseObject]) {
                    $propertyData = $null
                    try { $propertyData = $Item.Properties[$name] } catch {}
                    if ($propertyData) {
                        $value = $null
                        try { $value = $propertyData.Value } catch {}
                        if ($null -ne $value) { return $value }
                    }
                }
            }
            catch {}
        }

        return $null
    }.GetNewClosure()

    $formatRestorePointType = {
        param([object]$Value)

        $text = & $toRestoreCellText $Value
        if ([string]::IsNullOrWhiteSpace($text)) { return "" }
        if ($text -notmatch '^\d+$') { return $text }

        switch ([int]$text) {
            0 { return "Application Install" }
            1 { return "Application Uninstall" }
            10 { return "Device Driver Install" }
            12 { return "System" }
            13 { return "Cancelled Operation" }
            100 { return "Begin System Change" }
            101 { return "End System Change" }
            102 { return "Begin Nested System Change" }
            103 { return "End Nested System Change" }
            default { return $text }
        }
    }.GetNewClosure()

    $formatRestorePointTime = {
        param([object]$Value)

        $text = & $toRestoreCellText $Value
        if ([string]::IsNullOrWhiteSpace($text)) { return "" }

        if ($text -match '^\d{14}\.\d{6}[+-]\d{3}$') {
            try {
                $convertedTime = [System.Management.ManagementDateTimeConverter]::ToDateTime($text)
                if ($null -ne $convertedTime) { return $convertedTime.ToString("yyyy-MM-dd HH:mm:ss") }
            }
            catch {}
        }

        try {
            $parsedTime = [datetime]::Parse($text, [System.Globalization.CultureInfo]::CurrentCulture)
            return $parsedTime.ToString("yyyy-MM-dd HH:mm:ss")
        }
        catch {}

        return $text
    }.GetNewClosure()

    $getRestorePointItems = {
        $errors = [System.Collections.Generic.List[string]]::new()

        try {
            $items = @(Get-CimInstance -Namespace "root/default" -ClassName "SystemRestore" -ErrorAction Stop)
            return [PSCustomObject]@{ Source = "CIM"; Items = $items }
        }
        catch { [void]$errors.Add("CIM: $($_.Exception.Message)") }

        try {
            $items = @(Get-WmiObject -Namespace "root/default" -Class "SystemRestore" -ErrorAction Stop)
            return [PSCustomObject]@{ Source = "WMI"; Items = $items }
        }
        catch { [void]$errors.Add("WMI: $($_.Exception.Message)") }

        try {
            $items = @(Get-ComputerRestorePoint -ErrorAction Stop)
            return [PSCustomObject]@{ Source = "Get-ComputerRestorePoint"; Items = $items }
        }
        catch { [void]$errors.Add("Get-ComputerRestorePoint: $($_.Exception.Message)") }

        throw "All restore point queries failed. $($errors -join ' | ')"
    }.GetNewClosure()

    $restoreRefreshState = [hashtable]::Synchronized(@{
            Handler = $null
            Timer   = $null
        })

    $startRestorePointCreate = {
        param([string]$Description)

        $descriptionText = & $toRestoreCellText $Description
        if ([string]::IsNullOrWhiteSpace($descriptionText)) { return }

        $restoreDialog = $null
        $restoreStatusLabel = $null
        $restoreCreateButton = $null
        $restoreRefreshButton = $null
        try { $restoreDialog = $dialog } catch {}
        try { $restoreStatusLabel = $lblStatus } catch {}
        try { $restoreCreateButton = $btnCreate } catch {}
        try {
            if ($null -ne $restoreDialog) { $restoreRefreshButton = $restoreDialog.FindName("btnRefresh") }
        }
        catch {}
        try {
            if ($null -eq $restoreRefreshButton) { $restoreRefreshButton = $btnRefresh }
        }
        catch {}

        if ($script:WmtRestorePointCreateActive) {
            Show-WmtMessageBox -Owner $restoreDialog -Message "A restore point is already being created. Please wait for it to finish." -Title "System Restore Manager" -Image Information | Out-Null
            return
        }

        if ($descriptionText.Length -gt 256) { $descriptionText = $descriptionText.Substring(0, 256) }
        $script:WmtRestorePointCreateActive = $true
        if ($null -ne $restoreCreateButton) { $restoreCreateButton.IsEnabled = $false }
        if ($null -ne $restoreStatusLabel) { $restoreStatusLabel.Text = "Creating restore point..." }

        $progressContent = @'
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Name="lblCreateTitle" Text="Creating restore point in the background" FontSize="17" FontWeight="SemiBold" Margin="0,0,0,10"/>
        <TextBlock Name="lblCreateDetail" Grid.Row="1" Text="Starting Windows System Restore..." Foreground="{DynamicResource TextSecondary}" Margin="0,0,0,10" TextWrapping="Wrap"/>
        <ProgressBar Name="pbCreate" Grid.Row="2" Height="12" IsIndeterminate="True"/>
        <Button Name="btnHide" Grid.Row="3" Content="Hide" Width="96" Height="34" HorizontalAlignment="Right" Margin="0,18,0,0"/>
    </Grid>
'@
        $progressWindow = $null
        try {
            $progressWindow = New-WmtWindowFromXaml -Title "Create Restore Point" -ContentXaml $progressContent -Width 560 -Height 205 -MinWidth 520 -MinHeight 190 -NoResize
        }
        catch {
            $script:WmtRestorePointCreateActive = $false
            if ($null -ne $restoreCreateButton) { $restoreCreateButton.IsEnabled = $true }
            if ($null -ne $restoreStatusLabel) { $restoreStatusLabel.Text = "Restore point creation failed to start." }
            Show-WmtMessageBox -Owner $restoreDialog -Message "Could not open the restore point progress window.`n$($_.Exception.Message)" -Title "System Restore Manager" -Image Error | Out-Null
            return
        }

        try {
            if ($null -ne $restoreDialog) { $progressWindow.Owner = $restoreDialog }
        }
        catch {}
        try { $progressWindow.ShowInTaskbar = $false } catch {}
        $lblCreateDetail = $progressWindow.FindName("lblCreateDetail")
        $btnHideCreate = $progressWindow.FindName("btnHide")
        if ($btnHideCreate) {
            $btnHideCreate.Add_Click({ try { $progressWindow.Close() } catch {} }.GetNewClosure())
        }

        $workerId = [guid]::NewGuid().ToString("N")
        $tempPath = [System.IO.Path]::GetTempPath()
        $scriptPath = Join-Path $tempPath ("WMT_CreateRestorePoint_{0}.ps1" -f $workerId)
        $resultPath = Join-Path $tempPath ("WMT_CreateRestorePoint_{0}.json" -f $workerId)
        $encodedDescription = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($descriptionText))
        $childScriptTemplate = @'
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$resultPath = '__RESULT_PATH__'
$descriptionText = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('__DESCRIPTION_B64__'))

function Complete-RestorePointWorker {
    param(
        [bool]$Success,
        [string]$Message,
        [string]$ErrorMessage
    )

    try {
        $payload = [PSCustomObject]@{
            Success = $Success
            Message = $Message
            Error   = $ErrorMessage
        }
        $payload | ConvertTo-Json -Compress | Set-Content -LiteralPath $resultPath -Encoding UTF8 -Force
    }
    catch {}
}

try {
    if ([string]::IsNullOrWhiteSpace($descriptionText)) { throw "Restore point description is blank." }
    if ($descriptionText.Length -gt 256) { $descriptionText = $descriptionText.Substring(0, 256) }

    $errors = [System.Collections.Generic.List[string]]::new()
    $arguments = @{
        Description      = $descriptionText
        RestorePointType = 12
        EventType        = 100
    }

    $frequencyPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
    $frequencyName = "SystemRestorePointCreationFrequency"
    $frequencyState = @{ Changed = $false; Existed = $false; Value = $null }

    try {
        if (-not (Test-Path -LiteralPath $frequencyPath)) { New-Item -Path $frequencyPath -Force | Out-Null }
        $existing = Get-ItemProperty -LiteralPath $frequencyPath -Name $frequencyName -ErrorAction SilentlyContinue
        if ($existing -and $null -ne $existing.$frequencyName) {
            $frequencyState.Existed = $true
            $frequencyState.Value = [int]$existing.$frequencyName
        }
        if (-not $frequencyState.Existed -or [int]$frequencyState.Value -ne 0) {
            New-ItemProperty -LiteralPath $frequencyPath -Name $frequencyName -Value 0 -PropertyType DWord -Force | Out-Null
            $frequencyState.Changed = $true
        }
    }
    catch { [void]$errors.Add("Frequency override: $($_.Exception.Message)") }

    $successMessage = $null
    try {
        try {
            $result = Invoke-CimMethod -Namespace "root/default" -ClassName "SystemRestore" -MethodName "CreateRestorePoint" -Arguments $arguments -ErrorAction Stop
            $returnValue = if ($result -and $result.PSObject.Properties["ReturnValue"]) { [int]$result.ReturnValue } else { 0 }
            if ($returnValue -eq 0) {
                $successMessage = "Restore point created via CIM."
            }
            else { throw "ReturnValue=$returnValue" }
        }
        catch { [void]$errors.Add("CIM CreateRestorePoint: $($_.Exception.Message)") }

        if ([string]::IsNullOrWhiteSpace($successMessage)) {
            try {
                $systemRestoreClass = Get-WmiObject -Namespace "root/default" -Class "SystemRestore" -List -ErrorAction Stop
                $result = $systemRestoreClass.CreateRestorePoint($descriptionText, 12, 100)
                $returnValue = if ($result -and $result.PSObject.Properties["ReturnValue"]) { [int]$result.ReturnValue } else { [int]$result }
                if ($returnValue -eq 0) {
                    $successMessage = "Restore point created via WMI."
                }
                else { throw "ReturnValue=$returnValue" }
            }
            catch { [void]$errors.Add("WMI CreateRestorePoint: $($_.Exception.Message)") }
        }

        if ([string]::IsNullOrWhiteSpace($successMessage)) {
            try {
                Checkpoint-Computer -Description $descriptionText -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop | Out-Null
                $successMessage = "Restore point created via Checkpoint-Computer."
            }
            catch { [void]$errors.Add("Checkpoint-Computer: $($_.Exception.Message)") }
        }

        if ([string]::IsNullOrWhiteSpace($successMessage)) {
            throw "Failed to create restore point. $($errors -join ' | ')"
        }
    }
    finally {
        if ($frequencyState.Changed) {
            try {
                if ($frequencyState.Existed) {
                    New-ItemProperty -LiteralPath $frequencyPath -Name $frequencyName -Value ([int]$frequencyState.Value) -PropertyType DWord -Force | Out-Null
                }
                else {
                    Remove-ItemProperty -LiteralPath $frequencyPath -Name $frequencyName -ErrorAction SilentlyContinue
                }
            }
            catch {}
        }
    }

    Complete-RestorePointWorker -Success $true -Message $successMessage -ErrorMessage ""
    exit 0
}
catch {
    Complete-RestorePointWorker -Success $false -Message "" -ErrorMessage $_.Exception.Message
    exit 1
}
'@
        $childScript = $childScriptTemplate.Replace('__RESULT_PATH__', ($resultPath -replace "'", "''")).Replace('__DESCRIPTION_B64__', $encodedDescription)

        $process = $null
        try {
            Set-Content -LiteralPath $scriptPath -Value $childScript -Encoding UTF8 -Force
            $powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
            if (-not (Test-Path -LiteralPath $powershellPath -PathType Leaf -ErrorAction SilentlyContinue)) { $powershellPath = "powershell.exe" }
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = $powershellPath
            $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f ($scriptPath -replace '"', '\"')
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            $process = [System.Diagnostics.Process]::Start($psi)
            if ($null -eq $process) { throw "Windows did not return a restore-point worker process." }
            Write-GuiLog "Restore point creation started in a background process. PID: $($process.Id)"
        }
        catch {
            try { Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue } catch {}
            try { Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue } catch {}
            try { $progressWindow.Close() } catch {}
            $script:WmtRestorePointCreateActive = $false
            if ($null -ne $restoreCreateButton) { $restoreCreateButton.IsEnabled = $true }
            if ($null -ne $restoreStatusLabel) { $restoreStatusLabel.Text = "Restore point creation failed to start." }
            Show-WmtMessageBox -Owner $restoreDialog -Message "Failed to start restore point creation.`n$($_.Exception.Message)" -Title "System Restore Manager" -Image Error | Out-Null
            return
        }

        $startedAt = Get-Date
        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(350)
        $timer.Add_Tick({
                try {
                    $elapsed = [int]((Get-Date) - $startedAt).TotalSeconds
                    if ($lblCreateDetail) { $lblCreateDetail.Text = "Windows is creating the restore point... ${elapsed}s" }

                    if ($process -and -not $process.HasExited) { return }

                    $timer.Stop()
                    $exitCode = -1
                    try { if ($process) { $exitCode = [int]$process.ExitCode } } catch {}

                    $result = $null
                    $resultError = $null
                    try {
                        if (Test-Path -LiteralPath $resultPath -PathType Leaf -ErrorAction SilentlyContinue) {
                            $result = Get-Content -LiteralPath $resultPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                        }
                    }
                    catch { $resultError = $_.Exception.Message }

                    try { if ($process) { $process.Dispose() } } catch {}
                    try { Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue } catch {}
                    try { Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue } catch {}
                    try { if ($progressWindow) { $progressWindow.Close() } } catch {}

                    $script:WmtRestorePointCreateActive = $false
                    if ([object]::ReferenceEquals($script:WmtRestorePointCreateTimer, $timer)) { $script:WmtRestorePointCreateTimer = $null }
                    if ([object]::ReferenceEquals($script:WmtRestorePointCreateProcess, $process)) { $script:WmtRestorePointCreateProcess = $null }
                    if ($null -ne $restoreCreateButton) { $restoreCreateButton.IsEnabled = $true }

                    $messageOwner = $null
                    try { if ($null -ne $restoreDialog) { $messageOwner = $restoreDialog } } catch {}
                    if ($result -and [bool]$result.Success) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$result.Message)) { try { Write-GuiLog ([string]$result.Message) } catch {} }
                        Show-WmtMessageBox -Owner $messageOwner -Message "Restore point created successfully." -Title "Success" -Image Information | Out-Null
                        try {
                            if ($null -ne $restoreStatusLabel) { $restoreStatusLabel.Text = "Restore point created. Refreshing list..." }
                        }
                        catch {}
                        if ($null -eq $restoreRefreshButton) {
                            try {
                                if ($null -ne $restoreDialog) { $restoreRefreshButton = $restoreDialog.FindName("btnRefresh") }
                            }
                            catch {}
                        }
                        if ($null -ne $restoreRefreshButton) {
                            try {
                                Write-GuiLog "Clicking restore point Refresh button after creation."
                                $restoreRefreshButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
                            }
                            catch {
                                try { Write-GuiLog "Restore point Refresh button click failed: $($_.Exception.Message)" } catch {}
                            }
                        }
                        else {
                            try { Write-GuiLog "Restore point was created, but the Refresh button was not available." } catch {}
                        }
                    }
                    else {
                        $errorText = $null
                        if ($result -and -not [string]::IsNullOrWhiteSpace([string]$result.Error)) { $errorText = [string]$result.Error }
                        elseif (-not [string]::IsNullOrWhiteSpace([string]$resultError)) { $errorText = "Could not read worker result: $resultError" }
                        else { $errorText = "The restore-point worker exited with code $exitCode and did not return details." }
                        Write-GuiLog "Restore point creation failed: $errorText"
                        Show-WmtMessageBox -Owner $messageOwner -Message "Failed to create restore point.`n$errorText" -Title "Error" -Image Error | Out-Null
                    }
                }
                catch {
                    try { $timer.Stop() } catch {}
                    try { if ($process) { $process.Dispose() } } catch {}
                    try { Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue } catch {}
                    try { Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue } catch {}
                    $script:WmtRestorePointCreateActive = $false
                    if ([object]::ReferenceEquals($script:WmtRestorePointCreateTimer, $timer)) { $script:WmtRestorePointCreateTimer = $null }
                    if ([object]::ReferenceEquals($script:WmtRestorePointCreateProcess, $process)) { $script:WmtRestorePointCreateProcess = $null }
                    if ($null -ne $restoreCreateButton) { $restoreCreateButton.IsEnabled = $true }
                    try {
                        if ($null -ne $restoreStatusLabel) { $restoreStatusLabel.Text = "Restore point creation failed." }
                    }
                    catch {}
                    try { Write-GuiLog "Restore point completion handler failed: $($_.Exception.Message)" } catch {}
                    $messageOwner = $null
                    try { if ($null -ne $restoreDialog -and $restoreDialog.IsVisible) { $messageOwner = $restoreDialog } } catch {}
                    Show-WmtMessageBox -Owner $messageOwner -Message "Restore point creation finished, but WMT could not process the result.`n$($_.Exception.Message)" -Title "System Restore Manager" -Image Error | Out-Null
                }
            }.GetNewClosure())

        [void]$progressWindow.Show()
        $script:WmtRestorePointCreateTimer = $timer
        $script:WmtRestorePointCreateProcess = $process
        $timer.Start()
    }.GetNewClosure()

    $getRestoreRowValue = {
        param(
            [object]$Row,
            [string]$Name
        )

        if ($null -eq $Row -or [string]::IsNullOrWhiteSpace($Name)) { return "" }
        try {
            if ($Row -is [System.Data.DataRow]) { return & $toRestoreCellText $Row[$Name] }
            if ($Row -is [System.Data.DataRowView]) { return & $toRestoreCellText $Row.Row[$Name] }
            if ($Row -is [System.Collections.IDictionary] -and $Row.Contains($Name)) { return & $toRestoreCellText $Row[$Name] }
            $prop = $Row.PSObject.Properties[$Name]
            if ($prop) { return & $toRestoreCellText $prop.Value }
        }
        catch {}
        return ""
    }.GetNewClosure()

    $loadRestorePoints = {
        param([switch]$ShowError)

        $lblStatus.Text = "Restore points: loading..."
        if ($btnRefresh) { $btnRefresh.IsEnabled = $false }
        Set-WmtBusyCursor -Busy
        Invoke-WmtDispatcherPump -Dispatcher $dialog.Dispatcher

        try {
            $queryResult = & $getRestorePointItems
            $list = @($queryResult.Items | Sort-Object @{ Expression = {
                        $seqText = & $toRestoreCellText (& $getRestorePointValue $_ @("SequenceNumber", "Sequence"))
                        try { [int]$seqText } catch { 0 }
                    }; Descending                                    = $true 
                })
            $rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
            foreach ($rp in $list) {
                if ($null -eq $rp) { continue }
                try {
                    $rawTime = & $toRestoreCellText (& $getRestorePointValue $rp @("CreationTime", "Date and Time", "DateAndTime", "DateTime"))
                    $restoreType = & $getRestorePointValue $rp @("Type", "RestorePointType", "EventType")

                    [void]$rows.Add([PSCustomObject]@{
                            SequenceNumber = & $toRestoreCellText (& $getRestorePointValue $rp @("SequenceNumber", "Sequence"))
                            Description    = & $toRestoreCellText (& $getRestorePointValue $rp @("Description"))
                            Type           = & $formatRestorePointType $restoreType
                            Created        = & $formatRestorePointTime $rawTime
                            RawTime        = $rawTime
                        })
                }
                catch {
                    Write-GuiLog "Could not display one restore point row: $($_.Exception.Message)"
                }
            }

            $dg.ItemsSource = $null
            $dg.ItemsSource = $rows
            try { $dg.Items.Refresh() } catch {}
            try { $dg.UpdateLayout() } catch {}
            $lblStatus.Text = "Restore points: $($rows.Count)"
            Write-GuiLog "System Restore Manager loaded $($rows.Count) restore point(s) via $($queryResult.Source). Grid items: $($dg.Items.Count)."
        }
        catch {
            $message = "Could not load restore points: $($_.Exception.Message)"
            Write-GuiLog $message
            $dg.ItemsSource = $null
            $lblStatus.Text = $message
            if ($ShowError) {
                Show-WmtMessageBox -Owner $dialog -Message $message -Title "System Restore Manager" -Image Warning | Out-Null
            }
        }
        finally {
            if ($btnRefresh) { $btnRefresh.IsEnabled = $true }
            Set-WmtBusyCursor
        }
    }.GetNewClosure()

    $refreshRestorePointsAfterCreate = {
        try {
            if ($restoreRefreshState.Timer) {
                $restoreRefreshState.Timer.Stop()
                $restoreRefreshState.Timer = $null
            }
        }
        catch {}

        $refreshState = [hashtable]::Synchronized(@{ Attempt = 0; MaxAttempts = 6 })
        $invokeRestoreRefresh = {
            param([switch]$ShowError)

            if (-not $dialog) { return $false }
            $refreshState.Attempt = [int]$refreshState.Attempt + 1
            if ([int]$refreshState.Attempt -eq 1) {
                $lblStatus.Text = "Restore point created. Refreshing list..."
            }
            else {
                $lblStatus.Text = "Refreshing restore points... ($($refreshState.Attempt)/$($refreshState.MaxAttempts))"
            }

            if ($btnRefresh) {
                try {
                    $btnRefresh.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
                }
                catch {
                    Write-GuiLog "Restore point Refresh button click failed: $($_.Exception.Message)"
                    & $loadRestorePoints -ShowError:$ShowError
                }
            }
            else {
                & $loadRestorePoints -ShowError:$ShowError
            }
            return $true
        }.GetNewClosure()

        try { [void](& $invokeRestoreRefresh -ShowError) }
        catch { Write-GuiLog "Immediate restore point refresh failed: $($_.Exception.Message)" }

        $refreshTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $refreshTimer.Interval = [TimeSpan]::FromSeconds(2)
        $refreshTimer.Add_Tick({
                try {
                    if ([int]$refreshState.Attempt -ge [int]$refreshState.MaxAttempts) {
                        $refreshTimer.Stop()
                        if ([object]::ReferenceEquals($restoreRefreshState.Timer, $refreshTimer)) { $restoreRefreshState.Timer = $null }
                        return
                    }
                    if (-not (& $invokeRestoreRefresh)) {
                        $refreshTimer.Stop()
                        if ([object]::ReferenceEquals($restoreRefreshState.Timer, $refreshTimer)) { $restoreRefreshState.Timer = $null }
                    }
                }
                catch {
                    $refreshTimer.Stop()
                    if ([object]::ReferenceEquals($restoreRefreshState.Timer, $refreshTimer)) { $restoreRefreshState.Timer = $null }
                    Write-GuiLog "Delayed restore point refresh failed: $($_.Exception.Message)"
                }
            }.GetNewClosure())
        $restoreRefreshState.Timer = $refreshTimer
        $refreshTimer.Start()
    }.GetNewClosure()
    $restoreRefreshState.Handler = $refreshRestorePointsAfterCreate

    $getSelectedRows = { @(Get-WmtDataGridSelectedRows -DataGrid $dg) }.GetNewClosure()

    $btnRefresh.Add_Click({ & $loadRestorePoints -ShowError }.GetNewClosure())
    $btnEnable.Add_Click({
            try {
                Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
                Show-WmtMessageBox -Owner $dialog -Message "System Restore has been ENABLED on $env:SystemDrive." -Title "Success" -Image Information | Out-Null
                & $loadRestorePoints -ShowError
            }
            catch { Show-WmtMessageBox -Owner $dialog -Message "Failed to enable protection.`n$($_.Exception.Message)" -Title "Error" -Image Error | Out-Null }
        }.GetNewClosure())
    $btnDisable.Add_Click({
            $res = Show-WmtMessageBox -Owner $dialog -Message "Are you sure you want to disable System Restore on $env:SystemDrive?`n`nWARNING: This will immediately delete ALL existing restore points." -Title "Confirm Disable" -Button YesNo -Image Warning
            if ($res -ne [System.Windows.MessageBoxResult]::Yes) { return }
            try {
                Disable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
                Show-WmtMessageBox -Owner $dialog -Message "System Restore has been DISABLED." -Title "Success" -Image Information | Out-Null
                & $loadRestorePoints -ShowError
            }
            catch { Show-WmtMessageBox -Owner $dialog -Message "Failed to disable protection.`n$($_.Exception.Message)" -Title "Error" -Image Error | Out-Null }
        }.GetNewClosure())
    $btnCreate.Add_Click({
            $desc = Show-WmtInputDialog -Title "Create Restore Point" -Prompt "Description for the restore point:" -DefaultValue "WMT Manual Restore Point"
            if ([string]::IsNullOrWhiteSpace($desc)) { return }
            & $startRestorePointCreate $desc
        }.GetNewClosure())
    $btnDelete.Add_Click({
            $selected = & $getSelectedRows
            if ($selected.Count -eq 0) { return }
            if ((Show-WmtMessageBox -Owner $dialog -Message "Delete $($selected.Count) selected restore point(s)?" -Title "Confirm Delete" -Button YesNo -Image Warning) -ne [System.Windows.MessageBoxResult]::Yes) { return }
            if (-not ([System.Management.Automation.PSTypeName]'Win32.SysRestoreAPI').Type) {
                $apiCode = '[DllImport("srclient.dll")] public static extern int SRRemoveRestorePoint(int index);'
                Add-Type -MemberDefinition $apiCode -Name "SysRestoreAPI" -Namespace "Win32" -ErrorAction SilentlyContinue
            }
            $ok = 0; $fail = 0
            foreach ($row in $selected) {
                try { $seq = [int](& $getRestoreRowValue $row "SequenceNumber") } catch { $seq = 0 }
                if ($seq -le 0) { $fail++; continue }
                try {
                    $ret = [Win32.SysRestoreAPI]::SRRemoveRestorePoint($seq)
                    if ($ret -eq 0) { $ok++ } else { $fail++; Show-WmtMessageBox -Owner $dialog -Message "Deletion failed for Sequence $seq. Windows Error Code: $ret" -Title "Error Details" -Image Error | Out-Null }
                }
                catch { $fail++; Show-WmtMessageBox -Owner $dialog -Message "Exception for Sequence ${seq}: $($_.Exception.Message)" -Title "Error Details" -Image Error | Out-Null }
            }
            Show-WmtMessageBox -Owner $dialog -Message "Deleted: $ok`nFailed: $fail" -Title "Deletion Complete" -Image Information | Out-Null
            & $loadRestorePoints -ShowError
        }.GetNewClosure())
    $btnRestore.Add_Click({
            $selected = & $getSelectedRows
            if ($selected.Count -ne 1) { Show-WmtMessageBox -Owner $dialog -Message "Please select exactly ONE restore point to restore." -Title "Notice" -Image Warning | Out-Null; return }
            try { $seq = [int](& $getRestoreRowValue $selected[0] "SequenceNumber") } catch { $seq = 0 }
            if ($seq -le 0) { return }
            $res = Show-WmtMessageBox -Owner $dialog -Message "WARNING: This will restore your system to Sequence $seq and RESTART your computer immediately.`n`nPlease save all open work before proceeding.`n`nProceed with System Restore?" -Title "Confirm Restore" -Button YesNo -Image Warning
            if ($res -ne [System.Windows.MessageBoxResult]::Yes) { return }
            try { Restore-Computer -RestorePoint $seq -Confirm:$false }
            catch { Show-WmtMessageBox -Owner $dialog -Message "Failed to initialize restore.`n$($_.Exception.Message)" -Title "Error" -Image Error | Out-Null }
        }.GetNewClosure())
    $btnOpenUi.Add_Click({ Start-Process "rstrui.exe" }.GetNewClosure())
    $btnClose.Add_Click({ $dialog.Close() }.GetNewClosure())

    $dialog.Add_ContentRendered({ & $loadRestorePoints }.GetNewClosure())
    $dialog.Add_Closed({
            if ($script:WmtRestoreManagerWindow -eq $dialog) { $script:WmtRestoreManagerWindow = $null }
            try { $restoreRefreshState.Handler = $null } catch {}
            try {
                if ($restoreRefreshState.Timer) {
                    $restoreRefreshState.Timer.Stop()
                    $restoreRefreshState.Timer = $null
                }
            }
            catch {}
        }.GetNewClosure())
    $script:WmtRestoreManagerWindow = $dialog
    [void]$dialog.Show()
    try { $dialog.Activate() | Out-Null } catch {}
}

function Switch-WindowsFeature($FeatureName, $DisplayName) {
    Invoke-UiCommand {
        param($fn, $dn)
        if (-not (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)) {
            Write-GuiLog "PowerShell feature cmdlets unavailable; trying DISM fallback..."
            $featureInfo = (dism /Online /Get-FeatureInfo /FeatureName:$fn 2>&1) -join "`n"
            if ($featureInfo -match "State\\s*:\\s*Enabled") {
                dism /Online /Disable-Feature /FeatureName:$fn /NoRestart | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-GuiLog "Disabled: $dn (DISM)" }
                else { throw "DISM failed to disable $dn (code $LASTEXITCODE)." }
            }
            else {
                dism /Online /Enable-Feature /FeatureName:$fn /All /NoRestart | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-GuiLog "Enabled: $dn (DISM)" }
                else { throw "DISM failed to enable $dn (code $LASTEXITCODE). Windows source files may be required." }
            }
            return
        }

        $feature = Get-WindowsOptionalFeature -Online -FeatureName $fn -ErrorAction SilentlyContinue

        # Some systems report NetFx3 as unknown to PowerShell even when DISM can toggle it.
        if (-not $feature) {
            if ($fn -ne "NetFx3") { throw "Feature name $fn is unknown." }

            Write-GuiLog "$dn not detected via PowerShell; trying DISM fallback..."
            $featureInfo = (dism /Online /Get-FeatureInfo /FeatureName:$fn 2>&1) -join "`n"
            if ($featureInfo -match "State\\s*:\\s*Enabled") {
                dism /Online /Disable-Feature /FeatureName:$fn /NoRestart | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-GuiLog "Disabled: $dn (DISM)" }
                else { throw "DISM failed to disable $dn (code $LASTEXITCODE)." }
            }
            else {
                dism /Online /Enable-Feature /FeatureName:$fn /All /NoRestart | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-GuiLog "Enabled: $dn (DISM)" }
                else { throw "DISM failed to enable $dn (code $LASTEXITCODE). Windows source files may be required." }
            }
            return
        }

        if ($feature.State -eq "Enabled") {
            Disable-WindowsOptionalFeature -Online -FeatureName $fn -NoRestart -ErrorAction Stop | Out-Null
            Write-GuiLog "Disabled: $dn"
        }
        else {
            Enable-WindowsOptionalFeature -Online -FeatureName $fn -All -NoRestart -ErrorAction Stop | Out-Null
            Write-GuiLog "Enabled: $dn"
        }
    } "Toggling $DisplayName..." -ArgumentList $FeatureName, $DisplayName
}

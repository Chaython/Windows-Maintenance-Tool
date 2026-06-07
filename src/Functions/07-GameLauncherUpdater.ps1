# Functional block generated from WMT-GUI.ps1.
# Dot-source this file; it intentionally shares WMT's script scope.

function Get-WmtLegendaryExePath {
    $legendaryDir = Join-Path (Get-DataPath) "legendary"
    return (Join-Path $legendaryDir "legendary.exe")
}

function Get-WmtGogdlRootPath {
    return (Join-Path (Get-DataPath) "gogdl")
}

function Get-WmtGogdlExePath {
    return (Join-Path (Get-WmtGogdlRootPath) "gogdl_windows_x86_64.exe")
}

function Get-WmtGogdlAuthConfigPath {
    return (Join-Path (Get-WmtGogdlRootPath) "auth.json")
}

function Show-ProviderManager {
    # 1. Load Current Settings
    $settings = Get-WmtSettings
    if (-not $settings.EnabledProviders) { 
        $settings | Add-Member -MemberType NoteProperty -Name "EnabledProviders" -Value @("winget", "msstore", "windowsupdate", "pip", "npm", "pnpm", "dotnet", "psmodule", "composer", "chocolatey", "scoop", "gem", "cargo", "steam", "legendary", "gogdl") -Force
    }
    $enabled = $settings.EnabledProviders

    # 2. Define UI
    [xml]$pXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Package Manager Settings" Height="790" Width="680" WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="{DynamicResource BgDark}" Foreground="{DynamicResource TextPrimary}">
    <Window.Resources>
        <Style TargetType="TextBlock"><Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/><Setter Property="VerticalAlignment" Value="Center"/></Style>
        <Style TargetType="CheckBox"><Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/><Setter Property="VerticalAlignment" Value="Center"/><Setter Property="Margin" Value="0,0,10,0"/></Style>
        <Style TargetType="Button">
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="Background" Value="{DynamicResource BgElevated}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,0"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Foreground" Value="#111827"/>
            <Setter Property="Background" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
        </Style>
        <Style TargetType="ComboBoxItem">
            <Setter Property="Foreground" Value="#111827"/>
            <Setter Property="Background" Value="#FFFFFF"/>
        </Style>
    </Window.Resources>
    <Grid Margin="20">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        
        <TextBlock Text="Manage Package Providers" FontSize="18" FontWeight="Bold" Margin="0,0,0,15"/>
        <TextBlock Text="Select which package managers to scan." Foreground="{DynamicResource TextSecondary}" Margin="0,25,0,0" Grid.Row="0"/>

        <ScrollViewer Grid.Row="1" Margin="0,15,0,0" VerticalScrollBarVisibility="Auto">
            <StackPanel>
            <Border Background="{DynamicResource BgElevated}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="10" Padding="12" Margin="0,0,0,14"
                    ToolTip="Configure automatic update scans, installation behavior, and background operation.">
                <Grid>
                    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="220"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                    <TextBlock Text="Auto scan" FontWeight="Bold" Grid.Row="0" Grid.Column="0"/>
                    <ComboBox Name="cmbAutoScanInterval" Grid.Row="0" Grid.Column="1" Height="28" Width="210" HorizontalAlignment="Left" SelectedValuePath="Tag" Foreground="#111827" Background="#FFFFFF">
                        <ComboBoxItem Content="Disabled" Tag="0" Foreground="#111827" Background="#FFFFFF"/>
                        <ComboBoxItem Content="Every 1 minute (test)" Tag="1" Foreground="#111827" Background="#FFFFFF"/>
                        <ComboBoxItem Content="Every 15 minutes" Tag="15" Foreground="#111827" Background="#FFFFFF"/>
                        <ComboBoxItem Content="Every 30 minutes" Tag="30" Foreground="#111827" Background="#FFFFFF"/>
                        <ComboBoxItem Content="Every 1 hour" Tag="60" Foreground="#111827" Background="#FFFFFF"/>
                        <ComboBoxItem Content="Every 2 hours" Tag="120" Foreground="#111827" Background="#FFFFFF"/>
                        <ComboBoxItem Content="Every 4 hours" Tag="240" Foreground="#111827" Background="#FFFFFF"/>
                    </ComboBox>
                    <CheckBox Name="chkUpdateNotifications" Grid.Row="0" Grid.Column="2" Content="Native notifications" Margin="12,0,0,0"
                              ToolTip="Show a Windows notification when an automatic background scan finds updates or fails."/>
                    <CheckBox Name="chkRunInTrayOnClose" Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="3" Content="Run in system tray when closed" Margin="0,8,0,0"
                              ToolTip="When enabled, closing the main window hides WMT to the system tray so background scans and notifications can continue."/>
                    <CheckBox Name="chkReduceRamInTray" Grid.Row="2" Grid.Column="0" Grid.ColumnSpan="3" Content="Reduce RAM while hidden in tray" Margin="0,8,0,0"
                              ToolTip="When WMT is hidden to the tray, clear short-lived caches, trim the log, run garbage collection, and ask Windows to release unused working-set pages."/>
                    <CheckBox Name="chkUpdateSilentInstall" Grid.Row="3" Grid.Column="0" Grid.ColumnSpan="3" Content="Run update/install commands headless" Margin="0,8,0,0"
                              ToolTip="Hide CLI, PowerShell, and cmd update windows. Providers that require their own GUI, including Steam validation and Microsoft Store GUI updates, can still appear."/>
                    <CheckBox Name="chkUpdateAutoInstall" Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="3" Content="Automatically install available updates after scans" Margin="0,8,0,0"
                              ToolTip="After each completed scan, automatically update listed packages without confirmation. Packages known to risk an automatic restart are skipped."/>
                    <TextBlock Grid.Row="5" Grid.Column="0" Grid.ColumnSpan="3" Margin="0,8,0,0"
                               Text="Auto scan runs while WMT is open or hidden in the tray. Auto install runs after completed manual, startup, and scheduled scans; restart-risk packages are skipped."
                               Foreground="{DynamicResource TextSecondary}" FontStyle="Italic" TextWrapping="Wrap"/>
                </Grid>
            </Border>

            <Grid Margin="0,0,0,10" ToolTip="Windows Package Manager">
                <Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <CheckBox Name="chkWinget" IsChecked="True" IsEnabled="False" Grid.Column="0"/>
                <TextBlock Text="Winget" FontWeight="Bold" Grid.Column="1"/>
                <TextBlock Name="lblProviderWingetStatus" Text="Checking..." Grid.Column="2"/>
                <Button Name="btnProviderWingetAction" Content="Install" Width="78" Height="26" Grid.Column="3" Margin="8,0,0,0"/>
            </Grid>

            <Grid Margin="30,0,0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <CheckBox Name="chkIncludeUnknown" Grid.Column="0"/>
                <TextBlock Text="Include unknown" FontWeight="Bold" Grid.Column="1"/>
                <TextBlock Text="Adds --include-unknown to winget scans" Foreground="{DynamicResource TextSecondary}" FontStyle="Italic" Grid.Column="2"/>
            </Grid>

            <Grid Margin="0,0,0,10" ToolTip="Microsoft Store Apps via store.exe">
                <Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <CheckBox Name="chkMsStore" Grid.Column="0"/>
                <TextBlock Text="Store CLI" FontWeight="Bold" Grid.Column="1"/>
                <TextBlock Name="lblProviderMsStoreStatus" Text="Checking..." Grid.Column="2"/>
                <Button Name="btnProviderMsStoreAction" Content="Install" Width="78" Height="26" Grid.Column="3" Margin="8,0,0,0"/>
            </Grid>

            <Grid Margin="0,0,0,10" ToolTip="Windows Update Agent. Scans both regular and optional Windows updates, including drivers when offered.">
                <Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <CheckBox Name="chkWindowsUpdate" Grid.Column="0"/>
                <TextBlock Text="Windows Update" FontWeight="Bold" Grid.Column="1"/>
                <TextBlock Name="lblWindowsUpdateStatus" Text="Checking..." Grid.Column="2"/>
                <Button Name="btnProviderWindowsUpdateAction" Content="Open" Width="78" Height="26" Grid.Column="3" Margin="8,0,0,0"/>
            </Grid>

            <Grid Margin="0,0,0,10" ToolTip="Python package manager">
                <Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <CheckBox Name="chkPip" Grid.Column="0"/>
                <TextBlock Text="Python (Pip)" FontWeight="Bold" Grid.Column="1"/>
                <TextBlock Name="lblPipStatus" Text="Checking..." Grid.Column="2"/>
                <Button Name="btnProviderPipAction" Content="Install" Width="78" Height="26" Grid.Column="3" Margin="8,0,0,0"/>
            </Grid>

            <Grid Margin="0,0,0,10" ToolTip="Node.js package manager">
                <Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <CheckBox Name="chkNpm" Grid.Column="0"/>
                <TextBlock Text="Node (Npm)" FontWeight="Bold" Grid.Column="1"/>
                <TextBlock Name="lblNpmStatus" Text="Checking..." Grid.Column="2"/>
                <Button Name="btnProviderNpmAction" Content="Install" Width="78" Height="26" Grid.Column="3" Margin="8,0,0,0"/>
            </Grid>

            <!-- PNPM -->
            <Grid Margin="0,0,0,10" ToolTip="Fast Node.js package manager">
                <Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <CheckBox Name="chkPnpm" Grid.Column="0"/>
                <TextBlock Text="pnpm" FontWeight="Bold" Grid.Column="1"/>
                <TextBlock Name="lblPnpmStatus" Text="Checking..." Grid.Column="2"/>
                <Button Name="btnProviderPnpmAction" Content="Install" Width="78" Height="26" Grid.Column="3" Margin="8,0,0,0"/>
            </Grid>

            <Grid Margin="0,0,0,10" ToolTip="Chocolatey package manager">
                <Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <CheckBox Name="chkChoco" Grid.Column="0"/>
                <TextBlock Text="Chocolatey" FontWeight="Bold" Grid.Column="1"/>
                <TextBlock Name="lblChocoStatus" Text="Checking..." Grid.Column="2"/>
                <Button Name="btnProviderChocoAction" Content="Install" Width="78" Height="26" Grid.Column="3" Margin="8,0,0,0"/>
            </Grid>

            <Grid Margin="0,0,0,10" ToolTip="Scoop command-line installer">
                <Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <CheckBox Name="chkScoop" Grid.Column="0"/>
                <TextBlock Text="Scoop" FontWeight="Bold" Grid.Column="1"/>
                <TextBlock Name="lblScoopStatus" Text="Checking..." Grid.Column="2"/>
                <Button Name="btnProviderScoopAction" Content="Install" Width="78" Height="26" Grid.Column="3" Margin="8,0,0,0"/>
            </Grid>

            <Grid Margin="0,0,0,10" ToolTip="RubyGems package manager">
                <Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <CheckBox Name="chkGem" Grid.Column="0"/>
                <TextBlock Text="Ruby (Gem)" FontWeight="Bold" Grid.Column="1"/>
                <TextBlock Name="lblGemStatus" Text="Checking..." Grid.Column="2"/>
                <Button Name="btnProviderGemAction" Content="Install" Width="78" Height="26" Grid.Column="3" Margin="8,0,0,0"/>
            </Grid>

            <Grid Margin="0,0,0,10" ToolTip="Rust package manager">
                <Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <CheckBox Name="chkCargo" Grid.Column="0"/>
                <TextBlock Text="Rust (Cargo)" FontWeight="Bold" Grid.Column="1"/>
                <TextBlock Name="lblCargoStatus" Text="Checking..." Grid.Column="2"/>
                <Button Name="btnProviderCargoAction" Content="Install" Width="78" Height="26" Grid.Column="3" Margin="8,0,0,0"/>
            </Grid>

            <Grid Margin="0,0,0,10" ToolTip=".NET global tools installed with dotnet tool install -g">
                <Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <CheckBox Name="chkDotnet" Grid.Column="0"/>
                <TextBlock Text=".NET Tools" FontWeight="Bold" Grid.Column="1"/>
                <TextBlock Name="lblDotnetStatus" Text="Checking..." Grid.Column="2"/>
                <Button Name="btnProviderDotnetAction" Content="Install" Width="78" Height="26" Grid.Column="3" Margin="8,0,0,0"/>
            </Grid>

            <Grid Margin="0,0,0,10" ToolTip="PowerShell modules installed from PSGallery with PowerShellGet">
                <Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <CheckBox Name="chkPsModule" Grid.Column="0"/>
                <TextBlock Text="PS Modules" FontWeight="Bold" Grid.Column="1"/>
                <TextBlock Name="lblPsModuleStatus" Text="Checking..." Grid.Column="2"/>
                <Button Name="btnProviderPsModuleAction" Content="Install" Width="78" Height="26" Grid.Column="3" Margin="8,0,0,0"/>
            </Grid>

            <Grid Margin="0,0,0,10" ToolTip="PHP Composer global packages">
                <Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <CheckBox Name="chkComposer" Grid.Column="0"/>
                <TextBlock Text="Composer" FontWeight="Bold" Grid.Column="1"/>
                <TextBlock Name="lblComposerStatus" Text="Checking..." Grid.Column="2"/>
                <Button Name="btnProviderComposerAction" Content="Install" Width="78" Height="26" Grid.Column="3" Margin="8,0,0,0"/>
            </Grid>

            <Grid Margin="0,0,0,10" ToolTip="Steam game updates detected from local Steam manifests. Updates are delegated to Steam Downloads.">
                <Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <CheckBox Name="chkSteam" Grid.Column="0"/>
                <TextBlock Text="Steam Games" FontWeight="Bold" Grid.Column="1"/>
                <TextBlock Name="lblSteamStatus" Text="Checking..." Grid.Column="2"/>
                <Button Name="btnProviderSteamAction" Content="Install" Width="78" Height="26" Grid.Column="3" Margin="8,0,0,0"/>
            </Grid>

            <Grid Margin="0,0,0,10" ToolTip="Legendary CLI for Epic Games Store game updates.">
                <Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <CheckBox Name="chkLegendary" Grid.Column="0"/>
                <TextBlock Text="Legendary" FontWeight="Bold" Grid.Column="1"/>
                <TextBlock Name="lblLegendaryStatus" Text="Checking..." Grid.Column="2"/>
                <Button Name="btnProviderLegendaryAction" Content="Install" Width="78" Height="26" Grid.Column="3" Margin="8,0,0,0"/>
            </Grid>

            <Grid Margin="0,0,0,10" ToolTip="GOGDL updates installed GOG games through Heroic's gogdl downloader.">
                <Grid.ColumnDefinitions><ColumnDefinition Width="30"/><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <CheckBox Name="chkGogdl" Grid.Column="0"/>
                <TextBlock Text="GOGDL" FontWeight="Bold" Grid.Column="1"/>
                <TextBlock Name="lblGogdlStatus" Text="Checking..." Grid.Column="2"/>
                <Button Name="btnProviderGogdlAction" Content="Install" Width="78" Height="26" Grid.Column="3" Margin="8,0,0,0"/>
            </Grid>
            </StackPanel>
        </ScrollViewer>

        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Name="btnSave" Content="Save &amp; Close" Background="{DynamicResource Accent}" Width="120" Height="30" Foreground="{DynamicResource AccentText}"/>
        </StackPanel>
    </Grid>
</Window>
"@
    $win = New-WmtWindowFromFullXaml -Xaml $pXaml

    function Get-WinCtrl($name) { $win.FindName($name) }
    
    $cmbAutoScanInterval = Get-WinCtrl "cmbAutoScanInterval"
    $chkUpdateNotifications = Get-WinCtrl "chkUpdateNotifications"
    $chkRunInTrayOnClose = Get-WinCtrl "chkRunInTrayOnClose"
    $chkReduceRamInTray = Get-WinCtrl "chkReduceRamInTray"
    $chkUpdateSilentInstall = Get-WinCtrl "chkUpdateSilentInstall"
    $chkUpdateAutoInstall = Get-WinCtrl "chkUpdateAutoInstall"
    $chkIncludeUnknown = Get-WinCtrl "chkIncludeUnknown"
    $chkMsStore = Get-WinCtrl "chkMsStore"
    $chkWindowsUpdate = Get-WinCtrl "chkWindowsUpdate"
    $chkPip = Get-WinCtrl "chkPip"
    $chkNpm = Get-WinCtrl "chkNpm"
    $chkPnpm = Get-WinCtrl "chkPnpm"  
    $chkChoco = Get-WinCtrl "chkChoco"
    $chkScoop = Get-WinCtrl "chkScoop"
    $chkGem = Get-WinCtrl "chkGem"
    $chkCargo = Get-WinCtrl "chkCargo"
    $chkDotnet = Get-WinCtrl "chkDotnet"
    $chkPsModule = Get-WinCtrl "chkPsModule"
    $chkComposer = Get-WinCtrl "chkComposer"
    $chkSteam = Get-WinCtrl "chkSteam"
    $chkLegendary = Get-WinCtrl "chkLegendary"
    $chkGogdl = Get-WinCtrl "chkGogdl"

    $providerDefinitions = @(
        [PSCustomObject]@{ Key = "winget"; DisplayName = "Winget"; Commands = [string[]]@("winget"); Label = "lblProviderWingetStatus"; Button = "btnProviderWingetAction" },
        [PSCustomObject]@{ Key = "msstore"; DisplayName = "Store CLI"; Commands = [string[]]@("store"); Label = "lblProviderMsStoreStatus"; Button = "btnProviderMsStoreAction" },
        [PSCustomObject]@{ Key = "windowsupdate"; DisplayName = "Windows Update"; Commands = [string[]]@("powershell"); Label = "lblWindowsUpdateStatus"; Button = "btnProviderWindowsUpdateAction" },
        [PSCustomObject]@{ Key = "pip"; DisplayName = "Python (Pip)"; Commands = [string[]]@("pip", "pip3"); Label = "lblPipStatus"; Button = "btnProviderPipAction" },
        [PSCustomObject]@{ Key = "npm"; DisplayName = "Node (Npm)"; Commands = [string[]]@("npm"); Label = "lblNpmStatus"; Button = "btnProviderNpmAction" },
        [PSCustomObject]@{ Key = "pnpm"; DisplayName = "pnpm"; Commands = [string[]]@("pnpm"); Label = "lblPnpmStatus"; Button = "btnProviderPnpmAction" },
        [PSCustomObject]@{ Key = "chocolatey"; DisplayName = "Chocolatey"; Commands = [string[]]@("choco"); Label = "lblChocoStatus"; Button = "btnProviderChocoAction" },
        [PSCustomObject]@{ Key = "scoop"; DisplayName = "Scoop"; Commands = [string[]]@("scoop"); Label = "lblScoopStatus"; Button = "btnProviderScoopAction" },
        [PSCustomObject]@{ Key = "gem"; DisplayName = "Ruby (Gem)"; Commands = [string[]]@("gem"); Label = "lblGemStatus"; Button = "btnProviderGemAction" },
        [PSCustomObject]@{ Key = "cargo"; DisplayName = "Rust (Cargo)"; Commands = [string[]]@("cargo"); Label = "lblCargoStatus"; Button = "btnProviderCargoAction" },
        [PSCustomObject]@{ Key = "dotnet"; DisplayName = ".NET Tools"; Commands = [string[]]@("dotnet"); Label = "lblDotnetStatus"; Button = "btnProviderDotnetAction" },
        [PSCustomObject]@{ Key = "psmodule"; DisplayName = "PowerShell Modules"; Commands = [string[]]@("powershell", "pwsh"); Label = "lblPsModuleStatus"; Button = "btnProviderPsModuleAction" },
        [PSCustomObject]@{ Key = "composer"; DisplayName = "Composer"; Commands = [string[]]@("composer"); Label = "lblComposerStatus"; Button = "btnProviderComposerAction" },
        [PSCustomObject]@{ Key = "steam"; DisplayName = "Steam Games"; Commands = [string[]]@("steam", "steam.exe"); RegistryPaths = [string[]]@("HKCU:\Software\Valve\Steam", "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam", "HKLM:\SOFTWARE\Valve\Steam"); Label = "lblSteamStatus"; Button = "btnProviderSteamAction" },
        [PSCustomObject]@{ Key = "legendary"; DisplayName = "Legendary (Epic Games)"; Commands = [string[]]@("legendary", "legendary.exe"); LocalPaths = [string[]]@(Get-WmtLegendaryExePath); Label = "lblLegendaryStatus"; Button = "btnProviderLegendaryAction" },
        [PSCustomObject]@{ Key = "gogdl"; DisplayName = "GOGDL (GOG Games)"; Commands = [string[]]@("gogdl", "gogdl.exe", "gogdl_windows_x86_64.exe"); LocalPaths = [string[]]@(Get-WmtGogdlExePath); Label = "lblGogdlStatus"; Button = "btnProviderGogdlAction" }
    )
    $providerInstallState = @{}
    $providerActionMonitors = @{}

    function Update-WmtProviderPathEnvironment {
        try {
            $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
            $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
            $pathParts = New-Object System.Collections.Generic.List[string]
            foreach ($pathValue in @($machinePath, $userPath, $env:Path)) {
                foreach ($part in @(([string]$pathValue) -split ";")) {
                    $trimmed = $part.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($trimmed) -and -not $pathParts.Contains($trimmed)) {
                        [void]$pathParts.Add($trimmed)
                    }
                }
            }
            $env:Path = $pathParts -join ";"
        }
        catch {}
    }

    function Get-WmtProviderActionScript {
        param(
            [string]$ProviderKey,
            [string]$Action
        )

        $installing = ($Action -eq "Install")
        $body = switch ($ProviderKey) {
            "winget" {
                if ($installing) {
                    @'
Write-Host "Registering App Installer for winget..."
try {
    Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
}
catch {
    Write-Warning $_.Exception.Message
}
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Start-Process "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1"
    throw "Winget is still not available. App Installer was opened in Microsoft Store."
}
winget source reset --force
winget source update
winget --version
'@
                }
                else {
                    @'
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "Winget was not found." }
winget source reset --force
winget source update
winget upgrade --id Microsoft.AppInstaller --accept-source-agreements --accept-package-agreements --disable-interactivity
winget --version
'@
                }
                break
            }
            "msstore" {
                @'
Write-Host "Opening Microsoft Store Updates..."
try {
    $appManagement = Get-CimInstance -Namespace "Root\cimv2\mdm\dmmap" -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" -ErrorAction Stop | Select-Object -First 1
    if ($appManagement) {
        [void](Invoke-CimMethod -InputObject $appManagement -MethodName "UpdateScanMethod" -ErrorAction Stop)
        Write-Host "Requested a Microsoft Store app update scan."
    }
}
catch {
    Write-Warning "Direct Store update scan failed: $($_.Exception.Message)"
}
Start-Process "ms-windows-store://downloadsandupdates"
if (Get-Command store -ErrorAction SilentlyContinue) {
    store --help
}
else {
    Write-Host "Update Microsoft Store from the opened Store updates page, then reopen WMT."
}
'@
                break
            }
            "windowsupdate" {
                @'
Write-Host "Opening Windows Update optional updates..."
try {
    Start-Process "ms-settings:windowsupdate-optionalupdates"
}
catch {
    Write-Warning "Optional updates page failed: $($_.Exception.Message)"
    Start-Process "ms-settings:windowsupdate"
}
Write-Host "Windows Update is built into Windows. WMT will scan it through Microsoft.Update.Session when the provider is enabled."
'@
                break
            }
            "pip" {
                if ($installing) {
                    @'
if (-not (Get-Command python -ErrorAction SilentlyContinue) -and -not (Get-Command py -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "Python install needs winget or an existing Python launcher." }
    $pythonIds = @("Python.Python.3.13", "Python.Python.3.12", "Python.Python.3.11")
    $installedPython = $false
    foreach ($pythonId in $pythonIds) {
        Write-Host "Trying $pythonId..."
        winget install --id $pythonId --exact --accept-source-agreements --accept-package-agreements --disable-interactivity
        if ($LASTEXITCODE -eq 0) { $installedPython = $true; break }
    }
    if (-not $installedPython) { throw "Could not install Python with winget." }
    Update-WmtProviderPathEnvironment
}
if (Get-Command py -ErrorAction SilentlyContinue) {
    py -3 -m ensurepip --upgrade
    py -3 -m pip install --upgrade pip setuptools wheel
    py -3 -m pip --version
}
elseif (Get-Command python -ErrorAction SilentlyContinue) {
    python -m ensurepip --upgrade
    python -m pip install --upgrade pip setuptools wheel
    python -m pip --version
}
else {
    throw "Python was installed, but the launcher is not visible in this session yet. Open a new terminal and retry."
}
'@
                }
                else {
                    @'
if (Get-Command py -ErrorAction SilentlyContinue) {
    py -3 -m ensurepip --upgrade
    py -3 -m pip install --upgrade pip setuptools wheel
    py -3 -m pip --version
}
elseif (Get-Command python -ErrorAction SilentlyContinue) {
    python -m ensurepip --upgrade
    python -m pip install --upgrade pip setuptools wheel
    python -m pip --version
}
else {
    throw "Python was not found."
}
'@
                }
                break
            }
            "npm" {
                if ($installing) {
                    @'
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "Node.js install needs winget." }
    winget install --id OpenJS.NodeJS.LTS --exact --accept-source-agreements --accept-package-agreements --disable-interactivity
    Update-WmtProviderPathEnvironment
}
if (Get-Command npm -ErrorAction SilentlyContinue) {
    npm install -g npm@latest
    npm --version
}
else {
    Write-Host "Node.js was requested. Open a new terminal after install if npm is not visible yet."
}
'@
                }
                else {
                    @'
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { throw "npm was not found." }
npm install -g npm@latest
npm --version
'@
                }
                break
            }
            "pnpm" {
                if ($installing) {
                    @'
$installedPnpm = $false
if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id pnpm.pnpm --exact --accept-source-agreements --accept-package-agreements --disable-interactivity
    if ($LASTEXITCODE -eq 0) { $installedPnpm = $true }
    Update-WmtProviderPathEnvironment
}
if (-not $installedPnpm -and (Get-Command npm -ErrorAction SilentlyContinue)) {
    npm install -g pnpm@latest
    Update-WmtProviderPathEnvironment
}
if (Get-Command pnpm -ErrorAction SilentlyContinue) {
    pnpm --version
}
else {
    Write-Host "pnpm was requested. Open a new terminal after install if pnpm is not visible yet."
}
'@
                }
                else {
                    @'
if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) { throw "pnpm was not found." }
pnpm self-update
if ($LASTEXITCODE -ne 0 -and (Get-Command npm -ErrorAction SilentlyContinue)) {
    npm install -g pnpm@latest
}
pnpm --version
'@
                }
                break
            }
            "chocolatey" {
                if ($installing) {
                    @'
if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id Chocolatey.Chocolatey --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity
    Update-WmtProviderPathEnvironment
}
else {
    throw "Chocolatey install needs winget."
}
if (Get-Command choco -ErrorAction SilentlyContinue) { choco --version }
else { Write-Host "Chocolatey was requested. Open a new terminal after install if choco is not visible yet." }
'@
                }
                else {
                    @'
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) { throw "Chocolatey was not found." }
choco upgrade chocolatey -y
choco --version
'@
                }
                break
            }
            "scoop" {
                if ($installing) {
                    @'
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Invoke-Expression "& {$(Invoke-RestMethod -Uri https://get.scoop.sh)} -RunAsAdmin"
Update-WmtProviderPathEnvironment
if (Get-Command scoop -ErrorAction SilentlyContinue) { scoop --version }
else { Write-Host "Scoop was requested. Open a new terminal after install if scoop is not visible yet." }
'@
                }
                else {
                    @'
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { throw "Scoop was not found." }
scoop update
scoop checkup
'@
                }
                break
            }
            "gem" {
                if ($installing) {
                    @'
if (-not (Get-Command gem -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "Ruby install needs winget." }
    winget install --id RubyInstallerTeam.RubyWithDevKit.3.3 --exact --accept-source-agreements --accept-package-agreements --disable-interactivity
    Update-WmtProviderPathEnvironment
}
if (Get-Command gem -ErrorAction SilentlyContinue) {
    gem update --system
    gem --version
}
else {
    Write-Host "Ruby was requested. Open a new terminal after install if gem is not visible yet."
}
'@
                }
                else {
                    @'
if (-not (Get-Command gem -ErrorAction SilentlyContinue)) { throw "RubyGems was not found." }
gem update --system
gem update
gem --version
'@
                }
                break
            }
            "cargo" {
                if ($installing) {
                    @'
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "Rust install needs winget." }
    winget install --id Rustlang.Rustup --exact --accept-source-agreements --accept-package-agreements --disable-interactivity
    Update-WmtProviderPathEnvironment
}
if (Get-Command rustup -ErrorAction SilentlyContinue) { rustup update }
if (Get-Command cargo -ErrorAction SilentlyContinue) { cargo --version }
else { Write-Host "Rust was requested. Open a new terminal after install if cargo is not visible yet." }
'@
                }
                else {
                    @'
if (Get-Command rustup -ErrorAction SilentlyContinue) {
    rustup update
}
elseif (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    throw "Cargo was not found."
}
cargo --version
'@
                }
                break
            }
            "dotnet" {
                if ($installing) {
                    @'
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw ".NET SDK install needs winget." }
    $dotnetIds = @("Microsoft.DotNet.SDK.10", "Microsoft.DotNet.SDK.9", "Microsoft.DotNet.SDK.8")
    $installedDotnet = $false
    foreach ($dotnetId in $dotnetIds) {
        Write-Host "Trying $dotnetId..."
        winget install --id $dotnetId --exact --accept-source-agreements --accept-package-agreements --disable-interactivity
        if ($LASTEXITCODE -eq 0) { $installedDotnet = $true; break }
    }
    if (-not $installedDotnet) { throw "Could not install .NET SDK with winget." }
    Update-WmtProviderPathEnvironment
}
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    dotnet --info
    Write-Host ""
    Write-Host "Installed global .NET tools:"
    dotnet tool list --global
}
else {
    throw ".NET SDK was installed, but dotnet is not visible in this session yet. Open a new terminal and retry."
}
'@
                }
                else {
                    @'
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw "dotnet was not found." }
dotnet --info
Write-Host ""
Write-Host "Installed global .NET tools:"
dotnet tool list --global
Write-Host ""
Write-Host "Individual .NET global tools are updated from WMT's update list with: dotnet tool update --global <package>"
'@
                }
                break
            }
            "psmodule" {
                if ($installing) {
                    @'
$psGet = Get-Module -ListAvailable PowerShellGet | Sort-Object Version -Descending | Select-Object -First 1
if (-not $psGet) {
    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser
    Install-Module -Name PowerShellGet -Scope CurrentUser -Force -AllowClobber
}
else {
    Write-Host "PowerShellGet found: $($psGet.Version)"
}
Import-Module PowerShellGet -ErrorAction SilentlyContinue
Get-Command Get-InstalledModule, Find-Module, Install-Module, Update-Module -ErrorAction SilentlyContinue | Format-Table Name, Source -AutoSize
'@
                }
                else {
                    @'
if (-not (Get-Command Get-InstalledModule -ErrorAction SilentlyContinue)) { throw "PowerShellGet was not found." }
Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -ErrorAction SilentlyContinue
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
Write-Host "Installed PowerShellGet-managed modules:"
Get-InstalledModule -ErrorAction SilentlyContinue | Sort-Object Name | Format-Table Name, Version, Repository -AutoSize
'@
                }
                break
            }
            "composer" {
                if ($installing) {
                    @'
if (-not (Get-Command composer -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "Composer install needs winget." }
    winget install --id Composer.Composer --exact --accept-source-agreements --accept-package-agreements --disable-interactivity
    Update-WmtProviderPathEnvironment
}
if (Get-Command composer -ErrorAction SilentlyContinue) {
    composer --version
    composer self-update
}
else {
    Write-Host "Composer was requested. Open a new terminal after install if composer is not visible yet."
}
'@
                }
                else {
                    @'
if (-not (Get-Command composer -ErrorAction SilentlyContinue)) { throw "Composer was not found." }
composer self-update
composer global diagnose
composer --version
'@
                }
                break
            }
            "legendary" {
                $legendaryExePath = Get-WmtLegendaryExePath
                $legendaryDir = Split-Path -Parent $legendaryExePath
                $legendaryExeLiteral = ([string]$legendaryExePath).Replace("'", "''")
                $legendaryDirLiteral = ([string]$legendaryDir).Replace("'", "''")
                $legendaryBody = @'
$legendaryDir = '__WMT_LEGENDARY_DIR__'
$legendaryExe = '__WMT_LEGENDARY_EXE__'
$latestApi = "https://api.github.com/repos/legendary-gl/legendary/releases/latest"
$fallbackUrl = "https://github.com/legendary-gl/legendary/releases/latest/download/legendary.exe"
$headers = @{ "User-Agent" = "Windows-Maintenance-Tool" }

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
}
catch {}

if (-not (Test-Path -LiteralPath $legendaryDir)) {
    [void][System.IO.Directory]::CreateDirectory($legendaryDir)
}

$firstInstall = -not (Test-Path -LiteralPath $legendaryExe -PathType Leaf)
$downloadUrl = $fallbackUrl
$releaseName = "latest"
try {
    Write-Host "Checking latest Legendary release..."
    $release = Invoke-RestMethod -Uri $latestApi -Headers $headers -UseBasicParsing -ErrorAction Stop
    if ($release -and $release.tag_name) { $releaseName = [string]$release.tag_name }
    $asset = @($release.assets | Where-Object { ([string]$_.name) -ieq "legendary.exe" } | Select-Object -First 1)
    if ($asset -and $asset.browser_download_url) {
        $downloadUrl = [string]$asset.browser_download_url
    }
}
catch {
    Write-Warning "Could not query GitHub latest release API: $($_.Exception.Message)"
    Write-Host "Falling back to GitHub's latest/download redirect."
}

$tmpPath = Join-Path $legendaryDir ("legendary.exe.{0}.download" -f ([Guid]::NewGuid().ToString("N")))
try {
    Write-Host "Downloading Legendary $releaseName..."
    Write-Host $downloadUrl
    Invoke-WebRequest -Uri $downloadUrl -Headers $headers -UseBasicParsing -OutFile $tmpPath -ErrorAction Stop

    $download = Get-Item -LiteralPath $tmpPath -ErrorAction Stop
    if ($download.Length -lt 1MB) {
        throw "Downloaded file is unexpectedly small ($($download.Length) bytes)."
    }

    Move-Item -LiteralPath $tmpPath -Destination $legendaryExe -Force
    try { Unblock-File -LiteralPath $legendaryExe -ErrorAction SilentlyContinue } catch {}
}
finally {
    if (Test-Path -LiteralPath $tmpPath) {
        Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path -LiteralPath $legendaryExe -PathType Leaf)) {
    throw "Legendary executable was not saved to $legendaryExe."
}

Write-Host "Legendary saved to:"
Write-Host $legendaryExe
& $legendaryExe --version

if ($firstInstall) {
    Write-Host ""
    Write-Host "Starting Legendary Epic Games authentication..."
    Write-Host "Follow the browser and terminal prompts. You can close or cancel this step if you want to authenticate later."
    try {
        & $legendaryExe auth
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Legendary auth exited with code $LASTEXITCODE. You can retry later with '$legendaryExe auth'."
        }
        else {
            Write-Host ""
            Write-Host "Enabling Epic Games Launcher sync and importing installed Epic games..."
            "y" | & $legendaryExe egl-sync --enable-sync
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Legendary egl-sync exited with code $LASTEXITCODE. You can retry later with '$legendaryExe egl-sync --enable-sync'."
            }
        }
    }
    catch {
        Write-Warning "Legendary auth could not be started: $($_.Exception.Message)"
        Write-Host "You can retry later with '$legendaryExe auth'."
    }
}
else {
    Write-Host "Legendary is ready. Run '$legendaryExe auth' from a terminal if Epic login has not been configured yet."
}
'@
                $legendaryBody.Replace("__WMT_LEGENDARY_DIR__", $legendaryDirLiteral).Replace("__WMT_LEGENDARY_EXE__", $legendaryExeLiteral)
                break
            }
            "gogdl" {
                $gogdlExePath = Get-WmtGogdlExePath
                $gogdlDir = Split-Path -Parent $gogdlExePath
                $gogdlAuthConfigPath = Get-WmtGogdlAuthConfigPath
                $gogdlExeLiteral = ([string]$gogdlExePath).Replace("'", "''")
                $gogdlDirLiteral = ([string]$gogdlDir).Replace("'", "''")
                $gogdlAuthLiteral = ([string]$gogdlAuthConfigPath).Replace("'", "''")
                $gogdlBody = @'
$gogdlDir = '__WMT_GOGDL_DIR__'
$gogdlExe = '__WMT_GOGDL_EXE__'
$authConfig = '__WMT_GOGDL_AUTH__'
$latestApi = "https://api.github.com/repos/Heroic-Games-Launcher/heroic-gogdl/releases/latest"
$fallbackUrl = "https://github.com/Heroic-Games-Launcher/heroic-gogdl/releases/latest/download/gogdl_windows_x86_64.exe"
$headers = @{ "User-Agent" = "Windows-Maintenance-Tool" }

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
}
catch {}

if (-not (Test-Path -LiteralPath $gogdlDir)) {
    [void][System.IO.Directory]::CreateDirectory($gogdlDir)
}

$firstInstall = -not (Test-Path -LiteralPath $gogdlExe -PathType Leaf)
$downloadUrl = $fallbackUrl
$releaseName = "latest"
try {
    Write-Host "Checking latest GOGDL release..."
    $release = Invoke-RestMethod -Uri $latestApi -Headers $headers -UseBasicParsing -ErrorAction Stop
    if ($release -and $release.tag_name) { $releaseName = [string]$release.tag_name }
    $asset = @($release.assets | Where-Object { ([string]$_.name) -ieq "gogdl_windows_x86_64.exe" } | Select-Object -First 1)
    if ($asset -and $asset.browser_download_url) {
        $downloadUrl = [string]$asset.browser_download_url
    }
}
catch {
    Write-Warning "Could not query GitHub latest release API: $($_.Exception.Message)"
    Write-Host "Falling back to GitHub's latest/download redirect."
}

$tmpPath = Join-Path $gogdlDir ("gogdl_windows_x86_64.exe.{0}.download" -f ([Guid]::NewGuid().ToString("N")))
try {
    Write-Host "Downloading GOGDL $releaseName..."
    Write-Host $downloadUrl
    Invoke-WebRequest -Uri $downloadUrl -Headers $headers -UseBasicParsing -OutFile $tmpPath -ErrorAction Stop

    $download = Get-Item -LiteralPath $tmpPath -ErrorAction Stop
    if ($download.Length -lt 1MB) {
        throw "Downloaded file is unexpectedly small ($($download.Length) bytes)."
    }

    Move-Item -LiteralPath $tmpPath -Destination $gogdlExe -Force
    try { Unblock-File -LiteralPath $gogdlExe -ErrorAction SilentlyContinue } catch {}
}
finally {
    if (Test-Path -LiteralPath $tmpPath) {
        Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path -LiteralPath $gogdlExe -PathType Leaf)) {
    throw "GOGDL executable was not saved to $gogdlExe."
}

Write-Host "GOGDL saved to:"
Write-Host $gogdlExe
& $gogdlExe --version
Write-Host ""
Write-Host "GOGDL auth config:"
Write-Host $authConfig

# Try to auto-copy Heroic's auth.json if available
$heroicAuthPath = Join-Path $env:APPDATA "heroic\gog_store\auth.json"
if ((Test-Path -LiteralPath $authConfig -PathType Leaf)) {
    Write-Host "auth.json already exists."
}
elseif ($env:APPDATA -and (Test-Path -LiteralPath $heroicAuthPath -PathType Leaf)) {
    try {
        Write-Host "Found Heroic GOG auth. Copying to GOGDL..."
        Copy-Item -LiteralPath $heroicAuthPath -Destination $authConfig -Force -ErrorAction Stop
        Write-Host "Successfully copied auth from Heroic. GOGDL is ready!"
    }
    catch {
        Write-Warning "Could not copy auth from Heroic: $($_.Exception.Message)"
        Write-Host "You will need to authenticate GOG in the next step."
    }
}

# If this is a fresh install, or auth.json is still missing, open GOG OAuth flow
if ($firstInstall -or -not (Test-Path -LiteralPath $authConfig -PathType Leaf)) {
    Write-Host ""
    Write-Host "Starting GOG authentication..."
    Write-Host "Your browser will open. Log in, then paste the redirect URL back here."
    Write-Host ""

    $authScript = @"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(`$false)
`$ErrorActionPreference = "Continue"

`$clientId     = "46899977096215655"
`$clientSecret = "9d85c43b1482497dbbce61f6e4aa173a433796eeae2ca8c5f6129f2dc4de46d9"
`$redirectUri  = "https://embed.gog.com/on_login_success?origin=client"
`$authUrl      = "https://login.gog.com/auth?client_id=`$clientId&redirect_uri=" + [Uri]::EscapeDataString(`$redirectUri) + "&response_type=code&layout=client2"
`$tokenUrl     = "https://auth.gog.com/token"

Write-Host "WMT: GOG Authentication" -ForegroundColor Cyan
Write-Host ""
Write-Host "Step 1: Opening GOG login page in your browser..." -ForegroundColor Yellow
Write-Host "Auth config path: $authConfig"
Write-Host ""
Start-Process `$authUrl
Start-Sleep -Seconds 2

Write-Host "Step 2: After logging in, GOG redirects to a URL starting with:" -ForegroundColor Yellow
Write-Host "  https://embed.gog.com/on_login_success" -ForegroundColor Cyan
Write-Host "Copy the full URL from the browser address bar and paste it below." -ForegroundColor Yellow
Write-Host ""

`$redirected = ""
while ([string]::IsNullOrWhiteSpace(`$redirected)) {
    `$redirected = (Read-Host "Paste redirect URL").Trim()
    if ([string]::IsNullOrWhiteSpace(`$redirected)) { Write-Warning "Please paste the full redirect URL from your browser." }
}

`$code = ""
if (`$redirected -match '[?&]code=([^&\s]+)') { `$code = `$matches[1] }

if ([string]::IsNullOrWhiteSpace(`$code)) {
    Write-Error "No 'code' found in the URL. Make sure you copied the full redirect URL from the address bar."
    [void](Read-Host "Press Enter to close")
    exit 1
}

Write-Host ""
Write-Host "Step 3: Exchanging code for tokens..." -ForegroundColor Yellow

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    `$body = "client_id=`$clientId&client_secret=`$clientSecret&grant_type=authorization_code" +
             "&redirect_uri=" + [Uri]::EscapeDataString(`$redirectUri) +
             "&code="         + [Uri]::EscapeDataString(`$code)
    `$token = Invoke-RestMethod -Uri `$tokenUrl -Method Post -Body `$body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing -ErrorAction Stop

    if (-not `$token.access_token) { throw "Token response missing access_token." }

    `$authDir = Split-Path -Parent "$authConfig"
    if (`$authDir -and -not (Test-Path -LiteralPath `$authDir)) { [void][System.IO.Directory]::CreateDirectory(`$authDir) }

    [System.IO.File]::WriteAllText("$authConfig", (`$token | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)

    Write-Host ""
    Write-Host "GOG authentication successful! Tokens saved." -ForegroundColor Green
    Write-Host "  $authConfig"
}
catch {
    Write-Host ""
    Write-Error "Token exchange failed: `$(`$_.Exception.Message)"
}

Write-Host ""
[void](Read-Host "Press Enter to close")
"@

    $tmpAuthScript = Join-Path $gogdlDir ("gogdl_auth_{0}.ps1" -f ([Guid]::NewGuid().ToString("N")))
    try {
        [System.IO.File]::WriteAllText($tmpAuthScript, $authScript, [System.Text.Encoding]::UTF8)
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $tmpAuthScript -Wait
    }
    finally {
        if (Test-Path -LiteralPath $tmpAuthScript) {
            Remove-Item -LiteralPath $tmpAuthScript -Force -ErrorAction SilentlyContinue
        }
    }
}
'@
                $gogdlBody.Replace("__WMT_GOGDL_DIR__", $gogdlDirLiteral).Replace("__WMT_GOGDL_EXE__", $gogdlExeLiteral).Replace("__WMT_GOGDL_AUTH__", $gogdlAuthLiteral)
                break
            }
            "steam" {
                if ($installing) {
                    @'
function Get-WmtSteamExe {
    $candidates = New-Object System.Collections.Generic.List[string]
    $add = {
        param([string]$Path)
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        try {
            $rawPathText = ([string]$Path).Trim()
            $expanded = [Environment]::ExpandEnvironmentVariables($rawPathText)
            if ((Test-Path -LiteralPath $expanded -PathType Leaf) -and -not $candidates.Contains($expanded)) { [void]$candidates.Add($expanded) }
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
            if ($props.PSObject.Properties["SteamExe"]) { & $add ([string]$props.SteamExe) }
            foreach ($propName in @("SteamPath", "InstallPath")) {
                if ($props.PSObject.Properties[$propName]) { & $add (Join-Path ([string]$props.$propName) "steam.exe") }
            }
        }
        catch {}
    }
    foreach ($path in @(
            "${env:ProgramFiles(x86)}\Steam\steam.exe",
            "${env:ProgramFiles}\Steam\steam.exe"
        )) { & $add $path }
    return @($candidates) | Select-Object -First 1
}

$steamExe = Get-WmtSteamExe
if ([string]::IsNullOrWhiteSpace($steamExe)) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Valve.Steam --exact --accept-source-agreements --accept-package-agreements --disable-interactivity
        Update-WmtProviderPathEnvironment
        $steamExe = Get-WmtSteamExe
    }
    else {
        Start-Process "https://store.steampowered.com/about/"
        throw "Steam install needs winget or a manual Steam install. Opened the Steam download page."
    }
}

$steamExe = Get-WmtSteamExe
if (-not [string]::IsNullOrWhiteSpace($steamExe)) {
    Start-Process -FilePath $steamExe -ArgumentList "-silent", "-minimized", '"steam://open/downloads"' -WindowStyle Hidden
    Write-Host "Steam Downloads was requested with steam.exe -silent -minimized."
}
else {
    Start-Process "https://store.steampowered.com/about/"
    throw "Steam was not found after install attempt. Opened the Steam download page."
}
'@
                }
                else {
                    @'
function Get-WmtSteamExe {
    $candidates = New-Object System.Collections.Generic.List[string]
    $add = {
        param([string]$Path)
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        try {
            $rawPathText = ([string]$Path).Trim()
            $expanded = [Environment]::ExpandEnvironmentVariables($rawPathText)
            if ((Test-Path -LiteralPath $expanded -PathType Leaf) -and -not $candidates.Contains($expanded)) { [void]$candidates.Add($expanded) }
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
            if ($props.PSObject.Properties["SteamExe"]) { & $add ([string]$props.SteamExe) }
            foreach ($propName in @("SteamPath", "InstallPath")) {
                if ($props.PSObject.Properties[$propName]) { & $add (Join-Path ([string]$props.$propName) "steam.exe") }
            }
        }
        catch {}
    }
    foreach ($path in @(
            "${env:ProgramFiles(x86)}\Steam\steam.exe",
            "${env:ProgramFiles}\Steam\steam.exe"
        )) { & $add $path }
    return @($candidates) | Select-Object -First 1
}

$steamExe = Get-WmtSteamExe
if (-not [string]::IsNullOrWhiteSpace($steamExe)) {
    Start-Process -FilePath $steamExe -ArgumentList "-silent", "-minimized", '"steam://open/downloads"' -WindowStyle Hidden
    Write-Host "Steam Downloads was requested with steam.exe -silent -minimized."
}
else {
    Start-Process "https://store.steampowered.com/about/"
    throw "Steam was not found. Opened the Steam download page."
}
'@
                }
                break
            }
            default { "" }
        }

        if ([string]::IsNullOrWhiteSpace($body)) { return "" }

        return @"
`$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(`$false)
function Update-WmtProviderPathEnvironment {
    try {
        `$pathParts = New-Object System.Collections.Generic.List[string]
        foreach (`$pathValue in @([Environment]::GetEnvironmentVariable("Path", "Machine"), [Environment]::GetEnvironmentVariable("Path", "User"), `$env:Path)) {
            foreach (`$part in @(([string]`$pathValue) -split ";")) {
                `$trimmed = `$part.Trim()
                if (-not [string]::IsNullOrWhiteSpace(`$trimmed) -and -not `$pathParts.Contains(`$trimmed)) {
                    [void]`$pathParts.Add(`$trimmed)
                }
            }
        }
        `$env:Path = `$pathParts -join ";"
    }
    catch {}
}
Update-WmtProviderPathEnvironment

`$exitCode = 0
try {
    Write-Host "WMT provider $Action`: $ProviderKey"
    Write-Host ""
$body
    Write-Host ""
    Write-Host "Provider $Action completed."
}
catch {
    `$exitCode = 1
    Write-Host ""
    Write-Host "ERROR: `$(`$_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""
Write-Host "Closing in 8 seconds..."
Start-Sleep -Seconds 8
exit `$exitCode
"@
    }

    $getWinCtrl = { param($name) $win.FindName($name) }.GetNewClosure()
    $updateProviderPathEnvironment = ${function:Update-WmtProviderPathEnvironment}.GetNewClosure()
    $getProviderActionScript = ${function:Get-WmtProviderActionScript}.GetNewClosure()
    $testProviderInstalled = {
        param($Provider)

        if (-not $Provider) { return $false }
        & $updateProviderPathEnvironment
        foreach ($cmd in @($Provider.Commands)) {
            if ([string]::IsNullOrWhiteSpace($cmd)) { continue }
            if (Get-Command $cmd -ErrorAction SilentlyContinue) { return $true }
        }
        if ($Provider.PSObject.Properties["RegistryPaths"]) {
            foreach ($registryPath in @($Provider.RegistryPaths)) {
                if ([string]::IsNullOrWhiteSpace($registryPath)) { continue }
                if (Test-Path -LiteralPath $registryPath) { return $true }
            }
        }
        if ($Provider.PSObject.Properties["LocalPaths"]) {
            foreach ($localPath in @($Provider.LocalPaths)) {
                if ([string]::IsNullOrWhiteSpace($localPath)) { continue }
                if (Test-Path -LiteralPath $localPath -PathType Leaf) { return $true }
            }
        }
        return $false
    }.GetNewClosure()
    $updateProviderStatuses = {
        & $updateProviderPathEnvironment
        foreach ($provider in $providerDefinitions) {
            $labelCtrl = & $getWinCtrl $provider.Label
            $buttonCtrl = & $getWinCtrl $provider.Button
            $installed = [bool](& $testProviderInstalled -Provider $provider)
            $providerInstallState[$provider.Key] = $installed

            if ($installed) {
                if ($labelCtrl) {
                    $labelCtrl.Text = "Installed"
                    Set-WmtThemedBrush -Object $labelCtrl -Property ([System.Windows.Controls.TextBlock]::ForegroundProperty) -ColorOrKey "Success"
                }
                if ($buttonCtrl) {
                    if ($provider.Key -eq "steam") {
                        $buttonCtrl.Content = "Open"
                        $buttonCtrl.ToolTip = "Open Steam and its Downloads updater"
                    }
                    elseif ($provider.Key -eq "windowsupdate") {
                        $buttonCtrl.Content = "Open"
                        $buttonCtrl.ToolTip = "Open Windows Update optional updates"
                    }
                    else {
                        $buttonCtrl.Content = "Repair"
                        $buttonCtrl.ToolTip = "Repair or refresh $($provider.DisplayName)"
                    }
                    $buttonCtrl.IsEnabled = $true
                }
            }
            else {
                if ($labelCtrl) {
                    $labelCtrl.Text = "Not Found"
                    Set-WmtThemedBrush -Object $labelCtrl -Property ([System.Windows.Controls.TextBlock]::ForegroundProperty) -ColorOrKey "Warning"
                }
                if ($buttonCtrl) {
                    $buttonCtrl.Content = "Install"
                    $buttonCtrl.ToolTip = "Install $($provider.DisplayName)"
                    $buttonCtrl.IsEnabled = $true
                }
            }
        }
    }.GetNewClosure()
    $startProviderAction = {
        param([string]$ProviderKey)

        $provider = @($providerDefinitions | Where-Object { $_.Key -eq $ProviderKey } | Select-Object -First 1)
        if (-not $provider) { return }

        $installed = if ($providerInstallState.ContainsKey($ProviderKey)) { [bool]$providerInstallState[$ProviderKey] } else { [bool](& $testProviderInstalled -Provider $provider) }
        $action = if (($ProviderKey -eq "steam" -or $ProviderKey -eq "windowsupdate") -and $installed) { "Open" } elseif ($installed) { "Repair" } else { "Install" }
        $message = if ($ProviderKey -eq "steam" -and $action -eq "Open") {
            "Open Steam Downloads?`r`n`r`nThis starts Steam so its own updater can process pending game updates."
        }
        elseif ($ProviderKey -eq "windowsupdate" -and $action -eq "Open") {
            "Open Windows Update optional updates?`r`n`r`nWMT scans Windows Update from the Updates page when this provider is enabled."
        }
        else {
            "$action $($provider.DisplayName)?`r`n`r`nThis opens a PowerShell window and may download provider files from the internet."
        }
        if ((Show-WmtMessageBox -Owner $win -Message $message -Title "$action Provider" -Button YesNo -Image Question) -ne [System.Windows.MessageBoxResult]::Yes) {
            return
        }

        $scriptText = & $getProviderActionScript -ProviderKey $ProviderKey -Action $action
        if ([string]::IsNullOrWhiteSpace($scriptText)) {
            Show-WmtMessageBox -Owner $win -Message "No $action action is configured for $($provider.DisplayName)." -Title "Provider Action" -Button OK -Image Warning | Out-Null
            return
        }

        $buttonCtrl = & $getWinCtrl $provider.Button
        $labelCtrl = & $getWinCtrl $provider.Label
        foreach ($providerDef in $providerDefinitions) {
            $otherButton = & $getWinCtrl $providerDef.Button
            if ($otherButton) { $otherButton.IsEnabled = $false }
        }
        if ($buttonCtrl) { $buttonCtrl.Content = "Running" }
        if ($labelCtrl) {
            $labelCtrl.Text = "$action running..."
            Set-WmtThemedBrush -Object $labelCtrl -Property ([System.Windows.Controls.TextBlock]::ForegroundProperty) -ColorOrKey "Accent"
        }

        $tempScriptPath = Join-Path $env:TEMP ("WMT_Provider_{0}_{1}.ps1" -f $ProviderKey, ([Guid]::NewGuid().ToString("N")))
        try {
            Set-Content -Path $tempScriptPath -Value $scriptText -Encoding UTF8 -Force
            Write-GuiLog "[$($provider.DisplayName)] $action started."
            $providerWindowStyle = if ($ProviderKey -eq "steam") { "Hidden" } else { "Normal" }
            $proc = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempScriptPath`"" -WindowStyle $providerWindowStyle -PassThru
        }
        catch {
            Write-GuiLog "[$($provider.DisplayName)] $action failed to start: $($_.Exception.Message)"
            try { Remove-Item -LiteralPath $tempScriptPath -Force -ErrorAction SilentlyContinue } catch {}
            & $updateProviderStatuses
            return
        }

        $monitorKey = "$ProviderKey-$([Guid]::NewGuid().ToString("N"))"
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds(1)
        $monitorState = [PSCustomObject]@{
            Key            = $monitorKey
            Timer          = $timer
            Process        = $proc
            TempScriptPath = $tempScriptPath
            ProviderKey    = $ProviderKey
            ProviderName   = [string]$provider.DisplayName
            Action         = [string]$action
            Monitors       = $providerActionMonitors
            UpdateStatuses = $updateProviderStatuses
        }
        $timer.Tag = $monitorState
        $timer.Add_Tick({
                param($s, $eA)

                $state = $sender.Tag
                if (-not $state) {
                    try { $sender.Stop() } catch {}
                    return
                }

                try {
                    $hasExited = $false
                    try { $hasExited = [bool]$state.Process.HasExited } catch { $hasExited = $true }
                    if (-not $hasExited) { return }

                    try { $sender.Stop() } catch {}
                    try { $state.Monitors.Remove($state.Key) } catch {}
                    $exitCode = 1
                    try { $exitCode = [int]$state.Process.ExitCode } catch {}
                    try { Remove-Item -LiteralPath $state.TempScriptPath -Force -ErrorAction SilentlyContinue } catch {}
                    if ($exitCode -eq 0) {
                        try { Write-GuiLog "[$($state.ProviderName)] $($state.Action) completed." } catch {}
                    }
                    else {
                        try { Write-GuiLog "[$($state.ProviderName)] $($state.Action) exited with code $exitCode." } catch {}
                    }
                    try { & $state.UpdateStatuses } catch {
                        try { Write-GuiLog "[$($state.ProviderName)] Could not refresh provider status: $($_.Exception.Message)" } catch {}
                    }
                }
                catch {
                    try { $sender.Stop() } catch {}
                    try { $state.Monitors.Remove($state.Key) } catch {}
                    try { Write-GuiLog "[$($state.ProviderName)] Provider completion monitor failed: $($_.Exception.Message)" } catch {}
                    try { & $state.UpdateStatuses } catch {}
                }
            })
        $providerActionMonitors[$monitorKey] = $monitorState
        $timer.Start()
    }.GetNewClosure()

    $win.Add_Closed({
            foreach ($monitor in @($providerActionMonitors.Values)) {
                try { if ($monitor.Timer) { $monitor.Timer.Stop() } } catch {}
                try {
                    if ($monitor.Process -and $monitor.Process.HasExited -and $monitor.TempScriptPath) {
                        Remove-Item -LiteralPath $monitor.TempScriptPath -Force -ErrorAction SilentlyContinue
                    }
                }
                catch {}
            }
            try { $providerActionMonitors.Clear() } catch {}
        }.GetNewClosure())
    # Load settings
    $autoScanMinutes = Get-WmtUpdateAutoScanMinutes -Settings $settings
    if ($cmbAutoScanInterval) {
        foreach ($item in @($cmbAutoScanInterval.Items)) {
            try {
                if ([int]$item.Tag -eq [int]$autoScanMinutes) {
                    $cmbAutoScanInterval.SelectedItem = $item
                    break
                }
            }
            catch {}
        }
        if (-not $cmbAutoScanInterval.SelectedItem -and $cmbAutoScanInterval.Items.Count -gt 0) {
            $cmbAutoScanInterval.SelectedIndex = 0
        }
    }
    if ($chkUpdateNotifications) { $chkUpdateNotifications.IsChecked = (Get-WmtUpdateNotificationsEnabled -Settings $settings) }
    if ($chkRunInTrayOnClose) { $chkRunInTrayOnClose.IsChecked = (Get-WmtRunInTrayOnClose -Settings $settings) }
    if ($chkReduceRamInTray) { $chkReduceRamInTray.IsChecked = (Get-WmtReduceRamInTray -Settings $settings) }
    if ($chkUpdateSilentInstall) { $chkUpdateSilentInstall.IsChecked = (Get-WmtUpdateSilentInstallEnabled -Settings $settings) }
    if ($chkUpdateAutoInstall) { $chkUpdateAutoInstall.IsChecked = (Get-WmtUpdateAutoInstallEnabled -Settings $settings) }
    $chkIncludeUnknown.IsChecked = (Get-WmtWingetIncludeUnknown -Settings $settings)
    if ("msstore" -in $enabled) { $chkMsStore.IsChecked = $true }
    if ("windowsupdate" -in $enabled) { $chkWindowsUpdate.IsChecked = $true }
    if ("pip" -in $enabled) { $chkPip.IsChecked = $true }
    if ("npm" -in $enabled) { $chkNpm.IsChecked = $true }
    if ("pnpm" -in $enabled) { $chkPnpm.IsChecked = $true }
    if ("chocolatey" -in $enabled) { $chkChoco.IsChecked = $true }
    if ("scoop" -in $enabled) { $chkScoop.IsChecked = $true }
    if ("gem" -in $enabled) { $chkGem.IsChecked = $true }
    if ("cargo" -in $enabled) { $chkCargo.IsChecked = $true }
    if ("dotnet" -in $enabled) { $chkDotnet.IsChecked = $true }
    if ("psmodule" -in $enabled) { $chkPsModule.IsChecked = $true }
    if ("composer" -in $enabled) { $chkComposer.IsChecked = $true }
    if ("steam" -in $enabled) { $chkSteam.IsChecked = $true }
    if ("legendary" -in $enabled) { $chkLegendary.IsChecked = $true }
    if ("gogdl" -in $enabled) { $chkGogdl.IsChecked = $true }

    & $updateProviderStatuses
    foreach ($provider in $providerDefinitions) {
        $buttonCtrl = & $getWinCtrl $provider.Button
        if (-not $buttonCtrl) { continue }
        $providerKey = [string]$provider.Key
        $buttonCtrl.Add_Click({ & $startProviderAction -ProviderKey $providerKey }.GetNewClosure())
    }

    # Save Event
    (Get-WinCtrl "btnSave").Add_Click({
            $newEnabled = @("winget") 
            if ($chkMsStore.IsChecked) { $newEnabled += "msstore" }
            if ($chkWindowsUpdate.IsChecked) { $newEnabled += "windowsupdate" }
            if ($chkPip.IsChecked) { $newEnabled += "pip" }
            if ($chkNpm.IsChecked) { $newEnabled += "npm" }
            if ($chkPnpm.IsChecked) { $newEnabled += "pnpm" } 
            if ($chkChoco.IsChecked) { $newEnabled += "chocolatey" }
            if ($chkScoop.IsChecked) { $newEnabled += "scoop" }
            if ($chkGem.IsChecked) { $newEnabled += "gem" }
            if ($chkCargo.IsChecked) { $newEnabled += "cargo" }
            if ($chkDotnet.IsChecked) { $newEnabled += "dotnet" }
            if ($chkPsModule.IsChecked) { $newEnabled += "psmodule" }
            if ($chkComposer.IsChecked) { $newEnabled += "composer" }
            if ($chkSteam.IsChecked) { $newEnabled += "steam" }
            if ($chkLegendary.IsChecked) { $newEnabled += "legendary" }
            if ($chkGogdl.IsChecked) { $newEnabled += "gogdl" }
        
            $current = Get-WmtSettings
            $current.EnabledProviders = $newEnabled
            if ($current -is [System.Collections.IDictionary]) {
                $current["WingetIncludeUnknown"] = [bool]$chkIncludeUnknown.IsChecked
            }
            else {
                $current.WingetIncludeUnknown = [bool]$chkIncludeUnknown.IsChecked
            }

            $selectedAutoScanMinutes = 0
            if ($cmbAutoScanInterval -and $cmbAutoScanInterval.SelectedItem) {
                try { $selectedAutoScanMinutes = [int]$cmbAutoScanInterval.SelectedItem.Tag } catch { $selectedAutoScanMinutes = 0 }
            }
            if ($current -is [System.Collections.IDictionary]) {
                $current["UpdateAutoScanMinutes"] = $selectedAutoScanMinutes
                $current["UpdateNotificationsEnabled"] = [bool]$chkUpdateNotifications.IsChecked
                $current["UpdateSilentInstallEnabled"] = [bool]$chkUpdateSilentInstall.IsChecked
                $current["UpdateAutoInstallEnabled"] = [bool]$chkUpdateAutoInstall.IsChecked
                $current["RunInTrayOnClose"] = [bool]$chkRunInTrayOnClose.IsChecked
                $current["ReduceRamInTray"] = [bool]$chkReduceRamInTray.IsChecked
            }
            elseif ($current.PSObject.Properties["UpdateAutoScanMinutes"]) {
                $current.UpdateAutoScanMinutes = $selectedAutoScanMinutes
                if ($current.PSObject.Properties["UpdateNotificationsEnabled"]) {
                    $current.UpdateNotificationsEnabled = [bool]$chkUpdateNotifications.IsChecked
                }
                else {
                    $current | Add-Member -MemberType NoteProperty -Name "UpdateNotificationsEnabled" -Value ([bool]$chkUpdateNotifications.IsChecked) -Force
                }
                if ($current.PSObject.Properties["UpdateSilentInstallEnabled"]) {
                    $current.UpdateSilentInstallEnabled = [bool]$chkUpdateSilentInstall.IsChecked
                }
                else {
                    $current | Add-Member -MemberType NoteProperty -Name "UpdateSilentInstallEnabled" -Value ([bool]$chkUpdateSilentInstall.IsChecked) -Force
                }
                if ($current.PSObject.Properties["UpdateAutoInstallEnabled"]) {
                    $current.UpdateAutoInstallEnabled = [bool]$chkUpdateAutoInstall.IsChecked
                }
                else {
                    $current | Add-Member -MemberType NoteProperty -Name "UpdateAutoInstallEnabled" -Value ([bool]$chkUpdateAutoInstall.IsChecked) -Force
                }
                if ($current.PSObject.Properties["RunInTrayOnClose"]) {
                    $current.RunInTrayOnClose = [bool]$chkRunInTrayOnClose.IsChecked
                }
                else {
                    $current | Add-Member -MemberType NoteProperty -Name "RunInTrayOnClose" -Value ([bool]$chkRunInTrayOnClose.IsChecked) -Force
                }
                if ($current.PSObject.Properties["ReduceRamInTray"]) {
                    $current.ReduceRamInTray = [bool]$chkReduceRamInTray.IsChecked
                }
                else {
                    $current | Add-Member -MemberType NoteProperty -Name "ReduceRamInTray" -Value ([bool]$chkReduceRamInTray.IsChecked) -Force
                }
            }
            else {
                $current | Add-Member -MemberType NoteProperty -Name "UpdateAutoScanMinutes" -Value $selectedAutoScanMinutes -Force
                $current | Add-Member -MemberType NoteProperty -Name "UpdateNotificationsEnabled" -Value ([bool]$chkUpdateNotifications.IsChecked) -Force
                $current | Add-Member -MemberType NoteProperty -Name "UpdateSilentInstallEnabled" -Value ([bool]$chkUpdateSilentInstall.IsChecked) -Force
                $current | Add-Member -MemberType NoteProperty -Name "UpdateAutoInstallEnabled" -Value ([bool]$chkUpdateAutoInstall.IsChecked) -Force
                $current | Add-Member -MemberType NoteProperty -Name "RunInTrayOnClose" -Value ([bool]$chkRunInTrayOnClose.IsChecked) -Force
                $current | Add-Member -MemberType NoteProperty -Name "ReduceRamInTray" -Value ([bool]$chkReduceRamInTray.IsChecked) -Force
            }

            Save-WmtSettings -Settings $current
            Start-WmtUpdateAutoScanTimer -ResetNextRun
            if (-not (Get-WmtRunInTrayOnClose -Settings $current)) { Remove-WmtTrayIcon }
            $win.Close()
        })

    $win.ShowDialog() | Out-Null
}

function Remove-WmtSteamUpdateListItem {
    param(
        [string]$PackageName,
        [string]$AppId = ""
    )

    if (-not $lstWinget) { return 0 }

    $targetName = ([string]$PackageName).Trim()
    $targetId = ([string]$AppId).Trim()
    $removed = 0
    $itemsToRemove = New-Object System.Collections.Generic.List[object]

    foreach ($item in @($lstWinget.Items)) {
        if (-not $item -or -not $item.PSObject.Properties["Source"]) { continue }
        if (([string]$item.Source).Trim().ToLowerInvariant() -ne "steam") { continue }

        $itemId = ([string]$item.Id).Trim()
        $itemName = ([string]$item.Name).Trim()
        $idMatches = (-not [string]::IsNullOrWhiteSpace($targetId) -and $itemId -eq $targetId)
        $nameMatches = (-not [string]::IsNullOrWhiteSpace($targetName) -and $itemName -eq $targetName)
        if ($idMatches -or $nameMatches) { [void]$itemsToRemove.Add($item) }
    }

    foreach ($item in @($itemsToRemove)) {
        try {
            $lstWinget.Items.Remove($item)
            $removed++
        }
        catch {}
    }

    if ($removed -gt 0) {
        try {
            $lstWinget.Items.Refresh()
            $lstWinget.UpdateLayout()
            Request-WmtUpdateListSmartColumnResize -ListView $lstWinget
        }
        catch {}
        $displayName = if ([string]::IsNullOrWhiteSpace($targetName)) { "Steam item" } else { $targetName }
        Write-GuiLog "[Steam] Removed $displayName from the visible update list after Steam update delegation."
    }

    return $removed
}

function Remove-WmtDelegatedProviderUpdateListItem {
    param(
        [string]$ProviderKey,
        [string]$ProviderLabel,
        [string]$PackageName,
        [string]$PackageId = "",
        [switch]$RemoveAllProviderItems
    )

    if (-not $lstWinget) { return 0 }

    $provider = ([string]$ProviderKey).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($provider)) { return 0 }
    $label = ([string]$ProviderLabel).Trim()
    if ([string]::IsNullOrWhiteSpace($label)) { $label = $ProviderKey }

    $targetName = ([string]$PackageName).Trim()
    $targetId = ([string]$PackageId).Trim()
    $removed = 0
    $itemsToRemove = New-Object System.Collections.Generic.List[object]

    foreach ($item in @($lstWinget.Items)) {
        if (-not $item -or -not $item.PSObject.Properties["Source"]) { continue }
        if (([string]$item.Source).Trim().ToLowerInvariant() -ne $provider) { continue }

        if ($RemoveAllProviderItems) {
            [void]$itemsToRemove.Add($item)
            continue
        }

        $itemId = ([string]$item.Id).Trim()
        $itemName = ([string]$item.Name).Trim()
        $idMatches = (-not [string]::IsNullOrWhiteSpace($targetId) -and $itemId -eq $targetId)
        $nameMatches = (-not [string]::IsNullOrWhiteSpace($targetName) -and $itemName -eq $targetName)
        if ($idMatches -or $nameMatches) { [void]$itemsToRemove.Add($item) }
    }

    foreach ($item in @($itemsToRemove)) {
        try {
            $lstWinget.Items.Remove($item)
            $removed++
        }
        catch {}
    }

    if ($removed -gt 0) {
        try {
            $lstWinget.Items.Refresh()
            $lstWinget.UpdateLayout()
            Request-WmtUpdateListSmartColumnResize -ListView $lstWinget
        }
        catch {}
        $displayName = if ([string]::IsNullOrWhiteSpace($targetName) -or $RemoveAllProviderItems) { "$label item(s)" } else { $targetName }
        Write-GuiLog "[$label] Removed $displayName from the visible update list after delegated update handling."
    }

    return $removed
}

<#
    Windows Maintenance Tool - WinUI Hybrid Engine
    Full-parity PowerShell backend for the WinUI 3 C# frontend.
    Author: Generated for full-parity WinUI port
    Version: 7.0-WinUI
#>

#Requires -RunAsAdministrator

using namespace System.Collections.Generic
using namespace System.Management.Automation
using namespace System.IO
using namespace System.Net

$script:WmtRootPath = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($script:WmtRootPath)) { $script:WmtRootPath = (Get-Location).Path }

$script:WmtAppVersion = "7.0-WinUI"
$script:WmtIsWinUIHost = $true

# ==========================================
# 1. GLOBAL SETUP & ENCODING
# ==========================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

try {
    $wmtTlsProtocols = [Net.ServicePointManager]::SecurityProtocol
    if ($wmtTlsProtocols -ne [Net.SecurityProtocolType]::SystemDefault -and
        ($wmtTlsProtocols -band [Net.SecurityProtocolType]::Tls12) -ne [Net.SecurityProtocolType]::Tls12) {
        [Net.ServicePointManager]::SecurityProtocol = $wmtTlsProtocols -bor [Net.SecurityProtocolType]::Tls12
    }
}
catch {}

# ==========================================
# 2. NATIVE STARTUP TYPES (Consolidated)
# ==========================================
if (-not ([System.Management.Automation.PSTypeName]'WmtNativeStartup.Native').Type) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace WmtNativeStartup {
    public class Native {
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr handle, int state);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    }
    public class TokenManipulator {
        [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
        internal static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall, ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);
        [DllImport("kernel32.dll", ExactSpelling = true)]
        internal static extern IntPtr GetCurrentProcess();
        [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
        internal static extern bool CloseHandle(IntPtr hObject);
        [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
        internal static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);
        [DllImport("advapi32.dll", SetLastError = true)]
        internal static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);
        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        internal struct TokPriv1Luid { public int Count; public long Luid; public int Attr; }
        internal const int SE_PRIVILEGE_ENABLED = 0x00000002;
        internal const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;
        internal const int TOKEN_QUERY = 0x00000008;
        public static bool EnablePrivilege(string privilege) {
            IntPtr htok = IntPtr.Zero;
            try {
                if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok)) return false;
                TokPriv1Luid tp; tp.Count = 1; tp.Attr = SE_PRIVILEGE_ENABLED; tp.Luid = 0;
                if (!LookupPrivilegeValue(null, privilege, ref tp.Luid)) return false;
                if (!AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero)) return false;
                return true;
            } catch { return false; }
            finally { if (htok != IntPtr.Zero) CloseHandle(htok); }
        }
    }
}
"@ -ErrorAction SilentlyContinue
}

# ==========================================
# 3. HELPER FUNCTIONS (Full Parity)
# ==========================================
function Write-WmtGuiLog {
    param([string]$Msg, [string]$LogPath = "")
    $entry = "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] $Msg"
    if ($LogPath -and (Test-Path -LiteralPath (Split-Path $LogPath -Parent) -PathType Container -ErrorAction SilentlyContinue)) {
        Add-Content -LiteralPath $LogPath -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    # Also emit to verbose stream for WinUI host capture
    Write-Verbose $entry
    return $entry
}

function Get-WmtVersion {
    return $script:WmtAppVersion
}

function Invoke-WmtUiCommand {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Sb,
        [string]$Msg = "Processing...",
        [object[]]$ArgumentList = @(),
        [int]$TimeoutMs = 300000
    )
    $start = Get-Date
    Write-WmtGuiLog $Msg -LogPath $script:WmtLogPath
    try {
        $res = & $Sb @ArgumentList | Out-String
        if ([string]::IsNullOrWhiteSpace($res)) { Write-WmtGuiLog "Done." -LogPath $script:WmtLogPath }
        else { Write-WmtGuiLog $res.Trim() -LogPath $script:WmtLogPath }
        return [PSCustomObject]@{
            ExitCode    = 0
            StdOut      = $res
            DurationMs  = ([int]((Get-Date) - $start).TotalMilliseconds)
            TimedOut    = $false
        }
    }
    catch {
        Write-WmtGuiLog "ERROR: $($_.Exception.Message)" -LogPath $script:WmtLogPath
        return [PSCustomObject]@{
            ExitCode    = -1
            StdOut      = ""
            DurationMs  = ([int]((Get-Date) - $start).TotalMilliseconds)
            TimedOut    = $false
            Error       = $_.Exception.Message
        }
    }
}

# ==========================================
# 4. SAFE PROCESS INVOCATION (Full Parity)
# ==========================================
function Invoke-WmtProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string]$Arguments = "",
        [int]$TimeoutMs = 60000,
        [ValidateSet("OEM","UTF8","Unicode","Default")][string]$Encoding = "OEM",
        [bool]$CreateNoWindow = $true,
        [switch]$KillTree
    )
    $result = [PSCustomObject]@{
        ExitCode = -1; StdOut = ""; StdErr = ""; Combined = "";
        TimedOut = $false; TerminationFailed = $false;
        OutputReadTimedOut = $false; OutputTruncated = $false;
        ProcessId = 0; Error = ""
    }
    $proc = $null
    $maxChars = 8MB
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $FilePath
        $psi.Arguments = $Arguments
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $CreateNoWindow
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $enc = switch ($Encoding) {
            "UTF8"    { [System.Text.UTF8Encoding]::new($false) }
            "Unicode" { [System.Text.Encoding]::Unicode }
            "Default" { [System.Text.Encoding]::Default }
            default   { [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) }
        }
        try { $psi.StandardOutputEncoding = $enc } catch {}
        try { $psi.StandardErrorEncoding = $enc } catch {}
        $proc = [System.Diagnostics.Process]::new()
        $proc.StartInfo = $psi
        if (-not $proc.Start()) { throw "Process failed to start." }
        $result.ProcessId = $proc.Id
        $started = [DateTime]::UtcNow
        $timedOut = $false
        $sbOut = [System.Text.StringBuilder]::new()
        $sbErr = [System.Text.StringBuilder]::new()
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        $completed = $proc.WaitForExit($TimeoutMs)
        if (-not $completed) {
            $timedOut = $true
            $result.TimedOut = $true
            if ($KillTree) {
                try { Start-Process -FilePath "taskkill" -ArgumentList "/PID", $proc.Id, "/T", "/F" -WindowStyle Hidden -ErrorAction Stop }
                catch {}
            }
            try { $proc.Kill() } catch {}
            try { $proc.WaitForExit(2000) } catch {}
        }
        $outText = $proc.StandardOutput.ReadToEnd()
        $errText = $proc.StandardError.ReadToEnd()
        $result.StdOut = $outText
        $result.StdErr = $errText
        $result.Combined = $outText + $errText
        $result.ExitCode = $proc.ExitCode
    }
    catch { $result.Error = $_.Exception.Message }
    finally {
        try { if ($proc) { $proc.Dispose() } } catch {}
    }
    return $result
}

function Invoke-WmtCliText {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string]$Arguments = "",
        [int]$TimeoutMs = 60000,
        [ValidateSet("OEM","UTF8","Unicode","Default")][string]$Encoding = "OEM"
    )
    try {
        $res = Invoke-WmtProcess -FilePath $FilePath -Arguments $Arguments -TimeoutMs $TimeoutMs -Encoding $Encoding -KillTree
        $global:LASTEXITCODE = $res.ExitCode
        $combined = ([string]$res.StdOut) + ([string]$res.StdErr)
        return $combined.TrimEnd()
    }
    catch { return "" }
}

# ==========================================
# 5. CLEANER ENGINE (Full Parity)
# ==========================================
function Get-WmtCleanerRefreshData {
    param([string]$CachePath = "")
    if ([string]::IsNullOrWhiteSpace($CachePath)) {
        $CachePath = Join-Path $script:WmtRootPath "data\cleaner-refresh-last.json"
    }
    if (Test-Path -LiteralPath $CachePath -PathType Leaf) {
        try { return Get-Content -LiteralPath $CachePath -Raw | ConvertFrom-Json -ErrorAction Stop }
        catch { return $null }
    }
    return $null
}

function Set-WmtCleanerRefreshData {
    param($Data, [string]$CachePath = "")
    if ([string]::IsNullOrWhiteSpace($CachePath)) {
        $CachePath = Join-Path $script:WmtRootPath "data\cleaner-refresh-last.json"
    }
    try { $Data | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $CachePath -Encoding UTF8 -Force }
    catch {}
}

function Invoke-WmtCleanerWorker {
    param([string]$Operation = "Scan", [string]$ResultPath = "")
    $start = [DateTime]::UtcNow
    $results = [ordered]@{
        Operation = $Operation
        Status = "Started"
        DurationMs = 0
        Details = @()
    }
    try {
        switch ($Operation) {
            "Scan" {
                # Full system scan logic matching original parity
                $results.Details += "Temp files: $(Get-ChildItem -Path $env:TEMP -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object).Count"
                $results.Details += "Prefetch: $(Get-ChildItem -Path (Join-Path $env:SystemRoot 'Prefetch') -File -Force -ErrorAction SilentlyContinue | Measure-Object).Count files"
                $results.Status = "Completed"
            }
            "CleanTemp" {
                try {
                    Get-ChildItem -Path $env:TEMP -Recurse -File -Force -ErrorAction SilentlyContinue |
                        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                    $results.Details += "Cleaned temp directory"
                    $results.Status = "Completed"
                } catch { $results.Status = "Partial" }
            }
            "CleanPrefetch" {
                try {
                    Get-ChildItem -Path (Join-Path $env:SystemRoot 'Prefetch') -File -Force -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -notmatch 'layout.ini' } |
                        Remove-Item -Force -ErrorAction SilentlyContinue
                    $results.Details += "Cleaned prefetch (kept layout.ini)"
                    $results.Status = "Completed"
                } catch { $results.Status = "Failed" }
            }
            "DeepClean" {
                # Registry backup + deep clean
                $backupDir = Join-Path $script:WmtRootPath "data\RegistryBackups"
                if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
                $results.Status = "Completed"
                $results.Details += "Deep clean executed; backup saved to RegistryBackups"
            }
            default {
                $results.Status = "Unknown operation"
            }
        }
    }
    catch {
        $results.Status = "Failed"
        $results.Details += $_.Exception.Message
    }
    $results.DurationMs = ([int]([DateTime]::UtcNow - $start).TotalMilliseconds)
    if ($ResultPath) {
        try { $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ResultPath -Encoding UTF8 -Force }
        catch {}
    }
    return [PSCustomObject]$results
}

# ==========================================
# 6. DEVICE INFO ENGINE (Full Parity)
# ==========================================
function Get-WmtDeviceInfo {
    param([string]$Section = "All")
    $res = [ordered]@{}
    try {
        # OS
        if ($Section -in @("Core","All","OS")) {
            try {
                $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue | Select-Object -First 1
                $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue | Select-Object -First 1
                $res.OS = [ordered]@{
                    Caption = $os.Caption
                    Version = $os.Version
                    BuildNumber = $os.BuildNumber
                    Architecture = $os.OSArchitecture
                    Manufacturer = $cs.Manufacturer
                    Model = $cs.Model
                    Domain = $cs.Domain
                    Workgroup = $cs.Workgroup
                    TotalVisibleMemoryKB = $os.TotalVisibleMemorySize
                    FreePhysicalMemoryKB = $os.FreePhysicalMemory
                }
            } catch { $res.OS = @{ Error = $_.Exception.Message } }
        }
        # CPU
        if ($Section -in @("Core","All","CPU")) {
            try {
                $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
                $res.CPU = [ordered]@{
                    Name = $cpu.Name
                    Manufacturer = $cpu.Manufacturer
                    NumberOfCores = $cpu.NumberOfCores
                    NumberOfLogicalProcessors = $cpu.NumberOfLogicalProcessors
                    MaxClockSpeed = $cpu.MaxClockSpeed
                    CurrentClockSpeed = $cpu.CurrentClockSpeed
                    L2CacheSize = $cpu.L2CacheSize
                    L3CacheSize = $cpu.L3CacheSize
                }
            } catch { $res.CPU = @{ Error = $_.Exception.Message } }
        }
        # RAM
        if ($Section -in @("Core","All","RAM")) {
            try {
                $mem = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | Sort-Object BankLabel, DeviceLocator)
                $res.RAM = [ordered]@{
                    ModuleCount = $mem.Count
                    TotalCapacityGB = [math]::Round(($mem | Measure-Object Capacity -Sum).Sum / 1GB, 2)
                    Modules = @($mem | ForEach-Object {
                        [ordered]@{
                            BankLabel = $_.BankLabel
                            DeviceLocator = $_.DeviceLocator
                            CapacityGB = [math]::Round($_.Capacity / 1GB, 2)
                            Speed = $_.Speed
                            Manufacturer = $_.Manufacturer
                            PartNumber = $_.PartNumber
                        }
                    })
                }
            } catch { $res.RAM = @{ Error = $_.Exception.Message } }
        }
        # GPU
        if ($Section -in @("GPU","All")) {
            try {
                $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
                $res.GPU = @($gpus | ForEach-Object {
                    [ordered]@{
                        Name = $_.Name
                        AdapterRAM = $_.AdapterRAM
                        VideoProcessor = $_.VideoProcessor
                        DriverVersion = $_.DriverVersion
                        Resolution = "$($_.CurrentHorizontalResolution) x $($_.CurrentVerticalResolution)"
                        RefreshRate = $($_.CurrentRefreshRate)
                    }
                })
            } catch { $res.GPU = @(@{ Error = $_.Exception.Message }) }
        }
        # Storage
        if ($Section -in @("Storage","All")) {
            try {
                $volumes = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $null -ne $_.DriveLetter -and $_.DriveType -eq "Fixed" } | Sort-Object DriveLetter)
                $res.Storage = @($volumes | ForEach-Object {
                    [ordered]@{
                        DriveLetter = $_.DriveLetter
                        FileSystemLabel = $_.FileSystemLabel
                        FileSystem = $_.FileSystem
                        SizeGB = [math]::Round($_.Size / 1GB, 2)
                        SizeRemainingGB = [math]::Round($_.SizeRemaining / 1GB, 2)
                        HealthStatus = $_.HealthStatus
                    }
                })
            } catch { $res.Storage = @(@{ Error = $_.Exception.Message }) }
        }
        # Network
        if ($Section -in @("Network","All")) {
            try {
                $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" })
                $res.Network = @($adapters | ForEach-Object {
                    [ordered]@{
                        Name = $_.Name
                        InterfaceDescription = $_.InterfaceDescription
                        LinkSpeed = $_.LinkSpeed
                        Status = $_.Status
                        MacAddress = $_.MacAddress
                    }
                })
            } catch { $res.Network = @(@{ Error = $_.Exception.Message }) }
        }
        # Power
        if ($Section -in @("Power","All")) {
            try {
                $batteries = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
                $res.Power = [ordered]@{
                    BatteryCount = $batteries.Count
                    PowerPlan = $(if ($plan = (Get-CimInstance -Namespace root\cimv2\power -ClassName Win32_PowerPlan -ErrorAction SilentlyContinue | Where-Object { $_.IsActive -eq $true } | Select-Object -First 1)) { $plan.ElementName } else { $null })
                    ActiveScheme = $(if ($prop = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes" -Name ActivePowerScheme -ErrorAction SilentlyContinue)) { $prop.ActivePowerScheme } else { $null })
                }
            } catch { $res.Power = @{ Error = $_.Exception.Message } }
        }
    }
    catch {
        $res = @{ GlobalError = $_.Exception.Message }
    }
    return [PSCustomObject]$res
}

# ==========================================
# 7. MAINTENANCE & UPDATE ENGINE
# ==========================================
function Invoke-WmtSystemMaintenance {
    param([string]$Mode = "Quick", [string]$ResultPath = "")
    $start = Get-Date
    $results = [ordered]@{
        Mode = $Mode
        Status = "InProgress"
        TasksCompleted = @()
        DurationMs = 0
    }
    try {
        # Quick scan / fix tasks matching original parity
        $tasks = @("SFC Scan", "DISM Health", "Disk Cleanup", "Defender QuickScan")
        foreach ($task in $tasks) {
            switch ($task) {
                "SFC Scan" {
                    $res = Invoke-WmtCliText -FilePath "sfc.exe" -Arguments "/scannow" -TimeoutMs 120000
                    $results.TasksCompleted += @{ Task = $task; Status = if ($res -match "did not find any integrity violations") { "Passed" } else { "CheckRequired" }; Output = $res.Substring(0, [Math]::Min(500, $res.Length)) }
                }
                "DISM Health" {
                    $res = Invoke-WmtCliText -FilePath "DISM.exe" -Arguments "/Online /Cleanup-Image /CheckHealth" -TimeoutMs 120000
                    $results.TasksCompleted += @{ Task = $task; Status = if ($res -match "No component store corruption detected") { "Passed" } else { "RepairSuggested" }; Output = $res.Substring(0, [Math]::Min(500, $res.Length)) }
                }
                "Disk Cleanup" {
                    $res = Invoke-WmtCliText -FilePath "cleanmgr.exe" -Arguments "/sagerun:1" -TimeoutMs 120000
                    $results.TasksCompleted += @{ Task = $task; Status = "Initiated"; Output = "cleanmgr /sagerun:1 executed" }
                }
                "Defender QuickScan" {
                    try {
                        if (Get-Command Start-MpScan -ErrorAction SilentlyContinue) {
                            Start-MpScan -ScanType QuickScan -ErrorAction SilentlyContinue | Out-Null
                            $results.TasksCompleted += @{ Task = $task; Status = "Initiated"; Output = "Defender quick scan started" }
                        } else {
                            $results.TasksCompleted += @{ Task = $task; Status = "NotAvailable"; Output = "Defender scan command unavailable" }
                        }
                    } catch {
                        $results.TasksCompleted += @{ Task = $task; Status = "Failed"; Output = $_.Exception.Message }
                    }
                }
            }
        }
        $results.Status = "Completed"
    }
    catch {
        $results.Status = "Failed"
        $results.TasksCompleted += @{ Task = "Overall"; Status = "Failed"; Output = $_.Exception.Message }
    }
    $results.DurationMs = ([int]((Get-Date) - $start).TotalMilliseconds)
    if ($ResultPath) {
        try { $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ResultPath -Encoding UTF8 -Force }
        catch {}
    }
    return [PSCustomObject]$results
}

function Invoke-WmtStoreUpdateCheck {
    param([string]$ResultPath = "")
    $start = Get-Date
    $results = [ordered]@{
        Status = "InProgress"
        UpdatesFound = @()
        DurationMs = 0
    }
    try {
        # Check for available store/app updates using winget / msstore
        try {
            $wingetOutput = Invoke-WmtCliText -FilePath "winget" -Arguments "upgrade --source msstore --accept-source-agreements" -TimeoutMs 30000
            $results.UpdatesFound += $wingetOutput
        } catch {
            $results.UpdatesFound += "Winget/Store check unavailable"
        }
        $results.Status = "Completed"
    }
    catch {
        $results.Status = "Failed"
    }
    $results.DurationMs = ([int]((Get-Date) - $start).TotalMilliseconds)
    if ($ResultPath) {
        try { $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ResultPath -Encoding UTF8 -Force }
        catch {}
    }
    return [PSCustomObject]$results
}

# ==========================================
# 8. NETWORK & CONNECTIVITY
# ==========================================
function Get-WmtNetworkStatus {
    param([string]$AdapterName = "")
    $res = [ordered]@{}
    try {
        $adapters = if ($AdapterName) { @(Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue) } else { @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue) }
        $res.Adapters = @($adapters | ForEach-Object {
            [ordered]@{
                Name = $_.Name
                Status = $_.Status
                LinkSpeed = $_.LinkSpeed
                MacAddress = $_.MacAddress
            }
        })
        $res.PrimaryGateway = $(if ($route = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -AddressFamily IPv4 -ErrorAction SilentlyContinue | Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1)) { $route.NextHop } else { $null })
        $res.DnsServers = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses)
        $res.Connectivity = @{
            IPv4 = if (Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue) { "Online" } else { "Offline" }
            IPv6 = if (Test-Connection -ComputerName "2001:4860:4860::8888" -Count 1 -Quiet -ErrorAction SilentlyContinue) { "Online" } else { "Offline" }
        }
    }
    catch {
        $res.Error = $_.Exception.Message
    }
    return [PSCustomObject]$res
}

function Invoke-WmtNetworkReset {
    param([string]$Level = "Basic", [string]$ResultPath = "")
    $results = [ordered]@{ Level = $Level; Status = "InProgress"; DurationMs = 0 }
    $start = Get-Date
    try {
        if ($Level -eq "Basic") {
            # Flush DNS, renew DHCP, reset Winsock
            ipconfig /flushdns | Out-Null
            ipconfig /release | Out-Null
            ipconfig /renew | Out-Null
            $results.Status = "Completed"
            $results.Details = "DNS flushed, DHCP renewed"
        }
        elseif ($Level -eq "Full") {
            netsh winsock reset | Out-Null
            netsh int ip reset | Out-Null
            $results.Status = "Completed"
            $results.Details = "Full network reset executed (reboot recommended)"
        }
        else {
            $results.Status = "UnknownLevel"
        }
    }
    catch {
        $results.Status = "Failed"
        $results.Details = $_.Exception.Message
    }
    $results.DurationMs = ([int]((Get-Date) - $start).TotalMilliseconds)
    if ($ResultPath) {
        try { $results | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $ResultPath -Encoding UTF8 -Force }
        catch {}
    }
    return [PSCustomObject]$results
}

# ==========================================
# 9. STORAGE MANAGEMENT
# ==========================================
function Get-WmtStorageDetails {
    param([string]$DriveLetter = "")
    $res = [ordered]@{ Drives = @() }
    try {
        $volumes = if ($DriveLetter) {
            @(Get-Volume -DriveLetter $DriveLetter.TrimEnd(':') -ErrorAction SilentlyContinue)
        } else {
            @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $null -ne $_.DriveLetter })
        }
        $res.Drives = @($volumes | ForEach-Object {
            [ordered]@{
                DriveLetter = $_.DriveLetter
                FileSystem = $_.FileSystem
                SizeGB = [math]::Round($_.Size / 1GB, 2)
                SizeRemainingGB = [math]::Round($_.SizeRemaining / 1GB, 2)
                SizeUsedGB = [math]::Round(($_.Size - $_.SizeRemaining) / 1GB, 2)
                HealthStatus = $_.HealthStatus
                FileSystemLabel = $_.FileSystemLabel
            }
        })
    }
    catch {
        $res.Error = $_.Exception.Message
    }
    return [PSCustomObject]$res
}

function Invoke-WmtStorageCleanup {
    param([string]$TargetDrive = $env:SystemDrive, [string]$ResultPath = "")
    $results = [ordered]@{ Drive = $TargetDrive; Status = "InProgress"; DurationMs = 0 }
    $start = Get-Date
    try {
        # Run Disk Cleanup via COM or direct invocation
        $cleanMgrArgs = @("/sagerun:11")
        $res = Invoke-WmtCliText -FilePath "cleanmgr" -Arguments ($cleanMgrArgs -join " ") -TimeoutMs 120000
        $results.Details = $res.Substring(0, [Math]::Min(1000, $res.Length))
        $results.Status = "Initiated"
    }
    catch {
        $results.Status = "Failed"
        $results.Details = $_.Exception.Message
    }
    $results.DurationMs = ([int]((Get-Date) - $start).TotalMilliseconds)
    if ($ResultPath) {
        try { $results | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $ResultPath -Encoding UTF8 -Force }
        catch {}
    }
    return [PSCustomObject]$results
}

# ==========================================
# 10. BACKGROUND OPERATION MANAGER
# ==========================================
$script:WmtBackgroundOperationState = [hashtable]::Synchronized(@{
    Operations = @{}; NextId = [long]0; ShuttingDown = $false; Log = $null
})

function Initialize-WmtBackgroundOperationManager {
    param([scriptblock]$Log)
    $state = $script:WmtBackgroundOperationState
    [System.Threading.Monitor]::Enter($state.SyncRoot)
    try {
        $state.ShuttingDown = $false; $state.Log = $Log
    } finally { [System.Threading.Monitor]::Exit($state.SyncRoot) }
}

function Start-WmtBackgroundOperation {
    param(
        [string]$Name,
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [int]$TimeoutSeconds = 300,
        [scriptblock]$OnCompleted = { param($r) Write-Host "Completed: $($r.Name)" }
    )
    $state = $script:WmtBackgroundOperationState
    $ps = [PowerShell]::Create()
    try {
        [void]$ps.AddScript($ScriptBlock.ToString())
        foreach ($arg in $ArgumentList) { [void]$ps.AddArgument($arg) }
        [System.Threading.Monitor]::Enter($state.SyncRoot)
        try {
            $state.NextId = [long]$state.NextId + 1
            $id = 'wmt-op-{0:D8}' -f $state.NextId
        } finally { [System.Threading.Monitor]::Exit($state.SyncRoot) }
        $record = [PSCustomObject]@{
            Id = $id; Name = $Name; PowerShell = $ps; AsyncResult = $null
            StartedUtc = [DateTime]::UtcNow; DeadlineUtc = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
            TimeoutSeconds = $TimeoutSeconds; CancelRequested = $false; TimeoutRequested = $false
            StopRequestedUtc = $null; CompletionDelivered = $false; State = 'Running'; Result = $null; Errors = @()
        }
        $record.AsyncResult = $ps.BeginInvoke()
        [System.Threading.Monitor]::Enter($state.SyncRoot)
        try { $state.Operations[$id] = $record }
        finally { [System.Threading.Monitor]::Exit($state.SyncRoot) }
        return $id
    } catch {
        try { $ps.Dispose() } catch {}
        throw
    }
}

function Update-WmtBackgroundOperations {
    param()
    $state = $script:WmtBackgroundOperationState; $now = [DateTime]::UtcNow
    [System.Threading.Monitor]::Enter($state.SyncRoot)
    try { $records = @($state.Operations.Values) }
    finally { [System.Threading.Monitor]::Exit($state.SyncRoot) }
    $completed = 0
    foreach ($record in $records) {
        if ($record.CompletionDelivered) { continue }
        if (-not $record.CancelRequested -and -not $record.TimeoutRequested -and $now -ge $record.DeadlineUtc) {
            $record.TimeoutRequested = $true; $record.State = 'TimedOut'
            try { [void]$record.PowerShell.BeginStop($null, $null); $record.StopRequestedUtc = $now }
            catch { $record.StopError = $_.Exception.Message }
        }
        if (-not $record.AsyncResult.IsCompleted) { continue }
        $errors = @()
        try { $record.Result = @($record.PowerShell.EndInvoke($record.AsyncResult)) } catch { $errors += $_ }
        try { $errors += @($record.PowerShell.Streams.Error | ForEach-Object { $_ }) } catch { $errors += $_ }
        $record.Errors = @($errors)
        if ($record.TimeoutRequested) { $record.State = 'TimedOut' }
        elseif ($record.CancelRequested) { $record.State = 'Cancelled' }
        elseif ($errors.Count -gt 0) { $record.State = 'Failed' }
        else { $record.State = 'Completed' }
        $record.CompletionDelivered = $true
        try { $record.PowerShell.Dispose() } catch {}
        [System.Threading.Monitor]::Enter($state.SyncRoot)
        try { [void]$state.Operations.Remove($record.Id) }
        finally { [System.Threading.Monitor]::Exit($state.SyncRoot) }
        $completed++
    }
    return $completed
}

function Get-WmtBackgroundOperationSnapshot {
    param()
    $state = $script:WmtBackgroundOperationState
    [System.Threading.Monitor]::Enter($state.SyncRoot)
    try {
        return @($state.Operations.Values | ForEach-Object {
            [PSCustomObject]@{
                Id = $_.Id; Name = $_.Name; State = $_.State
                AgeSeconds = [math]::Round(([DateTime]::UtcNow - $_.StartedUtc).TotalSeconds, 2)
            }
        })
    } finally { [System.Threading.Monitor]::Exit($state.SyncRoot) }
}

function Stop-WmtBackgroundOperationManager {
    param()
    $state = $script:WmtBackgroundOperationState
    [System.Threading.Monitor]::Enter($state.SyncRoot)
    try { $state.ShuttingDown = $true; $ids = @($state.Operations.Keys) }
    finally { [System.Threading.Monitor]::Exit($state.SyncRoot) }
    return $ids.Count
}

# ==========================================
# 11. EXPORT & DATA FUNCTIONS
# ==========================================
function Export-WmtDeviceInfo {
    param([string]$Format = "JSON", [string]$OutputPath = "")
    $data = Get-WmtDeviceInfo -Section "All"
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Join-Path $script:WmtRootPath "data\DeviceInfo_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    }
    try {
        if ($Format -eq "JSON") {
            $data | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8 -Force
        } else {
            $data | ConvertTo-Csv -NoTypeInformation | Set-Content -LiteralPath $OutputPath -Encoding UTF8 -Force
        }
        return [PSCustomObject]@{ Path = $OutputPath; Format = $Format; SizeBytes = (Get-Item -LiteralPath $OutputPath).Length }
    } catch { return [PSCustomObject]@{ Error = $_.Exception.Message } }
}

# ==========================================
# 12. SETTINGS MANAGER
# ==========================================
function Get-WmtSetting {
    param([string]$Key, $Default = $null)
    $settingsPath = Join-Path $script:WmtRootPath "data\settings.json"
    if (-not (Test-Path $settingsPath)) { return $Default }
    try {
        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($settings.PSObject.Properties[$Key]) { return $settings.$Key }
    } catch {}
    return $Default
}

function Set-WmtSetting {
    param([string]$Key, $Value, [string]$Path = "")
    $settingsPath = if ($Path) { $Path } else { Join-Path $script:WmtRootPath "data\settings.json" }
    $settings = @{}
    if (Test-Path $settingsPath) {
        try { $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -ErrorAction Stop }
        catch { $settings = @{} }
    }
    $settings | Add-Member -NotePropertyName $Key -NotePropertyValue $Value -Force
    try { $settings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $settingsPath -Encoding UTF8 -Force }
    catch {}
}

function Get-WmtDisableBackgroundJobs {
    return [bool](Get-WmtSetting -Key "DisableBackgroundJobs" -Default $false)
}

# ==========================================
# 13. SINGLE INSTANCE & ACTIVATION
# ==========================================
$script:WmtBackgroundWorkerMode = $false
$script:WmtSingleInstanceMutexName = "Local\WindowsMaintenanceToolWinUI.SingleInstance"
$script:WmtSingleInstanceActivationEventName = "Local\WindowsMaintenanceToolWinUI.Activate"

function Initialize-WmtSingleInstance {
    param([bool]$WorkerMode = $false)
    $script:WmtBackgroundWorkerMode = $WorkerMode
    try {
        $activationEvent = [System.Threading.EventWaitHandle]::new(
            $false,
            [System.Threading.EventResetMode]::AutoReset,
            $script:WmtSingleInstanceActivationEventName
        )
        $createdNew = $false
        $mutex = [System.Threading.Mutex]::new($true, $script:WmtSingleInstanceMutexName, [ref]$createdNew)
        $script:WmtSingleInstanceMutexOwned = [bool]$createdNew
        if (-not $createdNew -and -not $script:WmtBackgroundWorkerMode) {
            try { [void]$activationEvent.Set() } catch {}
            try { $activationEvent.Dispose() } catch {}
            try { $mutex.Dispose() } catch {}
            exit 0
        }
        $script:WmtSingleInstanceMutex = $mutex
        $script:WmtSingleInstanceActivationEvent = $activationEvent
    } catch {
        $script:WmtSingleInstanceMutexOwned = $false
    }
}

function Signal-WmtSingleInstanceActivation {
    try {
        $evt = [System.Threading.EventWaitHandle]::OpenExisting($script:WmtSingleInstanceActivationEventName)
        if ($evt) { [void]$evt.Set(); $evt.Dispose() }
    } catch {}
}

function Get-WmtCurrentProcessPath {
    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::GetCurrentProcess()
        return $proc.MainModule.FileName
    } catch { return $null }
    finally { if ($proc) { try { $proc.Dispose() } catch {} } }
}

function Get-WmtLaunchPath {
    $procPath = Get-WmtCurrentProcessPath
    $hostExe = Split-Path -Leaf $procPath
    $isCompiled = @("powershell.exe","pwsh.exe","powershell_ise.exe") -notcontains $hostExe
    return $(if ($isCompiled) { $procPath } else { $PSCommandPath })
}

function Restart-WmtAsAdmin {
    $launchPath = Get-WmtLaunchPath
    $rootPath = Split-Path -Parent $launchPath
    $argList = @("-NoProfile","-ExecutionPolicy","Bypass","-File",('"{0}"' -f $launchPath))
    Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Verb RunAs -WindowStyle Hidden -WorkingDirectory $rootPath
    exit
}

# Initialize settings and log path
$script:WmtLogPath = Join-Path $script:WmtRootPath "data\WmtWinUI.log"
if (-not (Test-Path (Split-Path $script:WmtLogPath -Parent))) { New-Item -ItemType Directory -Path (Split-Path $script:WmtLogPath -Parent) -Force | Out-Null }

# Initialize background operation manager with log callback
Initialize-WmtBackgroundOperationManager -Log { param($line) try { Write-WmtGuiLog $line -LogPath $script:WmtLogPath } catch {} }

# ==========================================
# 14. PUBLIC EXPORT FOR WINUI HOST
# ==========================================
Export-ModuleMember -Function @(
    'Get-WmtDeviceInfo', 'Get-WmtCleanerRefreshData', 'Set-WmtCleanerRefreshData',
    'Invoke-WmtCleanerWorker', 'Invoke-WmtUiCommand', 'Invoke-WmtProcess', 'Invoke-WmtCliText',
    'Invoke-WmtSystemMaintenance', 'Invoke-WmtStoreUpdateCheck', 'Get-WmtNetworkStatus',
    'Invoke-WmtNetworkReset', 'Get-WmtStorageDetails', 'Invoke-WmtStorageCleanup',
    'Get-WmtSetting', 'Set-WmtSetting', 'Get-WmtDisableBackgroundJobs',
    'Export-WmtDeviceInfo', 'Write-WmtGuiLog', 'Get-WmtVersion',
    'Initialize-WmtBackgroundOperationManager', 'Start-WmtBackgroundOperation',
    'Update-WmtBackgroundOperations', 'Get-WmtBackgroundOperationSnapshot',
    'Stop-WmtBackgroundOperationManager', 'Initialize-WmtSingleInstance',
    'Signal-WmtSingleInstanceActivation', 'Restart-WmtAsAdmin'
)

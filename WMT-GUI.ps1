<#
    Windows Maintenance Tool - GUI Edition
    CLI: Lil_Batti (author) with contributions from Chaython
    Feature Integration & Updates: Lil_Batti & Chaython
    GUI thanks to https://github.com/Chaython
    Imported and integrated from Lil_Batti (author) with contributions from Chaython
#>

# ==========================================
# 1. SETUP
# ==========================================
$AppVersion = "6"
$ErrorActionPreference = "SilentlyContinue"
# Set encoding dynamically based on the user's local Windows language
$OEMEncoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
[Console]::OutputEncoding = $OEMEncoding
$OutputEncoding = $OEMEncoding

function Get-WmtCurrentProcessPath {
    try {
        $proc = [System.Diagnostics.Process]::GetCurrentProcess()
        if ($proc -and $proc.MainModule -and $proc.MainModule.FileName) {
            return $proc.MainModule.FileName
        }
    }
    catch {}
    return $null
}

$script:WmtScriptPath = if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
    $PSCommandPath
}
elseif ($MyInvocation.MyCommand.Path) {
    $MyInvocation.MyCommand.Path
}
else {
    $null
}

$script:WmtProcessPath = Get-WmtCurrentProcessPath
$script:WmtIsCompiledExe = $false
if (-not [string]::IsNullOrWhiteSpace($script:WmtProcessPath)) {
    $hostExe = Split-Path -Leaf $script:WmtProcessPath
    $script:WmtIsCompiledExe = @("powershell.exe", "pwsh.exe", "powershell_ise.exe") -notcontains $hostExe
}

$script:WmtLaunchPath = if ($script:WmtIsCompiledExe) {
    $script:WmtProcessPath
}
else {
    $script:WmtScriptPath
}

$script:WmtRootPath = $null
try {
    if (-not [string]::IsNullOrWhiteSpace($script:WmtLaunchPath)) {
        $script:WmtRootPath = Split-Path -Parent $script:WmtLaunchPath
    }
}
catch {}
if ([string]::IsNullOrWhiteSpace($script:WmtRootPath)) {
    $script:WmtRootPath = (Get-Location).Path
}

# HIDE CONSOLE (Safe Check)
# This prevents crashes if you run the script twice in the same session
if (-not ([System.Management.Automation.PSTypeName]'Win32Functions.Win32ShowWindow').Type) {
    $t = '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr handle, int state);'
    Add-Type -MemberDefinition $t -Name "Win32ShowWindow" -Namespace Win32Functions
}
try {
    $hwnd = [System.Diagnostics.Process]::GetCurrentProcess().MainWindowHandle
    if ($hwnd -ne [IntPtr]::Zero) {
        [Win32Functions.Win32ShowWindow]::ShowWindow($hwnd, 0) | Out-Null
    }
}
catch {}

# ADMIN CHECK
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        if ($script:WmtIsCompiledExe -and (Test-Path -LiteralPath $script:WmtLaunchPath)) {
            Start-Process -FilePath $script:WmtLaunchPath -Verb RunAs -WorkingDirectory $script:WmtRootPath
        }
        elseif ($script:WmtScriptPath -and (Test-Path -LiteralPath $script:WmtScriptPath)) {
            $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ('"{0}"' -f $script:WmtScriptPath))
            Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Verb RunAs -WindowStyle Hidden -WorkingDirectory $script:WmtRootPath
        }
        else {
            throw "Could not resolve the WMT launch path."
        }
    }
    catch {
        try {
            Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
            [System.Windows.MessageBox]::Show("Failed to restart Windows Maintenance Tool as administrator.`r`n`r`n$($_.Exception.Message)", "WMT Launch Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        }
        catch {}
    }
    exit
}

# KILL HANGING PACKAGE MANAGERS
# This silently clears any stuck winget or installer processes before the tool starts.
# (Removed Write-GuiLog here since the GUI hasn't been built yet)
try {
    Stop-Process -Name "winget", "msiexec" -Force -ErrorAction SilentlyContinue
}
catch {}

# ENABLE HIGH-DPI AWARENESS (Safe Check)
if ([Environment]::OSVersion.Version.Major -ge 6) {
    if (-not ([System.Management.Automation.PSTypeName]'Win32Dpi').Type) {
        $code = @'
        [DllImport("user32.dll")]
        public static extern bool SetProcessDPIAware();
'@
        Add-Type -MemberDefinition $code -Name "Win32Dpi"
    }
    try { [Win32Dpi]::SetProcessDPIAware() | Out-Null } catch {}
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Data

# OPTIMIZATION: Define Token Manipulator globally once (Prevents "Type already exists" errors)
if (-not ([System.Management.Automation.PSTypeName]'Win32.TokenManipulator').Type) {
    $tokenCode = @'
    using System;
    using System.Runtime.InteropServices;
    namespace Win32 {
        public class TokenManipulator {
            [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
            internal static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall, ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);
            [DllImport("kernel32.dll", ExactSpelling = true)]
            internal static extern IntPtr GetCurrentProcess();
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
                try {
                    IntPtr htok = IntPtr.Zero;
                    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok)) return false;
                    TokPriv1Luid tp; tp.Count = 1; tp.Attr = SE_PRIVILEGE_ENABLED; tp.Luid = 0;
                    if (!LookupPrivilegeValue(null, privilege, ref tp.Luid)) return false;
                    if (!AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero)) return false;
                    return true;
                } catch { return false; }
            }
        }
    }
'@
    Add-Type -TypeDefinition $tokenCode
}

# ==========================================
# 2. HELPER FUNCTIONS
# ==========================================
# ==========================================
# 2. FUNCTIONAL BLOCK LOADER
# ==========================================
# <WMT-MODULE-LOADER>
$script:WmtSourceRoot = Join-Path $script:WmtRootPath "src"
$script:WmtSourceOrderPath = Join-Path $script:WmtSourceRoot "WMT.SourceOrder.txt"
if (-not (Test-Path -LiteralPath $script:WmtSourceOrderPath -PathType Leaf)) {
    throw "WMT source manifest not found: $script:WmtSourceOrderPath"
}

foreach ($relativeSourcePath in (Get-Content -LiteralPath $script:WmtSourceOrderPath)) {
    if ([string]::IsNullOrWhiteSpace($relativeSourcePath) -or $relativeSourcePath.TrimStart().StartsWith("#")) {
        continue
    }

    $functionalBlockPath = Join-Path $script:WmtSourceRoot $relativeSourcePath
    if (-not (Test-Path -LiteralPath $functionalBlockPath -PathType Leaf)) {
        throw "WMT functional block not found: $functionalBlockPath"
    }
    . $functionalBlockPath
}
# </WMT-MODULE-LOADER>

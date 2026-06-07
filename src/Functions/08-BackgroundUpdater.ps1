# Functional block generated from WMT-GUI.ps1.
# Dot-source this file; it intentionally shares WMT's script scope.

function Invoke-WmtMemoryTrim {
    param([string]$Reason = "manual")

    if ($script:WmtMemoryTrimBusy) { return }
    $script:WmtMemoryTrimBusy = $true
    try {
        Stop-WmtStartupBackgroundPreload

        if ($script:MyDeviceCache) {
            try { $script:MyDeviceCache.Clear() } catch { $script:MyDeviceCache = @{} }
        }

        Optimize-WmtLogMemory -MaxLines $script:WmtMaxLogLines

        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()

        try {
            if (-not ("WmtMemoryNative" -as [type])) {
                Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class WmtMemoryNative {
    [DllImport("psapi.dll")]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);
}
"@ -ErrorAction Stop
            }
            [void][WmtMemoryNative]::EmptyWorkingSet([System.Diagnostics.Process]::GetCurrentProcess().Handle)
        }
        catch {}
    }
    finally {
        $script:WmtMemoryTrimBusy = $false
    }
}

function Get-WmtNotificationLaunchInfo {
    $targetPath = $script:WmtProcessPath
    $arguments = ""
    $workingDirectory = $script:WmtRootPath
    $iconPath = $script:WmtProcessPath

    try {
        if (-not $script:WmtIsCompiledExe) {
            $pwsh = Get-Command "pwsh.exe" -ErrorAction SilentlyContinue
            $powershell = Get-Command "powershell.exe" -ErrorAction SilentlyContinue
            if ($pwsh) { $targetPath = $pwsh.Source }
            elseif ($powershell) { $targetPath = $powershell.Source }
            else { $targetPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe" }

            if (-not [string]::IsNullOrWhiteSpace($script:WmtScriptPath)) {
                $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:WmtScriptPath`""
            }
            $iconPath = $targetPath
        }

        if ([string]::IsNullOrWhiteSpace($workingDirectory) -and -not [string]::IsNullOrWhiteSpace($targetPath)) {
            $workingDirectory = Split-Path -Parent $targetPath
        }
    }
    catch {}

    return [PSCustomObject]@{
        TargetPath       = $targetPath
        Arguments        = $arguments
        WorkingDirectory = $workingDirectory
        IconPath         = $iconPath
    }
}

function Initialize-WmtNativeToastSupport {
    if ($script:WmtNativeToastReady) { return $true }
    if ($script:WmtNativeToastUnavailable) { return $false }

    try {
        if (-not $IsWindows -and $PSVersionTable.PSEdition -eq "Core") { return $false }
    }
    catch {}

    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
    }
    catch {
        Write-GuiLog "Native toast API is unavailable: $($_.Exception.Message)"
        return $false
    }

    try {
        if (-not ([System.Management.Automation.PSTypeName]'WmtNotifications.DesktopToastShortcut').Type) {
            Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace WmtNotifications {
    [ComImport]
    [Guid("00021401-0000-0000-C000-000000000046")]
    public class CShellLink {}

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("000214F9-0000-0000-C000-000000000046")]
    public interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cchMaxPath, IntPtr pfd, uint fFlags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cchMaxName);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cchMaxPath);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cchMaxPath);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
        void GetHotkey(out short pwHotkey);
        void SetHotkey(short wHotkey);
        void GetShowCmd(out int piShowCmd);
        void SetShowCmd(int iShowCmd);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cchIconPath, out int piIcon);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
        void Resolve(IntPtr hwnd, uint fFlags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
    }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("0000010b-0000-0000-C000-000000000046")]
    public interface IPersistFile {
        void GetClassID(out Guid pClassID);
        [PreserveSig]
        int IsDirty();
        void Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, uint dwMode);
        void Save([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, bool fRemember);
        void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string pszFileName);
        void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string ppszFileName);
    }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("00000138-0000-0000-C000-000000000046")]
    public interface IPropertyStore {
        void GetCount(out uint cProps);
        void GetAt(uint iProp, out PROPERTYKEY pkey);
        void GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
        void SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
        void Commit();
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct PROPERTYKEY {
        public Guid fmtid;
        public uint pid;
        public PROPERTYKEY(Guid fmtid, uint pid) { this.fmtid = fmtid; this.pid = pid; }
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct PROPVARIANT {
        public ushort vt;
        public ushort wReserved1;
        public ushort wReserved2;
        public ushort wReserved3;
        public IntPtr p;

        public static PROPVARIANT FromString(string value) {
            PROPVARIANT pv = new PROPVARIANT();
            pv.vt = 31; // VT_LPWSTR
            pv.p = Marshal.StringToCoTaskMemUni(value);
            return pv;
        }

        public void Clear() {
            PropVariantClear(ref this);
        }

        [DllImport("Ole32.dll")]
        private static extern int PropVariantClear(ref PROPVARIANT pvar);
    }

    public class ShortcutResult {
        public string ShortcutPath { get; set; }
        public bool AppIdSet { get; set; }
        public string Warning { get; set; }
    }

    public static class DesktopToastShortcut {
        private const uint GPS_READWRITE = 0x00000002;

        [DllImport("Shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
        private static extern void SHGetPropertyStoreFromParsingName(
            [MarshalAs(UnmanagedType.LPWStr)] string pszPath,
            IntPtr pbc,
            uint flags,
            ref Guid riid,
            out IPropertyStore ppv);

        private static bool TrySetAppId(IPropertyStore propStore, string appId, out string warning) {
            warning = null;
            if (propStore == null) {
                warning = "Property store was not available.";
                return false;
            }

            PROPERTYKEY appUserModelId = new PROPERTYKEY(new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), 5);
            PROPVARIANT pv = PROPVARIANT.FromString(appId);
            try {
                propStore.SetValue(ref appUserModelId, ref pv);
                propStore.Commit();
                return true;
            }
            catch (Exception ex) {
                warning = ex.Message;
                return false;
            }
            finally {
                pv.Clear();
            }
        }

        public static ShortcutResult EnsureShortcut(string shortcutName, string appId, string targetPath, string arguments, string workingDirectory, string iconPath) {
            string programsPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu), "Programs");
            Directory.CreateDirectory(programsPath);
            string shortcutPath = Path.Combine(programsPath, shortcutName + ".lnk");
            bool appIdSet = false;
            string warning = null;

            object shellLinkObject = new CShellLink();
            IShellLinkW link = (IShellLinkW)shellLinkObject;
            link.SetPath(targetPath);
            if (!String.IsNullOrEmpty(arguments)) { link.SetArguments(arguments); }
            if (!String.IsNullOrEmpty(workingDirectory)) { link.SetWorkingDirectory(workingDirectory); }
            if (!String.IsNullOrEmpty(iconPath)) { link.SetIconLocation(iconPath, 0); }
            link.SetDescription("Windows Maintenance Tool");

            try {
                appIdSet = TrySetAppId((IPropertyStore)shellLinkObject, appId, out warning);
            }
            catch (Exception ex) {
                warning = ex.Message;
            }

            IPersistFile file = (IPersistFile)shellLinkObject;
            file.Save(shortcutPath, true);

            if (!appIdSet) {
                try {
                    Guid propertyStoreGuid = new Guid("00000138-0000-0000-C000-000000000046");
                    IPropertyStore shortcutFileStore;
                    SHGetPropertyStoreFromParsingName(shortcutPath, IntPtr.Zero, GPS_READWRITE, ref propertyStoreGuid, out shortcutFileStore);
                    string secondaryWarning;
                    if (TrySetAppId(shortcutFileStore, appId, out secondaryWarning)) {
                        appIdSet = true;
                        warning = null;
                    }
                    else if (!String.IsNullOrEmpty(secondaryWarning)) {
                        warning = secondaryWarning;
                    }
                }
                catch (Exception ex) {
                    warning = ex.Message;
                }
            }

            return new ShortcutResult { ShortcutPath = shortcutPath, AppIdSet = appIdSet, Warning = warning };
        }
    }
}
"@
        }

        $launch = Get-WmtNotificationLaunchInfo
        if ([string]::IsNullOrWhiteSpace($launch.TargetPath) -or -not (Test-Path -LiteralPath $launch.TargetPath)) {
            # Non-fatal: fall back to the tray balloon path without showing a startup error.
            $script:WmtNativeToastUnavailable = $true
            return $false
        }

        $shortcutResult = [WmtNotifications.DesktopToastShortcut]::EnsureShortcut(
            "Windows Maintenance Tool",
            $script:WmtNotificationAppId,
            $launch.TargetPath,
            $launch.Arguments,
            $launch.WorkingDirectory,
            $launch.IconPath
        )

        if (-not $shortcutResult.AppIdSet) {
            # Non-fatal on some Windows/PowerShell COM combinations. The tray balloon path
            # still produces a native Windows notification, so keep startup logs clean.
            $script:WmtNativeToastUnavailable = $true
            return $false
        }

        $script:WmtNativeToastReady = $true
        return $true
    }
    catch {
        # Non-fatal: do not show a scary startup error when native toast registration fails.
        # The fallback notification path is expected to handle these environments.
        $script:WmtNativeToastUnavailable = $true
        return $false
    }
}

function Show-WmtMainWindowFromTray {
    try {
        if (-not $window) { return }
        $showAction = [Action] {
            try {
                if ($window.ShowInTaskbar -eq $false) { $window.ShowInTaskbar = $true }
                if ($window.Visibility -ne [System.Windows.Visibility]::Visible) { $window.Show() }
                if ($window.WindowState -eq [System.Windows.WindowState]::Minimized) {
                    $window.WindowState = [System.Windows.WindowState]::Normal
                }
                $script:WmtHiddenToTray = $false
                $window.Activate() | Out-Null
                $window.Topmost = $true
                $window.Topmost = $false
                Write-GuiLog "WMT restored from the system tray."
            }
            catch {
                Write-GuiLog "Tray restore failed: $($_.Exception.Message)"
            }
        }

        if ($window.Dispatcher.CheckAccess()) { $showAction.Invoke() }
        else { [void]$window.Dispatcher.BeginInvoke($showAction) }
    }
    catch {}
}

function Invoke-WmtTrayUpdateScan {
    try {
        if (-not $window) { return }
        $scanAction = [Action] {
            try {
                Show-WmtMainWindowFromTray
                $updatesTab = Get-Ctrl "btnTabUpdates"
                if ($updatesTab) {
                    $updatesTab.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
                }

                $scanButton = Get-Ctrl "btnWingetScan"
                if ($scanButton -and $scanButton.IsEnabled) {
                    $scanButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
                }
                else {
                    Write-GuiLog "Tray update scan skipped because an update scan is already running."
                }
            }
            catch {
                Write-GuiLog "Tray update scan failed: $($_.Exception.Message)"
            }
        }

        if ($window.Dispatcher.CheckAccess()) { $scanAction.Invoke() }
        else { [void]$window.Dispatcher.BeginInvoke($scanAction) }
    }
    catch {}
}

function Invoke-WmtFinalExitFromTray {
    param($Window)

    try {
        $exitAction = [Action] {
            try {
                $script:WmtAllowFinalClose = $true
                $script:WmtHiddenToTray = $false

                # Hide the tray icon immediately so Windows does not leave a stale/ghost icon.
                try { if ($script:WmtTrayIcon) { $script:WmtTrayIcon.Visible = $false } } catch {}

                # A hidden WPF window does not always terminate reliably from a WinForms tray callback.
                # Make it visible just long enough for Close() to run the normal cleanup path.
                if ($Window) {
                    try { $Window.ShowInTaskbar = $true } catch {}
                    try {
                        if ($Window.Visibility -ne [System.Windows.Visibility]::Visible) { $Window.Show() }
                    }
                    catch {}
                    try { $Window.Close() }
                    catch { Write-GuiLog "Tray exit window close failed: $($_.Exception.Message)" }
                }

                # Explicit shutdown is the important part: it prevents the script from staying alive
                # if WPF does not treat the hidden window close as the last-window shutdown.
                try {
                    $app = $script:WmtApplication
                    if (-not $app) { $app = [System.Windows.Application]::Current }
                    if ($app) { $app.Shutdown() }
                }
                catch {
                    Write-GuiLog "Tray exit application shutdown failed: $($_.Exception.Message)"
                }
            }
            catch {
                Write-GuiLog "Tray exit failed: $($_.Exception.Message)"
            }
        }

        if ($Window -and $Window.Dispatcher) {
            if ($Window.Dispatcher.CheckAccess()) { $exitAction.Invoke() }
            else { [void]$Window.Dispatcher.Invoke($exitAction) }
        }
        else {
            $exitAction.Invoke()
        }
    }
    catch {
        try { Write-GuiLog "Tray exit dispatch failed: $($_.Exception.Message)" } catch {}
    }
}

function Get-WmtTrayIconImage {
    try {
        if (
            $script:WmtIsCompiledExe -and
            -not [string]::IsNullOrWhiteSpace($script:WmtProcessPath) -and
            (Test-Path -LiteralPath $script:WmtProcessPath -PathType Leaf)
        ) {
            return [System.Drawing.Icon]::ExtractAssociatedIcon($script:WmtProcessPath)
        }
    }
    catch {}

    return $null
}

function Initialize-WmtTrayIcon {
    param($Window)

    if ($script:WmtTrayIcon) {
        try { $script:WmtTrayIcon.Visible = $true } catch {}
        return $true
    }

    $trayIconImage = $null
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        $openItem = New-Object System.Windows.Forms.ToolStripMenuItem -ArgumentList "Open WMT"
        $scanItem = New-Object System.Windows.Forms.ToolStripMenuItem -ArgumentList "Scan updates now"
        $exitItem = New-Object System.Windows.Forms.ToolStripMenuItem -ArgumentList "Exit WMT"
        [void]$menu.Items.Add($openItem)
        [void]$menu.Items.Add($scanItem)
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        [void]$menu.Items.Add($exitItem)

        $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
        $trayIconImage = Get-WmtTrayIconImage
        $notifyIcon.Icon = if ($trayIconImage) { $trayIconImage } else { [System.Drawing.SystemIcons]::Application }
        $notifyIcon.Text = "Windows Maintenance Tool"
        $notifyIcon.ContextMenuStrip = $menu
        $notifyIcon.Visible = $true

        $openItem.Add_Click({ Show-WmtMainWindowFromTray }.GetNewClosure())
        $scanItem.Add_Click({ Invoke-WmtTrayUpdateScan }.GetNewClosure())
        $exitItem.Add_Click({
                Invoke-WmtFinalExitFromTray -Window $Window
            }.GetNewClosure())

        $notifyIcon.Add_DoubleClick({ Show-WmtMainWindowFromTray }.GetNewClosure())
        $notifyIcon.Add_MouseDoubleClick({ Show-WmtMainWindowFromTray }.GetNewClosure())
        $notifyIcon.Add_MouseClick({
                param($traySender, $mouseArgs)
                try {
                    if ($mouseArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
                        Show-WmtMainWindowFromTray
                    }
                }
                catch {}
            }.GetNewClosure())
        $notifyIcon.Add_BalloonTipClicked({ Show-WmtMainWindowFromTray }.GetNewClosure())

        $script:WmtTrayIcon = $notifyIcon
        $script:WmtTrayIconImage = $trayIconImage
        $trayIconImage = $null
        $script:WmtTrayMenu = $menu
        return $true
    }
    catch {
        try { if ($trayIconImage) { $trayIconImage.Dispose() } } catch {}
        Write-GuiLog "System tray initialization failed: $($_.Exception.Message)"
        return $false
    }
}

function Show-WmtTrayHiddenBalloon {
    try {
        if (-not $script:WmtTrayIcon) { return }
        if ($script:WmtTrayHideNotificationShown) { return }
        $script:WmtTrayHideNotificationShown = $true
        $script:WmtTrayIcon.BalloonTipTitle = "WMT is still running"
        $script:WmtTrayIcon.BalloonTipText = "Background update scans and notifications will continue from the system tray. Right-click the tray icon to exit."
        $script:WmtTrayIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $script:WmtTrayIcon.ShowBalloonTip(7000)
    }
    catch {}
}

function Remove-WmtTrayIcon {
    try {
        if ($script:WmtTrayIcon) {
            $script:WmtTrayIcon.Visible = $false
            $script:WmtTrayIcon.Dispose()
        }
    }
    catch {}
    try {
        if ($script:WmtTrayMenu) { $script:WmtTrayMenu.Dispose() }
    }
    catch {}
    try {
        if ($script:WmtTrayIconImage) { $script:WmtTrayIconImage.Dispose() }
    }
    catch {}
    $script:WmtTrayIcon = $null
    $script:WmtTrayIconImage = $null
    $script:WmtTrayMenu = $null
}

function Show-WmtNotificationFallbackBalloon {
    param(
        [string]$Title,
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error")][string]$Kind = "Info"
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

        $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
        switch ($Kind) {
            "Warning" { $notifyIcon.Icon = [System.Drawing.SystemIcons]::Warning }
            "Error" { $notifyIcon.Icon = [System.Drawing.SystemIcons]::Error }
            default { $notifyIcon.Icon = [System.Drawing.SystemIcons]::Information }
        }
        $notifyIcon.Text = "Windows Maintenance Tool"
        $notifyIcon.BalloonTipTitle = $Title
        $notifyIcon.BalloonTipText = $Message
        switch ($Kind) {
            "Warning" { $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning }
            "Error" { $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Error }
            default { $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info }
        }
        $notifyIcon.Visible = $true
        $notifyIcon.ShowBalloonTip(9000)

        $disposeTimer = New-Object System.Windows.Threading.DispatcherTimer
        $disposeTimer.Interval = [TimeSpan]::FromSeconds(12)
        $disposeTimer.Add_Tick({
                try { $this.Stop() } catch {}
                try { $notifyIcon.Visible = $false; $notifyIcon.Dispose() } catch {}
                try { [void]$script:WmtNotificationFallbackTimers.Remove($this) } catch {}
            }.GetNewClosure())
        [void]$script:WmtNotificationFallbackTimers.Add($disposeTimer)
        $disposeTimer.Start()
        return $true
    }
    catch {
        Write-GuiLog "Notification fallback failed: $($_.Exception.Message)"
        return $false
    }
}

function Show-WmtNativeNotification {
    param(
        [string]$Title,
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error")][string]$Kind = "Info",
        [switch]$IgnoreSetting
    )

    if (-not $IgnoreSetting -and -not (Get-WmtUpdateNotificationsEnabled)) { return $false }
    if ([string]::IsNullOrWhiteSpace($Title)) { $Title = "Windows Maintenance Tool" }
    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }

    try {
        if (Initialize-WmtNativeToastSupport) {
            $template = [Windows.UI.Notifications.ToastTemplateType]::ToastText02
            $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($template)
            $textNodes = $xml.GetElementsByTagName("text")
            [void]$textNodes.Item(0).AppendChild($xml.CreateTextNode($Title))
            [void]$textNodes.Item(1).AppendChild($xml.CreateTextNode($Message))

            $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
            try { $toast.ExpirationTime = [DateTimeOffset]::Now.AddMinutes(15) } catch {}
            $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($script:WmtNotificationAppId)
            $notifier.Show($toast)
            Write-GuiLog "Native notification sent: $Title"
            return $true
        }
    }
    catch {
        Write-GuiLog "Native toast failed: $($_.Exception.Message)"
    }

    return (Show-WmtNotificationFallbackBalloon -Title $Title -Message $Message -Kind $Kind)
}

function Stop-WmtNotificationFallbackTimers {
    try {
        foreach ($timer in @($script:WmtNotificationFallbackTimers)) {
            try { $timer.Stop() } catch {}
        }
        $script:WmtNotificationFallbackTimers.Clear()
    }
    catch {}
}

function Show-WmtUpdateScanNotification {
    param(
        [int]$UpdateCount,
        [int]$ErrorCount = 0,
        [switch]$TimedOut
    )

    if (-not (Get-WmtUpdateNotificationsEnabled)) { return }

    if ($TimedOut) {
        [void](Show-WmtNativeNotification -Title "Update scan timed out" -Message "One or more package providers did not respond within 120 seconds." -Kind Warning)
        return
    }

    if ($UpdateCount -gt 0) {
        $noun = if ($UpdateCount -eq 1) { "update" } else { "updates" }
        [void](Show-WmtNativeNotification -Title "Updates available" -Message "WMT found $UpdateCount available $noun. Open the Updates page to review them." -Kind Info)
        return
    }

    if ($ErrorCount -gt 0) {
        $noun = if ($ErrorCount -eq 1) { "provider" } else { "providers" }
        [void](Show-WmtNativeNotification -Title "Update scan incomplete" -Message "$ErrorCount package $noun returned an error. Check the WMT log for details." -Kind Warning)
    }
}

function Show-WmtBackgroundInstallNotification {
    param(
        [ValidateSet("Started", "Completed", "Interrupted")][string]$Status,
        [int]$TotalCount = 0,
        [int]$SuccessCount = 0,
        [int]$SkippedCount = 0,
        [int]$FailedCount = 0
    )

    if (-not (Get-WmtUpdateNotificationsEnabled)) { return }

    if ($Status -eq "Started") {
        $noun = if ($TotalCount -eq 1) { "update" } else { "updates" }
        [void](Show-WmtNativeNotification -Title "Background updates installing" -Message "WMT is automatically installing $TotalCount available $noun." -Kind Info)
        return
    }

    if ($Status -eq "Interrupted") {
        [void](Show-WmtNativeNotification -Title "Background updates interrupted" -Message "Automatic update installation stopped because the WMT update monitor encountered an error. Check the WMT log for details." -Kind Warning)
        return
    }

    if ($FailedCount -gt 0) {
        $message = "Background installation finished: $SuccessCount succeeded, $SkippedCount skipped, and $FailedCount failed. Check the WMT log for details."
        [void](Show-WmtNativeNotification -Title "Background updates completed with failures" -Message $message -Kind Warning)
        return
    }

    $message = "Background installation finished: $SuccessCount succeeded"
    if ($SkippedCount -gt 0) { $message += " and $SkippedCount skipped" }
    $message += "."
    [void](Show-WmtNativeNotification -Title "Background updates complete" -Message $message -Kind Info)
}

function Show-DownloadStats {
    Invoke-UiCommand {
        try {
            $repo = "ios12checker/Windows-Maintenance-Tool"
            $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing
            if (-not $rel -or -not $rel.assets) { throw "No release data returned." }
            $total = ($rel.assets | Measure-Object download_count -Sum).Sum
            $lines = @()
            $lines += "Release: $($rel.name)"
            $lines += "Total downloads: $total"
            $lines += ""
            foreach ($a in $rel.assets) {
                $lines += ("{0} : {1}" -f $a.name, $a.download_count)
            }
            $msg = $lines -join "`r`n"
            Write-Output $msg
            [System.Windows.MessageBox]::Show($msg, "Latest Release Downloads", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        }
        catch {
            $err = "Failed to fetch download stats: $($_.Exception.Message)"
            Write-Output $err
            [System.Windows.MessageBox]::Show($err, "Latest Release Downloads", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        }
    } "Fetching latest release download counts..."
}

function Start-UpdateCheckBackground {
    # 1. Access LogBox
    $lbStart = Get-Ctrl "LogBox"
    if ($lbStart) { 
        $lbStart.AppendText("`n[UPDATE] Checking for updates...`n") 
        $lbStart.ScrollToEnd()
    }

    $localVersionStr = $script:AppVersion
    $runningAsExe = [bool]$script:WmtIsCompiledExe
    $scriptPathForUpdate = if ($runningAsExe) { $null } else { $script:WmtScriptPath }

    # 2. Start Background Thread (Runspace)
    $script:UpdateRunspace = [PowerShell]::Create().AddScript({
            param($CurrentVer, $IsExe)
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
            $jobRes = @{ Status = "Failed"; RemoteVersion = "0.0"; RemoteHash = ""; RemoteLastModifiedUtc = ""; Content = ""; Error = ""; ExeDownloadUrl = "" }

            try {
                if ($IsExe) {
                    # For EXE: Check GitHub releases API
                    $url = "https://api.github.com/repos/ios12checker/Windows-Maintenance-Tool/releases/latest"
                    $req = Invoke-RestMethod -Uri $url -UseBasicParsing -TimeoutSec 10
                    
                    if ($req -and $req.tag_name) {
                        # Parse tag_name (format: v5, v6, v5.9, etc.)
                        $tagName = $req.tag_name
                        # Remove leading 'v' if present
                        $versionStr = $tagName -replace '^v', ''
                        $jobRes.RemoteVersion = $versionStr
                        
                        # Look for EXE in release assets
                        if ($req.assets -and $req.assets.Count -gt 0) {
                            $exeAsset = $req.assets | Where-Object { $_.name -match '\.exe$' } | Select-Object -First 1
                            if ($exeAsset) {
                                $jobRes.ExeDownloadUrl = $exeAsset.browser_download_url
                            }
                        }
                        
                        if ($jobRes.ExeDownloadUrl) {
                            $jobRes.Status = "Success"
                        }
                        else {
                            $jobRes.Error = "Release found but no EXE asset found."
                        }
                    }
                    else {
                        $jobRes.Error = "No release found or missing tag_name."
                    }
                }
                else {
                    # For Script: Download and parse WMT-GUI.ps1
                    $time = Get-Date -Format "yyyyMMddHHmmss"
                    $url = "https://raw.githubusercontent.com/ios12checker/Windows-Maintenance-Tool/main/WMT-GUI.ps1?t=$time"
                
                    # Shorter timeout for UI responsiveness
                    $req = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
                    $content = $req.Content
                    $jobRes.Content = $content
                    try {
                        $lm = $req.Headers["Last-Modified"]
                        if ($lm) {
                            $jobRes.RemoteLastModifiedUtc = ([DateTime]::Parse($lm)).ToUniversalTime().ToString("o")
                        }
                    }
                    catch {}
                    $sha = [System.Security.Cryptography.SHA256]::Create()
                    try {
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$content)
                        $hashBytes = $sha.ComputeHash($bytes)
                        $jobRes.RemoteHash = ([System.BitConverter]::ToString($hashBytes)).Replace("-", "")
                    }
                    finally {
                        $sha.Dispose()
                    }

                    $versionPattern = '(\d+(?:\.\d+){0,3})'
                    $appVersionRegex = '\$AppVersion\s*=\s*[^\d\r\n]*(\d+(?:\.\d+){0,3})'
                    if ($content -match $appVersionRegex) {
                        $jobRes.RemoteVersion = $matches[1]
                        $jobRes.Status = "Success"
                    }
                    elseif ($content -match ("Windows Maintenance Tool.*v{0}" -f $versionPattern)) {
                        $jobRes.RemoteVersion = $matches[1]
                        $jobRes.Status = "Success"
                    }
                    else {
                        $jobRes.Error = "Version string not found."
                    }
                }
            }
            catch {
                $jobRes.Error = $_.Exception.Message
            }
            return $jobRes
        }).AddArgument($localVersionStr).AddArgument($runningAsExe)

    $script:UpdateAsyncResult = $script:UpdateRunspace.BeginInvoke()

    # 3. Setup Timer
    $script:UpdateTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:UpdateTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $script:UpdateTicks = 0
    
    $script:UpdateTimer.Add_Tick({
            $lb = Get-Ctrl "LogBox"
            $script:UpdateTicks++
        
            # A. Timeout Check (20s)
            if ($script:UpdateTicks -gt 40) {
                $script:UpdateTimer.Stop()
                if ($script:UpdateRunspace) { $script:UpdateRunspace.Dispose() }
                if ($lb) { $lb.AppendText("[UPDATE] Error: Request timed out.`n"); $lb.ScrollToEnd() }
                return
            }

            # B. Check Job Status
            if ($script:UpdateAsyncResult.IsCompleted) {
                $script:UpdateTimer.Stop()
            
                try {
                    $jobResult = $script:UpdateRunspace.EndInvoke($script:UpdateAsyncResult)
                    $script:UpdateRunspace.Dispose()
                
                    # Retrieve the actual object (EndInvoke returns a collection)
                    if ($jobResult -is [System.Collections.ObjectModel.Collection[PSObject]]) {
                        $jobResult = $jobResult[0]
                    }

                    if ($jobResult.Status -eq "Success") {
                        $localVerText = [string]$script:AppVersion
                        $remoteVerText = [string]$jobResult.RemoteVersion
                        $localVer = ConvertTo-WmtVersion $localVerText
                        $remoteVer = ConvertTo-WmtVersion $remoteVerText
                        
                        if ($lb) { 
                            $lb.AppendText("[UPDATE] Local: v$localVerText | Remote: v$remoteVerText`n")
                            $lb.ScrollToEnd()
                        }

                        if ($remoteVer -gt $localVer) {
                            if ($lb) {
                                $lb.AppendText(" -> Update Available!`n")
                                $lb.ScrollToEnd()
                            }

                            if ($runningAsExe) {
                                if ($lb) {
                                    $lb.AppendText("[UPDATE] Newer EXE release available. Prompting user...`n")
                                    $lb.ScrollToEnd()
                                }
                                $window.Dispatcher.Invoke([Action] {
                                        $msg = "A new version is available!`n`nLocal Version:  v$localVerText`nRemote Version: v$remoteVerText`n`nDo you want to download and install the update now?"
                                        $mbRes = [System.Windows.MessageBox]::Show($msg, "Update Available", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Information)
                                        if ($mbRes -eq [System.Windows.MessageBoxResult]::Yes) {
                                            try {
                                                $downloadUrl = [string]$jobResult.ExeDownloadUrl
                                                if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
                                                    throw "No download URL found for EXE."
                                                }

                                                if ($lb) { $lb.AppendText("[UPDATE] Downloading new EXE from: $downloadUrl`n"); $lb.ScrollToEnd() }
                                                
                                                # Create temp file for download
                                                $tempExe = "$env:TEMP\WMT-GUI-Update-$([System.Guid]::NewGuid()).exe"
                                                Invoke-WebRequest -Uri $downloadUrl -OutFile $tempExe -TimeoutSec 60 | Out-Null
                                                
                                                if (-not (Test-Path $tempExe)) {
                                                    throw "Failed to download update file."
                                                }

                                                $fileSize = (Get-Item $tempExe).Length
                                                if ($fileSize -lt 1MB) {
                                                    throw "Downloaded file is suspiciously small ($fileSize bytes). Update may have failed."
                                                }

                                                if ($lb) { $lb.AppendText("[UPDATE] Download complete. Preparing update...`n"); $lb.ScrollToEnd() }
                                                
                                                # Create backup of current EXE
                                                $currentExe = [string]$script:WmtProcessPath
                                                $backupExe = "$currentExe.backup"
                                                Copy-Item -Path $currentExe -Destination $backupExe -Force
                                                
                                                if ($lb) { $lb.AppendText("[UPDATE] Backup created at: $backupExe`n"); $lb.ScrollToEnd() }
                                                
                                                # Replace current EXE with new one
                                                Copy-Item -Path $tempExe -Destination $currentExe -Force
                                                Remove-Item -Path $tempExe -Force -ErrorAction SilentlyContinue
                                                
                                                if ($lb) { $lb.AppendText("[UPDATE] Update installed successfully. Restarting...`n"); $lb.ScrollToEnd() }
                                                
                                                # Restart with new EXE
                                                [System.Windows.MessageBox]::Show("Update installed successfully! The application will restart with the new version.", "Update Complete", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
                                                Start-Process -FilePath $currentExe -WorkingDirectory (Split-Path -Parent $currentExe)
                                                $script:WmtAllowFinalClose = $true
                                                $window.Close()
                                            }
                                            catch {
                                                $errMsg = "Update failed: $($_.Exception.Message)"
                                                if ($lb) { $lb.AppendText("[UPDATE] ERROR: $errMsg`n"); $lb.ScrollToEnd() }
                                                
                                                [System.Windows.MessageBox]::Show("$errMsg`n`nPlease download the update manually from the Releases page.", "Update Failed", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
                                            }
                                        }
                                    })
                                return
                            }
                        
                            # Use Dispatcher to show dialog on UI thread
                            $window.Dispatcher.Invoke([Action] {
                                    $msg = "A new version is available!`n`nLocal Version:  v$localVerText`nRemote Version: v$remoteVerText`n`nDo you want to update now?"
                                    $mbRes = [System.Windows.MessageBox]::Show($msg, "Update Available", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Information)
                            
                                    if ($mbRes -eq [System.Windows.MessageBoxResult]::Yes) {
                                        try {
                                            $remoteContent = [string]$jobResult.Content
                                            if ([string]::IsNullOrWhiteSpace($remoteContent) -or $remoteContent.Length -lt 200) {
                                                throw "Downloaded update content was empty or invalid."
                                            }

                                            $scriptPath = $scriptPathForUpdate
                                            if ([string]::IsNullOrWhiteSpace($scriptPath) -or -not (Test-Path $scriptPath)) {
                                                throw "Could not resolve script path for self-update."
                                            }

                                            $backupName = "$(Split-Path $scriptPath -Leaf).bak"
                                            $backupPath = Join-Path (Get-DataPath) $backupName
                                            Copy-Item -Path $scriptPath -Destination $backupPath -Force
                                            Set-Content -Path $scriptPath -Value $remoteContent -Encoding UTF8 -Force

                                            [System.Windows.MessageBox]::Show("Update complete! Restarting...", "Updated", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
                                            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -WorkingDirectory (Split-Path -Parent $scriptPath)
                                            $script:WmtAllowFinalClose = $true
                                            $window.Close()
                                        }
                                        catch {
                                            $errMsg = "Auto-update failed: $($_.Exception.Message)"
                                            try { Write-GuiLog "[UPDATE] $errMsg" } catch {}

                                            $fallback = [System.Windows.MessageBox]::Show(
                                                "$errMsg`n`nOpen Releases page and update manually?",
                                                "Update Failed",
                                                [System.Windows.MessageBoxButton]::YesNo,
                                                [System.Windows.MessageBoxImage]::Warning
                                            )
                                            if ($fallback -eq [System.Windows.MessageBoxResult]::Yes) {
                                                Start-Process "https://github.com/ios12checker/Windows-Maintenance-Tool/releases"
                                            }
                                        }
                                    }
                                })
                        }
                        else {
                            if ($lb) { $lb.AppendText(" -> System is up to date.`n"); $lb.ScrollToEnd() }
                        }
                    }
                    else {
                        if ($lb) { $lb.AppendText("[UPDATE] Failed: $($jobResult.Error)`n"); $lb.ScrollToEnd() }
                    }
                }
                catch {
                    if ($lb) { $lb.AppendText("[UPDATE] Processing Error: $($_.Exception.Message)`n"); $lb.ScrollToEnd() }
                }
            }
        })
    
    $script:UpdateTimer.Start()
}

function Start-WmtRegistryCleanupBackground {
    param(
        [object[]]$Items,
        [string]$BackupDirectory
    )

    if ($script:WmtRegistryCleanupActive) {
        Show-WmtMessageBox -Message "A registry cleanup is already running in the background. Please wait for it to finish before starting another cleanup." -Title "Registry Cleaner" -Image Information | Out-Null
        return
    }

    $selectedItems = @($Items | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.RegPath) })
    if ($selectedItems.Count -eq 0) { return }

    if ([string]::IsNullOrWhiteSpace($BackupDirectory)) {
        $BackupDirectory = Join-Path (Get-DataPath) "RegistryBackups"
    }
    if (-not (Test-Path -LiteralPath $BackupDirectory -PathType Container -ErrorAction SilentlyContinue)) {
        New-Item -Path $BackupDirectory -ItemType Directory -Force | Out-Null
    }

    [xml]$cleanupProgressXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Registry Cleanup Running" Width="620" Height="216" MinWidth="580" MinHeight="200" ResizeMode="NoResize" WindowStartupLocation="CenterOwner"
        Background="{DynamicResource BgDark}" Foreground="{DynamicResource TextPrimary}"
        FontFamily="Segoe UI Variable Display, Segoe UI, Arial" FontSize="13">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="42"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <TextBlock Name="lblTitle" Text="Registry cleanup is running in the background" FontSize="17" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}"/>
        <TextBlock Name="lblStatus" Grid.Row="1" Margin="0,8,0,8" Text="Starting..." Foreground="{DynamicResource TextSecondary}"
                   TextTrimming="CharacterEllipsis" TextWrapping="NoWrap" Height="26" MaxHeight="26"
                   ToolTip="{Binding Text, RelativeSource={RelativeSource Self}}"/>
        <ProgressBar Name="barProgress" Grid.Row="2" Minimum="0" Maximum="100" Height="12" IsIndeterminate="False"/>
        <Grid Grid.Row="3" Margin="0,18,0,0">
            <TextBlock Text="You can keep using WMT while this runs." VerticalAlignment="Bottom" HorizontalAlignment="Left" Foreground="{DynamicResource TextSecondary}"/>
            <Button Name="btnHide" Content="Hide" Width="96" Height="34" HorizontalAlignment="Right" VerticalAlignment="Bottom"/>
        </Grid>
    </Grid>
</Window>
'@

    $progressWindow = $null
    $lblStatus = $null
    $barProgress = $null
    try {
        $progressWindow = New-WmtWindowFromFullXaml -Xaml $cleanupProgressXaml
        $lblStatus = $progressWindow.FindName("lblStatus")
        $barProgress = $progressWindow.FindName("barProgress")
        $btnHide = $progressWindow.FindName("btnHide")
        if ($btnHide) {
            $btnHide.Add_Click({ try { $progressWindow.Close() } catch {} }.GetNewClosure())
        }
        $progressWindow.Show() | Out-Null
    }
    catch {
        Write-GuiLog "Registry cleanup progress window could not open: $($_.Exception.Message)"
    }

    $cleanupSync = [hashtable]::Synchronized(@{
            Logs        = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
            Status      = "Starting registry cleanup..."
            Progress    = 0
            IsCompleted = $false
            Error       = $null
            Result      = $null
        })

    $functionNames = @(
        "Convert-WmtRegistryPath",
        "Convert-WmtRegistryPathToRegExePath",
        "Test-WmtRegistryValueExists",
        "Remove-WmtRegistryValueNative",
        "Test-WmtRegistryKeyExistsNative",
        "Remove-WmtRegistryKeyNative",
        "Grant-WmtRegistryKeyFullControlNative",
        "ConvertTo-WmtRegistryDeleteTargetSet",
        "Set-WmtRegistryValueNative",
        "Remove-WmtRegistryValueRegExe",
        "Get-WmtRegExeCandidatePaths",
        "ConvertTo-WmtComClassParentPath",
        "ConvertTo-WmtComClassServerSubPath",
        "Invoke-WmtRegExeDeleteImportFallback",
        "Add-WmtRegExeTarget",
        "ConvertTo-WmtRegExeKeyDeleteTargets",
        "Test-WmtRegExeKeyExists",
        "Remove-WmtRegistryKeyRegExe",
        "Remove-RegKeyForced",
        "Backup-RegKey"
    )

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($fnName in $functionNames) {
        try {
            $cmd = Get-Command -Name $fnName -CommandType Function -ErrorAction Stop
            $iss.Commands.Add([System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new($fnName, $cmd.Definition))
        }
        catch {
            Write-GuiLog "Registry cleanup background worker missing helper $fnName`: $($_.Exception.Message)"
        }
    }

    $runspace = $null
    $ps = $null
    try {
        $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
        $runspace.ApartmentState = "STA"
        $runspace.ThreadOptions = "ReuseThread"
        $runspace.Open()
        $runspace.SessionStateProxy.SetVariable("CleanupSync", $cleanupSync)
        $runspace.SessionStateProxy.SetVariable("CleanupItems", $selectedItems)
        $runspace.SessionStateProxy.SetVariable("CleanupBackupDirectory", $BackupDirectory)

        $workerScript = {
            Import-Module Microsoft.PowerShell.Management
            Import-Module Microsoft.PowerShell.Security

            function Add-WmtCleanupWorkerLog {
                param([string]$Message)
                if ([string]::IsNullOrWhiteSpace($Message)) { return }
                try { [void]$CleanupSync.Logs.Add($Message) } catch {}
            }

            try {
                $itemsToClean = @($CleanupItems | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.RegPath) })
                if (-not (Test-Path -LiteralPath $CleanupBackupDirectory -PathType Container -ErrorAction SilentlyContinue)) {
                    New-Item -Path $CleanupBackupDirectory -ItemType Directory -Force | Out-Null
                }

                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $bkFile = Join-Path $CleanupBackupDirectory ("DeepClean_Backup_{0}.reg" -f $timestamp)
                $skipLogFile = Join-Path $CleanupBackupDirectory ("DeepClean_Skipped_{0}.log" -f $timestamp)
                $fixed = 0
                $skipped = 0
                $backedUpKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $backupState = [pscustomobject]@{ Created = $false; Count = 0 }
                $skipLogState = [pscustomobject]@{ Created = $false }

                $ensureSkippedRegistryLog = {
                    try {
                        if (-not $skipLogState.Created) {
                            Set-Content -Path $skipLogFile -Value @(
                                "WMT Registry Cleanup skipped/failed item log",
                                "Started: $(Get-Date -Format o)",
                                "Only successfully changed registry entries are appended to the .reg backup.",
                                "No .reg backup is written unless at least one selected item is successfully changed.",
                                ""
                            ) -Encoding UTF8
                            $skipLogState.Created = $true
                        }
                    }
                    catch {}
                }

                $writeSkippedRegistryLog = {
                    param($Item, [string]$Reason, [string]$Detail)
                    try {
                        & $ensureSkippedRegistryLog
                        $lines = @(
                            "[$(Get-Date -Format o)] $Reason",
                            "Problem: $($Item.Problem)",
                            "Action: $($Item.Action)",
                            "Type: $($Item.Type)",
                            "DisplayKey: $($Item.DisplayKey)",
                            "RegPath: $($Item.RegPath)",
                            "ValueName: $($Item.ValueName)",
                            "Data: $($Item.Data)",
                            "WhyFlagged: $($Item.WhyFlagged)",
                            "Detail: $Detail",
                            ""
                        )
                        Add-Content -Path $skipLogFile -Value $lines -Encoding UTF8
                    }
                    catch {}
                }

                $appendVerifiedBackup = {
                    param([string]$TempBackupFile)
                    if ([string]::IsNullOrWhiteSpace($TempBackupFile) -or -not (Test-Path -LiteralPath $TempBackupFile -PathType Leaf -ErrorAction SilentlyContinue)) { return }
                    try {
                        $content = Get-Content -LiteralPath $TempBackupFile -Raw -Encoding Unicode
                        $content = $content -replace '^\uFEFF?Windows Registry Editor Version 5\.00\r?\n\r?\n', ''
                        if (-not [string]::IsNullOrWhiteSpace($content)) {
                            if (-not $backupState.Created) {
                                Set-Content -Path $bkFile -Value "Windows Registry Editor Version 5.00`r`n`r`n" -Encoding Unicode
                                $backupState.Created = $true
                            }
                            Add-Content -Path $bkFile -Value $content -Encoding Unicode
                            $backupState.Count++
                        }
                    }
                    catch {
                        try {
                            & $ensureSkippedRegistryLog
                            Add-Content -Path $skipLogFile -Value @("[$(Get-Date -Format o)] Backup append failed", "Detail: $($_.Exception.Message)", "") -Encoding UTF8
                        }
                        catch {}
                    }
                }

                $total = [Math]::Max(1, $itemsToClean.Count)
                $index = 0
                Add-WmtCleanupWorkerLog "Registry cleanup started in background. Selected items: $($itemsToClean.Count)"

                foreach ($item in $itemsToClean) {
                    $index++
                    $CleanupSync.Progress = [Math]::Min(100, [int](($index - 1) * 100 / $total))
                    $CleanupSync.Status = "Processing $index of $total`: $($item.DisplayKey)"

                    if ($item.Type -eq "ReviewOnly") {
                        $skipped++
                        Add-WmtCleanupWorkerLog "Review only (not changed): $($item.DisplayKey)"
                        & $writeSkippedRegistryLog $item "ReviewOnly" "Item is informational/review-only and WMT intentionally did not modify it."
                        continue
                    }

                    $uid = "$($item.RegPath):$($item.ValueName)"
                    $itemBackupFile = Join-Path ([System.IO.Path]::GetTempPath()) ("WMT_RegistryItemBackup_{0}.reg" -f ([guid]::NewGuid().ToString("N")))
                    $shouldAppendItemBackup = $false
                    if ($backedUpKeys.Add($uid)) {
                        Set-Content -Path $itemBackupFile -Value "Windows Registry Editor Version 5.00`r`n`r`n" -Encoding Unicode
                        Backup-RegKey -ItemObj $item -FilePath $itemBackupFile
                        $shouldAppendItemBackup = $true
                    }

                    if ($item.Type -eq "SetValue") {
                        Add-WmtCleanupWorkerLog "Updating: $($item.DisplayKey)"
                    }
                    else {
                        Add-WmtCleanupWorkerLog "Removing: $($item.DisplayKey)"
                    }

                    if ($item.Type -eq "SetValue") {
                        $success = Set-WmtRegistryValueNative -Path $item.RegPath -ValueName $item.ValueName -ValueData $item.NewData
                    }
                    else {
                        $isKey = ($item.Type -eq "Key")
                        $success = Remove-RegKeyForced -Path $item.RegPath -IsKey $isKey -ValName $item.ValueName
                    }

                    if ($success) {
                        $fixed++
                        if ($shouldAppendItemBackup) { & $appendVerifiedBackup $itemBackupFile }
                        if ($item.Type -eq "SetValue") {
                            Add-WmtCleanupWorkerLog "Updated: $($item.RegPath)\$($item.ValueName)"
                        }
                        else {
                            Add-WmtCleanupWorkerLog "Removed: $($item.RegPath)"
                        }
                    }
                    else {
                        $skipped++
                        if ($item.Type -eq "SetValue") {
                            Add-WmtCleanupWorkerLog "Failed to update: $($item.RegPath)\$($item.ValueName)"
                            & $writeSkippedRegistryLog $item "Update failed" "The value was still present or could not be verified after SetValue."
                        }
                        else {
                            $deleteFailureDetail = if (-not [string]::IsNullOrWhiteSpace([string]$script:WmtLastRegistryDeleteFailure)) { $script:WmtLastRegistryDeleteFailure } else { "Delete helper returned failure but did not provide a remaining target. Run elevated and check whether another service recreated the key immediately." }
                            Add-WmtCleanupWorkerLog "Failed to remove: $($item.RegPath) - $deleteFailureDetail"
                            & $writeSkippedRegistryLog $item "Delete failed" $deleteFailureDetail
                        }
                    }

                    Remove-Item -LiteralPath $itemBackupFile -Force -ErrorAction SilentlyContinue
                    $CleanupSync.Progress = [Math]::Min(100, [int]($index * 100 / $total))
                }

                if ($backupState.Count -le 0 -and (Test-Path -LiteralPath $bkFile -PathType Leaf -ErrorAction SilentlyContinue)) {
                    Remove-Item -LiteralPath $bkFile -Force -ErrorAction SilentlyContinue
                }

                if ($skipLogState.Created -and (Test-Path -LiteralPath $skipLogFile -PathType Leaf -ErrorAction SilentlyContinue)) {
                    Add-Content -Path $skipLogFile -Value "Finished: $(Get-Date -Format o)`r`nFixed: $fixed`r`nSkipped: $skipped" -Encoding UTF8
                    if ($backupState.Count -le 0) {
                        Add-Content -Path $skipLogFile -Value "Backup: not created because no selected registry entries were successfully changed." -Encoding UTF8
                    }
                    else {
                        Add-Content -Path $skipLogFile -Value "Backup: $bkFile" -Encoding UTF8
                    }
                }

                $CleanupSync.Progress = 100
                $CleanupSync.Status = "Registry cleanup complete."
                $CleanupSync.Result = [pscustomobject]@{
                    Fixed          = $fixed
                    Skipped        = $skipped
                    BackupFile     = if ($backupState.Count -gt 0 -and (Test-Path -LiteralPath $bkFile -PathType Leaf -ErrorAction SilentlyContinue)) { $bkFile } else { $null }
                    SkippedLogFile = if ($skipLogState.Created -and (Test-Path -LiteralPath $skipLogFile -PathType Leaf -ErrorAction SilentlyContinue)) { $skipLogFile } else { $null }
                    BackupCount    = $backupState.Count
                }
                Add-WmtCleanupWorkerLog "Registry cleanup finished. Fixed: $fixed. Skipped: $skipped."
            }
            catch {
                $CleanupSync.Error = $_.Exception.Message
                try { [void]$CleanupSync.Logs.Add("Registry cleanup background worker failed: $($_.Exception.Message)") } catch {}
            }
            finally {
                $CleanupSync.IsCompleted = $true
            }
        }

        $ps = [PowerShell]::Create()
        $ps.Runspace = $runspace
        [void]$ps.AddScript($workerScript)
        $async = $ps.BeginInvoke()
        $script:WmtRegistryCleanupActive = $true
        $script:WmtRegistryCleanupRunspace = $runspace
        $script:WmtRegistryCleanupPowerShell = $ps
        $script:WmtRegistryCleanupAsync = $async
        $script:WmtRegistryCleanupSync = $cleanupSync
        Write-GuiLog "Registry cleanup started in the background. WMT remains usable."
    }
    catch {
        $script:WmtRegistryCleanupActive = $false
        try { if ($ps) { $ps.Dispose() } } catch {}
        try { if ($runspace) { $runspace.Dispose() } } catch {}
        Write-GuiLog "Registry cleanup failed to start: $($_.Exception.Message)"
        Show-WmtMessageBox -Message "Registry cleanup failed to start:`n$($_.Exception.Message)" -Title "Registry Cleaner" -Image Error | Out-Null
        return
    }

    $lastLogIndex = 0
    $cleanupTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $cleanupTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $cleanupTimer.Add_Tick({
            try {
                while ($lastLogIndex -lt $cleanupSync.Logs.Count) {
                    Write-GuiLog ([string]$cleanupSync.Logs[$lastLogIndex])
                    $lastLogIndex++
                }

                try {
                    if ($lblStatus) {
                        $cleanupStatusText = [string]$cleanupSync.Status
                        $cleanupStatusText = ($cleanupStatusText -replace '[\r\n\t]+', '  ').Trim()
                        if ($cleanupStatusText.Length -gt 220) { $cleanupStatusText = $cleanupStatusText.Substring(0, 217) + '...' }
                        $lblStatus.Text = $cleanupStatusText
                    }
                    if ($barProgress) { $barProgress.Value = [double]$cleanupSync.Progress }
                }
                catch {}

                if (-not $cleanupSync.IsCompleted -and $async -and -not $async.IsCompleted) { return }

                $cleanupTimer.Stop()
                while ($lastLogIndex -lt $cleanupSync.Logs.Count) {
                    Write-GuiLog ([string]$cleanupSync.Logs[$lastLogIndex])
                    $lastLogIndex++
                }

                try {
                    if ($ps -and $async) { [void]$ps.EndInvoke($async) }
                }
                catch {
                    if (-not $cleanupSync.Error) { $cleanupSync.Error = $_.Exception.Message }
                }
                finally {
                    try { if ($ps) { $ps.Dispose() } } catch {}
                    try { if ($runspace) { $runspace.Dispose() } } catch {}
                    $script:WmtRegistryCleanupActive = $false
                    if ([object]::ReferenceEquals($script:WmtRegistryCleanupRunspace, $runspace)) { $script:WmtRegistryCleanupRunspace = $null }
                    if ([object]::ReferenceEquals($script:WmtRegistryCleanupPowerShell, $ps)) { $script:WmtRegistryCleanupPowerShell = $null }
                    if ([object]::ReferenceEquals($script:WmtRegistryCleanupTimer, $cleanupTimer)) { $script:WmtRegistryCleanupTimer = $null }
                    if ([object]::ReferenceEquals($script:WmtRegistryCleanupSync, $cleanupSync)) { $script:WmtRegistryCleanupSync = $null }
                    $script:WmtRegistryCleanupAsync = $null
                }

                try { if ($progressWindow) { $progressWindow.Close() } } catch {}

                if ($cleanupSync.Error) {
                    Write-GuiLog "Registry cleanup background worker error: $($cleanupSync.Error)"
                    Show-WmtMessageBox -Message "Registry cleanup failed:`n$($cleanupSync.Error)" -Title "Registry Cleaner" -Image Error | Out-Null
                    return
                }

                $result = $cleanupSync.Result
                if ($null -eq $result) {
                    Show-WmtMessageBox -Message "Registry cleanup finished, but no result summary was returned." -Title "Registry Cleaner" -Image Information | Out-Null
                    return
                }

                $finalMsg = "Cleanup Complete.`n`nFixed: $($result.Fixed) item(s)"
                if ([int]$result.Skipped -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$result.SkippedLogFile)) {
                    $finalMsg += "`nSkipped: $($result.Skipped) (details: $($result.SkippedLogFile))"
                }
                elseif ([int]$result.Skipped -gt 0) {
                    $finalMsg += "`nSkipped: $($result.Skipped)"
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$result.BackupFile)) {
                    $finalMsg += "`n`nBackup: $($result.BackupFile)"
                }
                else {
                    $finalMsg += "`n`nBackup: not created because nothing was successfully changed."
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$result.SkippedLogFile)) {
                    $finalMsg += "`nSkipped log: $($result.SkippedLogFile)"
                }
                Show-WmtMessageBox -Message $finalMsg -Title "Result" -Image Information | Out-Null
            }
            catch {
                try { $cleanupTimer.Stop() } catch {}
                try { if ($ps) { $ps.Dispose() } } catch {}
                try { if ($runspace) { $runspace.Dispose() } } catch {}
                $script:WmtRegistryCleanupActive = $false
                if ([object]::ReferenceEquals($script:WmtRegistryCleanupRunspace, $runspace)) { $script:WmtRegistryCleanupRunspace = $null }
                if ([object]::ReferenceEquals($script:WmtRegistryCleanupPowerShell, $ps)) { $script:WmtRegistryCleanupPowerShell = $null }
                if ([object]::ReferenceEquals($script:WmtRegistryCleanupTimer, $cleanupTimer)) { $script:WmtRegistryCleanupTimer = $null }
                if ([object]::ReferenceEquals($script:WmtRegistryCleanupSync, $cleanupSync)) { $script:WmtRegistryCleanupSync = $null }
                $script:WmtRegistryCleanupAsync = $null
                Write-GuiLog "Registry cleanup completion handler failed: $($_.Exception.Message)"
            }
        }.GetNewClosure())
    $script:WmtRegistryCleanupTimer = $cleanupTimer
    $cleanupTimer.Start()
}

function Test-WmtUpdateScanEngineBusy {
    try {
        if ($script:ActiveScans -and $script:ActiveScans.Count -gt 0) { return $true }
        if ($script:ScanTimer -and $script:ScanTimer.IsEnabled) { return $true }
        if ($script:GlobalScanTimer -and $script:GlobalScanTimer.IsEnabled) { return $true }
        if ($script:WingetScanSourcePreflightInProgress) { return $true }
        if ($script:WingetActiveAction) { return $true }
        if ($btnWingetScan -and -not $btnWingetScan.IsEnabled) { return $true }
    }
    catch {}
    return $false
}

function Test-WmtPackageSearchActive {
    try {
        # A live package search always owns the shared Updates/Search result list.
        if ($script:AsyncSearch) { return $true }
        if ($script:AsyncPowerShell) { return $true }
        if ($script:SearchTimer -and $script:SearchTimer.IsEnabled) { return $true }
        if ($btnWingetFind -and -not $btnWingetFind.IsEnabled) { return $true }
        if ($txtWingetSearch -and -not $txtWingetSearch.IsEnabled) { return $true }

        # Completed search results should only block auto scans while the user can actually see that view.
        $windowVisible = $true
        if ($window) {
            $windowVisible = ($window.Visibility -eq [System.Windows.Visibility]::Visible -and $window.WindowState -ne [System.Windows.WindowState]::Minimized)
        }
        if (-not $windowVisible) { return $false }

        $updatesVisible = $true
        if ($pnlUpdates) { $updatesVisible = ($pnlUpdates.Visibility -eq [System.Windows.Visibility]::Visible) }
        if (-not $updatesVisible) { return $false }

        if ($script:WmtPackageSearchActive) { return $true }
        if ($lblWingetTitle -and ([string]$lblWingetTitle.Text).StartsWith("Search Results:", [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($btnWingetInstall -and $btnWingetInstall.Visibility -eq [System.Windows.Visibility]::Visible) { return $true }
    }
    catch {}
    return $false
}

function Test-WmtUpdateAutoScanBusy {
    try {
        if (Test-WmtUpdateScanEngineBusy) { return $true }
        if (Test-WmtPackageSearchActive) { return $true }
    }
    catch {}
    return $false
}

function Get-WmtUpdateListItemKey {
    param([object]$Item)
    if (-not $Item) { return "" }

    $source = ([string]$Item.Source).Trim().ToLowerInvariant()
    $id = ([string]$Item.Id).Trim().ToLowerInvariant()
    $name = ([string]$Item.Name).Trim().ToLowerInvariant()
    $available = ([string]$Item.Available).Trim().ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($id)) { $id = $name }
    if ([string]::IsNullOrWhiteSpace($source) -or [string]::IsNullOrWhiteSpace($id)) { return "" }
    return "$source|$id|$available"
}

function Get-WmtVisibleUpdateResultItems {
    if (-not $lstWinget) { return @() }

    $seen = @{}
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($lstWinget.Items)) {
        if (-not $item -or -not $item.PSObject.Properties["Name"]) { continue }

        $source = ([string]$item.Source).Trim()
        $name = ([string]$item.Name).Trim()
        $id = ([string]$item.Id).Trim()
        $available = ([string]$item.Available).Trim()

        if ([string]::IsNullOrWhiteSpace($source)) { continue }
        if ([string]::IsNullOrWhiteSpace($name) -or $name -in @("No results found", "No updates available")) { continue }
        if ([string]::IsNullOrWhiteSpace($available) -or $available -eq "-") { continue }
        if ([string]::IsNullOrWhiteSpace($id) -and ([string]::IsNullOrWhiteSpace($name))) { continue }

        $key = Get-WmtUpdateListItemKey -Item $item
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        if ($seen.ContainsKey($key)) { continue }

        $seen[$key] = $true
        [void]$items.Add($item)
    }
    return $items.ToArray()
}

function Invoke-WmtUpdateAutoScan {
    param([switch]$Force)

    $minutes = Get-WmtUpdateAutoScanMinutes
    if ($minutes -le 0 -and -not $Force) { return }

    if (Test-WmtUpdateAutoScanBusy) {
        if (Test-WmtPackageSearchActive) {
            Write-GuiLog "Auto scan skipped because package search/results are active."
        }
        else {
            Write-GuiLog "Auto scan skipped because an update scan or package action is already running."
        }
        return
    }

    if (-not $btnWingetScan) { return }
    $script:WmtUpdateAutoScanLastRun = Get-Date
    $script:WmtUpdateAutoScanPending = $true
    Write-GuiLog "Auto scan starting in background..."
    try {
        $btnWingetScan.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
    }
    catch {
        $script:WmtUpdateAutoScanPending = $false
        $script:WmtUpdateAutoScanActive = $false
        Write-GuiLog "Auto scan failed to start: $($_.Exception.Message)"
    }
}

function Start-WmtUpdateAutoScanTimer {
    param([switch]$ResetNextRun)

    $minutes = Get-WmtUpdateAutoScanMinutes

    # DispatcherTimer is not IDisposable. Stop it and detach the Tick handler instead.
    Stop-WmtUpdateAutoScanTimer

    if ($minutes -le 0) {
        Write-GuiLog "Update auto scan is disabled."
        return
    }

    $script:WmtUpdateAutoScanIntervalMinutes = $minutes
    if ($ResetNextRun -or -not $script:WmtUpdateAutoScanLastRun) {
        $script:WmtUpdateAutoScanLastRun = Get-Date
    }

    $script:WmtUpdateAutoScanTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:WmtUpdateAutoScanTimer.Interval = [TimeSpan]::FromMinutes($minutes)
    $script:WmtUpdateAutoScanTimerTickHandler = [System.EventHandler] {
        param($s, $eventArg)
        Invoke-WmtUpdateAutoScan
    }
    $script:WmtUpdateAutoScanTimer.Add_Tick($script:WmtUpdateAutoScanTimerTickHandler)
    $script:WmtUpdateAutoScanTimer.Start()
    Write-GuiLog "Update auto scan enabled: every $minutes minute(s) while WMT is open."
}

function Stop-WmtUpdateAutoScanTimer {
    if ($script:WmtUpdateAutoScanTimer) {
        try { $script:WmtUpdateAutoScanTimer.Stop() } catch {}
        try {
            if ($script:WmtUpdateAutoScanTimerTickHandler) {
                $script:WmtUpdateAutoScanTimer.Remove_Tick($script:WmtUpdateAutoScanTimerTickHandler)
            }
        }
        catch {}
        $script:WmtUpdateAutoScanTimer = $null
    }
    $script:WmtUpdateAutoScanTimerTickHandler = $null
}

function Start-WingetScanSourcePreflight {
    param([string[]]$Sources)

    if (-not $Sources -or $Sources.Count -eq 0) {
        $script:WingetSourcePreflightReadyForScan = $true
        if ($btnWingetScan) {
            $btnWingetScan.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
        }
        return
    }

    if ($script:WingetScanSourcePreflightInProgress) {
        Write-GuiLog "Winget source preflight is already running."
        return
    }

    $script:WingetScanSourcePreflightInProgress = $true
    $script:WingetSourcePreflightReadyForScan = $false
    $script:WingetSourcePreflightSources = @($Sources | Select-Object -Unique)

    Write-GuiLog "Preparing winget sources before package scan: $($script:WingetSourcePreflightSources -join ', ')"
    if ($lblWingetStatus) {
        $lblWingetStatus.Text = "Preparing winget sources before scan..."
        $lblWingetStatus.Visibility = "Visible"
    }

    if ($script:WingetSourcePreflightTimer) {
        try { $script:WingetSourcePreflightTimer.Stop() } catch {}
        $script:WingetSourcePreflightTimer = $null
    }
    if ($script:WingetSourcePreflightRunspace) {
        try { $script:WingetSourcePreflightRunspace.Stop() } catch {}
        try { $script:WingetSourcePreflightRunspace.Dispose() } catch {}
        $script:WingetSourcePreflightRunspace = $null
    }

    $script:WingetSourcePreflightRunspace = [PowerShell]::Create().AddScript({
            param([string[]]$Sources)
            [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
            $log = New-Object System.Collections.Generic.List[string]

            function Add-Log { param([string]$Text) if (-not [string]::IsNullOrWhiteSpace($Text)) { [void]$log.Add($Text) } }
            function Invoke-WingetProcess {
                param([string]$Arguments, [int]$TimeoutMs = 30000)
                $psi = [System.Diagnostics.ProcessStartInfo]::new()
                $psi.FileName = "winget"
                $psi.Arguments = $Arguments
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                try { $psi.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
                try { $psi.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
                $proc = [System.Diagnostics.Process]::Start($psi)
                try { $proc.BeginOutputReadLine() } catch {}
                try { $proc.BeginErrorReadLine() } catch {}
                if (-not $proc.WaitForExit($TimeoutMs)) {
                    try { $proc.Kill() } catch {}
                    return [PSCustomObject]@{ ExitCode = -1; TimedOut = $true }
                }
                return [PSCustomObject]@{ ExitCode = [int]$proc.ExitCode; TimedOut = $false }
            }

            foreach ($source in @($Sources | Select-Object -Unique)) {
                try {
                    $refreshTimeoutMs = if ($source -eq "msstore") { 15000 } else { 30000 }
                    Add-Log "LOG:Refreshing $source source before scan (quick preflight, max $([int]($refreshTimeoutMs / 1000))s)..."
                    $refresh = Invoke-WingetProcess -Arguments "source update --name $source --disable-interactivity" -TimeoutMs $refreshTimeoutMs

                    if ($refresh.TimedOut) {
                        Add-Log "LOG:$source source refresh timed out after $([int]($refreshTimeoutMs / 1000))s; continuing to scan anyway."
                    }
                    elseif ($refresh.ExitCode -eq 0) {
                        Add-Log "LOG:$source source refresh completed before scan."
                    }
                    else {
                        Add-Log "LOG:$source source refresh exited with code $($refresh.ExitCode); continuing to scan anyway."
                    }
                }
                catch {
                    Add-Log "LOG:$source source preflight failed: $($_.Exception.Message); continuing to scan anyway."
                }
            }

            Add-Log "LOG:Winget source preflight finished; starting package scan."
            return $log.ToArray()
        }).AddArgument([string[]]$script:WingetSourcePreflightSources)

    $script:WingetSourcePreflightAsyncResult = $script:WingetSourcePreflightRunspace.BeginInvoke()
    $script:WingetSourcePreflightTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:WingetSourcePreflightTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $script:WingetSourcePreflightTimer.Add_Tick({
            if (-not $script:WingetSourcePreflightAsyncResult) { return }
            if (-not $script:WingetSourcePreflightAsyncResult.IsCompleted) { return }

            $script:WingetSourcePreflightTimer.Stop()
            try {
                $lines = $script:WingetSourcePreflightRunspace.EndInvoke($script:WingetSourcePreflightAsyncResult)
                foreach ($line in $lines) {
                    if ($line -is [string] -and $line.StartsWith("LOG:")) { Write-GuiLog ($line.Substring(4)) }
                    elseif ($line) { Write-GuiLog ([string]$line) }
                }
            }
            catch {
                Write-GuiLog "Winget source preflight background error: $($_.Exception.Message)"
            }
            finally {
                try { $script:WingetSourcePreflightRunspace.Dispose() } catch {}
                $script:WingetSourcePreflightRunspace = $null
                $script:WingetSourcePreflightAsyncResult = $null
                $script:WingetScanSourcePreflightInProgress = $false
                $script:WingetSourcePreflightReadyForScan = $true
            }

            if ($btnWingetScan) {
                $btnWingetScan.IsEnabled = $true
                $btnWingetScan.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
            }
        })
    $script:WingetSourcePreflightTimer.Start()
}

function Test-WingetRestartRiskItem {
    param($Item)
    if (-not $Item) { return $false }
    $id = [string]$Item.Id
    $name = [string]$Item.Name
    $eaIdPattern = '(?i)(ElectronicArts|EA\.Desktop|EADesktop|EAapp)'
    $eaNamePattern = '(?i)\b(EA app|Electronic Arts|EA Desktop)\b'
    return ($id -match $eaIdPattern -or $name -match $eaNamePattern)
}

function Show-WingetRestartRiskWarning {
    param(
        [object[]]$Items,
        [string]$Action = "Update"
    )
    if ($Action -ne "Update") { return $true }
    $risky = @($Items | Where-Object { Test-WingetRestartRiskItem $_ })
    if ($risky.Count -eq 0) { return $true }

    $pkgNames = @($risky | ForEach-Object {
            if ([string]::IsNullOrWhiteSpace([string]$_.Name)) { [string]$_.Id } else { [string]$_.Name }
        } | Select-Object -Unique)
    $joined = ($pkgNames -join ", ")
    if ([string]::IsNullOrWhiteSpace($joined)) { $joined = "the selected EA package" }

    $msg = "Warning: Updating $joined may trigger a Windows restart (installer behavior outside WMT control).`n`nDo you want to continue?"
    $res = [System.Windows.MessageBox]::Show($msg, "Restart Warning", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    return ($res -eq [System.Windows.MessageBoxResult]::Yes)
}

function Get-WingetListedUpdateItems {
    if (-not $lstWinget) { return @() }
    return @($lstWinget.Items | Where-Object {
            $id = [string]$_.Id
            $source = [string]$_.Source
            $name = [string]$_.Name
            $isStore = ($source.ToLowerInvariant() -eq "msstore")
            ($isStore -or -not [string]::IsNullOrWhiteSpace($id)) -and
            -not [string]::IsNullOrWhiteSpace($source) -and
            $name -notin @("No results found", "No updates available")
        })
}

function Invoke-WmtAutoInstallAvailableUpdates {
    if (-not (Get-WmtUpdateAutoInstallEnabled)) { return }
    if ($script:WmtAutoInstallActive -or $script:WingetActiveAction) {
        Write-GuiLog "Auto install skipped because a package action is already running."
        return
    }

    $items = @(Get-WingetListedUpdateItems)
    if ($items.Count -eq 0) {
        Write-GuiLog "Auto install found no available updates."
        return
    }

    $restartRiskItems = @($items | Where-Object { Test-WingetRestartRiskItem $_ })
    $eligibleItems = @($items | Where-Object { -not (Test-WingetRestartRiskItem $_) })
    if ($restartRiskItems.Count -gt 0) {
        $restartRiskNames = @($restartRiskItems | ForEach-Object {
                if ([string]::IsNullOrWhiteSpace([string]$_.Name)) { [string]$_.Id } else { [string]$_.Name }
            } | Select-Object -Unique)
        Write-GuiLog "Auto install skipped $($restartRiskItems.Count) restart-risk update(s): $($restartRiskNames -join ', ')."
    }
    if ($eligibleItems.Count -eq 0) {
        Write-GuiLog "Auto install had no eligible updates after safety filtering."
        return
    }

    $actionItems = @(ConvertTo-WmtUpdateAllActionItems -Items $eligibleItems)
    if ($actionItems.Count -eq 0) { return }

    $script:WmtAutoInstallActive = $true
    Write-GuiLog "Auto install starting $($eligibleItems.Count) available update(s)."
    Show-WmtBackgroundInstallNotification -Status Started -TotalCount $eligibleItems.Count
    & $Script:StartWingetAction -ListItems $actionItems -ActionName "Update"
}

function ConvertTo-WmtUpdateAllActionItems {
    param([object[]]$Items)

    $storeCount = @($Items | Where-Object { ([string]$_.Source).ToLowerInvariant() -eq "msstore" }).Count
    if ($storeCount -eq 0) { return @($Items) }

    $result = New-Object System.Collections.Generic.List[object]
    $storeActionAdded = $false
    foreach ($item in $Items) {
        if (([string]$item.Source).ToLowerInvariant() -eq "msstore") {
            if (-not $storeActionAdded) {
                $storeName = "Microsoft Store Updates"
                if ($storeCount -gt 1) { $storeName = "Microsoft Store Updates ($storeCount listed)" }
                [void]$result.Add([PSCustomObject]@{
                        Source = "msstore"
                        Name   = $storeName
                        Id     = "__WMT_STORE_UPDATES_ALL__"
                    })
                $storeActionAdded = $true
            }
            continue
        }

        [void]$result.Add($item)
    }

    return $result.ToArray()
}

function Test-WmtMyDevicePreloadBusy {
    try {
        if ($script:MyDevicePendingSections -and $script:MyDevicePendingSections.Count -gt 0) { return $true }
        if ($script:MyDeviceSectionJobs -and $script:MyDeviceSectionJobs.Count -gt 0) { return $true }
        if ($script:BitLockerStatusAsyncResult -and -not $script:BitLockerStatusAsyncResult.IsCompleted) { return $true }
    }
    catch {}

    return $false
}

function Stop-WmtStartupBackgroundPreload {
    if ($script:WmtStartupPreloadTimer) {
        try { $script:WmtStartupPreloadTimer.Stop() } catch {}
        $script:WmtStartupPreloadTimer = $null
    }
}

function Start-WmtStartupBackgroundPreload {
    if ($script:WmtStartupPreloadTimer) { return }

    if (-not $script:MyDeviceStatsStarted) {
        Update-MyDeviceStats -Preload
    }
    if (-not $script:FirewallRulesLoaded -and -not $script:FirewallLoadInProgress) {
        Start-FirewallRuleLoad -Preload
    }

    $script:WmtStartupPreloadTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:WmtStartupPreloadTimer.Interval = [TimeSpan]::FromMilliseconds(1000)
    $script:WmtStartupPreloadTimer.Add_Tick({
            if (Test-WmtMyDevicePreloadBusy) { return }
            if ($script:FirewallLoadInProgress) { return }
            Stop-WmtStartupBackgroundPreload
        })
    $script:WmtStartupPreloadTimer.Start()
}

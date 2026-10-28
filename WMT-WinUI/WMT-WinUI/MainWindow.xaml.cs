using System;
using System.IO;
using System.Management.Automation;
using System.Threading.Tasks;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Graphics;
using System.Linq;
using System.Collections.ObjectModel;

namespace WMT_WinUI;

public sealed partial class MainWindow : Window
{
    private PowerShellService? _psService;
    private ObservableCollection<string> _logLines = new();

    public MainWindow()
    {
        InitializeComponent();
        _psService = new PowerShellService();
    }

    private void OnWindowActivated(object sender, WindowActivatedEventArgs args)
    {
        // Ensure admin elevation
        var isAdmin = new System.Security.Principal.WindowsPrincipal(
            System.Security.Principal.WindowsIdentity.GetCurrent())
            .IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
        if (!isAdmin)
        {
            AppendLog("[WARN] Application is not running as Administrator. Some features may be unavailable.");
        }
        else
        {
            AppendLog("[Info] Elevated session confirmed.");
        }
    }

    private void OnWindowClosed(object sender, WindowEventArgs args)
    {
        _psService?.Dispose();
        // Signal any background workers to stop
        try
        {
            using (var ps = PowerShell.Create())
            {
                ps.AddScript("Stop-WmtBackgroundOperationManager");
                ps.Invoke();
            }
        }
        catch { }
    }

    private void OnWindowSizeChanged(object sender, SizeChangedEventArgs args)
    {
        // Responsive adjustments if needed
    }

    private void OnNavLoaded(object sender, RoutedEventArgs e)
    {
        // Default selection
        NavView.SelectedItem = NavView.MenuItems.OfType<NavigationViewItem>().First();
    }

    private void OnNavSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.IsSettingsSelected)
        {
            ContentFrame.Navigate(typeof(Pages.SettingsPage));
            return;
        }

        if (args.SelectedItem is NavigationViewItem item)
        {
            switch (item.Tag?.ToString())
            {
                case "Dashboard":
                    ContentFrame.Navigate(typeof(Pages.DashboardPage));
                    break;
                case "Cleaner":
                    ContentFrame.Navigate(typeof(Pages.CleanerPage));
                    break;
                case "Updates":
                    ContentFrame.Navigate(typeof(Pages.UpdatesPage));
                    break;
                case "DeviceInfo":
                    ContentFrame.Navigate(typeof(Pages.DeviceInfoPage));
                    break;
                case "Network":
                    ContentFrame.Navigate(typeof(Pages.NetworkPage));
                    break;
                case "Storage":
                    ContentFrame.Navigate(typeof(Pages.StoragePage));
                    break;
                case "Power":
                    ContentFrame.Navigate(typeof(Pages.PowerPage));
                    break;
                case "Settings":
                    ContentFrame.Navigate(typeof(Pages.SettingsPage));
                    break;
            }
        }
    }

    private async void OnRefreshClick(object sender, RoutedEventArgs e)
    {
        SetStatus("Refreshing...", true);
        AppendLog("[Info] User triggered refresh.");
        try
        {
            await Task.Run(() =>
            {
                using (var ps = PowerShell.Create())
                {
                    ps.AddScript("Import-Module -Name $(Join-Path $PSScriptRoot '..\\WMT-Engine.psm1') -Force; Get-WmtDeviceInfo -Section 'All' | ConvertTo-Json -Depth 5");
                    ps.AddParameter("EngineRoot", Path.GetDirectoryName(Path.GetFullPath("..\\WMT-Engine.psm1")) ?? "");
                    ps.Invoke();
                }
            });
            AppendLog("[Info] Refresh completed.");
            SetStatus("Ready", false);
        }
        catch (Exception ex)
        {
            AppendLog($"[ERROR] Refresh failed: {ex.Message}");
            SetStatus("Refresh failed", false);
        }
    }

    private async void OnRunScanClick(object sender, RoutedEventArgs e)
    {
        SetStatus("Running system scan...", true);
        AppendLog("[Info] Scan started.");
        try
        {
            await Task.Run(() =>
            {
                _psService?.RunCleaner("Scan");
            });
        }
        catch (Exception ex)
        {
            AppendLog($"[ERROR] Scan failed: {ex.Message}");
        }
        finally
        {
            SetStatus("Scan completed", false);
        }
    }

    public void AppendLog(string message)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            LogTextBlock.Text += $"{message}\n";
            LogScrollViewer?.ChangeView(0, LogScrollViewer.ScrollableHeight, null);
        });
    }

    public void SetStatus(string message, bool isBusy)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            StatusMessage.Text = message;
            ProgressRing.IsActive = isBusy;
            StatusIndicator.Text = isBusy ? "● Running" : "● Ready";
            StatusIndicator.Foreground = isBusy
                ? new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Orange)
                : new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.ForestGreen);
        });
    }
}

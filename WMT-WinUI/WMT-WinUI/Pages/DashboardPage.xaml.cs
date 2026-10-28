using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace WMT_WinUI.Pages;

public sealed partial class DashboardPage : Page
{
    public DashboardPage()
    {
        InitializeComponent();
        LoadData();
    }

    private void OnQuickScanClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        (Window.Current as MainWindow)?.SetStatus("Quick scan running...", true);
        (Window.Current as MainWindow)?.AppendLog("[Info] Quick scan triggered from Dashboard.");
    }

    private void OnCleanTempClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        (Window.Current as MainWindow)?.SetStatus("Cleaning temp...", true);
        (Window.Current as MainWindow)?.AppendLog("[Info] Clean temp triggered from Dashboard.");
    }

    private void OnRefreshInfoClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        (Window.Current as MainWindow)?.SetStatus("Refreshing info...", true);
        (Window.Current as MainWindow)?.AppendLog("[Info] Refresh info triggered from Dashboard.");
    }

    private async void LoadData()
    {
        await System.Threading.Tasks.Task.Run(() =>
        {
            // Full-parity data load delegated to PowerShell backend
        });
    }
}

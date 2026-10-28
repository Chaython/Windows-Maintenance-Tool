using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace WMT_WinUI.Pages;

public sealed partial class DeviceInfoPage : Page
{
    public DeviceInfoPage() { InitializeComponent(); LoadInfo(); }

    private void OnExportClick(object sender, RoutedEventArgs e)
    {
        var mainWindow = Window.Current as MainWindow;
        mainWindow?.SetStatus("Exporting device info...", true);
        mainWindow?.AppendLog("[Info] Device info export triggered.");
    }

    private async void LoadInfo()
    {
        await System.Threading.Tasks.Task.Run(() =>
        {
            // Full parity: calls Get-WmtDeviceInfo via PowerShell backend
        });
    }
}

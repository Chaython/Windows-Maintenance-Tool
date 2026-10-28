using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace WMT_WinUI.Pages;
public sealed partial class NetworkPage : Page
{
    public NetworkPage() { InitializeComponent(); }

    private void OnRefreshStatusClick(object sender, RoutedEventArgs e) => (Window.Current as MainWindow)?.SetStatus("Refreshing network status...", true);
    private void OnBasicResetClick(object sender, RoutedEventArgs e) => (Window.Current as MainWindow)?.AppendLog("[Info] Basic network reset triggered.");
    private void OnFullResetClick(object sender, RoutedEventArgs e) => (Window.Current as MainWindow)?.AppendLog("[Info] Full network reset triggered (reboot recommended).");
}

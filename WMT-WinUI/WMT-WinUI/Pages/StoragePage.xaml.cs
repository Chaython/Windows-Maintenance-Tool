using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace WMT_WinUI.Pages;
public sealed partial class StoragePage : Page
{
    public StoragePage() { InitializeComponent(); }
    private void OnCleanupClick(object sender, RoutedEventArgs e) => (Window.Current as MainWindow)?.AppendLog("[Info] Storage cleanup triggered.");
}

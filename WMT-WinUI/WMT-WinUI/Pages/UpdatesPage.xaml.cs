using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace WMT_WinUI.Pages;

public sealed partial class UpdatesPage : Page
{
    public UpdatesPage() { InitializeComponent(); }

    private void OnCheckUpdatesClick(object sender, RoutedEventArgs e)
    {
        var mainWindow = Window.Current as MainWindow;
        mainWindow?.SetStatus("Checking for updates...", true);
        mainWindow?.AppendLog("[Info] Update check triggered from Updates page.");
    }
}

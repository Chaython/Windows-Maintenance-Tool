using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace WMT_WinUI.Pages;

public sealed partial class CleanerPage : Page
{
    public CleanerPage()
    {
        InitializeComponent();
    }

    private void OnRunCleanClick(object sender, RoutedEventArgs e)
    {
        var mainWindow = Window.Current as MainWindow;
        mainWindow?.SetStatus("Standard clean in progress...", true);
        mainWindow?.AppendLog("[Info] Standard clean started.");
    }

    private void OnDeepCleanClick(object sender, RoutedEventArgs e)
    {
        var mainWindow = Window.Current as MainWindow;
        mainWindow?.SetStatus("Deep clean in progress...", true);
        mainWindow?.AppendLog("[Info] Deep clean started (this may take a while).");
    }

    private void OnRefreshSourcesClick(object sender, RoutedEventArgs e)
    {
        var mainWindow = Window.Current as MainWindow;
        mainWindow?.SetStatus("Refreshing cleaner sources...", true);
        mainWindow?.AppendLog("[Info] Cleaner refresh started.");
    }
}

using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using Windows.Graphics;

namespace WMT_WinUI;

public partial class App : Application
{
    public static MainWindow? MainWindowInstance { get; private set; }
    private Window? m_window;

    public App()
    {
        InitializeComponent();
        UnhandledException += OnUnhandledException;
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        m_window = new MainWindow();
        MainWindowInstance = m_window as MainWindow;
        m_window.Activate();

        // Set window title and icon
        if (m_window is MainWindow mainWindow)
        {
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(m_window);
            var windowId = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hwnd);
            var appWindow = AppWindow.GetFromWindowId(windowId);

            // Center and size the window
            var displayArea = DisplayArea.GetFromWindowId(windowId, DisplayAreaFallback.Primary);
            if (displayArea != null)
            {
                RectInt32 workArea = displayArea.WorkArea;
                int width = Math.Min(1400, workArea.Width - 100);
                int height = Math.Min(950, workArea.Height - 50);
                int x = workArea.X + (workArea.Width - width) / 2;
                int y = workArea.Y + (workArea.Height - height) / 2;
                appWindow.MoveAndResize(new RectInt32(x, y, width, height));
            }
        }
    }

    private void OnUnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
    {
        try
        {
            File.AppendAllText(
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WMT", "crash.log"),
                $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] UNHANDLED: {e.Exception.Message}\n{e.Exception.StackTrace}\n");
        }
        catch { }
        e.Handled = true;
    }
}

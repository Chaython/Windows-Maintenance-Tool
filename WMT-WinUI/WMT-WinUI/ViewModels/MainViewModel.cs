using CommunityToolkit.Mvvm.ComponentModel;

namespace WMT_WinUI.ViewModels;

public partial class MainViewModel : ObservableObject
{
    [ObservableProperty]
    private string statusMessage = "Ready";

    [ObservableProperty]
    private bool isBusy = false;

    public MainViewModel()
    {
    }
}

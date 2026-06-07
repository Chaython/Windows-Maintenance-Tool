# Functional block generated from WMT-GUI.ps1.
# Dot-source this file; it intentionally shares WMT's script scope.

function Invoke-WmtDispatcherPump {
    param([System.Windows.Threading.Dispatcher]$Dispatcher = $null)

    try {
        if (-not $Dispatcher) { $Dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher }
        $Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
    }
    catch {}
}

function Set-WmtBusyCursor {
    param([switch]$Busy)

    try {
        [System.Windows.Input.Mouse]::OverrideCursor = if ($Busy) { [System.Windows.Input.Cursors]::Wait } else { $null }
    }
    catch {}
}

function Invoke-UiCommand {
    param(
        [scriptblock]$Sb, 
        $Msg = "Processing...", 
        [object[]]$ArgumentList = @()
    )
    try {
        Set-WmtBusyCursor -Busy
        Write-GuiLog $Msg
        # Pass arguments to the scriptblock using splatting
        $res = & $Sb @ArgumentList | Out-String
        if (-not [string]::IsNullOrWhiteSpace($res)) { Write-GuiLog $res.Trim() }
        else { Write-GuiLog "Done." }
    }
    catch { 
        Write-GuiLog "ERROR: $($_.Exception.Message)" 
    }
    finally {
        Set-WmtBusyCursor
    }
}

function Enable-WmtWpfItemsVirtualization {
    param([System.Windows.Controls.ItemsControl]$Control)
    if (-not $Control) { return }
    try {
        [System.Windows.Controls.VirtualizingStackPanel]::SetIsVirtualizing($Control, $true)
        [System.Windows.Controls.VirtualizingStackPanel]::SetVirtualizationMode($Control, [System.Windows.Controls.VirtualizationMode]::Recycling)
        [System.Windows.Controls.ScrollViewer]::SetCanContentScroll($Control, $true)
    }
    catch {}
}

function Resolve-WmtThemeResourceKey {
    param([string]$ColorOrKey)

    if ([string]::IsNullOrWhiteSpace($ColorOrKey)) { return $null }
    $value = $ColorOrKey.Trim()

    if ($script:ThemePalettes) {
        foreach ($theme in @($script:ThemePalettes.Keys)) {
            if ($script:ThemePalettes[$theme].ContainsKey($value)) { return $value }
        }
    }

    switch -Regex ($value.ToUpperInvariant()) {
        "^#0D1117$" { return "BgDark" }
        "^#161B22$" { return "BgPanel" }
        "^#1C1C1E$" { return "BgPanel" }
        "^#141416$" { return "BgPanel" }
        "^#21262D$" { return "BgElevated" }
        "^#252526$" { return "BgElevated" }
        "^#30363D$" { return "BorderBrush" }
        "^#2C2C2E$" { return "BorderBrush" }
        "^#58A6FF$" { return "Accent" }
        "^#0078D7$" { return "Accent" }
        "^#1A0078D7$" { return "BgElevated" }
        "^#79C0FF$" { return "AccentHover" }
        "^#E6EDF3$" { return "TextPrimary" }
        "^#EBEBF5$" { return "TextPrimary" }
        "^#8B949E$" { return "TextSecondary" }
        "^#98989D$" { return "TextSecondary" }
        "^#6E7681$" { return "TextMuted" }
        "^#6E6E73$" { return "TextMuted" }
        "^#238636$" { return "Success" }
        "^#3FB950$" { return "SuccessHover" }
        "^#2EA043$" { return "SuccessHover" }
        "^#DA3633$" { return "Danger" }
        "^#F85149$" { return "DangerHover" }
        "^#D29922$" { return "Warning" }
        "^#E3B341$" { return "WarningHover" }
        "^#FFFFFF$" { return "AccentText" }
        "^WHITE$" { return "AccentText" }
        "^BLACK$" { return "BgDark" }
        default { return $null }
    }
}

function New-WmtBrush {
    param([string]$ColorOrKey)

    $resourceKey = Resolve-WmtThemeResourceKey $ColorOrKey
    if ($resourceKey -and $window -and $window.Resources[$resourceKey]) {
        return $window.Resources[$resourceKey]
    }

    if (-not $script:WmtBrushConverter) {
        $script:WmtBrushConverter = [System.Windows.Media.BrushConverter]::new()
    }

    try { return $script:WmtBrushConverter.ConvertFromString($ColorOrKey) }
    catch { return $script:WmtBrushConverter.ConvertFromString("#8B949E") }
}

function Set-WmtThemeResources {
    param(
        [System.Windows.FrameworkElement]$Element,
        [hashtable]$Palette
    )

    if (-not $Element -or -not $Palette) { return }
    foreach ($key in $Palette.Keys) {
        if ($key -eq "LogText") { continue }
        $color = [System.Windows.Media.ColorConverter]::ConvertFromString($Palette[$key])
        $Element.Resources[$key] = [System.Windows.Media.SolidColorBrush]::new($color)
    }
}

function Set-WmtThemedBrush {
    param(
        [System.Windows.DependencyObject]$Object,
        [System.Windows.DependencyProperty]$Property,
        [string]$ColorOrKey,
        [string]$FallbackKey = "TextSecondary"
    )

    if (-not $Object -or -not $Property) { return }

    $resourceKey = Resolve-WmtThemeResourceKey $ColorOrKey
    if (-not $resourceKey) { $resourceKey = $FallbackKey }

    if ($resourceKey -and $Object -is [System.Windows.FrameworkElement]) {
        $Object.SetResourceReference($Property, $resourceKey)
        return
    }
    if ($resourceKey -and $Object -is [System.Windows.FrameworkContentElement]) {
        $Object.SetResourceReference($Property, $resourceKey)
        return
    }

    $Object.SetValue($Property, (New-WmtBrush $ColorOrKey))
}

function Set-WmtWindowOwner {
    param([System.Windows.Window]$Child)

    if (-not $Child) { return }
    try {
        if ($window -and [object]::ReferenceEquals($Child, $window) -eq $false -and $window.IsVisible) {
            $Child.Owner = $window
        }
    }
    catch {}
}

function Add-WmtWpfRuntimeResources {
    param([System.Windows.FrameworkElement]$Element)

    if (-not $Element) { return }
    try {
        if ($Element.Resources.Contains("__WmtRuntimeResourcesApplied")) { return }
        if ($Element.Resources.Contains("TransparentScrollRepeatButton")) {
            $Element.Resources["__WmtRuntimeResourcesApplied"] = $true
            return
        }

        [xml]$runtimeResourcesXaml = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Style TargetType="{x:Type TextBlock}">
        <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
        <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>

    <Style TargetType="{x:Type Button}">
        <Setter Property="Height" Value="34"/>
        <Setter Property="MinWidth" Value="86"/>
        <Setter Property="Padding" Value="14,0"/>
        <Setter Property="Background" Value="{DynamicResource BgElevated}"/>
        <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
        <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="SnapsToDevicePixels" Value="True"/>
        <Setter Property="UseLayoutRounding" Value="True"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="{x:Type Button}">
                    <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                            BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4">
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BgHover}"/>
                            <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource TextSecondary}"/>
                        </Trigger>
                        <Trigger Property="IsPressed" Value="True">
                            <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BorderBrush}"/>
                        </Trigger>
                        <Trigger Property="IsEnabled" Value="False">
                            <Setter Property="Opacity" Value="0.55"/>
                            <Setter Property="Cursor" Value="Arrow"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <Style TargetType="{x:Type TextBox}">
        <Setter Property="Background" Value="{DynamicResource BgDark}"/>
        <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
        <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Padding" Value="9,6"/>
        <Setter Property="SelectionBrush" Value="{DynamicResource Accent}"/>
        <Setter Property="CaretBrush" Value="{DynamicResource TextPrimary}"/>
        <Setter Property="SnapsToDevicePixels" Value="True"/>
        <Style.Triggers>
            <Trigger Property="IsFocused" Value="True">
                <Setter Property="BorderBrush" Value="{DynamicResource Accent}"/>
            </Trigger>
        </Style.Triggers>
    </Style>

    <Style TargetType="{x:Type ComboBox}">
        <Setter Property="Background" Value="{DynamicResource BgDark}"/>
        <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
        <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
    </Style>

    <Style TargetType="{x:Type CheckBox}">
        <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
        <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>

    <Style TargetType="{x:Type RadioButton}">
        <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
        <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>

    <Style x:Key="WmtNoGutterMenuItemStyle" TargetType="{x:Type MenuItem}">
        <Setter Property="OverridesDefaultStyle" Value="True"/>
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
        <Setter Property="Padding" Value="10,7"/>
        <Setter Property="MinWidth" Value="150"/>
        <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="{x:Type MenuItem}">
                    <Border x:Name="Bd" Background="{TemplateBinding Background}" SnapsToDevicePixels="True">
                        <ContentPresenter ContentSource="Header"
                                          RecognizesAccessKey="True"
                                          Margin="{TemplateBinding Padding}"
                                          VerticalAlignment="Center"
                                          HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsHighlighted" Value="True">
                            <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BgHover}"/>
                        </Trigger>
                        <Trigger Property="IsEnabled" Value="False">
                            <Setter Property="Opacity" Value="0.55"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <Style TargetType="{x:Type MenuItem}" BasedOn="{StaticResource WmtNoGutterMenuItemStyle}"/>

    <Style x:Key="WmtNoGutterSeparatorStyle" TargetType="{x:Type Separator}">
        <Setter Property="OverridesDefaultStyle" Value="True"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="{x:Type Separator}">
                    <Border Height="1" Margin="6,4" Background="{DynamicResource BorderBrush}"/>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <Style TargetType="{x:Type Separator}" BasedOn="{StaticResource WmtNoGutterSeparatorStyle}"/>

    <Style TargetType="{x:Type ContextMenu}">
        <Setter Property="Background" Value="{DynamicResource BgElevated}"/>
        <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
        <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Padding" Value="4"/>
        <Setter Property="SnapsToDevicePixels" Value="True"/>
        <Setter Property="ItemContainerStyle" Value="{StaticResource WmtNoGutterMenuItemStyle}"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="{x:Type ContextMenu}">
                    <Border Background="{TemplateBinding Background}"
                            BorderBrush="{TemplateBinding BorderBrush}"
                            BorderThickness="{TemplateBinding BorderThickness}"
                            Padding="{TemplateBinding Padding}"
                            SnapsToDevicePixels="True">
                        <ScrollViewer Focusable="False" CanContentScroll="True">
                            <ItemsPresenter KeyboardNavigation.DirectionalNavigation="Cycle"/>
                        </ScrollViewer>
                    </Border>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <Style TargetType="{x:Type ListBox}">
        <Setter Property="Background" Value="{DynamicResource BgDark}"/>
        <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
        <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
    </Style>

    <Style TargetType="{x:Type ProgressBar}">
        <Setter Property="Height" Value="10"/>
        <Setter Property="Background" Value="{DynamicResource BgPanel}"/>
        <Setter Property="Foreground" Value="{DynamicResource Accent}"/>
        <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
        <Setter Property="BorderThickness" Value="1"/>
    </Style>

    <Style TargetType="{x:Type DataGrid}">
        <Setter Property="Background" Value="{DynamicResource BgDark}"/>
        <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
        <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
        <Setter Property="GridLinesVisibility" Value="Horizontal"/>
        <Setter Property="HorizontalGridLinesBrush" Value="{DynamicResource BorderBrush}"/>
        <Setter Property="VerticalGridLinesBrush" Value="{DynamicResource BorderBrush}"/>
        <Setter Property="RowBackground" Value="{DynamicResource BgDark}"/>
        <Setter Property="AlternatingRowBackground" Value="{DynamicResource BgPanel}"/>
        <Setter Property="HeadersVisibility" Value="Column"/>
        <Setter Property="SelectionMode" Value="Extended"/>
        <Setter Property="SelectionUnit" Value="FullRow"/>
        <Setter Property="AutoGenerateColumns" Value="False"/>
    </Style>

    <Style TargetType="{x:Type DataGridColumnHeader}">
        <Setter Property="Background" Value="{DynamicResource BgPanel}"/>
        <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
        <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
        <Setter Property="BorderThickness" Value="0,0,1,1"/>
        <Setter Property="Padding" Value="8,6"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>

    <Style TargetType="{x:Type DataGridCell}">
        <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
        <Setter Property="BorderThickness" Value="0"/>
    </Style>

    <Style TargetType="{x:Type DataGridRow}">
        <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
        <Style.Triggers>
            <Trigger Property="IsSelected" Value="True">
                <Setter Property="Background" Value="{DynamicResource Accent}"/>
                <Setter Property="Foreground" Value="{DynamicResource AccentText}"/>
            </Trigger>
        </Style.Triggers>
    </Style>

    <Style x:Key="TransparentScrollRepeatButton" TargetType="{x:Type RepeatButton}">
        <Setter Property="Focusable" Value="False"/>
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="{x:Type RepeatButton}">
                    <Border Background="Transparent"/>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <Style TargetType="{x:Type ScrollBar}">
        <Setter Property="Width" Value="10"/>
        <Setter Property="MinWidth" Value="10"/>
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="{x:Type ScrollBar}">
                    <Grid Background="{TemplateBinding Background}" SnapsToDevicePixels="True">
                        <Track x:Name="PART_Track" IsDirectionReversed="True">
                            <Track.DecreaseRepeatButton>
                                <RepeatButton x:Name="PageDecreaseButton" Command="{x:Static ScrollBar.PageUpCommand}" Style="{StaticResource TransparentScrollRepeatButton}"/>
                            </Track.DecreaseRepeatButton>
                            <Track.Thumb>
                                <Thumb x:Name="ScrollThumb" MinHeight="34" Background="{DynamicResource BorderBrush}">
                                    <Thumb.Template>
                                        <ControlTemplate TargetType="{x:Type Thumb}">
                                            <Border Background="{TemplateBinding Background}" CornerRadius="5" Margin="2"/>
                                        </ControlTemplate>
                                    </Thumb.Template>
                                </Thumb>
                            </Track.Thumb>
                            <Track.IncreaseRepeatButton>
                                <RepeatButton x:Name="PageIncreaseButton" Command="{x:Static ScrollBar.PageDownCommand}" Style="{StaticResource TransparentScrollRepeatButton}"/>
                            </Track.IncreaseRepeatButton>
                        </Track>
                    </Grid>
                    <ControlTemplate.Triggers>
                        <Trigger Property="Orientation" Value="Horizontal">
                            <Setter Property="Width" Value="Auto"/>
                            <Setter Property="MinWidth" Value="0"/>
                            <Setter Property="Height" Value="10"/>
                            <Setter Property="MinHeight" Value="10"/>
                            <Setter TargetName="PART_Track" Property="IsDirectionReversed" Value="False"/>
                            <Setter TargetName="ScrollThumb" Property="MinWidth" Value="34"/>
                            <Setter TargetName="ScrollThumb" Property="MinHeight" Value="0"/>
                            <Setter TargetName="PageDecreaseButton" Property="Command" Value="{x:Static ScrollBar.PageLeftCommand}"/>
                            <Setter TargetName="PageIncreaseButton" Property="Command" Value="{x:Static ScrollBar.PageRightCommand}"/>
                        </Trigger>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="ScrollThumb" Property="Background" Value="{DynamicResource TextSecondary}"/>
                        </Trigger>
                        <Trigger SourceName="ScrollThumb" Property="IsDragging" Value="True">
                            <Setter TargetName="ScrollThumb" Property="Background" Value="{DynamicResource Accent}"/>
                        </Trigger>
                        <Trigger Property="IsEnabled" Value="False">
                            <Setter Property="Opacity" Value="0.4"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
</ResourceDictionary>
'@
        $reader = [System.Xml.XmlNodeReader]::new($runtimeResourcesXaml)
        $runtimeResources = [Windows.Markup.XamlReader]::Load($reader)
        [void]$Element.Resources.MergedDictionaries.Add($runtimeResources)
        $Element.Resources["__WmtRuntimeResourcesApplied"] = $true
    }
    catch {}
}

function Add-WmtWpfScrollResources {
    param([System.Windows.FrameworkElement]$Element)
    Add-WmtWpfRuntimeResources -Element $Element
}

function Add-WmtThemeResources {
    param([System.Windows.FrameworkElement]$Element)

    if (-not $Element -or -not $script:ThemePalettes) { return }
    $theme = if ($script:CurrentTheme -and $script:ThemePalettes.ContainsKey($script:CurrentTheme)) { $script:CurrentTheme } else { "dark" }
    $palette = $script:ThemePalettes[$theme]
    Set-WmtThemeResources -Element $Element -Palette $palette
    Add-WmtWpfRuntimeResources -Element $Element

    if (-not $script:WmtThemedElements) {
        $script:WmtThemedElements = [System.Collections.ArrayList]::new()
    }

    $alreadyTracked = $false
    foreach ($tracked in @($script:WmtThemedElements)) {
        if ([object]::ReferenceEquals($tracked, $Element)) {
            $alreadyTracked = $true
            break
        }
    }

    if (-not $alreadyTracked) {
        [void]$script:WmtThemedElements.Add($Element)
        if ($Element -is [System.Windows.Window]) {
            $Element.Add_Closed({
                    param($closedWindow, $closedEventArgs)
                    $null = $closedEventArgs
                    try { [void]$script:WmtThemedElements.Remove($closedWindow) } catch {}
                })
        }
    }
}

function Show-WmtMessageBox {
    param(
        [string]$Message,
        [string]$Title = "Windows Maintenance Tool",
        [System.Windows.MessageBoxButton]$Button = [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]$Image = [System.Windows.MessageBoxImage]::None,
        [System.Windows.Window]$Owner = $null
    )

    try {
        if (-not $Owner -and $window -and $window.IsVisible) { $Owner = $window }
        if ($Owner) {
            return [System.Windows.MessageBox]::Show($Owner, $Message, $Title, $Button, $Image)
        }
    }
    catch {}
    return [System.Windows.MessageBox]::Show($Message, $Title, $Button, $Image)
}

function New-WmtWindowFromXaml {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$ContentXaml,
        [double]$Width = 640,
        [double]$Height = 420,
        [double]$MinWidth = 0,
        [double]$MinHeight = 0,
        [switch]$NoResize,
        [switch]$NoOwner
    )

    $escapedTitle = [System.Security.SecurityElement]::Escape($Title)
    $resizeMode = if ($NoResize) { "NoResize" } else { "CanResize" }
    $minWidthText = if ($MinWidth -gt 0) { " MinWidth=`"$MinWidth`"" } else { "" }
    $minHeightText = if ($MinHeight -gt 0) { " MinHeight=`"$MinHeight`"" } else { "" }
    [xml]$windowXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$escapedTitle" Width="$Width" Height="$Height"$minWidthText$minHeightText
        ResizeMode="$resizeMode" WindowStartupLocation="CenterOwner"
        Background="{DynamicResource BgDark}" Foreground="{DynamicResource TextPrimary}"
        FontFamily="Segoe UI Variable Display, Segoe UI, Arial" FontSize="13">
$ContentXaml
</Window>
"@

    $reader = [System.Xml.XmlNodeReader]::new($windowXaml)
    $dialog = [Windows.Markup.XamlReader]::Load($reader)
    Add-WmtThemeResources -Element $dialog
    if (-not $NoOwner) { Set-WmtWindowOwner -Child $dialog }
    return $dialog
}

function New-WmtWindowFromFullXaml {
    param(
        [Parameter(Mandatory = $true)]$Xaml,
        [switch]$NoOwner
    )

    $xamlDoc = if ($Xaml -is [System.Xml.XmlDocument]) { $Xaml } else { [xml]([string]$Xaml) }
    $reader = [System.Xml.XmlNodeReader]::new($xamlDoc)
    $dialog = [Windows.Markup.XamlReader]::Load($reader)
    Add-WmtThemeResources -Element $dialog
    if (-not $NoOwner) { Set-WmtWindowOwner -Child $dialog }
    return $dialog
}

function Show-WmtInputDialog {
    param(
        [string]$Title,
        [string]$Prompt,
        [string]$DefaultValue = "",
        [switch]$ReadOnly
    )

    $content = @'
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Name="lblPrompt" TextWrapping="Wrap" Margin="0,0,0,10"/>
        <TextBox Name="txtValue" Grid.Row="1" Height="34" VerticalContentAlignment="Center"/>
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button Name="btnCancel" Content="Cancel" Width="94" IsCancel="True" Margin="0,0,8,0"/>
            <Button Name="btnOk" Content="OK" Width="94" IsDefault="True" Background="{DynamicResource Accent}" Foreground="{DynamicResource AccentText}"/>
        </StackPanel>
    </Grid>
'@
    $dialog = New-WmtWindowFromXaml -Title $Title -ContentXaml $content -Width 460 -Height 190 -MinWidth 380 -MinHeight 170 -NoResize
    $lblPrompt = $dialog.FindName("lblPrompt")
    $txtValue = $dialog.FindName("txtValue")
    $btnOk = $dialog.FindName("btnOk")
    $btnCancel = $dialog.FindName("btnCancel")

    $lblPrompt.Text = $Prompt
    $txtValue.Text = $DefaultValue
    $txtValue.IsReadOnly = [bool]$ReadOnly
    $result = @{ Value = $null }
    $btnOk.Add_Click({
            $result.Value = [string]$txtValue.Text
            $dialog.DialogResult = $true
        }.GetNewClosure())
    $btnCancel.Add_Click({ $dialog.Close() }.GetNewClosure())
    $dialog.Add_ContentRendered({
            $txtValue.Focus() | Out-Null
            $txtValue.SelectAll()
        }.GetNewClosure())

    $dialog.ShowDialog() | Out-Null
    return $result.Value
}

function Select-WmtFolder {
    param(
        [string]$Description = "Select folder",
        [string]$InitialDirectory = ""
    )

    $shell = $null
    try {
        $shell = New-Object -ComObject Shell.Application
        $root = if (-not [string]::IsNullOrWhiteSpace($InitialDirectory) -and (Test-Path -LiteralPath $InitialDirectory)) { $InitialDirectory } else { 0 }
        $folder = $shell.BrowseForFolder(0, $Description, 0, $root)
        if ($folder -and $folder.Self) { return [string]$folder.Self.Path }
    }
    catch {}
    finally {
        try { if ($shell) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) } } catch {}
    }
    return $null
}

function New-WmtDataTable {
    param(
        [string[]]$Columns,
        [object[]]$Rows = @()
    )

    $table = [System.Data.DataTable]::new()
    foreach ($column in $Columns) { [void]$table.Columns.Add($column) }
    foreach ($item in @($Rows)) {
        $row = $table.NewRow()
        foreach ($column in $Columns) {
            $value = $null
            if ($item -is [System.Data.DataRow]) {
                if ($item.Table.Columns.Contains($column)) { $value = $item[$column] }
            }
            elseif ($item -is [System.Collections.IDictionary]) {
                if ($item.Contains($column)) { $value = $item[$column] }
            }
            else {
                $prop = $item.PSObject.Properties[$column]
                if ($prop) { $value = $prop.Value }
            }
            $row[$column] = if ($null -eq $value) { "" } else { [string]$value }
        }
        [void]$table.Rows.Add($row)
    }
    return $table
}

function Get-WmtDataGridSelectedRows {
    param([System.Windows.Controls.DataGrid]$DataGrid)

    $rows = @()
    if (-not $DataGrid) { return $rows }
    foreach ($item in @($DataGrid.SelectedItems)) {
        if ($item -is [System.Data.DataRowView]) { $rows += $item.Row }
        else { $rows += $item }
    }
    return $rows
}

function Add-WmtStatusTextTriggers {
    param(
        [System.Windows.Style]$Style,
        [string]$BindingPath,
        [string[]]$Values,
        [string]$ColorKey
    )

    if (-not $Style -or [string]::IsNullOrWhiteSpace($BindingPath)) { return }
    $brush = New-WmtBrush $ColorKey
    $fontWeight = [System.Windows.FontWeights]::SemiBold
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    foreach ($value in @($Values)) {
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        foreach ($variant in @($value, $value.ToLowerInvariant(), $value.ToUpperInvariant())) {
            if (-not $seen.Add($variant)) { continue }

            $trigger = [System.Windows.DataTrigger]::new()
            $trigger.Binding = [System.Windows.Data.Binding]::new($BindingPath)
            $trigger.Value = $variant
            [void]$trigger.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::ForegroundProperty, $brush))
            [void]$trigger.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::FontWeightProperty, $fontWeight))
            [void]$Style.Triggers.Add($trigger)
        }
    }
}

function New-WmtStatusTextStyle {
    param([string]$BindingPath)

    $style = [System.Windows.Style]::new([System.Windows.Controls.TextBlock])
    [void]$style.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.TextBlock]::TextTrimmingProperty, [System.Windows.TextTrimming]::CharacterEllipsis))

    Add-WmtStatusTextTriggers -Style $style -BindingPath $BindingPath -ColorKey "SuccessHover" -Values @(
        "Yes", "True", "Enabled", "Enable", "Allowed", "Allow", "Running", "Ready",
        "Automatic", "Auto", "Boot", "System", "Success", "OK", "Healthy", "Online",
        "Connected", "Up", "Installed", "Protected", "Active", "On"
    )
    Add-WmtStatusTextTriggers -Style $style -BindingPath $BindingPath -ColorKey "DangerHover" -Values @(
        "No", "False", "Disabled", "Disable", "Denied", "Deny", "Disallowed", "Not Allowed",
        "Blocked", "Block", "Stopped", "Failed", "Failure", "Error", "Access Denied",
        "Critical", "Unhealthy", "Offline", "Disconnected", "Not Present", "Unavailable", "Off"
    )
    Add-WmtStatusTextTriggers -Style $style -BindingPath $BindingPath -ColorKey "WarningHover" -Values @(
        "Manual", "Unknown", "Pending", "Queued", "Warning", "Degraded", "Limited",
        "Paused", "Starting", "Stopping", "Partially Enabled"
    )

    return $style
}

function Set-WmtDataGridColumns {
    param(
        [System.Windows.Controls.DataGrid]$DataGrid,
        [string[]]$Columns,
        [hashtable]$Widths = @{},
        [string[]]$Hidden = @(),
        [string[]]$StatusColumns = @("Enabled", "State", "Status", "StartType", "Action", "Protection", "Result")
    )

    if (-not $DataGrid) { return }
    $DataGrid.AutoGenerateColumns = $false
    $DataGrid.Columns.Clear()
    foreach ($column in $Columns) {
        $col = [System.Windows.Controls.DataGridTextColumn]::new()
        $col.Header = $column
        $col.Binding = [System.Windows.Data.Binding]::new($column)
        $col.IsReadOnly = $true
        if ($StatusColumns -contains $column) {
            $col.ElementStyle = New-WmtStatusTextStyle -BindingPath $column
        }
        if ($Widths -and $Widths.ContainsKey($column)) {
            $widthValue = $Widths[$column]
            if ([string]$widthValue -match '^(?<weight>\d+(?:\.\d+)?)?\*$') {
                $weight = if ($matches["weight"]) { [double]$matches["weight"] } else { 1.0 }
                $col.Width = [System.Windows.Controls.DataGridLength]::new($weight, [System.Windows.Controls.DataGridLengthUnitType]::Star)
            }
            else {
                $col.Width = [double]$widthValue
            }
        }
        [void]$DataGrid.Columns.Add($col)
        if ($Hidden -contains $column) { $col.Visibility = [System.Windows.Visibility]::Collapsed }
    }
}

function Get-WmtThemeHex {
    param(
        [string]$Key,
        [string]$Fallback = "#8B949E"
    )

    $resourceKey = Resolve-WmtThemeResourceKey $Key
    if (-not $resourceKey) { $resourceKey = $Key }

    if ($script:ThemePalettes) {
        $theme = if ($script:CurrentTheme -and $script:ThemePalettes.ContainsKey($script:CurrentTheme)) { $script:CurrentTheme } else { "dark" }
        $palette = $script:ThemePalettes[$theme]
        if ($palette -and $palette.ContainsKey($resourceKey)) { return $palette[$resourceKey] }
    }

    $darkFallback = @{
        BgDark        = "#0D1117"
        BgPanel       = "#161B22"
        BgElevated    = "#21262D"
        BgHover       = "#30363D"
        BorderBrush   = "#30363D"
        Accent        = "#58A6FF"
        AccentHover   = "#79C0FF"
        TextPrimary   = "#E6EDF3"
        TextSecondary = "#8B949E"
        TextMuted     = "#6E7681"
        Success       = "#238636"
        SuccessHover  = "#2EA043"
        Danger        = "#DA3633"
        DangerHover   = "#F85149"
        Warning       = "#D29922"
        WarningHover  = "#E3B341"
        Info          = "#1F6FEB"
        AccentText    = "#0D1117"
        SuccessText   = "#F6FFFA"
        DangerText    = "#FFF5F5"
        WarningText   = "#0D1117"
        InfoText      = "#F0F6FC"
    }

    if ($darkFallback.ContainsKey($resourceKey)) { return $darkFallback[$resourceKey] }
    if ($Key -match "^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$") { return $Key }
    return $Fallback
}

function Reset-WmtUpdateUiAfterMonitorError {
    param(
        [System.Exception]$Exception,
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$Context = "Update completion monitor failed",
        [switch]$SkipCrashWrite
    )

    if (-not $SkipCrashWrite) {
        Write-WmtLastCrash -Context $Context -Exception $Exception -ErrorRecord $ErrorRecord
    }

    $autoInstallWasActive = [bool]$script:WmtAutoInstallActive

    try { if ($script:WingetTimer) { $script:WingetTimer.Stop() } } catch {}
    try { if ($script:WingetJob) { Stop-Job -Job $script:WingetJob -ErrorAction SilentlyContinue } } catch {}
    try { if ($script:WingetJob) { Receive-Job -Job $script:WingetJob -ErrorAction SilentlyContinue | Out-Null } } catch {}
    try { if ($script:WingetJob) { Remove-Job -Job $script:WingetJob -Force -ErrorAction SilentlyContinue } } catch {}

    $script:WingetJob = $null
    $script:WingetActiveAction = $null
    $script:WingetActionStoreUpdateOnly = $false
    $script:WmtAutoInstallActive = $false
    $script:WingetCurrentIndex = 0
    $script:WingetCurrentPercent = 0
    $script:WingetCurrentItemName = ""
    $script:WingetCurrentItemSource = ""
    $script:WingetCurrentItemStartedAt = $null
    $script:WingetActionForcedTimeout = $false

    try { if ($script:RefreshWingetProgressUi) { & $script:RefreshWingetProgressUi } } catch {}

    foreach ($buttonName in @("btnWingetScan", "btnWingetUpdateSel", "btnWingetUpdateAll", "btnWingetInstall", "btnWingetUninstall")) {
        try {
            $button = Get-Variable -Name $buttonName -Scope Script -ValueOnly -ErrorAction SilentlyContinue
            if ($button) { $button.IsEnabled = $true }
        }
        catch {}
    }

    try {
        $statusLabel = Get-Variable -Name "lblWingetStatus" -Scope Script -ValueOnly -ErrorAction SilentlyContinue
        if ($statusLabel) { $statusLabel.Text = "Update monitor recovered from an internal error. See data\last-crash.txt." }
    }
    catch {}

    if ($autoInstallWasActive) {
        try { Show-WmtBackgroundInstallNotification -Status Interrupted } catch {}
    }
}

function Show-TextDialog {
    param(
        [string]$Title = "Output",
        [string]$Text = ""
    )

    [xml]$textDialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="860" Height="620" MinWidth="520" MinHeight="360"
        WindowStartupLocation="CenterOwner" Background="{DynamicResource BgDark}" Foreground="{DynamicResource TextPrimary}"
        FontFamily="Segoe UI Variable Display, Segoe UI, Arial" FontSize="13">
    <Grid Margin="14">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBox Name="txtOutput" Grid.Row="0" IsReadOnly="True" AcceptsReturn="True" AcceptsTab="True"
                 TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                 FontFamily="Consolas" FontSize="12" Background="{DynamicResource BgPanel}"/>

        <Button Name="btnClose" Grid.Row="1" Content="Close" Width="94" HorizontalAlignment="Right" Margin="0,12,0,0" IsCancel="True"/>
    </Grid>
</Window>
'@

    try {
        $dialog = New-WmtWindowFromFullXaml -Xaml $textDialogXaml
        $dialog.Title = $Title

        $txtOutput = $dialog.FindName("txtOutput")
        $btnClose = $dialog.FindName("btnClose")
        $txtOutput.Text = $Text
        $btnClose.Add_Click({ $dialog.Close() }.GetNewClosure())
        $dialog.ShowDialog() | Out-Null
    }
    catch {
        Write-GuiLog "Failed to open text dialog: $($_.Exception.Message)"
    }
}

function Get-WmtVisualAncestor {
    param(
        [object]$Element,
        [type]$AncestorType
    )

    $current = $Element
    while ($current -and ($current -is [System.Windows.DependencyObject])) {
        if ($AncestorType.IsInstanceOfType($current)) { return $current }
        try { $current = [System.Windows.Media.VisualTreeHelper]::GetParent($current) }
        catch { break }
    }
    return $null
}

function Get-WmtVisualDescendant {
    param(
        [object]$Element,
        [type]$DescendantType
    )

    if (-not $Element -or -not ($Element -is [System.Windows.DependencyObject]) -or -not $DescendantType) { return $null }

    $childCount = 0
    try { $childCount = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Element) }
    catch { return $null }

    for ($i = 0; $i -lt $childCount; $i++) {
        $child = $null
        try { $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Element, $i) } catch { continue }
        if ($child -and $DescendantType.IsInstanceOfType($child)) { return $child }

        $nested = Get-WmtVisualDescendant -Element $child -DescendantType $DescendantType
        if ($nested) { return $nested }
    }

    return $null
}

function Set-WmtListViewRightClickSelection {
    param(
        [System.Windows.Controls.ListView]$ListView,
        [object]$OriginalSource
    )

    if (-not $ListView -or -not $OriginalSource) { return }
    $itemContainer = Get-WmtVisualAncestor -Element $OriginalSource -AncestorType ([System.Windows.Controls.ListViewItem])
    if (-not $itemContainer) { return }

    if (-not $itemContainer.IsSelected) {
        $ListView.SelectedItems.Clear()
        $itemContainer.IsSelected = $true
    }
    try { $itemContainer.Focus() | Out-Null } catch {}
}

function Get-Ctrl {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    if ($script:WmtControlCache.ContainsKey($Name)) { return $script:WmtControlCache[$Name] }

    $ctrl = $window.FindName($Name)
    if ($ctrl) { $script:WmtControlCache[$Name] = $ctrl }
    return $ctrl
}

function Set-WmtTheme {
    param([string]$Theme = "dark")
    if (-not $script:ThemePalettes.ContainsKey($Theme)) { $Theme = "dark" }
    $palette = $script:ThemePalettes[$Theme]

    Set-WmtThemeResources -Element $window -Palette $palette

    $window.Background = $window.Resources["BgDark"]
    $window.Foreground = $window.Resources["TextPrimary"]

    if ($script:WmtThemedElements) {
        foreach ($element in @($script:WmtThemedElements)) {
            try {
                if (-not $element -or [object]::ReferenceEquals($element, $window)) { continue }
                Set-WmtThemeResources -Element $element -Palette $palette
                if ($element -is [System.Windows.Window]) {
                    $element.Background = $element.Resources["BgDark"]
                    $element.Foreground = $element.Resources["TextPrimary"]
                }
            }
            catch {}
        }
    }

    $logBoxCtrl = Get-Ctrl "LogBox"
    if ($logBoxCtrl) { $logBoxCtrl.Foreground = $palette.LogText }

    $quickFindCtrl = Get-Ctrl "txtGlobalSearch"
    if ($quickFindCtrl) { Set-WmtQuickFindForeground -TextBox $quickFindCtrl }

    $toggleBtn = Get-Ctrl "btnToggleTheme"
    if ($toggleBtn) {
        $toggleBtn.Content = if ($Theme -eq "dark") { "Light Mode" } else { "Dark Mode" }
    }

    if ($TabButtons) {
        foreach ($btnName in $TabButtons) {
            $btn = Get-Ctrl $btnName
            if (-not $btn) { continue }
            if ($btn.Tag -eq "Visible") {
                $btn.Background = $window.Resources["BgElevated"]
                $btn.Foreground = $window.Resources["TextPrimary"]
            }
            else {
                $btn.ClearValue([System.Windows.Controls.Button]::BackgroundProperty)
                $btn.Foreground = $window.Resources["TextSecondary"]
            }
        }
    }

    $script:CurrentTheme = $Theme
}

function Set-WmtQuickFindForeground {
    param([System.Windows.Controls.TextBox]$TextBox)

    if (-not $TextBox) { return }
    $resourceKey = if ($TextBox.Text -eq $script:QuickFindPlaceholder) { "TextMuted" } else { "TextPrimary" }
    $TextBox.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, $resourceKey)
}

function Set-WmtThemePreference {
    param([string]$Theme = "dark")

    if (-not $script:ThemePalettes.ContainsKey($Theme)) { $Theme = "dark" }
    Set-WmtTheme -Theme $Theme

    try {
        $settings = Get-WmtSettings
        $settings.Theme = $Theme
        Save-WmtSettings -Settings $settings
    }
    catch {}

    $themeLabel = if ($Theme -eq "light") { "Light" } else { "Dark" }
    Write-GuiLog "$themeLabel mode enabled."
}

function Set-ButtonIcon {
    param($BtnName, $PathData, $Text, $Tooltip = "", $Scale = 16, $Color = $null)
    $btn = Get-Ctrl $BtnName
    if (-not $btn) { return }

    if ($Scale -is [string] -and $Scale -match '^#') {
        $Color = $Scale
        $Scale = 16
    }
    
    # Visuals
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Orientation = "Horizontal"
    $path = New-Object System.Windows.Shapes.Path
    $path.Data = [System.Windows.Media.Geometry]::Parse($PathData)
    if ([string]::IsNullOrWhiteSpace([string]$Color)) {
        $path.SetResourceReference([System.Windows.Shapes.Path]::FillProperty, "TextSecondary")
    }
    else {
        $path.Fill = New-WmtBrush $Color
    }
    $path.Stretch = "Uniform"; $path.Height = $Scale; $path.Width = $Scale; $path.Margin = "0,0,10,0"
    $txt = New-Object System.Windows.Controls.TextBlock; $txt.Text = $Text; $txt.VerticalAlignment = "Center"
    [void]$sp.Children.Add($path); [void]$sp.Children.Add($txt)
    $btn.Content = $sp
    
    # Tooltip
    if ($Tooltip) { $btn.ToolTip = $Tooltip }
}

function Add-SearchIndexEntry { param($BtnName, $Desc, $ParentTab) $b = Get-Ctrl $BtnName; if ($b) { $SearchIndex[$Desc] = @{Button = $b; Tab = $ParentTab; Action = $null } } }

function Add-SearchIndexAction { param($Desc, [scriptblock]$Action, $ParentTab) if ($Action) { $SearchIndex[$Desc] = @{Button = $null; Tab = $ParentTab; Action = $Action } } }

function Update-WmtSearchIndexEntries {
    $entries = [System.Collections.ArrayList]::new()
    foreach ($entry in ($SearchIndex.GetEnumerator() | Sort-Object Key)) {
        [void]$entries.Add([PSCustomObject]@{
                Text = [string]$entry.Key
                Item = $entry.Value
            })
    }
    $script:WmtSearchIndexEntries = $entries
}

function Set-ListViewSort {
    param(
        [System.Windows.Controls.ListView]$ListView,
        [System.Collections.ArrayList]$Chain
    )
    if (-not $ListView -or $null -eq $Chain -or $Chain.Count -eq 0) { return }
    if ($ListView.Items.Count -eq 0) { return }

    if ($ListView.ItemsSource) {
        try {
            $ListView.Items.SortDescriptions.Clear()
            foreach ($rule in $Chain) {
                if ([string]::IsNullOrWhiteSpace([string]$rule.Property)) { continue }
                $direction = if ([bool]$rule.Descending) {
                    [System.ComponentModel.ListSortDirection]::Descending
                }
                else {
                    [System.ComponentModel.ListSortDirection]::Ascending
                }
                $description = [System.ComponentModel.SortDescription]::new([string]$rule.Property, $direction)
                [void]$ListView.Items.SortDescriptions.Add($description)
            }
            $ListView.Items.Refresh()
            return
        }
        catch {
            try { $ListView.Items.SortDescriptions.Clear() } catch {}
        }
    }

    $items = @($ListView.Items)
    if ($items.Count -eq 0) { return }
    $sortSpec = foreach ($rule in $Chain) {
        $propertyName = [string]$rule.Property
        if (-not [string]::IsNullOrWhiteSpace($propertyName)) {
            $propertyNameForClosure = $propertyName
            @{
                Expression = { Get-WmtListSortValue -Item $_ -PropertyName $propertyNameForClosure }.GetNewClosure()
                Descending = [bool]$rule.Descending
            }
        }
    }
    if (-not $sortSpec -or $sortSpec.Count -eq 0) { return }

    $selectedItems = @($ListView.SelectedItems)
    $sorted = $items | Sort-Object -Property $sortSpec
    try { $ListView.Items.SortDescriptions.Clear() } catch {}
    $ListView.Items.Clear()
    foreach ($item in $sorted) {
        [void]$ListView.Items.Add($item)
        if ($selectedItems -contains $item) {
            try { $ListView.SelectedItems.Add($item) } catch {}
        }
    }
}

function Set-WmtContextMenuChrome {
    param([System.Windows.Controls.ContextMenu]$ContextMenu)

    if (-not $ContextMenu) { return }
    Add-WmtThemeResources -Element $ContextMenu
    Set-WmtThemedBrush -Object $ContextMenu -Property ([System.Windows.Controls.Control]::BackgroundProperty) -ColorOrKey "BgElevated"
    Set-WmtThemedBrush -Object $ContextMenu -Property ([System.Windows.Controls.Control]::ForegroundProperty) -ColorOrKey "TextPrimary"
    Set-WmtThemedBrush -Object $ContextMenu -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -ColorOrKey "BorderBrush"
    try {
        $contextMenuStyle = $ContextMenu.TryFindResource([System.Windows.Controls.ContextMenu])
        if ($contextMenuStyle) { $ContextMenu.Style = $contextMenuStyle }
    }
    catch {}

    $applyNoGutterChrome = {
        $menuItemStyle = $null
        $separatorStyle = $null
        try { $menuItemStyle = $ContextMenu.TryFindResource("WmtNoGutterMenuItemStyle") } catch {}
        try { $separatorStyle = $ContextMenu.TryFindResource("WmtNoGutterSeparatorStyle") } catch {}

        if ($menuItemStyle) {
            try { $ContextMenu.ItemContainerStyle = $menuItemStyle } catch {}
        }

        foreach ($item in @($ContextMenu.Items)) {
            if ($item -is [System.Windows.Controls.MenuItem]) {
                try { $item.Icon = $null } catch {}
                if ($menuItemStyle) { try { $item.Style = $menuItemStyle } catch {} }
            }
            elseif ($item -is [System.Windows.Controls.Separator]) {
                if ($separatorStyle) { try { $item.Style = $separatorStyle } catch {} }
            }
        }
    }.GetNewClosure()

    & $applyNoGutterChrome
    try {
        $notifyItems = [System.Collections.Specialized.INotifyCollectionChanged]$ContextMenu.Items
        $notifyItems.add_CollectionChanged({ & $applyNoGutterChrome }.GetNewClosure())
    }
    catch {}
    $ContextMenu.Add_Opened({ & $applyNoGutterChrome }.GetNewClosure())
}

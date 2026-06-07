# Functional block generated from WMT-GUI.ps1.
# Dot-source this file; it intentionally shares WMT's script scope.

function Copy-WmtUpdateSelectedRowsToClipboard {
    param(
        [System.Windows.Controls.ListView]$ListView = $lstWinget
    )

    if (-not $ListView) { return $false }
    $selectedRows = @($ListView.SelectedItems | Where-Object { $null -ne $_ })
    if ($selectedRows.Count -eq 0 -and $ListView.SelectedItem) {
        $selectedRows = @($ListView.SelectedItem)
    }
    if ($selectedRows.Count -eq 0) {
        Write-GuiLog "Copy row data skipped: no update row selected."
        return $false
    }

    $text = ConvertTo-WmtUpdateRowClipboardText -Items $selectedRows
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }

    try {
        [System.Windows.Clipboard]::SetText($text)
        Write-GuiLog "Copied $($selectedRows.Count) update row(s) to clipboard."
        return $true
    }
    catch {
        Write-GuiLog "ERROR: Could not copy update row data: $($_.Exception.Message)"
        return $false
    }
}

function Get-CleanHeader {
    param([object]$Header)
    if ($null -eq $Header) { return "" }
    return ([regex]::Replace([string]$Header, '\s+(?:[\u25B2\u25BC]|\u00E2\u2013[\u00B2\u00BC])$', '')).Trim()
}

function Get-GridViewColumnHeaderFromSource {
    param([object]$OriginalSource)
    if (-not $OriginalSource) { return $null }
    if ($OriginalSource -is [System.Windows.Controls.GridViewColumnHeader]) { return $OriginalSource }
    return Get-WmtVisualAncestor -Element $OriginalSource -AncestorType ([System.Windows.Controls.GridViewColumnHeader])
}

function Update-GridViewHeaders {
    param([System.Windows.Controls.ListView]$ListView, [string]$ActiveHeader, [bool]$Ascending)
    if (-not $ListView -or -not $ListView.View -or -not ($ListView.View -is [System.Windows.Controls.GridView])) { return }
    foreach ($col in $ListView.View.Columns) {
        $clean = Get-CleanHeader $col.Header
        if ($clean -eq $ActiveHeader) {
            $glyph = if ($Ascending) { $script:GridSortAscendingGlyph } else { $script:GridSortDescendingGlyph }
            $col.Header = "$clean $glyph"
        }
        else {
            $col.Header = $clean
        }
    }
}

function Set-SortChainPrimary {
    param(
        [System.Collections.ArrayList]$Chain,
        [string]$PropertyName
    )
    if ($null -eq $Chain -or [string]::IsNullOrWhiteSpace($PropertyName)) { return $false }

    $existingIndex = -1
    for ($i = 0; $i -lt $Chain.Count; $i++) {
        if ($Chain[$i].Property -eq $PropertyName) { $existingIndex = $i; break }
    }

    if ($existingIndex -eq 0) {
        $Chain[0].Descending = -not [bool]$Chain[0].Descending
        return [bool](-not $Chain[0].Descending)
    }

    if ($existingIndex -gt 0) { $Chain.RemoveAt($existingIndex) }
    $entry = [PSCustomObject]@{ Property = $PropertyName; Descending = $false }
    $Chain.Insert(0, $entry)
    return $true
}

function Get-WmtNaturalSortKey {
    param([object]$Value)

    if ($null -eq $Value) { return "" }
    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }

    return [regex]::Replace($text, '\d+', {
            param($Match)
            $Match.Value.PadLeft(20, '0')
        })
}

function Test-WingetManifestSupportedItem {
    param([object]$Item)

    if (-not $Item) { return $false }
    $id = [string]$Item.Id
    $source = ([string]$Item.Source).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($id)) { return $false }
    return ($source -in @("winget", "msstore"))
}

function ConvertTo-WmtUpdateRowClipboardText {
    param([object[]]$Items)

    $rows = @($Items | Where-Object { $null -ne $_ })
    if ($rows.Count -eq 0) { return "" }

    $preferredProperties = @(
        "Source",
        "Name",
        "Id",
        "Version",
        "Available",
        "IsChecked",
        "WUIsOptional",
        "VersionSort",
        "AvailableSort",
        "RawAvailable",
        "LibraryPath",
        "InstallDir",
        "ManifestPath",
        "ExecutablePath",
        "Platform"
    )
    $preferredSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($propertyName in $preferredProperties) { [void]$preferredSet.Add($propertyName) }

    $formatValue = {
        param($Value)
        if ($null -eq $Value) { return "" }
        if ($Value -is [System.Array]) {
            return ((@($Value) | ForEach-Object { [string]$_ }) -join ", ") -replace '\r?\n', ' '
        }
        return (([string]$Value) -replace '\r?\n', ' ').Trim()
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    [void]$lines.Add("WMT Update Row Data")
    [void]$lines.Add("Count: $($rows.Count)")
    [void]$lines.Add("Copied: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))")

    $rowIndex = 0
    foreach ($row in $rows) {
        $rowIndex++
        [void]$lines.Add("")
        [void]$lines.Add("Row $rowIndex")

        foreach ($propertyName in $preferredProperties) {
            $property = $row.PSObject.Properties[$propertyName]
            if (-not $property) { continue }
            [void]$lines.Add("${propertyName}: $(& $formatValue $property.Value)")
        }

        $extraProperties = @($row.PSObject.Properties | Where-Object { -not $preferredSet.Contains($_.Name) } | Sort-Object Name)
        foreach ($property in $extraProperties) {
            [void]$lines.Add("$($property.Name): $(& $formatValue $property.Value)")
        }
    }

    return [string]::Join([Environment]::NewLine, $lines)
}

function Get-WingetManifestText {
    param(
        [object]$Item,
        [int]$TimeoutMs = 45000
    )

    if (-not (Test-WingetManifestSupportedItem $Item)) {
        return [PSCustomObject]@{
            Success  = $false
            ExitCode = $null
            Text     = "App manifests are only available for winget and Microsoft Store packages."
        }
    }

    $id = [string]$Item.Id
    $source = ([string]$Item.Source).ToLowerInvariant()
    $argsLine = @(
        "show",
        "--id", (ConvertTo-WmtProcessArgument $id),
        "--source", (ConvertTo-WmtProcessArgument $source),
        "--exact",
        "--accept-source-agreements",
        "--disable-interactivity"
    ) -join " "

    try {
        $pInfo = New-Object System.Diagnostics.ProcessStartInfo
        $pInfo.FileName = "winget"
        $pInfo.Arguments = $argsLine
        $pInfo.RedirectStandardOutput = $true
        $pInfo.RedirectStandardError = $true
        $pInfo.UseShellExecute = $false
        $pInfo.CreateNoWindow = $true
        $pInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $pInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)

        $proc = [System.Diagnostics.Process]::Start($pInfo)
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit($TimeoutMs)) {
            try { $proc.Kill() } catch {}
            try { [void]$proc.WaitForExit(2000) } catch {}
            return [PSCustomObject]@{
                Success  = $false
                ExitCode = $null
                Text     = "Timed out while loading the manifest for $id.`r`n`r`nCommand: winget $argsLine"
            }
        }

        $out = $outTask.GetAwaiter().GetResult()
        $err = $errTask.GetAwaiter().GetResult()
        $textParts = @()
        if (-not [string]::IsNullOrWhiteSpace($out)) { $textParts += $out.TrimEnd() }
        if (-not [string]::IsNullOrWhiteSpace($err)) { $textParts += $err.TrimEnd() }
        $text = ($textParts -join "`r`n`r`n")
        if ([string]::IsNullOrWhiteSpace($text)) { $text = "No manifest output was returned for $id." }

        return [PSCustomObject]@{
            Success  = ($proc.ExitCode -eq 0)
            ExitCode = $proc.ExitCode
            Text     = $text
        }
    }
    catch {
        return [PSCustomObject]@{
            Success  = $false
            ExitCode = $null
            Text     = "Failed to load manifest for $id.`r`n`r`n$($_.Exception.Message)"
        }
    }
}

function Show-WingetPackageManifest {
    param([object]$Item)

    if (-not (Test-WingetManifestSupportedItem $Item)) {
        [System.Windows.MessageBox]::Show(
            "App manifests are only available for winget and Microsoft Store packages.",
            "Manifest Unavailable",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        ) | Out-Null
        return
    }

    $name = [string]$Item.Name
    $id = [string]$Item.Id
    $source = ([string]$Item.Source).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $id }

    Write-GuiLog "Loading app manifest for $name ($id) from $source..."
    if ($lblWingetStatus) {
        $lblWingetStatus.Text = "Loading manifest for $name..."
        $lblWingetStatus.Visibility = "Visible"
    }

    Set-WmtBusyCursor -Busy
    try {
        $result = Get-WingetManifestText -Item $Item
        if (-not $result.Success) {
            Write-GuiLog "Manifest lookup failed for $id$(if ($null -ne $result.ExitCode) { " (exit $($result.ExitCode))" })."
        }
        else {
            Write-GuiLog "Manifest loaded for $id."
        }

        $header = "Package: $name`r`nID: $id`r`nSource: $source`r`nCommand: winget show --id `"$id`" --source $source --exact`r`n"
        $separator = ("-" * 80)
        Show-TextDialog -Title "App Manifest - $name" -Text "$header`r`n$separator`r`n`r`n$($result.Text)"
    }
    finally {
        Set-WmtBusyCursor
        if ($lblWingetStatus) {
            $lblWingetStatus.Text = "Ready"
            $lblWingetStatus.Visibility = "Hidden"
        }
    }
}

function Test-WmtUpdateListActionableItem {
    param([object]$Item)

    if (-not $Item) { return $false }
    $source = ([string]$Item.Source).Trim()
    $name = ([string]$Item.Name).Trim()
    $id = ([string]$Item.Id).Trim()

    if ([string]::IsNullOrWhiteSpace($source)) { return $false }
    if ($name -in @("No results found", "No updates available")) { return $false }
    if ([string]::IsNullOrWhiteSpace($name) -and [string]::IsNullOrWhiteSpace($id)) { return $false }

    return $true
}

function Set-WmtUpdateListItemCheckState {
    param(
        [object]$Item,
        [bool]$DefaultChecked = $false
    )

    if (-not $Item) { return $Item }
    $checked = if (Test-WmtUpdateListActionableItem -Item $Item) { [bool]$DefaultChecked } else { $false }
    if ($checked -and $Item.PSObject.Properties["WUIsOptional"] -and [bool]$Item.WUIsOptional) { $checked = $false }

    if (-not $Item.PSObject.Properties["IsChecked"]) {
        try { $Item | Add-Member -MemberType NoteProperty -Name "IsChecked" -Value $checked -Force } catch {}
    }
    elseif ($null -eq $Item.IsChecked) {
        try { $Item.IsChecked = $checked } catch {}
    }

    return $Item
}

function Get-WmtUpdateListCheckedItems {
    param(
        [System.Windows.Controls.ListView]$ListView = $lstWinget,
        [switch]$FallbackToSelection
    )

    if (-not $ListView) { return @() }

    try {
        $checked = [System.Collections.Generic.List[object]]::new()
        $itemCount = [int]$ListView.Items.Count
        for ($i = 0; $i -lt $itemCount; $i++) {
            $item = $null
            try { $item = $ListView.Items.GetItemAt($i) } catch { continue }
            if (-not (Test-WmtUpdateListActionableItem -Item $item)) { continue }
            if (-not $item.PSObject.Properties["IsChecked"]) { continue }
            if ([bool]$item.IsChecked) { [void]$checked.Add($item) }
        }

        if ($checked.Count -eq 0 -and $FallbackToSelection) {
            $selectedCount = [int]$ListView.SelectedItems.Count
            for ($i = 0; $i -lt $selectedCount; $i++) {
                $item = $null
                try { $item = $ListView.SelectedItems[$i] } catch { continue }
                if (Test-WmtUpdateListActionableItem -Item $item) { [void]$checked.Add($item) }
            }
        }

        return $checked.ToArray()
    }
    catch {
        Write-GuiLog "ERROR: Could not read checked update rows: $($_.Exception.Message)"
        return @()
    }
}

function Set-WmtUpdateListCheckedState {
    param(
        [object[]]$Items,
        [bool]$IsChecked
    )

    foreach ($item in @($Items)) {
        if (-not $item) { continue }
        if (-not (Test-WmtUpdateListActionableItem -Item $item)) { continue }
        [void](Set-WmtUpdateListItemCheckState -Item $item -DefaultChecked:$IsChecked)
        try { $item.IsChecked = $IsChecked } catch {}
    }
    try { if ($lstWinget) { $lstWinget.Items.Refresh() } } catch {}
}

function Measure-WmtUpdateListTextScore {
    param([object]$Text)

    if ($null -eq $Text) { return 0.0 }
    $s = [string]$Text
    if ([string]::IsNullOrEmpty($s)) { return 0.0 }

    $score = 0.0
    foreach ($ch in $s.ToCharArray()) {
        $c = [string]$ch
        if ($c -match '\s') { $score += 0.35 }
        elseif ("ilI1.,:;|![]()".IndexOf($c) -ge 0) { $score += 0.35 }
        elseif ("MW@#%&".IndexOf($c) -ge 0) { $score += 1.25 }
        elseif ($c -cmatch '[A-Z0-9]') { $score += 0.90 }
        else { $score += 0.72 }
    }

    return [Math]::Min(140.0, [Math]::Ceiling($score))
}

function Get-WmtUpdateListPropertyText {
    param(
        [object]$Item,
        [string]$PropertyName
    )

    if ($null -eq $Item -or [string]::IsNullOrWhiteSpace($PropertyName)) { return "" }
    if ($Item.PSObject.Properties[$PropertyName]) { return [string]$Item.$PropertyName }
    return ""
}

function Set-WmtUpdateListSmartColumnWidths {
    param([System.Windows.Controls.ListView]$ListView = $lstWinget)

    if (-not $ListView -or -not $ListView.View -or -not ($ListView.View -is [System.Windows.Controls.GridView])) { return }
    $grid = [System.Windows.Controls.GridView]$ListView.View
    if (-not $grid.Columns -or $grid.Columns.Count -lt 6) { return }

    # There should only be six real update columns. If a stale/extra GridViewColumn ever survives
    # a patch merge, collapse it so it cannot look like an unused seventh column.
    if ($grid.Columns.Count -gt 6) {
        for ($i = 6; $i -lt $grid.Columns.Count; $i++) {
            try { $grid.Columns[$i].Width = 0.0 } catch {}
        }
    }

    $available = 0.0
    try {
        $viewer = Get-WmtVisualDescendant -Element $ListView -DescendantType ([System.Windows.Controls.ScrollViewer])
        if ($viewer -and -not [double]::IsNaN([double]$viewer.ViewportWidth) -and [double]$viewer.ViewportWidth -gt 150) {
            # ViewportWidth already excludes the vertical scrollbar, so using it prevents the
            # right-side blank GridView filler from being mistaken for another column.
            $available = [double]$viewer.ViewportWidth
        }
    }
    catch {}

    if ($available -le 150) {
        try { $available = [double]$ListView.ActualWidth - 4.0 } catch {}
    }
    if ($available -le 150) {
        try { $available = [double]$ListView.RenderSize.Width - 4.0 } catch {}
    }
    if ($available -le 150) { return }
    $available = [Math]::Max(420.0, [Math]::Floor($available) - 2.0)

    $specs = @(
        [PSCustomObject]@{ Index = 0; Header = "Select"; Property = "IsChecked"; Min = 64.0; Char = 0.0; Grow = 0.0; Fixed = $true },
        [PSCustomObject]@{ Index = 1; Header = "Source"; Property = "Source"; Min = 82.0; Char = 7.0; Grow = 0.35; Fixed = $false },
        [PSCustomObject]@{ Index = 2; Header = "Package Name"; Property = "Name"; Min = 210.0; Char = 7.0; Grow = 5.00; Fixed = $false },
        [PSCustomObject]@{ Index = 3; Header = "ID"; Property = "Id"; Min = 170.0; Char = 6.7; Grow = 3.50; Fixed = $false },
        [PSCustomObject]@{ Index = 4; Header = "Installed"; Property = "Version"; Min = 100.0; Char = 6.8; Grow = 0.85; Fixed = $false },
        [PSCustomObject]@{ Index = 5; Header = "Latest"; Property = "Available"; Min = 100.0; Char = 6.8; Grow = 0.85; Fixed = $false }
    )

    $scores = @{}
    foreach ($spec in $specs) {
        $scores[[int]$spec.Index] = Measure-WmtUpdateListTextScore $spec.Header
    }

    $sampled = 0
    foreach ($item in @($ListView.Items)) {
        if ($sampled -ge 600) { break }
        $sampled++
        foreach ($spec in $specs) {
            if ([bool]$spec.Fixed) { continue }
            $score = Measure-WmtUpdateListTextScore (Get-WmtUpdateListPropertyText -Item $item -PropertyName $spec.Property)
            if ($score -gt $scores[[int]$spec.Index]) { $scores[[int]$spec.Index] = $score }
        }
    }

    $widths = @{}
    foreach ($spec in $specs) {
        if ([bool]$spec.Fixed) {
            $widths[[int]$spec.Index] = [double]$spec.Min
            continue
        }
        $desired = ([double]$scores[[int]$spec.Index] * [double]$spec.Char) + 30.0
        $widths[[int]$spec.Index] = [Math]::Max([double]$spec.Min, [Math]::Ceiling($desired))
    }

    $total = 0.0
    foreach ($spec in $specs) { $total += [double]$widths[[int]$spec.Index] }

    if ($total -lt $available) {
        $extra = $available - $total
        $growTotal = 0.0
        foreach ($spec in $specs) { if (-not [bool]$spec.Fixed) { $growTotal += [double]$spec.Grow } }
        if ($growTotal -gt 0) {
            foreach ($spec in $specs) {
                if ([bool]$spec.Fixed) { continue }
                $widths[[int]$spec.Index] = [double]$widths[[int]$spec.Index] + ($extra * ([double]$spec.Grow / $growTotal))
            }
        }
    }
    elseif ($total -gt $available) {
        $overflow = $total - $available
        $shrinkRoom = 0.0
        foreach ($spec in $specs) {
            if ([bool]$spec.Fixed) { continue }
            $shrinkRoom += [Math]::Max(0.0, ([double]$widths[[int]$spec.Index] - [double]$spec.Min))
        }
        if ($shrinkRoom -gt 0) {
            foreach ($spec in $specs) {
                if ([bool]$spec.Fixed) { continue }
                $room = [Math]::Max(0.0, ([double]$widths[[int]$spec.Index] - [double]$spec.Min))
                $reduce = [Math]::Min($room, $overflow * ($room / $shrinkRoom))
                $widths[[int]$spec.Index] = [double]$widths[[int]$spec.Index] - $reduce
            }
        }
    }

    $roundedTotal = 0.0
    foreach ($spec in $specs) {
        $idx = [int]$spec.Index
        $newWidth = [Math]::Max([double]$spec.Min, [Math]::Floor([double]$widths[$idx]))
        $grid.Columns[$idx].Width = $newWidth
        $roundedTotal += $newWidth
    }

    $remainder = [Math]::Floor($available - $roundedTotal)
    if ($remainder -gt 0 -and $grid.Columns.Count -gt 2) {
        # Use the name column as the final elastic column so the GridView fills the card cleanly
        # instead of leaving a blank right-side filler that looks like an unused column.
        $grid.Columns[2].Width = [double]$grid.Columns[2].Width + $remainder
    }
    elseif ($remainder -lt -1 -and $grid.Columns.Count -gt 2) {
        # Last-pixel correction for DPI/rounding: trim the elastic name column before WPF creates
        # a horizontal scroll area or visually separates a phantom filler column.
        $trim = [Math]::Min([Math]::Abs($remainder), [Math]::Max(0.0, [double]$grid.Columns[2].Width - 210.0))
        if ($trim -gt 0) { $grid.Columns[2].Width = [double]$grid.Columns[2].Width - $trim }
    }
}

function Request-WmtUpdateListSmartColumnResize {
    param([System.Windows.Controls.ListView]$ListView = $lstWinget)

    if (-not $ListView) { return }
    $targetListView = $ListView
    try {
        $resizeAction = {
            Set-WmtUpdateListSmartColumnWidths -ListView $targetListView
        }.GetNewClosure()
        [void]$targetListView.Dispatcher.BeginInvoke([Action]$resizeAction, [System.Windows.Threading.DispatcherPriority]::Background)
    }
    catch {
        try { Set-WmtUpdateListSmartColumnWidths -ListView $targetListView } catch {}
    }
}

function Get-WmtListSortValue {
    param(
        [object]$Item,
        [string]$PropertyName
    )

    if ($null -eq $Item -or [string]::IsNullOrWhiteSpace($PropertyName)) { return "" }

    $value = $null
    if ($Item.PSObject.Properties[$PropertyName]) {
        $value = $Item.$PropertyName
    }
    elseif ($PropertyName -eq "VersionSort" -and $Item.PSObject.Properties["Version"]) {
        $value = $Item.Version
    }
    elseif ($PropertyName -eq "AvailableSort" -and $Item.PSObject.Properties["Available"]) {
        $value = $Item.Available
    }

    return Get-WmtNaturalSortKey $value
}

function Resolve-WingetSortProperty {
    param([string]$Header)
    switch ($Header) {
        "Select" { return "IsChecked" }
        "Package Name" { return "Name" }
        "Installed" { return "VersionSort" }
        "Latest" { return "AvailableSort" }
        default { return $Header }
    }
}

function Add-WmtCatalogListItems {
    param(
        [System.Windows.Controls.ListView]$ListView,
        [System.Collections.IEnumerable]$Items
    )

    if (-not $ListView) { return }
    $ListView.Items.Clear()
    foreach ($item in $Items) {
        if ($item) { [void]$ListView.Items.Add($item) }
    }
}

function Get-WmtCatalogItemsBySearch {
    param([string]$Query)

    $results = [System.Collections.Generic.List[object]]::new()
    $queryText = ([string]$Query).Trim()
    foreach ($item in $script:SoftwareCatalog) {
        if ([string]::IsNullOrWhiteSpace($queryText) -or
            ([string]$item.Name).IndexOf($queryText, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            ([string]$item.Description).IndexOf($queryText, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            [void]$results.Add($item)
        }
    }
    return $results.ToArray()
}

function Get-WmtCatalogItemsByCategory {
    param([string]$Category)

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $script:SoftwareCatalog) {
        if ([string]::Equals([string]$item.Category, $Category, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$results.Add($item)
        }
    }
    return $results.ToArray()
}

function Get-CatalogByCategory($Category) {
    Add-WmtCatalogListItems -ListView $lstCatalog -Items (Get-WmtCatalogItemsByCategory -Category $Category)
}

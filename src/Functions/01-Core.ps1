# Functional block generated from WMT-GUI.ps1.
# Dot-source this file; it intentionally shares WMT's script scope.

function ConvertTo-WmtVersion {
    param([string]$VersionText)

    $raw = ([string]$VersionText).Trim()
    $match = [regex]::Match($raw, '^\s*v?(\d+(?:\.\d+){0,3})\s*$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        throw "Invalid version string: $VersionText"
    }

    $parts = @($match.Groups[1].Value.Split("."))
    while ($parts.Count -lt 4) { $parts += "0" }
    return [System.Version]::new([int]$parts[0], [int]$parts[1], [int]$parts[2], [int]$parts[3])
}

function Test-WmtDirectoryReparsePoint {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }
    try {
        $attributes = [System.IO.Directory]::GetAttributes($Path)
        return (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
    }
    catch {
        return $true
    }
}

function Get-WmtEnumeratedFiles {
    param(
        [string]$Path,
        [string]$Filter = "*",
        [switch]$Recurse
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.Directory]::Exists($Path)) { return }

    if (-not $Recurse) {
        try {
            foreach ($file in [System.IO.Directory]::EnumerateFiles($Path, $Filter, [System.IO.SearchOption]::TopDirectoryOnly)) {
                $file
            }
        }
        catch {}
        return
    }

    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $pending = [System.Collections.Generic.Stack[string]]::new()
    try { $pending.Push([System.IO.DirectoryInfo]::new($Path).FullName) } catch { $pending.Push($Path) }
    while ($pending.Count -gt 0) {
        $dir = $pending.Pop()
        try { $dirKey = [System.IO.DirectoryInfo]::new($dir).FullName.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) } catch { $dirKey = $dir }
        if (-not $visited.Add($dirKey)) { continue }
        if (Test-WmtDirectoryReparsePoint -Path $dir) { continue }

        try {
            foreach ($file in [System.IO.Directory]::EnumerateFiles($dir, $Filter, [System.IO.SearchOption]::TopDirectoryOnly)) {
                $file
            }
        }
        catch {}

        try {
            foreach ($child in [System.IO.Directory]::EnumerateDirectories($dir, "*", [System.IO.SearchOption]::TopDirectoryOnly)) {
                if (Test-WmtDirectoryReparsePoint -Path $child) { continue }
                $pending.Push($child)
            }
        }
        catch {}
    }
}

function Find-WmtFirstEnumeratedFile {
    param([string]$Path, [string]$Filter)
    foreach ($file in Get-WmtEnumeratedFiles -Path $Path -Filter $Filter -Recurse) {
        return $file
    }
    return $null
}

function Measure-WmtPathBytes {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return 0 }
    try {
        if ([System.IO.File]::Exists($Path)) {
            return [System.IO.FileInfo]::new($Path).Length
        }
        if ([System.IO.Directory]::Exists($Path)) {
            $total = [int64]0
            foreach ($file in Get-WmtEnumeratedFiles -Path $Path -Recurse) {
                try { $total += [System.IO.FileInfo]::new($file).Length } catch {}
            }
            return $total
        }
    }
    catch {}
    return 0
}

function Test-WmtDirectoryHasEntries {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.Directory]::Exists($Path)) { return $false }
    try {
        foreach ($entry in [System.IO.Directory]::EnumerateFileSystemEntries($Path)) {
            return $true
        }
    }
    catch {}
    return $false
}

function Remove-WmtEmptyChildDirectories {
    param(
        [string]$Path,
        [System.Collections.Generic.HashSet[string]]$Visited
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.Directory]::Exists($Path)) { return }
    if (-not $Visited) {
        $Visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }
    try { $pathKey = [System.IO.DirectoryInfo]::new($Path).FullName.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) } catch { $pathKey = $Path }
    if (-not $Visited.Add($pathKey)) { return }
    if (Test-WmtDirectoryReparsePoint -Path $Path) { return }
    try {
        foreach ($dir in [System.IO.Directory]::EnumerateDirectories($Path, "*", [System.IO.SearchOption]::TopDirectoryOnly)) {
            if (Test-WmtDirectoryReparsePoint -Path $dir) { continue }
            Remove-WmtEmptyChildDirectories -Path $dir -Visited $Visited
            try { [System.IO.Directory]::Delete($dir, $false) } catch {}
        }
    }
    catch {}
}

function New-WmtVirtualRows {
    param([object[]]$Items)
    $rows = [System.Collections.ArrayList]::new()
    foreach ($item in @($Items)) { [void]$rows.Add($item) }
    return , $rows
}

function ConvertTo-WmtProcessArgument {
    param([string]$Value)

    if ($null -eq $Value) { return '""' }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Start-AppByStartMenuName {
    param([string[]]$NamePatterns)
    try {
        $apps = @(Get-StartApps -ErrorAction SilentlyContinue)
        foreach ($pattern in $NamePatterns) {
            $match = $apps | Where-Object { $_.Name -match $pattern } | Select-Object -First 1
            if ($match -and $match.AppID) {
                Start-Process "explorer.exe" -ArgumentList "shell:AppsFolder\$($match.AppID)"
                return $true
            }
        }
    }
    catch {}
    return $false
}

function Start-ExistingExecutable {
    param([string[]]$Paths)
    foreach ($path in $Paths) {
        try {
            $expanded = [Environment]::ExpandEnvironmentVariables($path)
            if (Test-Path $expanded) {
                Start-Process $expanded
                return $true
            }
        }
        catch {}
    }
    return $false
}

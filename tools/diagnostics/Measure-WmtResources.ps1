#requires -Version 5.1
<#
.SYNOPSIS
    Samples WMT process memory and resource usage to help diagnose gradual RAM growth.
.DESCRIPTION
    Records the selected process and its descendant processes to CSV. This opt-in
    utility does not change WMT settings or terminate processes. Access-denied
    processes are skipped and counted. Run elevated only when necessary.
.PARAMETER ProcessId
    PID of the WMT process to monitor. For a script-based launch, use the PID of
    the PowerShell process hosting WMT, not this diagnostic script's PID.
.PARAMETER SampleIntervalSeconds
    Time between samples (1-60 seconds).
.PARAMETER DurationMinutes
    Maximum capture duration (1-1440 minutes). Ctrl+C stops the capture.
.PARAMETER OutputPath
    CSV path. Defaults to a timestamped file in the current directory.
.EXAMPLE
    .\Measure-WmtResources.ps1 -ProcessId 1234 -DurationMinutes 30
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 2147483647)]
    [int]$ProcessId,

    [ValidateRange(1, 60)]
    [int]$SampleIntervalSeconds = 2,

    [ValidateRange(1, 1440)]
    [int]$DurationMinutes = 30,

    [string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = Join-Path (Get-Location).Path "WMT-resource-diagnostics-$stamp.csv"
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = [System.IO.Path]::GetDirectoryName($resolvedOutput)
if (-not [System.IO.Directory]::Exists($outputDirectory)) {
    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}
if (Test-Path -LiteralPath $resolvedOutput) {
    throw "Output file already exists; choose another path to avoid mixing captures: $resolvedOutput"
}

function Get-WmtProcessTreeSnapshot {
    param([Parameter(Mandatory = $true)][int]$RootProcessId)

    $errors = 0
    $allProcesses = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop)
    $childrenByParent = @{}
    foreach ($item in $allProcesses) {
        $parentKey = [string]$item.ParentProcessId
        if (-not $childrenByParent.ContainsKey($parentKey)) {
            $childrenByParent[$parentKey] = [System.Collections.Generic.List[object]]::new()
        }
        $childrenByParent[$parentKey].Add($item)
    }

    $queue = [System.Collections.Generic.Queue[int]]::new()
    $queue.Enqueue($RootProcessId)
    $seen = [System.Collections.Generic.HashSet[int]]::new()
    $tree = [System.Collections.Generic.List[object]]::new()

    while ($queue.Count -gt 0) {
        $currentId = $queue.Dequeue()
        if (-not $seen.Add($currentId)) { continue }

        try {
            $proc = Get-Process -Id $currentId -ErrorAction Stop
            $tree.Add([pscustomobject]@{
                ProcessId = $proc.Id
                ProcessName = $proc.ProcessName
                WorkingSetBytes = [long]$proc.WorkingSet64
                PrivateBytes = [long]$proc.PrivateMemorySize64
                PagedMemoryBytes = [long]$proc.PagedMemorySize64
                HandleCount = [int]$proc.HandleCount
                ThreadCount = [int]$proc.Threads.Count
                CpuSeconds = [double]$proc.TotalProcessorTime.TotalSeconds
            })
        }
        catch {
            $errors++
        }

        $key = [string]$currentId
        if ($childrenByParent.ContainsKey($key)) {
            foreach ($child in $childrenByParent[$key]) {
                $childId = 0
                if ([int]::TryParse([string]$child.ProcessId, [ref]$childId)) {
                    $queue.Enqueue($childId)
                }
            }
        }
    }

    [pscustomobject]@{
        Processes = @($tree.ToArray())
        AccessErrors = $errors
    }
}

function Get-WmtMetricTotal {
    param(
        [Parameter(Mandatory = $true)][object[]]$Processes,
        [Parameter(Mandatory = $true)][string]$Property
    )
    $total = [double]0
    foreach ($entry in $Processes) {
        $total += [double]$entry.$Property
    }
    return $total
}

Write-Host "Monitoring WMT process tree rooted at PID $ProcessId."
Write-Host "Interval: $SampleIntervalSeconds seconds; duration: $DurationMinutes minutes."
Write-Host "CSV: $resolvedOutput"
Write-Host 'Press Ctrl+C to stop early.'

$deadline = (Get-Date).AddMinutes($DurationMinutes)
$sampleNumber = 0
$firstSample = $null
$lastSample = $null
$previousRootPrivateBytes = $null
$previousRootWorkingSetBytes = $null

while ((Get-Date) -lt $deadline) {
    $sampleTime = Get-Date
    try {
        $snapshot = Get-WmtProcessTreeSnapshot -RootProcessId $ProcessId
    }
    catch {
        Write-Warning "Process enumeration failed: $($_.Exception.Message)"
        break
    }

    $processes = @($snapshot.Processes)
    if ($processes.Count -eq 0 -or -not ($processes | Where-Object { $_.ProcessId -eq $ProcessId })) {
        Write-Warning "Root PID $ProcessId is no longer accessible or has exited. Ending capture."
        break
    }

    $root = $processes | Where-Object { $_.ProcessId -eq $ProcessId } | Select-Object -First 1
    $descendants = @($processes | Where-Object { $_.ProcessId -ne $ProcessId })
    $availableMemory = $null
    $systemMemory = $null
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $systemMemory = [long]$os.TotalVisibleMemorySize * 1024
        $availableMemory = [long]$os.FreePhysicalMemory * 1024
    }
    catch { }

    $treeWorkingSet = Get-WmtMetricTotal -Processes $processes -Property 'WorkingSetBytes'
    $treePrivate = Get-WmtMetricTotal -Processes $processes -Property 'PrivateBytes'
    $treeHandles = Get-WmtMetricTotal -Processes $processes -Property 'HandleCount'
    $treeThreads = Get-WmtMetricTotal -Processes $processes -Property 'ThreadCount'
    $treeCpuSeconds = Get-WmtMetricTotal -Processes $processes -Property 'CpuSeconds'
    $sampleNumber++

    $row = [pscustomobject]@{
        Timestamp = $sampleTime.ToString('o')
        Sample = $sampleNumber
        RootProcessId = $ProcessId
        RootProcessName = $root.ProcessName
        RootWorkingSetMiB = [math]::Round($root.WorkingSetBytes / 1MB, 2)
        RootPrivateMiB = [math]::Round($root.PrivateBytes / 1MB, 2)
        RootPagedMemoryMiB = [math]::Round($root.PagedMemoryBytes / 1MB, 2)
        RootHandles = $root.HandleCount
        RootThreads = $root.ThreadCount
        RootCpuSeconds = [math]::Round($root.CpuSeconds, 2)
        TreeProcessCount = $processes.Count
        ChildProcessCount = $descendants.Count
        TreeWorkingSetMiB = [math]::Round($treeWorkingSet / 1MB, 2)
        TreePrivateMiB = [math]::Round($treePrivate / 1MB, 2)
        TreeHandles = $treeHandles
        TreeThreads = $treeThreads
        TreeCpuSeconds = [math]::Round($treeCpuSeconds, 2)
        AvailableSystemMemoryMiB = if ($null -ne $availableMemory) { [math]::Round($availableMemory / 1MB, 2) } else { $null }
        TotalSystemMemoryMiB = if ($null -ne $systemMemory) { [math]::Round($systemMemory / 1MB, 2) } else { $null }
        ProcessAccessErrors = $snapshot.AccessErrors
        ChildProcessNames = (($descendants | Group-Object ProcessName | Sort-Object Count -Descending | ForEach-Object { "$($_.Name):$($_.Count)" }) -join ';')
    }

    if ($null -eq $firstSample) {
        $firstSample = $row
        $row | Export-Csv -LiteralPath $resolvedOutput -NoTypeInformation
    }
    else {
        $row | Export-Csv -LiteralPath $resolvedOutput -NoTypeInformation -Append
    }
    $lastSample = $row

    $privateDelta = if ($null -ne $previousRootPrivateBytes) { [math]::Round(($root.PrivateBytes - $previousRootPrivateBytes) / 1MB, 2) } else { 0 }
    $workingSetDelta = if ($null -ne $previousRootWorkingSetBytes) { [math]::Round(($root.WorkingSetBytes - $previousRootWorkingSetBytes) / 1MB, 2) } else { 0 }
    Write-Host ('[{0}] PID {1} WS {2:N1} MiB ({3:+0.0;-0.0;0.0}), Private {4:N1} MiB ({5:+0.0;-0.0;0.0}), tree private {6:N1} MiB, children {7}, handles {8}, threads {9}' -f $sampleTime.ToString('HH:mm:ss'), $ProcessId, ($root.WorkingSetBytes / 1MB), $workingSetDelta, ($root.PrivateBytes / 1MB), $privateDelta, ($treePrivate / 1MB), $descendants.Count, $root.HandleCount, $root.ThreadCount)

    $previousRootPrivateBytes = $root.PrivateBytes
    $previousRootWorkingSetBytes = $root.WorkingSetBytes
    Start-Sleep -Seconds $SampleIntervalSeconds
}

if ($sampleNumber -gt 0) {
    Write-Host ''
    Write-Host "Capture finished: $sampleNumber samples."
    Write-Host ('Root private memory: {0:N1} MiB -> {1:N1} MiB (delta {2:+0.0;-0.0;0.0} MiB)' -f $firstSample.RootPrivateMiB, $lastSample.RootPrivateMiB, ($lastSample.RootPrivateMiB - $firstSample.RootPrivateMiB))
    Write-Host ('Root working set: {0:N1} MiB -> {1:N1} MiB (delta {2:+0.0;-0.0;0.0} MiB)' -f $firstSample.RootWorkingSetMiB, $lastSample.RootWorkingSetMiB, ($lastSample.RootWorkingSetMiB - $firstSample.RootWorkingSetMiB))
    Write-Host ('Process-tree private memory: {0:N1} MiB -> {1:N1} MiB (delta {2:+0.0;-0.0;0.0} MiB)' -f $firstSample.TreePrivateMiB, $lastSample.TreePrivateMiB, ($lastSample.TreePrivateMiB - $firstSample.TreePrivateMiB))
    Write-Host "Saved: $resolvedOutput"
}
else {
    Write-Warning 'No samples were captured.'
}

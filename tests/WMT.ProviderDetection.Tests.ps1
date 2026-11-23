# Provider installed-state detection regressions for Windows PowerShell 5.1.
# These tests exercise the compiled detector, the persisted first-run cache,
# the scan filter, and the single "not detected" scan summary.
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) {
    throw 'The provider detection regressions require Windows PowerShell 5.1.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot 'WMT-GUI.ps1'
$source = [System.IO.File]::ReadAllText($sourcePath)
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput(
    $source,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors -and $parseErrors.Count -gt 0) {
    throw ($parseErrors.Message -join '; ')
}

function Get-ProductionFunctionText([string]$Name) {
    $node = $ast.Find({
            param($candidate)
            $candidate -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $candidate.Name -eq $Name
        }, $true)
    if (-not $node) { throw "Missing production function: $Name" }
    return $node.Extent.Text
}

foreach ($name in @(
        'Get-WmtCanonicalProviderKey',
        'Initialize-WmtProviderDetector',
        'Get-WmtProviderPathText',
        'Get-WmtProviderPathStamp',
        'Get-WmtProviderStatusCachePath',
        'Read-WmtProviderStatusCache',
        'Write-WmtProviderStatusCache',
        'Set-WmtProviderStatusCacheEntry',
        'Get-WmtProviderAvailability',
        'Select-WmtScannableProviderKeys',
        'Get-WmtProviderDisplayName',
        'Get-WmtProviderDefinitions',
        'Get-WmtUpdateScanCompletion'
    )) {
    Invoke-Expression (Get-ProductionFunctionText $name)
}

# The shared provider table references the portable game-provider paths. Stub
# them so this regression does not depend on the developer's data folder.
function Get-WmtLegendaryExePath { return '' }
function Get-WmtGogdlExePath { return '' }

$detectorSourceAssignment = $ast.Find({
        param($candidate)
        $candidate -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $candidate.Left.Extent.Text -eq '$script:WmtProviderDetectorSource'
    }, $true)
if (-not $detectorSourceAssignment) {
    throw 'The compiled provider detector source is missing.'
}
Invoke-Expression $detectorSourceAssignment.Extent.Text

$aliasProbeAssignment = $ast.Find({
        param($candidate)
        $candidate -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $candidate.Left.Extent.Text -eq '$script:WmtProviderAliasProbeCommands'
    }, $true)
if (-not $aliasProbeAssignment) {
    throw 'The alias-probe command set is missing.'
}
Invoke-Expression $aliasProbeAssignment.Extent.Text

$probeScriptAssignment = $ast.Find({
        param($candidate)
        $candidate -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $candidate.Left.Extent.Text -eq '$script:WmtProviderProbeScript'
    }, $true)
if (-not $probeScriptAssignment) {
    throw 'The shared installed-state probe is missing.'
}
Invoke-Expression $probeScriptAssignment.Extent.Text

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$script:ProviderDetectionLog = [System.Collections.Generic.List[string]]::new()
function Write-GuiLog {
    param($Message)
    [void]$script:ProviderDetectionLog.Add([string]$Message)
}

$script:ProviderDetectionDataPath = Join-Path ([System.IO.Path]::GetTempPath()) ('wmt-provider-detection-' + [Guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($script:ProviderDetectionDataPath)
function Get-DataPath { return $script:ProviderDetectionDataPath }
$script:WmtProviderAvailabilityCache = $null
$script:WmtProviderAvailabilityCachePath = $null

$oldPath = $env:PATH
try {
    Assert-True (Initialize-WmtProviderDetector) 'The compiled .NET provider detector did not initialize.'
    Assert-True ($null -ne ('Wmt.Providers.Detector' -as [type])) 'The compiled detector type is unavailable.'

    $fixtureDirectory = Join-Path $script:ProviderDetectionDataPath 'bin'
    [void][System.IO.Directory]::CreateDirectory($fixtureDirectory)
    [System.IO.File]::WriteAllText(
        (Join-Path $fixtureDirectory 'wmt-fixture-tool.cmd'),
        "@echo off`r`necho fixture",
        [System.Text.UTF8Encoding]::new($false)
    )
    $localProviderPath = Join-Path $script:ProviderDetectionDataPath 'portable-provider.exe'
    [System.IO.File]::WriteAllText(
        $localProviderPath,
        'fixture',
        [System.Text.UTF8Encoding]::new($false)
    )
    $env:PATH = $fixtureDirectory + ';' + $oldPath

    Assert-True ([Wmt.Providers.Detector]::TestCommand('wmt-fixture-tool', $env:PATH)) 'The compiled detector did not find a PATH command.'
    Assert-True (-not [Wmt.Providers.Detector]::TestCommand('wmt-missing-tool', $env:PATH)) 'The compiled detector invented a PATH command.'
    Assert-True ([Wmt.Providers.Detector]::TestRegistryPath('HKCU:\Software')) 'The compiled detector did not see an existing registry key.'
    Assert-True ([Wmt.Providers.Detector]::TestLocalPath($localProviderPath)) 'The compiled detector did not see a local provider file.'

    $providerDefinitions = @(
        [PSCustomObject]@{ Key = 'winget'; Commands = [string[]]@('wmt-fixture-tool') },
        [PSCustomObject]@{ Key = 'scoop'; Commands = [string[]]@('wmt-missing-tool') },
        [PSCustomObject]@{ Key = 'legendary'; Commands = [string[]]@(); LocalPaths = [string[]]@($localProviderPath) }
    )

    $availability = Get-WmtProviderAvailability -ProviderDefinitions $providerDefinitions -Force
    Assert-True (-not $availability.FromCache) 'A forced installed-state scan reported a cache hit.'
    Assert-True ([bool]$availability.Providers['winget']) 'A configured PATH provider was not detected.'
    Assert-True (-not [bool]$availability.Providers['scoop']) 'A missing provider was reported as installed.'
    Assert-True ([bool]$availability.Providers['legendary']) 'A portable local-path provider was not detected.'
    Assert-True (Test-Path -LiteralPath (Get-WmtProviderStatusCachePath) -PathType Leaf) 'The first-run provider cache was not persisted.'

    $cachedAvailability = Get-WmtProviderAvailability -ProviderDefinitions $providerDefinitions -MaxAgeMinutes 60
    Assert-True ($cachedAvailability.FromCache) 'A fresh persisted provider cache was not reused.'

    # A PATH change is an explicit invalidation signal even while the cache TTL
    # is still fresh. Installing a provider must be visible to the next scan.
    $env:PATH = (Join-Path $script:ProviderDetectionDataPath 'empty') + ';' + $env:PATH
    $invalidatedAvailability = Get-WmtProviderAvailability -ProviderDefinitions $providerDefinitions -MaxAgeMinutes 60
    Assert-True (-not $invalidatedAvailability.FromCache) 'A PATH change did not invalidate the provider cache.'
    Assert-True ([bool]$invalidatedAvailability.Providers['winget']) 'A provider disappeared after a harmless PATH change.'

    $selection = Select-WmtScannableProviderKeys `
        -EnabledProviders @('winget', 'scoop', 'legendary') `
        -Availability $cachedAvailability
    Assert-True (@($selection.Runnable) -join ',' -eq 'winget,legendary') 'The scan filter did not retain installed providers.'
    Assert-True (@($selection.Unavailable) -join ',' -eq 'scoop') 'The scan filter did not isolate the missing provider.'

    # The same probe text runs in the Provider panel's background runspace.
    # Verify it works without any WMT functions in scope and restores PATH.
    $parentPath = $env:Path
    $sharedPathText = $parentPath + ';' + (Join-Path $script:ProviderDetectionDataPath 'empty')
    $inlineProbe = @(& $script:WmtProviderProbeScript `
            -Providers $providerDefinitions `
            -AliasProbeCommands $script:WmtProviderAliasProbeCommands `
            -PathText $sharedPathText)
    Assert-True ($env:Path -eq $parentPath) 'The shared probe did not restore the process PATH.'
    Assert-True (@($inlineProbe | Where-Object { $_.Key -eq 'winget' -and $_.Installed }).Count -eq 1) 'The shared probe did not detect the PATH fixture provider.'
    Assert-True (@($inlineProbe | Where-Object { $_.Key -eq 'scoop' -and -not $_.Installed }).Count -eq 1) 'The shared probe invented the missing provider.'

    $childProbe = [PowerShell]::Create()
    try {
        $childCommand = $childProbe.AddScript($script:WmtProviderProbeScript.ToString())
        [void]$childCommand.AddArgument($providerDefinitions)
        [void]$childCommand.AddArgument([string[]]@($script:WmtProviderAliasProbeCommands))
        [void]$childCommand.AddArgument([string]$sharedPathText)
        $childResults = @($childProbe.Invoke())
        Assert-True (-not $childProbe.HadErrors) 'The shared probe failed in a clean background runspace.'
        Assert-True (@($childResults | Where-Object { $_.Key -eq 'winget' -and $_.Installed }).Count -eq 1) 'The background probe did not detect the PATH fixture provider.'
        Assert-True (@($childResults | Where-Object { $_.Key -eq 'scoop' -and -not $_.Installed }).Count -eq 1) 'The background probe invented the missing provider.'
    }
    finally {
        $childProbe.Dispose()
    }

    [void](Set-WmtProviderStatusCacheEntry -ProviderKey 'scoop' -Installed $true)
    $updatedCache = Read-WmtProviderStatusCache -Refresh
    Assert-True ([bool]$updatedCache.Providers['scoop']) 'A provider action did not invalidate its cached missing state.'

    $summary = Get-WmtUpdateScanCompletion `
        -UpdateCount 2 `
        -UnavailableProviders @('scoop', 'gem') `
        -ProviderLabels @{ scoop = 'Scoop'; gem = 'Ruby (Gem)' }
    Assert-True ($summary.IsComplete) 'A scan with a missing provider was not complete.'
    Assert-True (-not $summary.HasProviderFailures) 'A missing provider was treated as a provider failure.'
    Assert-True ($summary.HasUnavailableProviders) 'A missing provider was not reported as unavailable.'
    Assert-True ($summary.LogMessage -match 'Scoop, Ruby \(Gem\) are not detected\.') 'The scan summary did not name the missing providers.'
    Assert-True ($summary.LogMessage -notmatch 'provider failed independently') 'The scan summary still called missing providers failures.'
    Assert-True ($summary.StatusText -match 'not detected: Scoop, Ruby \(Gem\)') 'The scan status did not name the missing providers.'

    $partial = Get-WmtUpdateScanCompletion `
        -UpdateCount 1 `
        -ProviderFailures @{ pip = 'simulated failure' } `
        -UnavailableProviders @('scoop') `
        -ProviderLabels @{ pip = 'Python (Pip)'; scoop = 'Scoop' }
    Assert-True ($partial.HasProviderFailures) 'A real provider failure was lost when a provider was also missing.'
    Assert-True ($partial.HasUnavailableProviders) 'A missing provider was lost when another provider failed.'
    Assert-True ($partial.LogMessage -match 'provider failed independently: pip\.') 'The real provider failure was not summarized.'
    Assert-True ($partial.LogMessage -match 'Scoop is not detected\.') 'The missing provider was not summarized alongside the real failure.'

    # Alias-only providers still use a narrow Get-Command fallback. The probe
    # list is intentionally small; scanning every missing command made the
    # first run slower than the compiled file checks it was supplementing.
    function global:wmt-fixture-alias { return 'fixture' }
    [void]$script:WmtProviderAliasProbeCommands.Add('wmt-fixture-alias')
    $aliasAvailability = Get-WmtProviderAvailability -ProviderDefinitions @(
        [PSCustomObject]@{ Key = 'aliasprovider'; Commands = [string[]]@('wmt-fixture-alias') }
    ) -Force
    Assert-True ([bool]$aliasAvailability.Providers['aliasprovider']) 'The alias-command fallback did not detect a PowerShell alias provider.'

    # The scan builds its definitions from the shared function because the
    # Provider Settings dialog's $providerDefinitions is not in scope there.
    # Verify the shared table is complete and directly usable by the detector.
    $sharedDefinitions = @(Get-WmtProviderDefinitions)
    Assert-True ($sharedDefinitions.Count -eq 16) 'The shared provider definition table is incomplete.'
    $sharedKeys = @($sharedDefinitions | ForEach-Object { [string]$_.Key })
    foreach ($requiredKey in @(
            'winget', 'msstore', 'windowsupdate', 'pip', 'npm', 'pnpm',
            'chocolatey', 'scoop', 'gem', 'cargo', 'dotnet', 'psmodule',
            'composer', 'steam', 'legendary', 'gogdl'
        )) {
        Assert-True ($sharedKeys -contains $requiredKey) "The shared provider definition table is missing '$requiredKey'."
    }
    $sharedAvailability = Get-WmtProviderAvailability -ProviderDefinitions $sharedDefinitions -Force
    Assert-True (@($sharedAvailability.Providers.Keys).Count -eq 16) 'The shared provider definition table did not produce a complete availability cache.'

    # Guard the scan scope regression that a real first-run GUI scan exposed:
    # Provider Settings' local definitions must not be referenced by the scan.
    Assert-True ($source -match '\$scanProviderDefinitions\s*=\s*@\(Get-WmtProviderDefinitions\)') 'The update scan does not build provider definitions from the shared table.'
    Assert-True ($source -match '-ProviderDefinitions \$scanProviderDefinitions') 'The update scan does not pass the shared definitions to installed-state detection.'
    Assert-True ($source -match '\$providerDetectionPs\.AddScript\(\$sharedProviderProbeScript\.ToString\(\)\)') 'The Provider panel background probe does not use the shared probe.'
    Assert-True ($source -match '\$detector\.AddScript\(\$state\.ProbeScript\.ToString\(\)\)') 'The post-install provider probe does not use the shared probe.'
    Assert-True ($source -match '(?s)\$testProviderInstalled\s*=\s*\{.*?& \$sharedProviderProbeScript') 'The provider action installed-state check does not use the shared probe.'

    # Scan completion must resolve display names even when no label map is
    # supplied, so a scan never reports raw keys such as "scoop, gem".
    $unlabeledSummary = Get-WmtUpdateScanCompletion -UpdateCount 0 -UnavailableProviders @('scoop', 'gem')
    Assert-True ($unlabeledSummary.LogMessage -match 'Scoop, Ruby \(Gem\) are not detected\.') 'The scan summary did not resolve display names without a label map.'

    Write-Host 'PASS: compiled provider detection, shared definitions, cache, scan filtering, alias fallback, and not-detected summary.'
}
finally {
    $env:PATH = $oldPath
    try { Remove-Item -LiteralPath $script:ProviderDetectionDataPath -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    $script:WmtProviderAvailabilityCache = $null
    $script:WmtProviderAvailabilityCachePath = $null
}

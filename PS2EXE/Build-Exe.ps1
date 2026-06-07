#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$InputFile,
    [string]$OutputFile,
    [string]$IconFile,
    [switch]$InstallPS2EXE
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$script:WmtBuildScriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
}
elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    (Get-Location).Path
}

$script:WmtProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $script:WmtBuildScriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($InputFile)) {
    $InputFile = Join-Path $script:WmtProjectRoot "WMT-GUI.ps1"
}

if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $OutputFile = Join-Path $script:WmtProjectRoot "dist\WindowsMaintenanceTool.exe"
}

if ([string]::IsNullOrWhiteSpace($IconFile)) {
    $IconFile = Join-Path $script:WmtBuildScriptRoot "WMT.ico"
}

function Resolve-WmtBuildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BasePath
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Get-WmtSourceVersion {
    param([Parameter(Mandatory = $true)][string]$Path)

    $content = Get-Content -LiteralPath $Path -Raw

    $assignmentMatch = [regex]::Match(
        $content,
        '(?im)^\s*(?:\$(?:script:|global:|private:)?AppVersion)\s*=\s*(["'']?)(v?\d+(?:\.\d+){0,3})\1\s*(?:$|[;#])'
    )

    if ($assignmentMatch.Success) {
        return $assignmentMatch.Groups[2].Value
    }

    throw "App version not found in source file: $Path"
}

function ConvertTo-WmtVersionText {
    param([Parameter(Mandatory = $true)][string]$Version)

    $match = [regex]::Match(([string]$Version).Trim(), '^\s*v?(\d+(?:\.\d+){0,3})\s*$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        throw "Invalid AppVersion format: $Version"
    }

    return $match.Groups[1].Value
}

function ConvertTo-WmtFileVersion {
    param([Parameter(Mandatory = $true)][string]$Version)

    $versionText = ConvertTo-WmtVersionText -Version $Version
    $parts = @($versionText.Split("."))
    while ($parts.Count -lt 4) {
        $parts += "0"
    }

    return ($parts[0..3] -join ".")
}

function Assert-WmtPowerShellSyntax {
    param([Parameter(Mandatory = $true)][string]$Path)

    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)

    if ($parseErrors -and $parseErrors.Count -gt 0) {
        $messages = $parseErrors | ForEach-Object {
            "{0}:{1}: {2}" -f $_.Extent.StartLineNumber, $_.Extent.StartColumnNumber, $_.Message
        }
        throw "PowerShell parse errors were found:`r`n$($messages -join "`r`n")"
    }
}

function New-WmtBundledSource {
    param(
        [Parameter(Mandatory = $true)][string]$EntryPoint,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$OutputDirectory
    )

    $entryContent = [System.IO.File]::ReadAllText($EntryPoint)
    $loaderPattern = '(?ms)^\s*# <WMT-MODULE-LOADER>\s*$.*?^\s*# </WMT-MODULE-LOADER>\s*$'
    if (-not [regex]::IsMatch($entryContent, $loaderPattern)) {
        return $EntryPoint
    }

    $sourceRoot = Join-Path $ProjectRoot "src"
    $manifestPath = Join-Path $sourceRoot "WMT.SourceOrder.txt"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Modular source manifest not found: $manifestPath"
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine([regex]::Replace($entryContent, $loaderPattern, ""))
    foreach ($relativeSourcePath in (Get-Content -LiteralPath $manifestPath)) {
        if ([string]::IsNullOrWhiteSpace($relativeSourcePath) -or $relativeSourcePath.TrimStart().StartsWith("#")) {
            continue
        }

        $sourcePath = Join-Path $sourceRoot $relativeSourcePath
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Modular source file not found: $sourcePath"
        }
        [void]$builder.AppendLine([System.IO.File]::ReadAllText($sourcePath))
    }

    $bundledPath = Join-Path $OutputDirectory ("WMT-GUI.bundled.{0}.ps1" -f ([Guid]::NewGuid().ToString("N")))
    [System.IO.File]::WriteAllText($bundledPath, $builder.ToString(), (New-Object System.Text.UTF8Encoding($true)))
    return $bundledPath
}

function Get-WmtPS2EXECommand {
    param([switch]$Install)

    $command = Get-Command Invoke-PS2EXE -ErrorAction SilentlyContinue
    if ($command) {
        return $command
    }

    if (-not $Install) {
        throw "Invoke-PS2EXE was not found. Install PS2EXE first, or rerun this script with -InstallPS2EXE."
    }

    Write-Host "Installing PS2EXE for the current user..."
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
    }

    Install-Module -Name ps2exe -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -Confirm:$false
    Import-Module ps2exe -Force

    return (Get-Command Invoke-PS2EXE -ErrorAction Stop)
}

function Add-WmtPS2EXEValue {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Arguments,
        [Parameter(Mandatory = $true)][string[]]$AvailableParameters,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value
    )

    if ($AvailableParameters -contains $Name) {
        $Arguments[$Name] = $Value
    }
}

function Add-WmtPS2EXESwitch {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Arguments,
        [Parameter(Mandatory = $true)][string[]]$AvailableParameters,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($AvailableParameters -contains $Name) {
        $Arguments[$Name] = $true
    }
}

$resolvedInput = Resolve-WmtBuildPath -Path $InputFile -BasePath $script:WmtProjectRoot
$resolvedOutput = Resolve-WmtBuildPath -Path $OutputFile -BasePath $script:WmtProjectRoot
$resolvedIcon = Resolve-WmtBuildPath -Path $IconFile -BasePath $script:WmtBuildScriptRoot

if (-not (Test-Path -LiteralPath $resolvedInput -PathType Leaf)) {
    throw "Input file not found: $resolvedInput"
}

if (-not (Test-Path -LiteralPath $resolvedIcon -PathType Leaf)) {
    throw "Icon file not found: $resolvedIcon"
}

$outputDirectory = Split-Path -Parent $resolvedOutput
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

Assert-WmtPowerShellSyntax -Path $resolvedInput
$buildInput = New-WmtBundledSource -EntryPoint $resolvedInput -ProjectRoot $script:WmtProjectRoot -OutputDirectory $outputDirectory
Assert-WmtPowerShellSyntax -Path $buildInput

$appVersion = ConvertTo-WmtVersionText -Version (Get-WmtSourceVersion -Path $resolvedInput)
$fileVersion = ConvertTo-WmtFileVersion -Version $appVersion
$ps2exe = Get-WmtPS2EXECommand -Install:$InstallPS2EXE
$availableParameters = @($ps2exe.Parameters.Keys)

$invokeArguments = @{
    InputFile  = $buildInput
    OutputFile = $resolvedOutput
}

Add-WmtPS2EXESwitch -Arguments $invokeArguments -AvailableParameters $availableParameters -Name "NoConsole"
Add-WmtPS2EXESwitch -Arguments $invokeArguments -AvailableParameters $availableParameters -Name "STA"
Add-WmtPS2EXESwitch -Arguments $invokeArguments -AvailableParameters $availableParameters -Name "RequireAdmin"
Add-WmtPS2EXESwitch -Arguments $invokeArguments -AvailableParameters $availableParameters -Name "DPIAware"
Add-WmtPS2EXESwitch -Arguments $invokeArguments -AvailableParameters $availableParameters -Name "LongPaths"

Add-WmtPS2EXEValue -Arguments $invokeArguments -AvailableParameters $availableParameters -Name "IconFile" -Value $resolvedIcon
Add-WmtPS2EXEValue -Arguments $invokeArguments -AvailableParameters $availableParameters -Name "Title" -Value "Windows Maintenance Tool"
Add-WmtPS2EXEValue -Arguments $invokeArguments -AvailableParameters $availableParameters -Name "Description" -Value "Windows Maintenance Tool GUI"
Add-WmtPS2EXEValue -Arguments $invokeArguments -AvailableParameters $availableParameters -Name "Product" -Value "Windows Maintenance Tool"
Add-WmtPS2EXEValue -Arguments $invokeArguments -AvailableParameters $availableParameters -Name "Company" -Value "Windows Maintenance Tool"
Add-WmtPS2EXEValue -Arguments $invokeArguments -AvailableParameters $availableParameters -Name "Copyright" -Value "MIT License"
Add-WmtPS2EXEValue -Arguments $invokeArguments -AvailableParameters $availableParameters -Name "Version" -Value $fileVersion

Write-Host "Building Windows Maintenance Tool v$appVersion..."
Write-Host "Source: $resolvedInput"
if ($buildInput -ne $resolvedInput) {
    Write-Host "Bundled modular source: $buildInput"
}
Write-Host "Icon:   $resolvedIcon"
Write-Host "Output: $resolvedOutput"
try {
    Invoke-PS2EXE @invokeArguments
}
finally {
    if ($buildInput -ne $resolvedInput -and (Test-Path -LiteralPath $buildInput)) {
        Remove-Item -LiteralPath $buildInput -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Leaf)) {
    throw "Build finished, but the EXE was not created: $resolvedOutput"
}

Write-Host "Built: $resolvedOutput"

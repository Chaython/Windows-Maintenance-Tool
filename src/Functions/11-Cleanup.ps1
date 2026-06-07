# Functional block generated from WMT-GUI.ps1.
# Dot-source this file; it intentionally shares WMT's script scope.

function ConvertTo-WmtRegistryProviderPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }

    return $Path -replace "^(?i)HKCU\\?", "Registry::HKEY_CURRENT_USER\" `
        -replace "^(?i)HKLM\\?", "Registry::HKEY_LOCAL_MACHINE\" `
        -replace "^(?i)HKCR\\?", "Registry::HKEY_CLASSES_ROOT\" `
        -replace "^(?i)HKU\\?", "Registry::HKEY_USERS\"
}

function Expand-EnvPath {
    param($Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    # Expand standard vars (%AppData%, etc)
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    # Handle common Winapp2 specific variables if needed (e.g. %ProgramFiles%)
    return $expanded
}

function Test-WmtCleanerMlOs {
    param($Node)

    if (-not $Node) { return $true }
    $os = ""
    try { $os = [string]$Node.os } catch {}
    if ([string]::IsNullOrWhiteSpace($os)) { return $true }
    return ($os -match "(?i)\bwindows\b")
}

function Get-WmtXmlInnerText {
    param($Node, [string]$Name)

    if (-not $Node) { return "" }
    $child = $Node.SelectSingleNode($Name)
    if (-not $child) { return "" }
    return ([string]$child.InnerText).Trim()
}

function Get-WmtCleanerMlEnvMap {
    $documents = [Environment]::GetFolderPath("MyDocuments")
    $music = [Environment]::GetFolderPath("MyMusic")
    $pictures = [Environment]::GetFolderPath("MyPictures")
    $videos = [Environment]::GetFolderPath("MyVideos")
    $programW6432 = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
    $commonProgramW6432 = if (${env:CommonProgramW6432}) { ${env:CommonProgramW6432} } else { ${env:CommonProgramFiles} }

    $map = @{
        "AppData"            = $env:APPDATA
        "LocalAppData"       = $env:LOCALAPPDATA
        "LocalAppDataLow"    = (Join-Path $env:USERPROFILE "AppData\LocalLow")
        "CommonAppData"      = $env:ProgramData
        "ProgramFiles"       = $env:ProgramFiles
        "ProgramW6432"       = $programW6432
        "ProgramFiles(x86)"  = ${env:ProgramFiles(x86)}
        "CommonProgramFiles" = ${env:CommonProgramFiles}
        "CommonProgramW6432" = $commonProgramW6432
        "UserProfile"        = $env:USERPROFILE
        "HOME"               = $env:USERPROFILE
        "Documents"          = $documents
        "Music"              = $music
        "Pictures"           = $pictures
        "Video"              = $videos
        "TEMP"               = $env:TEMP
        "TMP"                = $env:TEMP
        "WinDir"             = $env:WINDIR
        "SystemRoot"         = $env:SystemRoot
        "XDG_CACHE_HOME"     = (Join-Path $env:LOCALAPPDATA "cache")
        "XDG_CONFIG_HOME"    = $env:APPDATA
        "XDG_DATA_HOME"      = $env:LOCALAPPDATA
        "LOGNAME"            = $env:USERNAME
        "USERNAME"           = $env:USERNAME
        "cd"                 = (Get-Location).Path
    }

    return $map
}

function Expand-WmtCleanerMlPathVariants {
    param(
        [string]$Path,
        [hashtable]$Variables
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return @() }

    $paths = @([string]$Path)
    $multiMatches = [regex]::Matches($Path, '\$\$([A-Za-z0-9_\-]+)\$\$')
    foreach ($match in @($multiMatches)) {
        $name = $match.Groups[1].Value
        $token = '$$' + $name + '$$'
        $values = @()
        if ($Variables.ContainsKey($name)) { $values = @($Variables[$name]) }
        $values = @($values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($values.Count -eq 0) { return @() }

        $expanded = @()
        foreach ($pathCandidate in $paths) {
            foreach ($value in $values) {
                $expanded += $pathCandidate.Replace($token, [string]$value)
            }
        }
        $paths = $expanded
    }

    $envMap = Get-WmtCleanerMlEnvMap
    $final = New-Object System.Collections.Generic.List[string]
    foreach ($pathCandidate in $paths) {
        $p = [string]$pathCandidate
        if ($p.StartsWith("~/") -or $p.StartsWith("~\")) {
            $p = Join-Path $env:USERPROFILE $p.Substring(2)
        }
        elseif ($p -eq "~") {
            $p = $env:USERPROFILE
        }

        foreach ($key in $envMap.Keys) {
            $value = [string]$envMap[$key]
            if ([string]::IsNullOrWhiteSpace($value)) { continue }
            $escapedKey = [regex]::Escape([string]$key)
            $escapedValue = $value.Replace('$', '$$')
            $p = [regex]::Replace($p, '%' + $escapedKey + '%', $escapedValue, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $p = [regex]::Replace($p, '\$\{' + $escapedKey + '\}', $escapedValue, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $p = [regex]::Replace($p, '\$' + $escapedKey + '\$', $escapedValue, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $p = [regex]::Replace($p, '\$' + $escapedKey + '\b', $escapedValue, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }

        $p = [Environment]::ExpandEnvironmentVariables($p)
        $p = $p -replace '/', '\'
        if (-not [string]::IsNullOrWhiteSpace($p)) { [void]$final.Add($p) }
    }

    return @($final.ToArray() | Select-Object -Unique)
}

function Get-WmtCleanerMlRegistryValue {
    param(
        [string]$Path,
        [string]$Name
    )

    $registryPath = ConvertTo-WmtRegistryProviderPath -Path $Path
    if ([string]::IsNullOrWhiteSpace($registryPath) -or -not (Test-Path -LiteralPath $registryPath)) { return @() }
    if ([string]::IsNullOrWhiteSpace($Name)) { return @($registryPath) }

    try {
        $item = Get-ItemProperty -LiteralPath $registryPath -Name $Name -ErrorAction Stop
        $value = $item.$Name
        if ($null -eq $value) { return @() }
        return @($value)
    }
    catch {
        return @()
    }
}

function Get-WmtCleanerMlWildcardRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    $wildcardIndex = $Path.IndexOfAny([char[]]@('*', '?'))
    if ($wildcardIndex -lt 0) { return "" }

    $beforeWildcard = $Path.Substring(0, $wildcardIndex)
    $separatorIndex = $beforeWildcard.LastIndexOfAny([char[]]@('\', '/'))
    if ($separatorIndex -le 0) { return "" }

    return $beforeWildcard.Substring(0, $separatorIndex).TrimEnd('\', '/')
}

function Test-WmtCleanerMlGenericEvidenceRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }

    try { $normalized = [System.IO.Path]::GetFullPath($Path).TrimEnd('\') }
    catch { $normalized = $Path.TrimEnd('\') }

    $genericRoots = @(
        $env:SystemDrive,
        $env:USERPROFILE,
        $env:APPDATA,
        $env:LOCALAPPDATA,
        $env:ProgramData,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:TEMP,
        $env:WINDIR,
        $env:SystemRoot
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    foreach ($root in $genericRoots) {
        try { $rootPath = [System.IO.Path]::GetFullPath([string]$root).TrimEnd('\') }
        catch { $rootPath = ([string]$root).TrimEnd('\') }
        if ($normalized.Equals($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }

    return $false
}

function Test-WmtCleanerMlPathEvidence {
    param(
        [string]$Path,
        [string]$Search = "file"
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path) -replace '/', '\'
    if (-not (Test-WmtCleanerMlWindowsPath $expandedPath)) { return $false }

    try {
        if ($expandedPath -match '[\*\?]') {
            if (Test-Path -Path $expandedPath -ErrorAction SilentlyContinue) { return $true }
            $wildcardRoot = Get-WmtCleanerMlWildcardRoot -Path $expandedPath
            if (-not [string]::IsNullOrWhiteSpace($wildcardRoot) -and
                -not (Test-WmtCleanerMlGenericEvidenceRoot -Path $wildcardRoot) -and
                (Test-Path -LiteralPath $wildcardRoot -ErrorAction SilentlyContinue)) {
                return $true
            }
            return $false
        }

        if (Test-Path -LiteralPath $expandedPath -ErrorAction SilentlyContinue) { return $true }

        if ($Search -eq "file") {
            $parent = [System.IO.Path]::GetDirectoryName($expandedPath)
            if (-not [string]::IsNullOrWhiteSpace($parent) -and
                -not (Test-WmtCleanerMlGenericEvidenceRoot -Path $parent) -and
                (Test-Path -LiteralPath $parent -ErrorAction SilentlyContinue)) {
                return $true
            }
        }
    }
    catch {}

    return $false
}

function Test-WmtCleanerMlWindowsPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -match '^[\\/](bin|boot|dev|etc|home|lib|media|mnt|opt|proc|root|run|sbin|srv|sys|tmp|usr|var)([\\/]|$)') {
        return $false
    }
    return $true
}

function Get-WmtBleachBitCleanerXmlDirectories {
    $dataPath = Get-DataPath
    $dirs = [System.Collections.Generic.List[string]]::new()
    [void]$dirs.Add((Join-Path $dataPath "bleachbit_cleanerml\bleachbit-master\cleaners"))
    [void]$dirs.Add((Join-Path $dataPath "bleachbit-master\bleachbit-master\cleaners"))
    [void]$dirs.Add((Join-Path $dataPath "cleanerml-master\cleanerml-master\release"))
    [void]$dirs.Add((Join-Path $env:APPDATA "BleachBit\cleaners"))
    [void]$dirs.Add((Join-Path $env:ProgramFiles "BleachBit\share\cleaners"))

    if (${env:ProgramFiles(x86)}) {
        [void]$dirs.Add((Join-Path ${env:ProgramFiles(x86)} "BleachBit\share\cleaners"))
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $existing = [System.Collections.Generic.List[string]]::new()
    foreach ($dir in $dirs) {
        if ([string]::IsNullOrWhiteSpace($dir) -or -not [System.IO.Directory]::Exists($dir)) { continue }
        try { $key = [System.IO.DirectoryInfo]::new($dir).FullName } catch { $key = $dir }
        if ($seen.Add($key)) { [void]$existing.Add($dir) }
    }
    return $existing.ToArray()
}

function Get-WmtBleachBitCleanerXmlFiles {
    $dirs = @(Get-WmtBleachBitCleanerXmlDirectories)
    if ($dirs.Count -eq 0) { return @() }

    $filesByPath = [System.Collections.Generic.SortedDictionary[string, System.IO.FileInfo]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($dir in $dirs) {
        try {
            foreach ($path in [System.IO.Directory]::EnumerateFiles($dir, "*.xml", [System.IO.SearchOption]::TopDirectoryOnly)) {
                try {
                    $file = [System.IO.FileInfo]::new($path)
                    if (-not $filesByPath.ContainsKey($file.FullName)) { $filesByPath.Add($file.FullName, $file) }
                }
                catch {}
            }
        }
        catch {}
    }

    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $filesByPath.Values) { [void]$files.Add($file) }
    return $files.ToArray()
}

function Get-WmtCleanerMlSourceSignature {
    param($XmlFiles)

    $filesByPath = [System.Collections.Generic.SortedDictionary[string, System.IO.FileInfo]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($XmlFiles)) {
        if (-not $item) { continue }
        try {
            $file = if ($item -is [System.IO.FileInfo]) { $item } else { [System.IO.FileInfo]::new([string]$item) }
            if (-not $filesByPath.ContainsKey($file.FullName)) { $filesByPath.Add($file.FullName, $file) }
        }
        catch {}
    }

    $totalLength = [int64]0
    $latestWriteTicks = [int64]0
    $fileMeta = New-Object System.Collections.Generic.List[object]

    foreach ($file in $filesByPath.Values) {
        $length = [int64]$file.Length
        $writeTicks = [int64]$file.LastWriteTimeUtc.Ticks
        $totalLength += $length
        if ($writeTicks -gt $latestWriteTicks) { $latestWriteTicks = $writeTicks }

        [void]$fileMeta.Add([PSCustomObject]@{
                Path              = [string]$file.FullName
                Length            = $length
                LastWriteUtcTicks = $writeTicks
            })
    }

    return [PSCustomObject]@{
        FileCount           = [int]$filesByPath.Count
        TotalLength         = $totalLength
        LatestWriteUtcTicks = $latestWriteTicks
        Files               = @($fileMeta.ToArray())
    }
}

function Test-WmtCleanerMlCacheMetaMatch {
    param(
        $Meta,
        $SourceSignature,
        [int]$CacheVersion
    )

    if (-not $Meta -or -not $SourceSignature) { return $false }

    try {
        if ([int]$Meta.CacheVersion -ne $CacheVersion) { return $false }
        if ([int]$Meta.FileCount -ne [int]$SourceSignature.FileCount) { return $false }
        if ([int64]$Meta.TotalLength -ne [int64]$SourceSignature.TotalLength) { return $false }
        if ([int64]$Meta.LatestWriteUtcTicks -ne [int64]$SourceSignature.LatestWriteUtcTicks) { return $false }

        $metaFiles = @($Meta.Files)
        $sourceFiles = @($SourceSignature.Files)
        if ($metaFiles.Count -ne $sourceFiles.Count) { return $false }

        for ($i = 0; $i -lt $sourceFiles.Count; $i++) {
            if ([string]$metaFiles[$i].Path -ne [string]$sourceFiles[$i].Path) { return $false }
            if ([int64]$metaFiles[$i].Length -ne [int64]$sourceFiles[$i].Length) { return $false }
            if ([int64]$metaFiles[$i].LastWriteUtcTicks -ne [int64]$sourceFiles[$i].LastWriteUtcTicks) { return $false }
        }

        return $true
    }
    catch {
        return $false
    }
}

function Update-WmtBleachBitCleanerMlFiles {
    $dataPath = Get-DataPath
    $targetRoot = Join-Path $dataPath "bleachbit_cleanerml"
    $zipPath = Join-Path $targetRoot "bleachbit-master.zip"
    $extractRoot = Join-Path $targetRoot "bleachbit-master"

    try {
        [System.IO.Directory]::CreateDirectory($targetRoot) | Out-Null
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $url = "https://codeload.github.com/bleachbit/bleachbit/zip/refs/heads/master"
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($url, $zipPath)
        $wc.Dispose()

        if (Test-Path -LiteralPath $extractRoot) {
            Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        [System.IO.Directory]::CreateDirectory($extractRoot) | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractRoot)

        $nested = Get-ChildItem -LiteralPath $extractRoot -Directory -Filter "bleachbit-*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($nested -and (Test-Path -LiteralPath (Join-Path $nested.FullName "cleaners"))) {
            $finalRoot = Join-Path $targetRoot "bleachbit-master-normalized"
            if (Test-Path -LiteralPath $finalRoot) {
                Remove-Item -LiteralPath $finalRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
            Move-Item -LiteralPath $nested.FullName -Destination $finalRoot -Force
            Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
            Rename-Item -LiteralPath $finalRoot -NewName "bleachbit-master" -Force
        }
    }
    catch {
        Write-GuiLog "CleanerML download warning: $($_.Exception.Message)"
    }
}

function Get-WmtCleanerMlSection {
    param([string]$CleanerName)

    if ($CleanerName -match "(?i)\b(Chrome|Chromium|Edge|Firefox|Brave|Opera|Internet Explorer|SeaMonkey|Waterfox|LibreWolf|Vivaldi|Zen)\b") { return "Browsers / Internet" }
    if ($CleanerName -match "(?i)\b(Discord|Pidgin|Skype|Telegram|Signal|HexChat|Thunderbird|FileZilla)\b") { return "Internet & Chat" }
    if ($CleanerName -match "(?i)\b(Office|LibreOffice|Adobe|GIMP|Paint|Audacity|HandBrake|VLC|Java|Claude)\b") { return "Productivity" }
    if ($CleanerName -match "(?i)\b(Deep scan|System|Windows|Explorer|Thumbnails|Localizations)\b") { return "System" }
    if ($CleanerName -match "(?i)\b(Game|Steam|Minecraft|Roblox|Nexuiz|Warzone|Poker)\b") { return "Games" }
    return "Applications"
}

function ConvertFrom-WmtCleanerMlFile {
    param([string]$Path)

    try { [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop }
    catch { return @() }

    $cleaner = $xml.cleaner
    if (-not $cleaner -or -not (Test-WmtCleanerMlOs $cleaner)) { return @() }

    $cleanerId = if ($cleaner.id) { [string]$cleaner.id } else { [System.IO.Path]::GetFileNameWithoutExtension($Path) }
    $cleanerName = Get-WmtXmlInnerText -Node $cleaner -Name "label"
    if ([string]::IsNullOrWhiteSpace($cleanerName)) { $cleanerName = $cleanerId -replace '[_\-]+', ' ' }
    $cleanerDesc = Get-WmtXmlInnerText -Node $cleaner -Name "description"

    $envMapForVars = Get-WmtCleanerMlEnvMap
    $variables = @{}
    $variables["ProgramFiles"] = @($envMapForVars["ProgramFiles"], $envMapForVars["ProgramW6432"]) |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
    Select-Object -Unique
    $variables["CommonProgramFiles"] = @($envMapForVars["CommonProgramFiles"], $envMapForVars["CommonProgramW6432"]) |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
    Select-Object -Unique
    foreach ($var in @($cleaner.var)) {
        if (-not $var.name) { continue }
        $values = New-Object System.Collections.Generic.List[string]
        foreach ($valueNode in @($var.value)) {
            if (-not (Test-WmtCleanerMlOs $valueNode)) { continue }
            $searchType = if ($valueNode.search) { [string]$valueNode.search } else { "" }
            $expandedValues = @()

            if ($searchType -eq "winreg") {
                foreach ($registryValue in @(Get-WmtCleanerMlRegistryValue -Path ([string]$valueNode.path) -Name ([string]$valueNode.name))) {
                    $expandedValues += [string]$registryValue
                }
            }
            else {
                $expandedValues = @(Expand-WmtCleanerMlPathVariants -Path ([string]$valueNode.InnerText) -Variables $variables)
                if ($searchType -eq "glob") {
                    $globbedValues = New-Object System.Collections.Generic.List[string]
                    foreach ($expandedValue in $expandedValues) {
                        foreach ($match in @(Get-ChildItem -Path $expandedValue -Force -ErrorAction SilentlyContinue)) {
                            [void]$globbedValues.Add($match.FullName)
                        }
                    }
                    $expandedValues = @($globbedValues.ToArray())
                }
            }

            foreach ($expandedValue in $expandedValues) {
                if ((Test-WmtCleanerMlWindowsPath $expandedValue) -and (Test-WmtCleanerMlPathEvidence -Path $expandedValue -Search "file")) {
                    [void]$values.Add($expandedValue)
                }
            }
        }
        if ($values.Count -gt 0) { $variables[[string]$var.name] = @($values.ToArray() | Select-Object -Unique) }
    }

    $rules = New-Object System.Collections.Generic.List[object]
    foreach ($option in @($cleaner.option)) {
        if (-not (Test-WmtCleanerMlOs $option)) { continue }

        $optionId = if ($option.id) { [string]$option.id } else { "option" }
        $optionName = Get-WmtXmlInnerText -Node $option -Name "label"
        if ([string]::IsNullOrWhiteSpace($optionName)) { $optionName = $optionId -replace '[_\-]+', ' ' }
        $optionDesc = Get-WmtXmlInnerText -Node $option -Name "description"
        $optionWarning = Get-WmtXmlInnerText -Node $option -Name "warning"
        $paths = New-Object System.Collections.Generic.List[object]

        foreach ($action in @($option.action)) {
            if ([string]$action.command -ne "delete") { continue }
            if (-not (Test-WmtCleanerMlOs $action)) { continue }

            $search = if ($action.search) { [string]$action.search } else { "file" }
            if ($search -notin @("file", "glob", "walk.files", "walk.all", "walk.top", "deep")) { continue }

            $rawPath = if ($action.path) { [string]$action.path } elseif ($search -eq "deep") { "%UserProfile%" } else { "" }
            foreach ($expandedPath in (Expand-WmtCleanerMlPathVariants -Path $rawPath -Variables $variables)) {
                if (-not (Test-WmtCleanerMlWindowsPath $expandedPath)) { continue }
                [void]$paths.Add([PSCustomObject]@{
                        Path        = $expandedPath
                        Search      = $search
                        Regex       = if ($action.regex) { [string]$action.regex } else { "" }
                        WholeRegex  = if ($action.wholeregex) { [string]$action.wholeregex } else { "" }
                        NRegex      = if ($action.nregex) { [string]$action.nregex } else { "" }
                        NWholeRegex = if ($action.nwholeregex) { [string]$action.nwholeregex } else { "" }
                        Type        = if ($action.type) { [string]$action.type } elseif ($search -eq "file") { "f" } else { "" }
                    })
            }
        }

        $hasCleanerMlEvidence = $false
        foreach ($pathRule in @($paths.ToArray())) {
            if (Test-WmtCleanerMlPathEvidence -Path ([string]$pathRule.Path) -Search ([string]$pathRule.Search)) {
                $hasCleanerMlEvidence = $true
                break
            }
        }

        if ($paths.Count -gt 0 -and $hasCleanerMlEvidence) {
            $safeId = ("CleanerML_{0}_{1}" -f $cleanerId, $optionId) -replace '[^a-zA-Z0-9_]', ''
            [void]$rules.Add([PSCustomObject]@{
                    Name        = "$cleanerName - $optionName"
                    ID          = $safeId
                    Section     = Get-WmtCleanerMlSection -CleanerName $cleanerName
                    AppGroup    = $cleanerName
                    Paths       = @($paths.ToArray())
                    Desc        = (@($cleanerDesc, $optionDesc, $optionWarning) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join " "
                    IsInternal  = $false
                    IsCleanerML = $true
                    Source      = "CleanerML"
                })
        }
    }

    return $rules.ToArray()
}

function Get-BleachBitCleanerMlRules {
    param([switch]$Download)

    $dataPath = Get-DataPath
    $cachePath = Join-Path $dataPath "cleanerml_cache.json"
    $cacheMetaPath = Join-Path $dataPath "cleanerml_cache.meta.json"
    $cacheVersion = 2

    if ($Download) { Update-WmtBleachBitCleanerMlFiles }
    if (-not $script:CleanerMlRulesMemoryCache) { $script:CleanerMlRulesMemoryCache = @{} }

    $xmlFiles = @(Get-WmtBleachBitCleanerXmlFiles)
    $sourceSignature = Get-WmtCleanerMlSourceSignature -XmlFiles $xmlFiles
    $memoryKey = if ($sourceSignature.FileCount -gt 0) {
        "{0}|{1}|{2}|{3}" -f $cacheVersion, [int]$sourceSignature.FileCount, [int64]$sourceSignature.TotalLength, [int64]$sourceSignature.LatestWriteUtcTicks
    }
    elseif (Test-Path $cachePath) {
        $cacheInfo = Get-Item -LiteralPath $cachePath -ErrorAction SilentlyContinue
        if ($cacheInfo) { "cache-only|{0}|{1}" -f [int64]$cacheInfo.Length, $cacheInfo.LastWriteTimeUtc.Ticks } else { "" }
    }
    else { "" }

    if (-not $Download -and $memoryKey -and $script:CleanerMlRulesMemoryCache.ContainsKey($memoryKey)) {
        return $script:CleanerMlRulesMemoryCache[$memoryKey]
    }

    $forceRebuild = $false
    if (Test-Path $cachePath) {
        try {
            if ($sourceSignature.FileCount -gt 0) {
                $cacheInfo = Get-Item -LiteralPath $cachePath -ErrorAction Stop
                $meta = $null
                if (Test-Path $cacheMetaPath) {
                    $meta = Get-Content -LiteralPath $cacheMetaPath -Raw -ErrorAction Stop | ConvertFrom-Json
                }

                if ($meta) {
                    if (-not (Test-WmtCleanerMlCacheMetaMatch -Meta $meta -SourceSignature $sourceSignature -CacheVersion $cacheVersion)) {
                        $forceRebuild = $true
                    }
                }
                elseif ($sourceSignature.LatestWriteUtcTicks -gt $cacheInfo.LastWriteTimeUtc.Ticks) {
                    $forceRebuild = $true
                }
            }
            elseif (Test-Path $cacheMetaPath) {
                $meta = Get-Content -LiteralPath $cacheMetaPath -Raw -ErrorAction Stop | ConvertFrom-Json
                if ([int]$meta.CacheVersion -ne $cacheVersion) { $forceRebuild = $true }
            }
        }
        catch {
            $forceRebuild = ($sourceSignature.FileCount -gt 0)
        }
    }

    if (-not $forceRebuild -and (Test-Path $cachePath)) {
        try {
            $cachedRules = @(Get-Content -LiteralPath $cachePath -Raw -ErrorAction Stop | ConvertFrom-Json)
            if ($cachedRules.Count -gt 0) {
                if (($sourceSignature.FileCount -gt 0) -and -not (Test-Path $cacheMetaPath)) {
                    try {
                        [PSCustomObject]@{
                            CacheVersion        = $cacheVersion
                            FileCount           = [int]$sourceSignature.FileCount
                            TotalLength         = [int64]$sourceSignature.TotalLength
                            LatestWriteUtcTicks = [int64]$sourceSignature.LatestWriteUtcTicks
                            Files               = @($sourceSignature.Files)
                        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cacheMetaPath -Force
                    }
                    catch {}
                }
                if ($memoryKey) { $script:CleanerMlRulesMemoryCache[$memoryKey] = $cachedRules }
                return $cachedRules
            }
        }
        catch {}
    }

    if ($xmlFiles.Count -eq 0) { return @() }

    $allRules = New-Object System.Collections.Generic.List[object]
    foreach ($file in $xmlFiles) {
        foreach ($rule in @(ConvertFrom-WmtCleanerMlFile -Path $file.FullName)) {
            [void]$allRules.Add($rule)
        }
    }

    $final = @($allRules.ToArray() | Group-Object ID | ForEach-Object { $_.Group[0] } | Sort-Object Section, AppGroup, Name)

    try {
        $final | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $cachePath -Force
        [PSCustomObject]@{
            CacheVersion        = $cacheVersion
            FileCount           = [int]$sourceSignature.FileCount
            TotalLength         = [int64]$sourceSignature.TotalLength
            LatestWriteUtcTicks = [int64]$sourceSignature.LatestWriteUtcTicks
            Files               = @($sourceSignature.Files)
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cacheMetaPath -Force
        $memoryKey = "{0}|{1}|{2}|{3}" -f $cacheVersion, [int]$sourceSignature.FileCount, [int64]$sourceSignature.TotalLength, [int64]$sourceSignature.LatestWriteUtcTicks
    }
    catch {}

    if ($memoryKey) { $script:CleanerMlRulesMemoryCache[$memoryKey] = $final }
    return $final
}

function Get-Winapp2Rules {
    param([switch]$Download)

    $dataPath = Get-DataPath
    $iniPath = Join-Path $dataPath "winapp2.ini"
    $cachePath = Join-Path $dataPath "winapp2_cache.json" 
    $cacheMetaPath = Join-Path $dataPath "winapp2_cache.meta.json"
    $cacheVersion = 2
    if (-not $script:Winapp2RulesMemoryCache) { $script:Winapp2RulesMemoryCache = @{} }
    $iniInfoForCache = $null
    if (Test-Path $iniPath) {
        try { $iniInfoForCache = Get-Item -LiteralPath $iniPath -ErrorAction Stop } catch {}
    }
    $memoryKey = if ($iniInfoForCache) {
        "{0}|{1}|{2}" -f $cacheVersion, [int64]$iniInfoForCache.Length, $iniInfoForCache.LastWriteTimeUtc.Ticks
    }
    elseif (Test-Path $cachePath) {
        $cacheInfo = Get-Item -LiteralPath $cachePath -ErrorAction SilentlyContinue
        if ($cacheInfo) { "cache-only|{0}|{1}" -f [int64]$cacheInfo.Length, $cacheInfo.LastWriteTimeUtc.Ticks } else { "" }
    }
    else { "" }

    if (-not $Download -and $memoryKey -and $script:Winapp2RulesMemoryCache.ContainsKey($memoryKey)) {
        return $script:Winapp2RulesMemoryCache[$memoryKey]
    }

    # --- 1. SMART CACHE CHECK ---
    $forceRebuild = $false

    if (Test-Path $cachePath) {
        try {
            if (Test-Path $iniPath) {
                $iniInfo = Get-Item -LiteralPath $iniPath -ErrorAction Stop
                $cacheInfo = Get-Item -LiteralPath $cachePath -ErrorAction Stop
                $meta = $null
                if (Test-Path $cacheMetaPath) {
                    $meta = Get-Content -LiteralPath $cacheMetaPath -Raw -ErrorAction Stop | ConvertFrom-Json
                }

                if ($meta) {
                    if ([int]$meta.CacheVersion -ne $cacheVersion -or
                        [int64]$meta.IniLength -ne [int64]$iniInfo.Length -or
                        [datetime]$meta.IniLastWriteUtc -ne $iniInfo.LastWriteTimeUtc) {
                        $forceRebuild = $true
                    }
                }
                elseif ($iniInfo.LastWriteTimeUtc -gt $cacheInfo.LastWriteTimeUtc) {
                    $forceRebuild = $true
                }
            }
        }
        catch {
            if (-not (Test-Path $iniPath)) {
                $forceRebuild = $false
            }
            else {
                $forceRebuild = $true
            }
        }
    }

    # --- 2. DOWNLOAD ---
    if ($Download) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Add-Type -AssemblyName System.Net.Http
            $client = New-Object System.Net.Http.HttpClient
            $client.Timeout = [TimeSpan]::FromSeconds(15)
            
            $url = "https://cdn.jsdelivr.net/gh/MoscaDotTo/Winapp2@master/Winapp2.ini"
            $response = $client.GetAsync($url).Result
            if ($response.IsSuccessStatusCode) {
                $contentBytes = $response.Content.ReadAsByteArrayAsync().Result
                $iniContent = [System.Text.Encoding]::UTF8.GetString($contentBytes)
                [System.IO.File]::WriteAllText($iniPath, $iniContent)
                $forceRebuild = $true
            }
            $client.Dispose()
        }
        catch { Write-GuiLog "Download Warning: $($_.Exception.Message)" }
    }

    # --- 3. CACHE LOAD ---
    if (-not $forceRebuild -and (Test-Path $cachePath)) {
        try { 
            $cachedRules = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
            if ($cachedRules.Count -gt 5) {
                if ((Test-Path $iniPath) -and -not (Test-Path $cacheMetaPath)) {
                    try {
                        $iniInfo = Get-Item -LiteralPath $iniPath -ErrorAction Stop
                        [PSCustomObject]@{
                            CacheVersion    = $cacheVersion
                            IniLength       = [int64]$iniInfo.Length
                            IniLastWriteUtc = $iniInfo.LastWriteTimeUtc
                        } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $cacheMetaPath -Force
                    }
                    catch {}
                }
                if ($memoryKey) { $script:Winapp2RulesMemoryCache[$memoryKey] = $cachedRules }
                return $cachedRules
            }
        }
        catch {}
    }

    # --- 4. PARSE INI ---
    $iniContent = $null
    if (Test-Path $iniPath) { $iniContent = Get-Content $iniPath -Raw }
    if ([string]::IsNullOrWhiteSpace($iniContent)) { return @() }

    $rules = New-Object System.Collections.Generic.List[Object]
    
    $envVars = @{ 
        "%Documents%"         = [Environment]::GetFolderPath("MyDocuments")
        "%ProgramFiles%"      = $env:ProgramFiles
        "%ProgramFiles(x86)%" = ${env:ProgramFiles(x86)}
        "%SystemDrive%"       = $env:SystemDrive
        "%AppData%"           = $env:APPDATA
        "%LocalAppData%"      = $env:LOCALAPPDATA
        "%CommonAppData%"     = $env:ProgramData
        "%UserProfile%"       = $env:USERPROFILE
    }
    $dirCache = @{} 

    $lines = $iniContent -split "\r?\n"
    $currentApp = $null; $skipApp = $false; $hasDetect = $false

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line[0] -eq ';') { continue }

        if ($line[0] -eq '[') {
            if ($currentApp -and -not $skipApp) { $rules.Add([PSCustomObject]$currentApp) }
            $appName = $line.Trim(" []")
            $currentApp = [ordered]@{ 
                Name       = $appName
                ID         = "Winapp2_" + ($appName -replace '[^a-zA-Z0-9]', '')
                Section    = "Applications"
                AppGroup   = "General"
                Paths      = New-Object System.Collections.Generic.List[Object]
                Desc       = ""
                IsInternal = $false
            }
            $skipApp = $false; $hasDetect = $false
            continue
        }

        $eqIndex = $line.IndexOf('=')
        if ($eqIndex -le 0) { continue }
        if ($skipApp) { continue }

        $key = $line.Substring(0, $eqIndex).Trim()
        $val = $line.Substring($eqIndex + 1).Trim()

        if ($key -eq "Section") { $currentApp.Section = $val }
        elseif ($key.StartsWith("Detect")) {
            if (-not $hasDetect) { $hasDetect = $true; $skipApp = $true } 
            
            if ($val.IndexOf('%') -ge 0) { 
                foreach ($k in $envVars.Keys) { 
                    if ($val.Contains($k)) { $val = $val.Replace($k, $envVars[$k]) } 
                } 
            }

            # Registry Detection
            if ($val -match "^HK") {
                $regPath = $val -replace "^(?i)HKCU", "Registry::HKEY_CURRENT_USER" `
                    -replace "^(?i)HKLM", "Registry::HKEY_LOCAL_MACHINE" `
                    -replace "^(?i)HKCR", "Registry::HKEY_CLASSES_ROOT" `
                    -replace "^(?i)HKU", "Registry::HKEY_USERS"
                if (Test-Path $regPath) { $skipApp = $false }
            } 
            # File Detection
            else {
                try {
                    $parent = [System.IO.Path]::GetDirectoryName($val)
                    if (-not [string]::IsNullOrWhiteSpace($parent)) {
                        if (-not $dirCache.ContainsKey($parent)) { $dirCache[$parent] = (Test-Path $parent) }
                        if ($dirCache[$parent]) { 
                            if (Test-Path $val) { $skipApp = $false } 
                        }
                    }
                }
                catch { 
                    if (Test-Path $val) { $skipApp = $false } 
                }
            }
        }
        elseif ($key.StartsWith("FileKey")) {
            $parts = $val -split "\|"
            if ($parts.Count -ge 2) {
                $rawPath = $parts[0]
                if ($rawPath.IndexOf('%') -ge 0) { foreach ($k in $envVars.Keys) { if ($rawPath.Contains($k)) { $rawPath = $rawPath.Replace($k, $envVars[$k]) } } }
                $rawPath = [Environment]::ExpandEnvironmentVariables($rawPath)
                if (-not $skipApp) { $currentApp.Paths.Add(@{ Path = $rawPath; Pattern = $parts[1]; Options = if ($parts.Count -gt 2) { $parts[2] } else { "" } }) }
            }
        }
        elseif ($key -eq "Description") { $currentApp.Desc = $val }
    }
    if ($currentApp -and -not $skipApp) { $rules.Add([PSCustomObject]$currentApp) }

    # --- 5. CATEGORIZATION ---
    $finalList = $rules | Where-Object { $_.Paths.Count -gt 0 }
    
    foreach ($app in $finalList) {
        $name = $app.Name

        # 1. BROWSERS
        if ($name -match "^Google Chrome") { $app.AppGroup = "Google Chrome"; $app.Section = "Browsers / Internet"; $app.Name = $name -replace "Google Chrome\s*", "" }
        elseif ($name -match "^Microsoft Edge") { $app.AppGroup = "Microsoft Edge"; $app.Section = "Browsers / Internet"; $app.Name = $name -replace "Microsoft Edge\s*", "" }
        elseif ($name -match "^Mozilla Firefox") { $app.AppGroup = "Mozilla Firefox"; $app.Section = "Browsers / Internet"; $app.Name = $name -replace "Mozilla Firefox\s*", "" }
        elseif ($name -match "^Opera") { $app.AppGroup = "Opera"; $app.Section = "Browsers / Internet" }
        elseif ($name -match "^Brave") { $app.AppGroup = "Brave"; $app.Section = "Browsers / Internet" }

        # 2. SPECIFIC PRODUCTIVITY
        elseif ($name -match "PowerToys") { 
            $app.Section = "Productivity"
            $app.AppGroup = "Microsoft PowerToys"
            $app.Name = $name -replace "^Microsoft\s*PowerToys\s*", "" 
        }
        elseif ($name -match "^Microsoft\sOffice|^Office\s") { $app.Section = "Productivity"; $app.AppGroup = "Microsoft Office" }
        elseif ($name -match "^Adobe\s") { $app.Section = "Productivity"; $app.AppGroup = "Adobe"; $app.Name = $name -replace "^Adobe\s+", "" }
        
        # 3. GAMES (New Category)
        elseif ($name -match "(?i)\b(Steam|Epic Games|Origin|Uplay|Ubisoft Connect|Battle.net|GOG Galaxy)\b") {
            $app.Section = "Games"
            $app.AppGroup = $name -split " " | Select-Object -First 1
        }

        # 4. CHAT APPS
        elseif ($name -match "(?i)\b(Discord|Spotify|Skype|TeamViewer|Zoom|Slack|Telegram|WhatsApp)\b") { 
            $app.Section = "Internet & Chat"
            $app.AppGroup = $name -split " " | Select-Object -First 1 
        }

        # 5. SYSTEM CATCH-ALL
        elseif ($name -match "^Windows\s" -or $name -eq "Windows" -or $name -match "Defender|Explorer|Store|Management Console") {
            $app.Section = "System"
            $app.AppGroup = "Windows"
            $app.Name = $name -replace "^Windows\s+", "" 
        }
    }

    try {
        $finalList | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cachePath -Force
        if (Test-Path $iniPath) {
            $iniInfo = Get-Item -LiteralPath $iniPath -ErrorAction Stop
            [PSCustomObject]@{
                CacheVersion    = $cacheVersion
                IniLength       = [int64]$iniInfo.Length
                IniLastWriteUtc = $iniInfo.LastWriteTimeUtc
            } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $cacheMetaPath -Force
            $memoryKey = "{0}|{1}|{2}" -f $cacheVersion, [int64]$iniInfo.Length, $iniInfo.LastWriteTimeUtc.Ticks
        }
    }
    catch {}

    if ($memoryKey) { $script:Winapp2RulesMemoryCache[$memoryKey] = $finalList }
    
    return $finalList
}

function Show-AdvancedCleanupSelection {
    Show-WmtAdvancedCleanupSelectionWpf
}

function Show-WmtAdvancedCleanupSelectionWpf {
    $currentSettings = Get-WmtSettings
    $savedStates = $currentSettings.TempCleanup
    $isWinapp2Enabled = [bool]$currentSettings.LoadWinapp2
    $isCleanerMlEnabled = [bool]$currentSettings.LoadCleanerML

    [xml]$cleanupSelectionXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Advanced Cleanup Selection" Width="720" Height="820" MinWidth="620" MinHeight="540"
        WindowStartupLocation="CenterOwner" Background="{DynamicResource BgDark}" Foreground="{DynamicResource TextPrimary}"
        FontFamily="Segoe UI Variable Display, Segoe UI, Arial" FontSize="13">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="{DynamicResource BgPanel}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="0,0,0,1" Padding="16,12">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="260"/>
                </Grid.ColumnDefinitions>
                <StackPanel>
                    <CheckBox Name="chkToggleWinapp2" Content="Winapp2.ini rules" FontWeight="SemiBold" Margin="0,0,0,8"/>
                    <CheckBox Name="chkToggleCleanerML" Content="BleachBit CleanerML" FontWeight="SemiBold"/>
                </StackPanel>
                <TextBlock Name="lblStatus" Grid.Column="1" Margin="18,0" VerticalAlignment="Center" Foreground="{DynamicResource Warning}"/>
                <StackPanel Grid.Column="2">
                    <TextBlock Text="Search" Foreground="{DynamicResource TextSecondary}" Margin="0,0,0,4"/>
                    <TextBox Name="txtSearch" Height="34" VerticalContentAlignment="Center"/>
                </StackPanel>
            </Grid>
        </Border>

        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="16,12">
            <StackPanel Name="pnlRules"/>
        </ScrollViewer>

        <Border Grid.Row="2" Background="{DynamicResource BgPanel}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="0,1,0,0" Padding="16,12">
            <Grid>
                <Button Name="btnEventLogs" Content="Clear Event Logs" Width="132" HorizontalAlignment="Left" Background="{DynamicResource Warning}" Foreground="{DynamicResource WarningText}"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                    <Button Name="btnCancel" Content="Cancel" Width="94" IsCancel="True" Margin="0,0,8,0"/>
                    <Button Name="btnAnalyze" Content="Analyze" Width="104" Background="{DynamicResource Accent}" Foreground="{DynamicResource AccentText}" Margin="0,0,8,0"/>
                    <Button Name="btnClean" Content="Clean Selected" Width="128" Background="{DynamicResource Success}" Foreground="{DynamicResource SuccessText}" IsDefault="True"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

    try {
        $dialog = New-WmtWindowFromFullXaml -Xaml $cleanupSelectionXaml
        $workArea = [System.Windows.SystemParameters]::WorkArea
        $dialog.Width = [Math]::Min(720, [Math]::Max(620, $workArea.Width - 80))
        $dialog.Height = [Math]::Min(820, [Math]::Max(540, $workArea.Height - 80))
    }
    catch {
        Write-GuiLog "Failed to open WPF cleanup selection: $($_.Exception.Message)"
        return $null
    }

    $chkToggleWinapp2 = $dialog.FindName("chkToggleWinapp2")
    $chkToggleCleanerML = $dialog.FindName("chkToggleCleanerML")
    $txtSearch = $dialog.FindName("txtSearch")
    $lblStatus = $dialog.FindName("lblStatus")
    $pnlRules = $dialog.FindName("pnlRules")
    $btnClean = $dialog.FindName("btnClean")
    $btnAnalyze = $dialog.FindName("btnAnalyze")
    $btnCancel = $dialog.FindName("btnCancel")
    $btnEventLogs = $dialog.FindName("btnEventLogs")

    $chkToggleWinapp2.IsChecked = $isWinapp2Enabled
    $chkToggleCleanerML.IsChecked = $isCleanerMlEnabled

    $internalRules = @(
        [PSCustomObject]@{ Section = "System"; AppGroup = "Windows"; Name = "Temporary Files"; Key = "TempFiles"; Desc = "User and System Temp"; IsInternal = $true }
        [PSCustomObject]@{ Section = "System"; AppGroup = "Windows"; Name = "Recycle Bin"; Key = "RecycleBin"; Desc = "Empties Recycle Bin"; IsInternal = $true }
        [PSCustomObject]@{ Section = "System"; AppGroup = "Windows"; Name = "Error Logs (WER)"; Key = "WER"; Desc = "Crash dumps"; IsInternal = $true }
        [PSCustomObject]@{ Section = "System"; AppGroup = "Windows"; Name = "DNS Cache"; Key = "DNS"; Desc = "Network cache"; IsInternal = $true }
        [PSCustomObject]@{ Section = "System"; AppGroup = "Explorer"; Name = "Thumbnail / Thumbs Cache"; Key = "Thumbnails"; Desc = "Explorer thumbcache_*.db thumbnail cache"; IsInternal = $true }
        [PSCustomObject]@{ Section = "System"; AppGroup = "Explorer"; Name = "Deep Scan: Thumbs.db"; Key = "ThumbsDb"; Desc = "Finds scattered Thumbs.db files under your user profile. Can be slow."; IsInternal = $true; DefaultChecked = $false }
        [PSCustomObject]@{ Section = "System"; AppGroup = "Explorer"; Name = "Recent Items"; Key = "Recent"; Desc = "Recent files list"; IsInternal = $true }
        [PSCustomObject]@{ Section = "System"; AppGroup = "Explorer"; Name = "Run History"; Key = "RunMRU"; Desc = "Run dialog history"; IsInternal = $true }
        [PSCustomObject]@{ Section = "Browsers / Internet"; AppGroup = "Google Chrome"; Name = "Cache (Internal)"; Key = "Chrome"; Desc = "Standard Cache"; IsInternal = $true }
        [PSCustomObject]@{ Section = "Browsers / Internet"; AppGroup = "Microsoft Edge"; Name = "Cache (Internal)"; Key = "Edge"; Desc = "Standard Cache"; IsInternal = $true }
        [PSCustomObject]@{ Section = "Browsers / Internet"; AppGroup = "Mozilla Firefox"; Name = "Cache (Internal)"; Key = "Firefox"; Desc = "Standard Cache"; IsInternal = $true }
        [PSCustomObject]@{ Section = "Browsers / Internet"; AppGroup = "Brave"; Name = "Cache (Internal)"; Key = "Brave"; Desc = "Standard Cache"; IsInternal = $true }
        [PSCustomObject]@{ Section = "Browsers / Internet"; AppGroup = "Opera"; Name = "Cache (Internal)"; Key = "Opera"; Desc = "Standard Cache"; IsInternal = $true }
    )

    $cleanupCheckboxes = [ordered]@{}
    $checkboxSearchText = @{}
    $sectionEntries = [System.Collections.Generic.List[object]]::new()

    $sectionOrder = @{
        "System"              = 0
        "Browsers / Internet" = 1
        "Productivity"        = 2
        "Internet & Chat"     = 3
        "Games"               = 4
        "Applications"        = 5
    }

    $preferredGroupOrder = @{
        "System|Windows"                      = 0
        "System|Explorer"                     = 1
        "System|Windows Update"               = 2
        "System|Windows Logs"                 = 3
        "Browsers / Internet|Google Chrome"   = 0
        "Browsers / Internet|Microsoft Edge"  = 1
        "Browsers / Internet|Mozilla Firefox" = 2
        "Browsers / Internet|Brave"           = 3
        "Browsers / Internet|Opera"           = 4
        "Productivity|Microsoft Office"       = 0
        "Productivity|Microsoft Outlook"      = 1
        "Productivity|Microsoft PowerToys"    = 2
        "Productivity|Adobe"                  = 3
        "Internet & Chat|Discord"             = 0
        "Internet & Chat|Spotify"             = 1
        "Games|Steam"                         = 0
        "Games|Epic Games"                    = 1
        "Games|Xbox"                          = 2
    }

    $normalizeCleanerName = {
        param($Text)
        $name = ([string]$Text).Trim().Trim(" *")
        $name = $name -replace "\s+", " "
        if ($name -eq ".Thumbnails") { return "Thumbnail / Thumbs Cache" }
        return $name
    }.GetNewClosure()

    $getCleanerDisplayGroup = {
        param($item)
        $rawGroup = ([string]$item.AppGroup).Trim()
        $name = & $normalizeCleanerName $item.Name
        if ([bool]$item.IsInternal) {
            if (-not [string]::IsNullOrWhiteSpace($rawGroup)) { return $rawGroup }
            return "Windows"
        }
        switch -Regex ($name) {
            "^(Google Chrome|Chrome)\b" { return "Google Chrome" }
            "^(Microsoft Edge|Edge)\b" { return "Microsoft Edge" }
            "^(Mozilla Firefox|Firefox)\b" { return "Mozilla Firefox" }
            "^Brave\b" { return "Brave" }
            "^Opera\b" { return "Opera" }
            "^SeaMonkey\b" { return "SeaMonkey" }
            "^Microsoft\s+Office\b|^Office\b" { return "Microsoft Office" }
            "^Microsoft\s+Outlook\b|^Outlook\b" { return "Microsoft Outlook" }
            "^Microsoft\s+PowerToys\b|^PowerToys\b" { return "Microsoft PowerToys" }
            "^Adobe\b|Flash Player" { return "Adobe" }
            "^Steam\b" { return "Steam" }
            "^Epic Games\b|^Epic\b|Fortnite" { return "Epic Games" }
            "^Xbox\b|Minecraft|Roblox" { return "Xbox" }
            "^Discord\b" { return "Discord" }
            "^Spotify\b" { return "Spotify" }
            "^NVIDIA\b" { return "NVIDIA" }
            "^AMD\b" { return "AMD" }
            "^Windows Update\b" { return "Windows Update" }
            "^Windows Logs\b|Event Logs|Event Viewer|Error Reporting" { return "Windows Logs" }
            "^Windows\b|^Microsoft Store\b|^Microsoft\s+Windows\b" { return "Windows" }
        }
        if (-not [string]::IsNullOrWhiteSpace($rawGroup) -and $rawGroup -ne "General") {
            if ($rawGroup -eq "Epic") { return "Epic Games" }
            return $rawGroup
        }
        return "Other Apps"
    }.GetNewClosure()

    $getCleanerDisplayName = {
        param($item)
        $itemKey = if ($item.Key) { [string]$item.Key } else { [string]$item.ID }
        if ($itemKey -eq "Thumbnails") { return "Thumbnail / Thumbs Cache" }
        $name = & $normalizeCleanerName $item.Name
        if (-not [bool]$item.IsInternal) {
            $displayGroup = & $getCleanerDisplayGroup $item
            if (-not [string]::IsNullOrWhiteSpace($displayGroup) -and $displayGroup -ne "Other Apps") {
                $name = ($name -replace ("^" + [regex]::Escape($displayGroup) + "\s*[-:]?\s*"), "").Trim()
            }
        }
        if ([string]::IsNullOrWhiteSpace($name)) { return "General Cleanup" }
        return $name
    }.GetNewClosure()

    $getCleanerDisplaySection = {
        param($item)
        $rawSection = ([string]$item.Section).Trim()
        $name = & $normalizeCleanerName $item.Name
        $group = & $getCleanerDisplayGroup $item
        if ([bool]$item.IsInternal) {
            if (-not [string]::IsNullOrWhiteSpace($rawSection)) { return $rawSection }
            return "System"
        }
        if ($group -in @("Google Chrome", "Microsoft Edge", "Mozilla Firefox", "Brave", "Opera", "SeaMonkey")) { return "Browsers / Internet" }
        if ($group -in @("Discord", "Spotify")) { return "Internet & Chat" }
        if ($group -in @("Steam", "Epic Games", "Xbox") -or $rawSection -eq "Games") { return "Games" }
        if ($group -in @("Microsoft Office", "Microsoft Outlook", "Microsoft PowerToys", "Adobe")) { return "Productivity" }
        if ($rawSection -in @("System", "Browsers / Internet", "Productivity", "Internet & Chat", "Games", "Applications")) { return $rawSection }
        if ($name -match "(?i)\b(Outlook|Office|PowerToys|Adobe)\b") { return "Productivity" }
        if ($name -match "(?i)\b(Chrome|Edge|Firefox|Brave|Opera|SeaMonkey|Browser)\b") { return "Browsers / Internet" }
        if ($name -match "(?i)\b(Discord|Spotify|Slack|Telegram|WhatsApp|Signal|Zoom)\b") { return "Internet & Chat" }
        if ($name -match "(?i)\b(Steam|Epic Games|Fortnite|Xbox|Minecraft|Roblox)\b") { return "Games" }
        return "Applications"
    }.GetNewClosure()

    $getCleanerSectionOrder = {
        param($section)
        $sectionName = [string]$section
        if ($sectionOrder.ContainsKey($sectionName)) { return [int]$sectionOrder[$sectionName] }
        return 99
    }.GetNewClosure()

    $getCleanerGroupOrder = {
        param($item)
        $section = & $getCleanerDisplaySection $item
        $group = & $getCleanerDisplayGroup $item
        $key = "$section|$group"
        if ($preferredGroupOrder.ContainsKey($key)) { return [int]$preferredGroupOrder[$key] }
        return 50
    }.GetNewClosure()

    $setVisibility = {
        param($Element, [bool]$Visible)
        if ($Element) {
            $Element.Visibility = if ($Visible) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        }
    }.GetNewClosure()

    $applyCleanerSearch = {
        $q = ([string]$txtSearch.Text).ToLowerInvariant()
        foreach ($entry in @($sectionEntries.ToArray())) {
            $hasVisibleChildren = $false
            $currentGroupHeader = $null
            $currentGroupHasVisibleChildren = $false

            foreach ($child in @($entry.Flow.Children)) {
                if ([string]$child.Tag -eq "GROUPHEADER") {
                    if ($currentGroupHeader) {
                        & $setVisibility $currentGroupHeader ($q.Length -eq 0 -or $currentGroupHasVisibleChildren)
                    }
                    $currentGroupHeader = $child
                    $currentGroupHasVisibleChildren = $false
                    & $setVisibility $child ($q.Length -eq 0)
                    continue
                }

                if ($child -is [System.Windows.Controls.CheckBox]) {
                    $searchKey = [string]$child.Uid
                    $match = ($q.Length -eq 0 -or ($checkboxSearchText.ContainsKey($searchKey) -and $checkboxSearchText[$searchKey].Contains($q)))
                    & $setVisibility $child $match
                    if ($match) {
                        $hasVisibleChildren = $true
                        $currentGroupHasVisibleChildren = $true
                    }
                }
            }

            if ($currentGroupHeader) {
                & $setVisibility $currentGroupHeader ($q.Length -eq 0 -or $currentGroupHasVisibleChildren)
            }
            & $setVisibility $entry.Header $hasVisibleChildren
            & $setVisibility $entry.Flow $hasVisibleChildren
        }
    }.GetNewClosure()

    $RenderAllRules = {
        param($allRules)

        $prevStates = @{}
        foreach ($k in $cleanupCheckboxes.Keys) {
            $prevStates[$k] = [bool]$cleanupCheckboxes[$k].IsChecked
        }

        $pnlRules.Children.Clear()
        $cleanupCheckboxes.Clear()
        $checkboxSearchText.Clear()
        $sectionEntries.Clear()

        $grouped = $allRules |
        Group-Object -Property { & $getCleanerDisplaySection $_ } |
        Sort-Object @{ Expression = { & $getCleanerSectionOrder $_.Name } }, Name

        foreach ($group in $grouped) {
            $sec = $group.Name

            $header = [System.Windows.Controls.Border]::new()
            $header.Background = New-WmtBrush "BgPanel"
            $header.BorderBrush = New-WmtBrush "BorderBrush"
            $header.BorderThickness = "1"
            $header.CornerRadius = "4"
            $header.Padding = "10,7"
            $header.Margin = "0,10,0,6"

            $secChk = [System.Windows.Controls.CheckBox]::new()
            $secChk.Content = $sec
            $secChk.FontSize = 15
            $secChk.FontWeight = [System.Windows.FontWeights]::SemiBold
            Set-WmtThemedBrush -Object $secChk -Property ([System.Windows.Controls.CheckBox]::ForegroundProperty) -ColorOrKey "Accent"
            $header.Child = $secChk

            $flow = [System.Windows.Controls.StackPanel]::new()
            $flow.Margin = "16,0,0,4"

            $secItems = $group.Group | Sort-Object `
            @{ Expression = { & $getCleanerGroupOrder $_ } }, `
            @{ Expression = { & $getCleanerDisplayGroup $_ } }, `
            @{ Expression = { if ([bool]$_.IsInternal) { 0 } else { 1 } } }, `
            @{ Expression = { & $getCleanerDisplayName $_ } }

            $childChecks = [System.Collections.Generic.List[object]]::new()
            $currentGroup = $null
            $isSecChecked = $true

            foreach ($item in $secItems) {
                $displayGroup = & $getCleanerDisplayGroup $item
                if ($displayGroup -ne $currentGroup) {
                    $currentGroup = $displayGroup
                    $grpLbl = [System.Windows.Controls.TextBlock]::new()
                    $grpLbl.Text = $currentGroup
                    $grpLbl.Tag = "GROUPHEADER"
                    $grpLbl.Margin = "0,10,0,4"
                    $grpLbl.FontWeight = [System.Windows.FontWeights]::SemiBold
                    Set-WmtThemedBrush -Object $grpLbl -Property ([System.Windows.Controls.TextBlock]::ForegroundProperty) -ColorOrKey "TextSecondary"
                    [void]$flow.Children.Add($grpLbl)
                }

                $itemKey = if ($item.Key) { [string]$item.Key } else { [string]$item.ID }
                $displayName = & $getCleanerDisplayName $item

                $chk = [System.Windows.Controls.CheckBox]::new()
                $chk.Margin = "10,0,0,5"
                $chk.Uid = $itemKey
                $chk.Tag = if ($item.IsInternal) { $itemKey } else { $item }

                if ($item.IsInternal) {
                    $chk.Content = $displayName
                    Set-WmtThemedBrush -Object $chk -Property ([System.Windows.Controls.CheckBox]::ForegroundProperty) -ColorOrKey "TextPrimary"
                }
                elseif ($item.IsCleanerML) {
                    $chk.Content = "$displayName (CleanerML)"
                    Set-WmtThemedBrush -Object $chk -Property ([System.Windows.Controls.CheckBox]::ForegroundProperty) -ColorOrKey "Accent"
                }
                else {
                    $chk.Content = "$displayName (winapp2.ini)"
                    Set-WmtThemedBrush -Object $chk -Property ([System.Windows.Controls.CheckBox]::ForegroundProperty) -ColorOrKey "Accent"
                }

                $searchParts = [System.Collections.Generic.List[string]]::new()
                foreach ($part in @($chk.Content, $displayName, $displayGroup, $itemKey, $item.Name, $item.Desc, $item.AppGroup, $item.Section)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$part)) { $searchParts.Add([string]$part) }
                }
                if ($itemKey -eq "Thumbnails") {
                    $searchParts.AddRange([string[]]@("thumbs", "thumbcache", "thumbcache_*.db", "thumbs.db"))
                }
                elseif ($itemKey -eq "ThumbsDb") {
                    $searchParts.AddRange([string[]]@("thumbs", "thumbnail", "thumbs.db", "deep scan"))
                }
                elseif (-not $item.IsInternal -and $item.Paths) {
                    foreach ($pathRule in $item.Paths) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$pathRule.Path)) { $searchParts.Add([string]$pathRule.Path) }
                        if (-not [string]::IsNullOrWhiteSpace([string]$pathRule.Pattern)) { $searchParts.Add([string]$pathRule.Pattern) }
                    }
                }
                $checkboxSearchText[$itemKey] = ($searchParts -join " ").ToLowerInvariant()

                if ($prevStates.ContainsKey($itemKey)) {
                    $chk.IsChecked = [bool]$prevStates[$itemKey]
                }
                elseif ($savedStates.ContainsKey($itemKey)) {
                    $chk.IsChecked = [bool]$savedStates[$itemKey]
                }
                elseif ($item.PSObject.Properties["DefaultChecked"]) {
                    $chk.IsChecked = [bool]$item.DefaultChecked
                }
                else {
                    $chk.IsChecked = ([bool]$item.IsInternal)
                }

                if (-not [bool]$chk.IsChecked) { $isSecChecked = $false }
                if ($item.Desc) { $chk.ToolTip = [string]$item.Desc }

                [void]$flow.Children.Add($chk)
                $cleanupCheckboxes[$itemKey] = $chk
                [void]$childChecks.Add($chk)
            }

            $secChk.IsChecked = $isSecChecked
            $secChk.Add_Checked({
                    param($s, $e)
                    $filterActive = -not [string]::IsNullOrWhiteSpace($txtSearch.Text)
                    foreach ($c in $childChecks) {
                        if (-not $filterActive -or $c.Visibility -eq [System.Windows.Visibility]::Visible) { $c.IsChecked = $true }
                    }
                }.GetNewClosure())
            $secChk.Add_Unchecked({
                    param($s, $e)
                    $filterActive = -not [string]::IsNullOrWhiteSpace($txtSearch.Text)
                    foreach ($c in $childChecks) {
                        if (-not $filterActive -or $c.Visibility -eq [System.Windows.Visibility]::Visible) { $c.IsChecked = $false }
                    }
                }.GetNewClosure())

            [void]$pnlRules.Children.Add($header)
            [void]$pnlRules.Children.Add($flow)
            [void]$sectionEntries.Add([PSCustomObject]@{ Header = $header; Flow = $flow; HeaderCheck = $secChk; Children = $childChecks })
        }

        & $applyCleanerSearch
    }.GetNewClosure()

    $externalRuleState = @{
        Winapp2   = @()
        CleanerML = @()
    }

    $renderCurrentCleanerRules = {
        $combined = @($internalRules)
        if ($externalRuleState.Winapp2) { $combined += @($externalRuleState.Winapp2) }
        if ($externalRuleState.CleanerML) { $combined += @($externalRuleState.CleanerML) }
        & $RenderAllRules -allRules $combined
    }.GetNewClosure()

    & $renderCurrentCleanerRules

    $loadExternalCleanerRules = {
        param(
            [switch]$ForceWinapp2Download,
            [switch]$ForceCleanerMlDownload
        )

        $lblStatus.Text = "Loading cleaner rules..."
        $dialog.Cursor = [System.Windows.Input.Cursors]::Wait
        Invoke-WmtDispatcherPump -Dispatcher $dialog.Dispatcher

        try {
            if ([bool]$chkToggleWinapp2.IsChecked) {
                $lblStatus.Text = "Loading Winapp2 rules..."
                Invoke-WmtDispatcherPump -Dispatcher $dialog.Dispatcher
                $iniPath = Join-Path (Get-DataPath) "winapp2.ini"
                $cachePath = Join-Path (Get-DataPath) "winapp2_cache.json"
                $shouldDownload = $ForceWinapp2Download -or ((-not (Test-Path $iniPath)) -and (-not (Test-Path $cachePath)))
                $externalRuleState.Winapp2 = @(Get-Winapp2Rules -Download:$shouldDownload)
            }
            else {
                $externalRuleState.Winapp2 = @()
            }

            if ([bool]$chkToggleCleanerML.IsChecked) {
                $lblStatus.Text = "Loading BleachBit CleanerML..."
                Invoke-WmtDispatcherPump -Dispatcher $dialog.Dispatcher
                $hasLocalCleanerMl = ((Get-WmtBleachBitCleanerXmlDirectories).Count -gt 0)
                $cachePath = Join-Path (Get-DataPath) "cleanerml_cache.json"
                $shouldDownloadCleanerMl = $ForceCleanerMlDownload -or ((-not $hasLocalCleanerMl) -and (-not (Test-Path $cachePath)))
                $externalRuleState.CleanerML = @(Get-BleachBitCleanerMlRules -Download:$shouldDownloadCleanerMl)
            }
            else {
                $externalRuleState.CleanerML = @()
            }

            & $renderCurrentCleanerRules
        }
        catch {
            Write-GuiLog "Cleaner rules warning: $($_.Exception.Message)"
            & $renderCurrentCleanerRules
        }
        finally {
            $dialog.Cursor = [System.Windows.Input.Cursors]::Arrow
            $lblStatus.Text = ""
        }
    }.GetNewClosure()

    $communityLoadState = @{ Started = $false }
    $loadCommunityRulesIfEnabled = {
        if ($communityLoadState.Started -or (-not [bool]$chkToggleWinapp2.IsChecked -and -not [bool]$chkToggleCleanerML.IsChecked)) { return }
        $communityLoadState.Started = $true
        & $loadExternalCleanerRules
    }.GetNewClosure()

    $dialog.Add_ContentRendered({ & $loadCommunityRulesIfEnabled }.GetNewClosure())
    $dialog.Add_Activated({ & $loadCommunityRulesIfEnabled }.GetNewClosure())

    $chkToggleWinapp2.Add_Click({
            $currentSettings.LoadWinapp2 = [bool]$chkToggleWinapp2.IsChecked
            Save-WmtSettings -Settings $currentSettings

            $iniPath = Join-Path (Get-DataPath) "winapp2.ini"
            $forceDownload = [bool]$chkToggleWinapp2.IsChecked -and (-not (Test-Path $iniPath))
            & $loadExternalCleanerRules -ForceWinapp2Download:$forceDownload
        }.GetNewClosure())

    $chkToggleCleanerML.Add_Click({
            $currentSettings.LoadCleanerML = [bool]$chkToggleCleanerML.IsChecked
            Save-WmtSettings -Settings $currentSettings

            $cachePath = Join-Path (Get-DataPath) "cleanerml_cache.json"
            $forceDownload = [bool]$chkToggleCleanerML.IsChecked -and ((Get-WmtBleachBitCleanerXmlDirectories).Count -eq 0) -and (-not (Test-Path $cachePath))
            & $loadExternalCleanerRules -ForceCleanerMlDownload:$forceDownload
        }.GetNewClosure())

    $searchDelayTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $searchDelayTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $searchDelayTimer.Add_Tick({
            $searchDelayTimer.Stop()
            & $applyCleanerSearch
        }.GetNewClosure())

    $txtSearch.Add_TextChanged({
            $searchDelayTimer.Stop()
            $searchDelayTimer.Start()
        }.GetNewClosure())

    $dialog.Add_Closed({
            try { $searchDelayTimer.Stop() } catch {}
        }.GetNewClosure())

    $selectionState = @{ Result = $null }

    $getSelectedCleanerItems = {
        $selectedItems = [System.Collections.Generic.List[object]]::new()
        $filterActive = -not [string]::IsNullOrWhiteSpace($txtSearch.Text)
        foreach ($key in $cleanupCheckboxes.Keys) {
            $cb = $cleanupCheckboxes[$key]
            $isVisibleForAction = (-not $filterActive) -or ($cb.Visibility -eq [System.Windows.Visibility]::Visible -and $cb.Parent.Visibility -eq [System.Windows.Visibility]::Visible)
            if ([bool]$cb.IsChecked -and $isVisibleForAction) { [void]$selectedItems.Add($cb.Tag) }
        }
        return , $selectedItems
    }.GetNewClosure()

    $submitCleanupSelection = {
        param([string]$Action)

        $searchDelayTimer.Stop()
        & $applyCleanerSearch

        $selectedItems = & $getSelectedCleanerItems
        if ($selectedItems.Count -le 0) {
            $message = if ([string]::IsNullOrWhiteSpace($txtSearch.Text)) {
                "Select at least one cleaner first."
            }
            else {
                "No visible checked cleaners match the current search. Clear the search or check a visible cleaner."
            }
            Show-WmtMessageBox -Owner $dialog -Message $message -Title "No Cleaners Selected" -Image Information | Out-Null
            return
        }

        foreach ($key in $cleanupCheckboxes.Keys) {
            $currentSettings.TempCleanup[$key] = [bool]$cleanupCheckboxes[$key].IsChecked
        }
        $currentSettings.LoadWinapp2 = [bool]$chkToggleWinapp2.IsChecked
        $currentSettings.LoadCleanerML = [bool]$chkToggleCleanerML.IsChecked
        Save-WmtSettings -Settings $currentSettings

        $selectionState.Result = [PSCustomObject]@{
            Action = $Action
            Items  = $selectedItems.ToArray()
        }
        $dialog.DialogResult = $true
    }.GetNewClosure()

    $btnClean.Add_Click({ & $submitCleanupSelection "Clean" }.GetNewClosure())
    $btnAnalyze.Add_Click({ & $submitCleanupSelection "Analyze" }.GetNewClosure())
    $btnCancel.Add_Click({ $dialog.Close() }.GetNewClosure())

    $btnEventLogs.Add_Click({
            $confirm = Show-WmtMessageBox -Owner $dialog -Message "Clear all Windows Event Logs?`n`nThis safely flushes all registered Event Logs on your system.`n`nWARNING: This process can take several minutes to complete." -Title "Confirm Clear Logs" -Button YesNo -Image Warning
            if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

            $dialog.Cursor = [System.Windows.Input.Cursors]::Wait
            $btnEventLogs.IsEnabled = $false
            $btnEventLogs.Content = "Clearing..."

            $script:EventLogRunspace = [PowerShell]::Create().AddScript({
                    $logs = wevtutil el
                    $cleared = 0
                    foreach ($log in $logs) {
                        wevtutil cl "$log" 2>$null
                        $cleared++
                    }
                    return $cleared
                })
            $script:EventLogAsyncResult = $script:EventLogRunspace.BeginInvoke()

            $script:EventLogTimer = [System.Windows.Threading.DispatcherTimer]::new()
            $script:EventLogTimer.Interval = [TimeSpan]::FromMilliseconds(250)
            $script:EventLogTimer.Add_Tick({
                    if ($script:EventLogAsyncResult.IsCompleted) {
                        $script:EventLogTimer.Stop()
                        $dialog.Cursor = [System.Windows.Input.Cursors]::Arrow
                        $btnEventLogs.IsEnabled = $true
                        $btnEventLogs.Content = "Clear Event Logs"
                        try {
                            $clearedCount = $script:EventLogRunspace.EndInvoke($script:EventLogAsyncResult)
                            if ($clearedCount -is [System.Collections.ObjectModel.Collection[PSObject]]) {
                                $clearedCount = $clearedCount[0]
                            }
                            Show-WmtMessageBox -Owner $dialog -Message "Successfully processed $clearedCount Event Logs." -Title "Success" -Image Information | Out-Null
                        }
                        catch {
                            Show-WmtMessageBox -Owner $dialog -Message "Error: $($_.Exception.Message)" -Title "Error" -Image Error | Out-Null
                        }
                        $script:EventLogRunspace.Dispose()
                    }
                }.GetNewClosure())
            $script:EventLogTimer.Start()
        }.GetNewClosure())

    $dialog.ShowDialog() | Out-Null
    return $selectionState.Result
}

function Show-WmtCleanupPreviewWpf {
    param(
        [System.Collections.IEnumerable]$PreviewList,
        [string]$FinalTotalFormatted
    )

    $formatPreviewBytes = {
        param([int64]$Bytes)
        if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
        if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
        if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
        return "$Bytes B"
    }.GetNewClosure()

    [xml]$cleanupPreviewXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="960" Height="680" MinWidth="760" MinHeight="500" WindowStartupLocation="CenterOwner"
        Background="{DynamicResource BgDark}" Foreground="{DynamicResource TextPrimary}"
        FontFamily="Segoe UI Variable Display, Segoe UI, Arial" FontSize="13">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <DataGrid Name="dgPreview" Grid.Row="0" AlternationCount="2" IsReadOnly="True" CanUserAddRows="False" CanUserDeleteRows="False">
            <DataGrid.Columns>
                <DataGridTextColumn Header="RuleName" Binding="{Binding RuleName}" Width="180" IsReadOnly="True"/>
                <DataGridTextColumn Header="Status" Binding="{Binding Protection}" Width="160" IsReadOnly="True"/>
                <DataGridTextColumn Header="FilePath" Binding="{Binding FilePath}" Width="*" IsReadOnly="True"/>
                <DataGridTextColumn Header="Size" Binding="{Binding SizeText}" SortMemberPath="Size" Width="96" IsReadOnly="True"/>
            </DataGrid.Columns>
        </DataGrid>

        <Border Grid.Row="1" Background="{DynamicResource BgPanel}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="4" Padding="12" Margin="0,12,0,0">
            <Grid>
                <CheckBox Name="chkHideProtected" Content="Hide protected" Foreground="{DynamicResource Warning}" VerticalAlignment="Center"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                    <Button Name="btnCleanSelected" Content="Clean Selected" MinWidth="124" Background="{DynamicResource Accent}" Foreground="{DynamicResource AccentText}" Margin="0,0,8,0"/>
                    <Button Name="btnCleanAll" Content="Clean All" MinWidth="104" Background="{DynamicResource Danger}" Foreground="{DynamicResource DangerText}" Margin="0,0,8,0"/>
                    <Button Name="btnClose" Content="Close" Width="90" IsCancel="True"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

    $previewWindow = New-WmtWindowFromFullXaml -Xaml $cleanupPreviewXaml

    $dg = $previewWindow.FindName("dgPreview")
    $chkHideProtected = $previewWindow.FindName("chkHideProtected")
    $btnCleanSelected = $previewWindow.FindName("btnCleanSelected")
    $btnCleanAll = $previewWindow.FindName("btnCleanAll")
    $btnClose = $previewWindow.FindName("btnClose")

    $allPreviewRows = [System.Collections.Generic.List[object]]::new()
    $rowId = 0
    foreach ($item in @($PreviewList)) {
        $isProtected = $false
        if ($item.PSObject.Properties["IsProtected"]) { $isProtected = [bool]$item.IsProtected }
        $protectionReason = ""
        if ($item.PSObject.Properties["ProtectionReason"]) { $protectionReason = [string]$item.ProtectionReason }
        if ($isProtected -and [string]::IsNullOrWhiteSpace($protectionReason)) { $protectionReason = "Protected / in use" }

        $bytes = [int64]0
        try { $bytes = [int64]$item.RawBytes } catch {}

        [void]$allPreviewRows.Add([PSCustomObject]@{
                RowId            = $rowId
                RuleName         = [string]$item.RuleName
                Protection       = if ($isProtected) { $protectionReason } else { "" }
                FilePath         = [string]$item.FilePath
                Size             = $bytes
                SizeText         = & $formatPreviewBytes $bytes
                IsProtected      = $isProtected
                ProtectionReason = $protectionReason
            })
        $rowId++
    }

    $previewRows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $dg.ItemsSource = $previewRows

    $ctxMenu = [System.Windows.Controls.ContextMenu]::new()
    Set-WmtContextMenuChrome -ContextMenu $ctxMenu
    $menuOpen = [System.Windows.Controls.MenuItem]::new()
    $menuOpen.Header = "Go to file [Open folder]"
    $menuDelete = [System.Windows.Controls.MenuItem]::new()
    $menuDelete.Header = "Delete file"
    [void]$ctxMenu.Items.Add($menuOpen)
    [void]$ctxMenu.Items.Add($menuDelete)
    $dg.ContextMenu = $ctxMenu

    $dg.Add_PreviewMouseRightButtonDown({
            param($s, $e)
            $row = Get-WmtVisualAncestor -Element $e.OriginalSource -AncestorType ([System.Windows.Controls.DataGridRow])
            if ($row) {
                if (-not $row.IsSelected) {
                    $dg.SelectedItems.Clear()
                    $row.IsSelected = $true
                }
                try { $row.Focus() | Out-Null } catch {}
            }
        }.GetNewClosure())

    $refreshPreviewFilter = {
        $previewRows.Clear()
        foreach ($row in @($allPreviewRows.ToArray())) {
            if ([bool]$chkHideProtected.IsChecked -and [bool]$row.IsProtected) { continue }
            [void]$previewRows.Add($row)
        }

        $protectedRemaining = @($allPreviewRows.ToArray() | Where-Object { [bool]$_.IsProtected }).Count
        $hiddenProtected = if ([bool]$chkHideProtected.IsChecked) { $protectedRemaining } else { 0 }
        if ($protectedRemaining -gt 0) {
            $suffix = "$protectedRemaining protected/in use"
            if ($hiddenProtected -gt 0) { $suffix += ", $hiddenProtected hidden" }
            $previewWindow.Title = "Cleanup Analysis Preview ($FinalTotalFormatted Total, $suffix)"
        }
        else {
            $previewWindow.Title = "Cleanup Analysis Preview ($FinalTotalFormatted Total)"
        }

        $hasRows = ($previewRows.Count -gt 0)
        $btnCleanSelected.IsEnabled = $hasRows
        $btnCleanAll.IsEnabled = $hasRows
        $menuDelete.IsEnabled = $hasRows
    }.GetNewClosure()

    $removePreviewRowsByIds = {
        param([int[]]$RowIds)
        if (-not $RowIds -or $RowIds.Count -eq 0) { return }
        $removeLookup = @{}
        foreach ($id in $RowIds) { $removeLookup[[int]$id] = $true }
        for ($i = $allPreviewRows.Count - 1; $i -ge 0; $i--) {
            if ($removeLookup.ContainsKey([int]$allPreviewRows[$i].RowId)) {
                $allPreviewRows.RemoveAt($i)
            }
        }
        & $refreshPreviewFilter
    }.GetNewClosure()

    $openSelectedPath = {
        if ($dg.SelectedItems.Count -le 0) { return }
        $path = [string]$dg.SelectedItems[0].FilePath
        if (Test-Path -LiteralPath $path) {
            Start-Process "explorer.exe" -ArgumentList "/select,`"$path`""
        }
    }.GetNewClosure()

    $invokePreviewDeletion = {
        param(
            [object[]]$Targets,
            [string]$ActionTitle
        )

        $deleteTargets = [System.Collections.Generic.List[object]]::new()
        $seenIds = @{}
        foreach ($target in @($Targets)) {
            if (-not $target) { continue }
            $id = [int]$target.RowId
            if ($seenIds.ContainsKey($id)) { continue }
            [void]$deleteTargets.Add([PSCustomObject]@{
                    RowId    = $id
                    FilePath = [string]$target.FilePath
                    Size     = [int64]$target.Size
                })
            $seenIds[$id] = $true
        }

        if ($deleteTargets.Count -eq 0) { return }

        $targetArray = $deleteTargets.ToArray()
        $completedIds = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        $failedPaths = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        $deleteState = [hashtable]::Synchronized(@{
                Total        = $targetArray.Count
                Processed    = 0
                Deleted      = 0
                Missing      = 0
                Failed       = 0
                Bytes        = [int64]0
                Current      = ""
                Cancel       = $false
                IsCompleted  = $false
                Error        = ""
                CompletedIds = $completedIds
                FailedPaths  = $failedPaths
            })

        [xml]$deleteProgressXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="560" Height="190" ResizeMode="NoResize" WindowStartupLocation="CenterOwner"
        Background="{DynamicResource BgDark}" Foreground="{DynamicResource TextPrimary}"
        FontFamily="Segoe UI Variable Display, Segoe UI, Arial" FontSize="13">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Name="deleteLabel" Text="Preparing deletion..." TextTrimming="CharacterEllipsis"/>
        <TextBlock Name="deleteCurrent" Grid.Row="1" Text="Starting worker..." Foreground="{DynamicResource TextSecondary}" Margin="0,8,0,14" TextTrimming="CharacterEllipsis"/>
        <ProgressBar Name="deleteProgress" Grid.Row="2" Height="12" Minimum="0"/>
        <Button Name="btnCancelDelete" Grid.Row="3" Content="Cancel" Width="94" HorizontalAlignment="Right" Margin="0,16,0,0"/>
    </Grid>
</Window>
'@
        $deleteWindow = New-WmtWindowFromFullXaml -Xaml $deleteProgressXaml -NoOwner
        try { $deleteWindow.Owner = $previewWindow } catch {}
        $deleteWindow.Title = $ActionTitle
        $deleteLabel = $deleteWindow.FindName("deleteLabel")
        $deleteCurrent = $deleteWindow.FindName("deleteCurrent")
        $deleteProgress = $deleteWindow.FindName("deleteProgress")
        $btnCancelDelete = $deleteWindow.FindName("btnCancelDelete")
        $deleteProgress.Maximum = [Math]::Max(1, $targetArray.Count)

        $worker = @{
            PowerShell = $null
            Runspace   = $null
            Async      = $null
            Ended      = $false
        }

        $disposeWorker = {
            try { if ($worker.PowerShell) { $worker.PowerShell.Dispose() } } catch {}
            try {
                if ($worker.Runspace) {
                    $worker.Runspace.Close()
                    $worker.Runspace.Dispose()
                }
            }
            catch {}
            $worker.PowerShell = $null
            $worker.Runspace = $null
            $worker.Async = $null
        }.GetNewClosure()

        try {
            $runspace = [runspacefactory]::CreateRunspace()
            $runspace.ThreadOptions = "ReuseThread"
            $runspace.Open()

            $ps = [PowerShell]::Create()
            $ps.Runspace = $runspace
            [void]$ps.AddScript({
                    param([object[]]$Targets, [hashtable]$State)
                    $ErrorActionPreference = "SilentlyContinue"
                    try {
                        foreach ($target in @($Targets)) {
                            if ([bool]$State["Cancel"]) { break }

                            $path = [string]$target.FilePath
                            $rowId = [int]$target.RowId
                            $bytes = [int64]0
                            try { $bytes = [int64]$target.Size } catch {}

                            $State["Current"] = $path
                            try {
                                if ([string]::IsNullOrWhiteSpace($path)) {
                                    [void]$State["CompletedIds"].Add($rowId)
                                    $State["Missing"] = ([int]$State["Missing"]) + 1
                                    continue
                                }

                                if (Test-Path -LiteralPath $path) {
                                    $itemInfo = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
                                    if ($itemInfo -and -not $itemInfo.PSIsContainer) {
                                        try { $itemInfo.Attributes = [System.IO.FileAttributes]::Normal } catch {}
                                    }
                                    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
                                    $State["Deleted"] = ([int]$State["Deleted"]) + 1
                                    $State["Bytes"] = ([int64]$State["Bytes"]) + $bytes
                                }
                                else {
                                    $State["Missing"] = ([int]$State["Missing"]) + 1
                                }
                                [void]$State["CompletedIds"].Add($rowId)
                            }
                            catch {
                                $State["Failed"] = ([int]$State["Failed"]) + 1
                                if (-not [string]::IsNullOrWhiteSpace($path)) {
                                    [void]$State["FailedPaths"].Add($path)
                                }
                            }
                            finally {
                                $State["Processed"] = ([int]$State["Processed"]) + 1
                            }
                        }
                    }
                    catch {
                        $State["Error"] = $_.Exception.Message
                    }
                    finally {
                        $State["IsCompleted"] = $true
                    }
                }).AddArgument($targetArray).AddArgument($deleteState)

            $worker.PowerShell = $ps
            $worker.Runspace = $runspace
            $worker.Async = $ps.BeginInvoke()
        }
        catch {
            & $disposeWorker
            Show-WmtMessageBox -Owner $previewWindow -Message "Could not start cleanup worker.`n$($_.Exception.Message)" -Title "Cleanup Error" -Image Error | Out-Null
            return
        }

        $btnCleanSelected.IsEnabled = $false
        $btnCleanAll.IsEnabled = $false
        $menuDelete.IsEnabled = $false

        $btnCancelDelete.Add_Click({
                $deleteState["Cancel"] = $true
                $btnCancelDelete.IsEnabled = $false
                $deleteCurrent.Text = "Stopping after the current item..."
            }.GetNewClosure())

        $deleteTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $deleteTimer.Interval = [TimeSpan]::FromMilliseconds(150)
        $deleteTimer.Add_Tick({
                try {
                    $total = [Math]::Max(1, [int]$deleteState["Total"])
                    $processed = [Math]::Max(0, [int]$deleteState["Processed"])
                    $deleted = [Math]::Max(0, [int]$deleteState["Deleted"])
                    $missing = [Math]::Max(0, [int]$deleteState["Missing"])
                    $failed = [Math]::Max(0, [int]$deleteState["Failed"])
                    $bytes = [int64]$deleteState["Bytes"]
                    $currentPath = [string]$deleteState["Current"]
                    $freed = & $formatPreviewBytes $bytes

                    $deleteProgress.Value = [Math]::Min($deleteProgress.Maximum, $processed)
                    $deleteLabel.Text = "$processed/$total processed | Deleted: $deleted | Failed: $failed | Recovered: $freed"
                    if ([bool]$deleteState["Cancel"] -and -not [bool]$deleteState["IsCompleted"]) {
                        $deleteCurrent.Text = "Stopping after the current item..."
                    }
                    elseif ($missing -gt 0) {
                        $deleteCurrent.Text = "Current: $currentPath  ($missing already missing)"
                    }
                    else {
                        $deleteCurrent.Text = "Current: $currentPath"
                    }

                    if ([bool]$deleteState["IsCompleted"] -or ($worker.Async -and $worker.Async.IsCompleted)) {
                        $deleteTimer.Stop()
                        try {
                            if ($worker.Async -and -not $worker.Ended) {
                                [void]$worker.PowerShell.EndInvoke($worker.Async)
                                $worker.Ended = $true
                            }
                        }
                        catch {
                            if ([string]::IsNullOrWhiteSpace([string]$deleteState["Error"])) {
                                $deleteState["Error"] = $_.Exception.Message
                            }
                        }
                        $deleteWindow.Close()
                    }
                }
                catch {
                    $deleteState["Error"] = $_.Exception.Message
                    $deleteTimer.Stop()
                    $deleteWindow.Close()
                }
            }.GetNewClosure())

        try {
            $deleteWindow.Add_ContentRendered({ $deleteTimer.Start() }.GetNewClosure())
            $deleteWindow.ShowDialog() | Out-Null
        }
        finally {
            try { $deleteTimer.Stop() } catch {}
            try {
                if ($worker.Async -and $worker.Async.IsCompleted -and -not $worker.Ended) {
                    [void]$worker.PowerShell.EndInvoke($worker.Async)
                    $worker.Ended = $true
                }
            }
            catch {
                if ([string]::IsNullOrWhiteSpace([string]$deleteState["Error"])) {
                    $deleteState["Error"] = $_.Exception.Message
                }
            }
            & $disposeWorker
        }

        $completedRowIds = @($deleteState["CompletedIds"] | ForEach-Object { [int]$_ })
        $failedLookup = @{}
        foreach ($failedPath in @($deleteState["FailedPaths"])) {
            if (-not [string]::IsNullOrWhiteSpace([string]$failedPath)) { $failedLookup[[string]$failedPath] = $true }
        }

        if ($failedLookup.Count -gt 0) {
            foreach ($row in @($allPreviewRows.ToArray())) {
                if ($row -and $failedLookup.ContainsKey([string]$row.FilePath)) {
                    $row.IsProtected = $true
                    $row.ProtectionReason = "Delete failed"
                    $row.Protection = "Delete failed"
                }
            }
        }

        if ($completedRowIds.Count -gt 0) { & $removePreviewRowsByIds -RowIds ([int[]]$completedRowIds) }
        else { & $refreshPreviewFilter }

        $finalFreed = & $formatPreviewBytes ([int64]$deleteState["Bytes"])
        $finalDeleted = [int]$deleteState["Deleted"]
        $finalMissing = [int]$deleteState["Missing"]
        $finalFailed = [int]$deleteState["Failed"]
        $wasCanceled = [bool]$deleteState["Cancel"]
        $workerError = [string]$deleteState["Error"]

        if ($finalFailed -gt 0) {
            Write-GuiLog "Preview cleanup completed with $finalFailed failure(s). Recovered: $finalFreed"
            foreach ($failedPath in @($deleteState["FailedPaths"] | Select-Object -First 5)) {
                Write-GuiLog "Failed to delete from Analyze: $failedPath"
            }
        }
        elseif ($wasCanceled) {
            Write-GuiLog "Preview cleanup canceled. Recovered: $finalFreed"
        }
        else {
            Write-GuiLog "Preview cleanup finished. Recovered: $finalFreed"
        }

        $resultText = if ($wasCanceled) {
            "Cleanup canceled.`n`nDeleted: $finalDeleted`nAlready missing: $finalMissing`nFailed: $finalFailed`nRecovered: $finalFreed"
        }
        else {
            "Cleanup complete.`n`nDeleted: $finalDeleted`nAlready missing: $finalMissing`nFailed: $finalFailed`nRecovered: $finalFreed"
        }
        if (-not [string]::IsNullOrWhiteSpace($workerError)) { $resultText += "`n`nWorker note: $workerError" }

        $icon = if ($finalFailed -gt 0 -or -not [string]::IsNullOrWhiteSpace($workerError)) {
            [System.Windows.MessageBoxImage]::Warning
        }
        else {
            [System.Windows.MessageBoxImage]::Information
        }
        Show-WmtMessageBox -Owner $previewWindow -Message $resultText -Title "Cleanup Results" -Image $icon | Out-Null
    }.GetNewClosure()

    $menuOpen.Add_Click({ & $openSelectedPath }.GetNewClosure())
    $menuDelete.Add_Click({
            if ($dg.SelectedItems.Count -gt 0) {
                & $invokePreviewDeletion -Targets @($dg.SelectedItems) -ActionTitle "Deleting Preview Items"
            }
        }.GetNewClosure())
    $dg.Add_MouseDoubleClick({ & $openSelectedPath }.GetNewClosure())
    $chkHideProtected.Add_Checked({ & $refreshPreviewFilter }.GetNewClosure())
    $chkHideProtected.Add_Unchecked({ & $refreshPreviewFilter }.GetNewClosure())
    $btnClose.Add_Click({ $previewWindow.Close() }.GetNewClosure())
    $btnCleanSelected.Add_Click({
            if ($dg.SelectedItems.Count -gt 0) {
                & $invokePreviewDeletion -Targets @($dg.SelectedItems) -ActionTitle "Cleaning Selected Items"
            }
        }.GetNewClosure())
    $btnCleanAll.Add_Click({
            if ($previewRows.Count -eq 0) { return }
            $confirm = Show-WmtMessageBox -Owner $previewWindow -Message "Are you sure you want to permanently delete ALL $($previewRows.Count) files shown?" -Title "Confirm Clean All" -Button YesNo -Image Warning
            if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
                & $invokePreviewDeletion -Targets @($previewRows) -ActionTitle "Cleaning All Preview Items"
            }
        }.GetNewClosure())

    $protectedPreviewCount = @($allPreviewRows.ToArray() | Where-Object { [bool]$_.IsProtected }).Count
    if ($protectedPreviewCount -gt 0) {
        Write-GuiLog "Analysis flagged $protectedPreviewCount protected or in-use item(s)."
    }
    & $refreshPreviewFilter
    $previewWindow.ShowDialog() | Out-Null
}

function Invoke-TempCleanup {
    # 1. GET SELECTION
    $uiResult = Show-WmtAdvancedCleanupSelectionWpf

    # FIX: Force the returned items into an array @() to prevent PowerShell
    # from unrolling single-item selections and losing the .Count property.
    $selections = @($uiResult.Items)

    if (-not $uiResult -or $selections.Count -eq 0) {
        Write-GuiLog "Cleanup/Analysis canceled: No items selected."
        return
    }

    $isAnalyze = ($uiResult.Action -eq "Analyze")

    # Generic List for high-performance preview tracking
    $previewList = New-Object System.Collections.Generic.List[PSCustomObject]

    # 2. SETUP PROGRESS UI
    [xml]$cleanupProgressXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="520" Height="170" ResizeMode="NoResize" WindowStartupLocation="CenterOwner"
        Background="{DynamicResource BgDark}" Foreground="{DynamicResource TextPrimary}"
        FontFamily="Segoe UI Variable Display, Segoe UI, Arial" FontSize="13">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Name="pLabel" Text="Initializing..." Foreground="{DynamicResource TextPrimary}" TextTrimming="CharacterEllipsis"/>
        <TextBlock Name="pStatus" Grid.Row="1" Text="Preparing..." Foreground="{DynamicResource TextSecondary}" Margin="0,8,0,14" TextTrimming="CharacterEllipsis"/>
        <ProgressBar Name="pBar" Grid.Row="2" Minimum="0" Maximum="100" Height="12"/>
    </Grid>
</Window>
'@
    $pForm = New-WmtWindowFromFullXaml -Xaml $cleanupProgressXaml
    $pForm.Title = if ($isAnalyze) { "Analyzing System..." } else { "Deep Cleaning System" }
    $pLabel = $pForm.FindName("pLabel")
    $pStatus = $pForm.FindName("pStatus")
    $pBar = $pForm.FindName("pBar")
    $progressState = @{ Closed = $false }
    $pForm.Add_Closed({ $progressState.Closed = $true }.GetNewClosure())
    $pForm.Show()
    Invoke-WmtDispatcherPump -Dispatcher $pForm.Dispatcher

    # 3. STATS TRACKING
    $stats = @{
        Deleted  = 0
        Bytes    = 0
        Progress = 0.0
    }

    $ruleWeight = 100.0 / ($selections.Count)

    # --- HELPER: FILE SIZE FORMATTER ---
    function Format-FileSize {
        param([long]$Bytes)
        if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
        if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
        if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
        return "$Bytes B"
    }

    function Test-WmtCleanupPathStartsWith {
        param(
            [string]$Path,
            [string]$Root
        )

        if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }

        try {
            $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd("\")
            $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd("\")
            return ($fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
                $fullPath.StartsWith($fullRoot + "\", [System.StringComparison]::OrdinalIgnoreCase))
        }
        catch {
            return $false
        }
    }

    function Get-WmtCleanupProtectionInfo {
        param(
            [string]$Path,
            [System.IO.FileSystemInfo]$ItemInfo = $null
        )

        $reasons = [System.Collections.Generic.List[string]]::new()

        if ([string]::IsNullOrWhiteSpace($Path)) {
            return [PSCustomObject]@{ IsProtected = $false; Reason = "" }
        }

        try {
            if (-not $ItemInfo) {
                $ItemInfo = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
            }
        }
        catch [System.UnauthorizedAccessException] {
            [void]$reasons.Add("Access denied")
        }
        catch {
            if ($_.Exception.Message -match "(?i)access.*denied|unauthorized") {
                [void]$reasons.Add("Access denied")
            }
        }

        if ($ItemInfo) {
            try {
                $attrs = $ItemInfo.Attributes
                if (($attrs -band [System.IO.FileAttributes]::System) -eq [System.IO.FileAttributes]::System) {
                    [void]$reasons.Add("System attribute")
                }

                $protectedRoots = @(
                    "$env:SystemRoot\Temp",
                    "$env:SystemRoot\System32",
                    "$env:SystemRoot\SysWOW64",
                    "$env:SystemRoot\WinSxS",
                    "$env:SystemRoot\servicing",
                    "$env:SystemRoot\SystemResources",
                    "$env:ProgramFiles\WindowsApps",
                    "$env:ProgramFiles\Windows Defender",
                    "${env:ProgramFiles(x86)}\Windows Defender",
                    "$env:ProgramData\Microsoft\Windows Defender"
                ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

                $isSystemArea = $false
                foreach ($root in $protectedRoots) {
                    if (Test-WmtCleanupPathStartsWith -Path $ItemInfo.FullName -Root $root) {
                        $isSystemArea = $true
                        break
                    }
                }

                if ($isSystemArea -or (($attrs -band [System.IO.FileAttributes]::System) -eq [System.IO.FileAttributes]::System)) {
                    try {
                        $owner = [string](Get-Acl -LiteralPath $ItemInfo.FullName -ErrorAction Stop).Owner
                        if ($owner -match "(?i)TrustedInstaller|NT AUTHORITY\\SYSTEM|^SYSTEM$") {
                            [void]$reasons.Add("System-owned")
                        }
                    }
                    catch {
                        if ($_.Exception.Message -match "(?i)access.*denied|unauthorized") {
                            [void]$reasons.Add("Access denied")
                        }
                    }
                }

                if (-not $ItemInfo.PSIsContainer) {
                    $stream = $null
                    try {
                        $stream = [System.IO.File]::Open($ItemInfo.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
                    }
                    catch [System.UnauthorizedAccessException] {
                        [void]$reasons.Add("Access denied")
                    }
                    catch [System.IO.IOException] {
                        [void]$reasons.Add("In use")
                    }
                    catch {}
                    finally {
                        if ($stream) {
                            try { $stream.Close() } catch {}
                            try { $stream.Dispose() } catch {}
                        }
                    }
                }
            }
            catch {}
        }

        $reasonText = (@($reasons.ToArray()) | Select-Object -Unique) -join ", "
        return [PSCustomObject]@{
            IsProtected = -not [string]::IsNullOrWhiteSpace($reasonText)
            Reason      = $reasonText
        }
    }

    # --- HELPER: ROBUST CLEANER ---
    function Invoke-RobustClean {
        param($Path, $Pattern = "*", $Recurse = $true, $RuleName = "System File")

        $Path = [Environment]::ExpandEnvironmentVariables($Path)
        $pathHasWildcard = ($Path -match '[\*\?]')
        if (-not $pathHasWildcard -and -not (Test-Path -LiteralPath $Path)) { return }

        $pStatus.Text = "Scanning: $(Split-Path $Path -Leaf)"
        Invoke-WmtDispatcherPump -Dispatcher $pForm.Dispatcher

        try {
            $batchCount = 0
            $patterns = @($Pattern -split ';' | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($patterns.Count -eq 0) { $patterns = @("*") }

            $roots = @()
            if ($pathHasWildcard) {
                $roots = @(Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue)
            }
            else {
                $roots = @(Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
            }

            foreach ($root in $roots) {
                if (-not $root) { continue }

                if (-not $root.PSIsContainer) {
                    foreach ($patternItem in $patterns) {
                        if ($root.Name -like $patternItem) {
                            Add-WmtCleanupTarget -Path $root.FullName -RuleName $RuleName
                            $batchCount++
                            break
                        }
                    }
                }
                else {
                    foreach ($patternItem in $patterns) {
                        foreach ($file in @(Get-ChildItem -LiteralPath $root.FullName -Filter $patternItem -File -Recurse:$Recurse -Force -ErrorAction SilentlyContinue)) {
                            Add-WmtCleanupTarget -Path $file.FullName -RuleName $RuleName
                            $batchCount++

                            if ($batchCount -gt 50) {
                                $mb = [math]::Round($stats.Bytes / 1MB, 2)
                                $verb = if ($isAnalyze) { "Found" } else { "Removed" }
                                $pLabel.Text = "${verb}: $($stats.Deleted) | Space: $mb MB"
                                Invoke-WmtDispatcherPump -Dispatcher $pForm.Dispatcher
                                $batchCount = 0
                            }
                        }
                    }
                }
            }

            if ($Recurse) {
                if (-not $isAnalyze) {
                    Remove-WmtEmptyChildDirectories -Path $Path
                }
            }
        }
        catch {}
    }

    function Add-WmtCleanupTarget {
        param(
            [string]$Path,
            [string]$RuleName = "System File"
        )

        if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return }

        try {
            $itemInfo = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
            $size = if ($itemInfo.PSIsContainer) { Measure-WmtPathBytes -Path $Path } else { [int64]$itemInfo.Length }

            if (-not $isAnalyze) {
                if (-not $itemInfo.PSIsContainer) {
                    try { $itemInfo.Attributes = [System.IO.FileAttributes]::Normal } catch {}
                }
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            }
            else {
                $protectionInfo = Get-WmtCleanupProtectionInfo -Path $Path -ItemInfo $itemInfo
                $previewList.Add([PSCustomObject]@{
                        RuleName         = $RuleName
                        FilePath         = $Path
                        RawBytes         = $size
                        IsProtected      = [bool]$protectionInfo.IsProtected
                        ProtectionReason = [string]$protectionInfo.Reason
                    })
            }

            $stats.Deleted++
            $stats.Bytes += $size
        }
        catch {}
    }

    function Test-WmtCleanerMlTargetMatch {
        param(
            [System.IO.FileSystemInfo]$Item,
            $Rule
        )

        if (-not $Item) { return $false }
        $type = [string]$Rule.Type
        if ($type -eq "f" -and $Item.PSIsContainer) { return $false }
        if ($type -eq "d" -and -not $Item.PSIsContainer) { return $false }

        $leaf = $Item.Name
        $full = $Item.FullName
        $regexOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase

        try {
            if ($Rule.Regex -and -not [regex]::IsMatch($leaf, [string]$Rule.Regex, $regexOptions)) { return $false }
            if ($Rule.WholeRegex -and -not [regex]::IsMatch($full, [string]$Rule.WholeRegex, $regexOptions)) { return $false }
            if ($Rule.NRegex -and [regex]::IsMatch($leaf, [string]$Rule.NRegex, $regexOptions)) { return $false }
            if ($Rule.NWholeRegex -and [regex]::IsMatch($full, [string]$Rule.NWholeRegex, $regexOptions)) { return $false }
        }
        catch {
            return $false
        }

        return $true
    }

    function Invoke-CleanerMlClean {
        param(
            $Rule,
            [string]$RuleName
        )

        $path = [Environment]::ExpandEnvironmentVariables([string]$Rule.Path)
        if ([string]::IsNullOrWhiteSpace($path)) { return }

        $search = if ($Rule.Search) { [string]$Rule.Search } else { "file" }
        $targets = New-Object System.Collections.Generic.List[System.IO.FileSystemInfo]

        try {
            switch ($search) {
                "file" {
                    if ($path -match '[\*\?]') {
                        foreach ($target in @(Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue)) {
                            if (Test-WmtCleanerMlTargetMatch -Item $target -Rule $Rule) { [void]$targets.Add($target) }
                        }
                    }
                    elseif (Test-Path -LiteralPath $path) {
                        $target = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
                        if (Test-WmtCleanerMlTargetMatch -Item $target -Rule $Rule) { [void]$targets.Add($target) }
                    }
                }
                "glob" {
                    foreach ($target in @(Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue)) {
                        if (Test-WmtCleanerMlTargetMatch -Item $target -Rule $Rule) { [void]$targets.Add($target) }
                    }
                }
                "walk.files" {
                    $roots = @(Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue)
                    if ((Test-Path -LiteralPath $path) -and -not ($path -match '[\*\?]')) {
                        $roots = @(Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue)
                    }
                    foreach ($root in $roots) {
                        if (-not $root) { continue }
                        if (-not $root.PSIsContainer) {
                            if (Test-WmtCleanerMlTargetMatch -Item $root -Rule $Rule) { [void]$targets.Add($root) }
                            continue
                        }
                        foreach ($target in @(Get-ChildItem -LiteralPath $root.FullName -File -Recurse -Force -ErrorAction SilentlyContinue)) {
                            if (Test-WmtCleanerMlTargetMatch -Item $target -Rule $Rule) { [void]$targets.Add($target) }
                        }
                    }
                }
                "walk.all" {
                    $roots = @(Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue)
                    if ((Test-Path -LiteralPath $path) -and -not ($path -match '[\*\?]')) {
                        $roots = @(Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue)
                    }
                    foreach ($root in $roots) {
                        if (-not $root) { continue }
                        if (Test-WmtCleanerMlTargetMatch -Item $root -Rule $Rule) { [void]$targets.Add($root) }
                        if ($root.PSIsContainer) {
                            foreach ($target in @(Get-ChildItem -LiteralPath $root.FullName -Recurse -Force -ErrorAction SilentlyContinue)) {
                                if (Test-WmtCleanerMlTargetMatch -Item $target -Rule $Rule) { [void]$targets.Add($target) }
                            }
                        }
                    }
                }
                "walk.top" {
                    if (Test-Path -LiteralPath $path) {
                        $root = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
                        if ($root -and (Test-WmtCleanerMlTargetMatch -Item $root -Rule $Rule)) { [void]$targets.Add($root) }
                        if ($root -and $root.PSIsContainer) {
                            foreach ($target in @(Get-ChildItem -LiteralPath $root.FullName -Force -ErrorAction SilentlyContinue)) {
                                if (Test-WmtCleanerMlTargetMatch -Item $target -Rule $Rule) { [void]$targets.Add($target) }
                            }
                        }
                    }
                }
                "deep" {
                    if (Test-Path -LiteralPath $path) {
                        $pStatus.Text = "Deep scan: $(Split-Path $path -Leaf)"
                        Invoke-WmtDispatcherPump -Dispatcher $pForm.Dispatcher
                        $root = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
                        if ($root -and (Test-WmtCleanerMlTargetMatch -Item $root -Rule $Rule)) { [void]$targets.Add($root) }
                        if ($root -and $root.PSIsContainer) {
                            foreach ($target in @(Get-ChildItem -LiteralPath $root.FullName -Recurse -Force -ErrorAction SilentlyContinue)) {
                                if (Test-WmtCleanerMlTargetMatch -Item $target -Rule $Rule) { [void]$targets.Add($target) }
                            }
                        }
                    }
                }
            }

            foreach ($target in @($targets.ToArray() | Sort-Object FullName -Unique)) {
                Add-WmtCleanupTarget -Path $target.FullName -RuleName $RuleName
            }
        }
        catch {}
    }

    function Invoke-ThumbsDbDeepScan {
        param([string]$RuleName)

        $rule = [PSCustomObject]@{
            Path        = $env:USERPROFILE
            Search      = "deep"
            Regex       = "^Thumbs\.db(:encryptable)?$"
            WholeRegex  = ""
            NRegex      = ""
            NWholeRegex = ""
            Type        = "f"
        }
        Invoke-CleanerMlClean -Rule $rule -RuleName $RuleName
    }

    function Get-WmtCleanupObjectValue {
        param(
            $InputObject,
            [string]$Name,
            $Default = $null
        )

        if ($null -eq $InputObject -or [string]::IsNullOrWhiteSpace($Name)) { return $Default }

        try {
            if ($InputObject -is [System.Collections.IDictionary]) {
                if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
                if ($InputObject.ContainsKey($Name)) { return $InputObject[$Name] }
            }
        }
        catch {}

        try {
            $prop = $InputObject.PSObject.Properties[$Name]
            if ($prop) { return $prop.Value }
        }
        catch {}

        return $Default
    }

    function Test-WmtCleanupObjectFlag {
        param(
            $InputObject,
            [string]$Name
        )

        try { return [bool](Get-WmtCleanupObjectValue -InputObject $InputObject -Name $Name -Default $false) }
        catch { return $false }
    }

    function Get-WmtCleanupItemPaths {
        param($Item)

        $paths = Get-WmtCleanupObjectValue -InputObject $Item -Name "Paths" -Default $null
        if ($null -eq $paths) { return @() }
        if ($paths -is [string]) { return @() }
        if ($paths -is [System.Collections.IDictionary]) { return , $paths }
        return @($paths)
    }

    function ConvertTo-WmtWinapp2PathRule {
        param($Rule)

        $path = ([string](Get-WmtCleanupObjectValue -InputObject $Rule -Name "Path" -Default "")).Trim()
        if ([string]::IsNullOrWhiteSpace($path)) { return $null }

        $pattern = ([string](Get-WmtCleanupObjectValue -InputObject $Rule -Name "Pattern" -Default "*")).Trim()
        if ([string]::IsNullOrWhiteSpace($pattern)) { $pattern = "*" }

        $options = ([string](Get-WmtCleanupObjectValue -InputObject $Rule -Name "Options" -Default "")).Trim()
        $hasRecurseFlag = ($options -match "(?i)(^|[\s,;|])(RECURSE|REMOVESELF)($|[\s,;|])")
        $hasRemoveSelfFlag = ($options -match "(?i)(^|[\s,;|])REMOVESELF($|[\s,;|])")

        return [PSCustomObject]@{
            Path       = $path
            Pattern    = $pattern
            Options    = $options
            Recurse    = [bool]$hasRecurseFlag
            RemoveSelf = [bool]$hasRemoveSelfFlag
        }
    }

    function Get-WmtCleanupItemDisplayName {
        param($Item)

        if ($Item -is [string]) {
            if ($internalRuleDisplayNames.ContainsKey($Item)) { return $internalRuleDisplayNames[$Item] }
            return $Item
        }

        $name = ([string](Get-WmtCleanupObjectValue -InputObject $Item -Name "Name" -Default "")).Trim().Trim(" *")
        if ([string]::IsNullOrWhiteSpace($name)) { return [string](Get-WmtCleanupObjectValue -InputObject $Item -Name "ID" -Default "") }
        return $name
    }

    function New-WmtAnalyzeScanTasks {
        param($Items)

        $tasks = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Items) {
            $itemName = Get-WmtCleanupItemDisplayName -Item $item
            $itemPaths = @(Get-WmtCleanupItemPaths -Item $item)

            if (Test-WmtCleanupObjectFlag -InputObject $item -Name "IsCleanerML") {
                foreach ($rule in $itemPaths) {
                    $path = ([string](Get-WmtCleanupObjectValue -InputObject $rule -Name "Path" -Default "")).Trim()
                    if ([string]::IsNullOrWhiteSpace($path)) { continue }
                    [void]$tasks.Add([PSCustomObject]@{
                            Engine      = "CleanerML"
                            RuleName    = $itemName
                            Path        = $path
                            Search      = [string](Get-WmtCleanupObjectValue -InputObject $rule -Name "Search" -Default "file")
                            Regex       = [string](Get-WmtCleanupObjectValue -InputObject $rule -Name "Regex" -Default "")
                            WholeRegex  = [string](Get-WmtCleanupObjectValue -InputObject $rule -Name "WholeRegex" -Default "")
                            NRegex      = [string](Get-WmtCleanupObjectValue -InputObject $rule -Name "NRegex" -Default "")
                            NWholeRegex = [string](Get-WmtCleanupObjectValue -InputObject $rule -Name "NWholeRegex" -Default "")
                            Type        = [string](Get-WmtCleanupObjectValue -InputObject $rule -Name "Type" -Default "")
                        })
                }
            }
            elseif ($itemPaths.Count -gt 0 -and -not ($item -is [string])) {
                foreach ($rawRule in $itemPaths) {
                    $rule = ConvertTo-WmtWinapp2PathRule -Rule $rawRule
                    if (-not $rule) { continue }
                    [void]$tasks.Add([PSCustomObject]@{
                            Engine   = "Robust"
                            RuleName = $itemName
                            Path     = [string]$rule.Path
                            Pattern  = [string]$rule.Pattern
                            Recurse  = [bool]$rule.Recurse
                        })
                }
            }
            else {
                switch ($item) {
                    "TempFiles" {
                        [void]$tasks.Add([PSCustomObject]@{ Engine = "Robust"; RuleName = $itemName; Path = $env:TEMP; Pattern = "*"; Recurse = $true })
                        [void]$tasks.Add([PSCustomObject]@{ Engine = "Robust"; RuleName = $itemName; Path = "$env:SystemRoot\Temp"; Pattern = "*"; Recurse = $true })
                    }
                    "RecycleBin" { [void]$tasks.Add([PSCustomObject]@{ Engine = "RecycleBin"; RuleName = $itemName }) }
                    "WER" { [void]$tasks.Add([PSCustomObject]@{ Engine = "Robust"; RuleName = $itemName; Path = "$env:ProgramData\Microsoft\Windows\WER"; Pattern = "*"; Recurse = $true }) }
                    "Thumbnails" { [void]$tasks.Add([PSCustomObject]@{ Engine = "Robust"; RuleName = $itemName; Path = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; Pattern = "thumbcache_*.db"; Recurse = $false }) }
                    "ThumbsDb" { [void]$tasks.Add([PSCustomObject]@{ Engine = "CleanerML"; RuleName = $itemName; Path = $env:USERPROFILE; Search = "deep"; Regex = "^Thumbs\.db(:encryptable)?$"; WholeRegex = ""; NRegex = ""; NWholeRegex = ""; Type = "f" }) }
                    "Recent" { [void]$tasks.Add([PSCustomObject]@{ Engine = "Robust"; RuleName = $itemName; Path = "$env:APPDATA\Microsoft\Windows\Recent"; Pattern = "*"; Recurse = $true }) }
                    "Edge" { [void]$tasks.Add([PSCustomObject]@{ Engine = "Robust"; RuleName = $itemName; Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"; Pattern = "*"; Recurse = $true }) }
                    "Chrome" { [void]$tasks.Add([PSCustomObject]@{ Engine = "Robust"; RuleName = $itemName; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"; Pattern = "*"; Recurse = $true }) }
                    "Brave" { [void]$tasks.Add([PSCustomObject]@{ Engine = "Robust"; RuleName = $itemName; Path = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache"; Pattern = "*"; Recurse = $true }) }
                    "Firefox" {
                        if (Test-Path "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles") {
                            try {
                                foreach ($profilePath in [System.IO.Directory]::EnumerateDirectories("$env:LOCALAPPDATA\Mozilla\Firefox\Profiles")) {
                                    [void]$tasks.Add([PSCustomObject]@{ Engine = "Robust"; RuleName = $itemName; Path = "$profilePath\cache2\entries"; Pattern = "*"; Recurse = $true })
                                }
                            }
                            catch {}
                        }
                    }
                    "Opera" { [void]$tasks.Add([PSCustomObject]@{ Engine = "Robust"; RuleName = $itemName; Path = "$env:APPDATA\Opera Software\Opera Stable\Cache"; Pattern = "*"; Recurse = $true }) }
                    "OperaGX" { [void]$tasks.Add([PSCustomObject]@{ Engine = "Robust"; RuleName = $itemName; Path = "$env:APPDATA\Opera Software\Opera GX Stable\Cache"; Pattern = "*"; Recurse = $true }) }
                }
            }
        }

        return $tasks.ToArray()
    }

    function Invoke-WmtOutOfProcessAnalyze {
        param($ScanTasks)

        $tasks = @($ScanTasks)
        if ($tasks.Count -eq 0) { return }

        $jobScript = {
            param($Task)

            $ErrorActionPreference = "SilentlyContinue"
            $results = [System.Collections.Generic.List[object]]::new()

            function Measure-WorkerPathBytes {
                param([string]$Path)

                try {
                    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
                    if (-not $item.PSIsContainer) { return [int64]$item.Length }

                    $total = [int64]0
                    foreach ($file in @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue)) {
                        try { $total += [int64]$file.Length } catch {}
                    }
                    return $total
                }
                catch { return [int64]0 }
            }

            function Test-WorkerPathStartsWith {
                param(
                    [string]$Path,
                    [string]$Root
                )

                if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }

                try {
                    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd("\")
                    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd("\")
                    return ($fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
                        $fullPath.StartsWith($fullRoot + "\", [System.StringComparison]::OrdinalIgnoreCase))
                }
                catch {
                    return $false
                }
            }

            function Get-WorkerProtectionInfo {
                param(
                    [string]$Path,
                    [System.IO.FileSystemInfo]$ItemInfo = $null
                )

                $reasons = [System.Collections.Generic.List[string]]::new()

                if ([string]::IsNullOrWhiteSpace($Path)) {
                    return [PSCustomObject]@{ IsProtected = $false; Reason = "" }
                }

                try {
                    if (-not $ItemInfo) {
                        $ItemInfo = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
                    }
                }
                catch [System.UnauthorizedAccessException] {
                    [void]$reasons.Add("Access denied")
                }
                catch {
                    if ($_.Exception.Message -match "(?i)access.*denied|unauthorized") {
                        [void]$reasons.Add("Access denied")
                    }
                }

                if ($ItemInfo) {
                    try {
                        $attrs = $ItemInfo.Attributes
                        if (($attrs -band [System.IO.FileAttributes]::System) -eq [System.IO.FileAttributes]::System) {
                            [void]$reasons.Add("System attribute")
                        }

                        $protectedRoots = @(
                            "$env:SystemRoot\Temp",
                            "$env:SystemRoot\System32",
                            "$env:SystemRoot\SysWOW64",
                            "$env:SystemRoot\WinSxS",
                            "$env:SystemRoot\servicing",
                            "$env:SystemRoot\SystemResources",
                            "$env:ProgramFiles\WindowsApps",
                            "$env:ProgramFiles\Windows Defender",
                            "${env:ProgramFiles(x86)}\Windows Defender",
                            "$env:ProgramData\Microsoft\Windows Defender"
                        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

                        $isSystemArea = $false
                        foreach ($root in $protectedRoots) {
                            if (Test-WorkerPathStartsWith -Path $ItemInfo.FullName -Root $root) {
                                $isSystemArea = $true
                                break
                            }
                        }

                        if ($isSystemArea -or (($attrs -band [System.IO.FileAttributes]::System) -eq [System.IO.FileAttributes]::System)) {
                            try {
                                $owner = [string](Get-Acl -LiteralPath $ItemInfo.FullName -ErrorAction Stop).Owner
                                if ($owner -match "(?i)TrustedInstaller|NT AUTHORITY\\SYSTEM|^SYSTEM$") {
                                    [void]$reasons.Add("System-owned")
                                }
                            }
                            catch {
                                if ($_.Exception.Message -match "(?i)access.*denied|unauthorized") {
                                    [void]$reasons.Add("Access denied")
                                }
                            }
                        }

                        if (-not $ItemInfo.PSIsContainer) {
                            $stream = $null
                            try {
                                $stream = [System.IO.File]::Open($ItemInfo.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
                            }
                            catch [System.UnauthorizedAccessException] {
                                [void]$reasons.Add("Access denied")
                            }
                            catch [System.IO.IOException] {
                                [void]$reasons.Add("In use")
                            }
                            catch {}
                            finally {
                                if ($stream) {
                                    try { $stream.Close() } catch {}
                                    try { $stream.Dispose() } catch {}
                                }
                            }
                        }
                    }
                    catch {}
                }

                $reasonText = (@($reasons.ToArray()) | Select-Object -Unique) -join ", "
                return [PSCustomObject]@{
                    IsProtected = -not [string]::IsNullOrWhiteSpace($reasonText)
                    Reason      = $reasonText
                }
            }

            function Add-WorkerTarget {
                param([string]$Path, [string]$RuleName)

                if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return }
                try {
                    $itemInfo = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
                    $size = Measure-WorkerPathBytes -Path $Path
                    $protectionInfo = Get-WorkerProtectionInfo -Path $Path -ItemInfo $itemInfo
                    [void]$results.Add([PSCustomObject]@{
                            RuleName         = $RuleName
                            FilePath         = $Path
                            RawBytes         = $size
                            IsProtected      = [bool]$protectionInfo.IsProtected
                            ProtectionReason = [string]$protectionInfo.Reason
                        })
                }
                catch {}
            }

            function Test-WorkerCleanerMlTargetMatch {
                param($Item, $Rule)

                if (-not $Item) { return $false }
                $type = [string]$Rule.Type
                if ($type -eq "f" -and $Item.PSIsContainer) { return $false }
                if ($type -eq "d" -and -not $Item.PSIsContainer) { return $false }

                $leaf = $Item.Name
                $full = $Item.FullName
                $regexOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase

                try {
                    if ($Rule.Regex -and -not [regex]::IsMatch($leaf, [string]$Rule.Regex, $regexOptions)) { return $false }
                    if ($Rule.WholeRegex -and -not [regex]::IsMatch($full, [string]$Rule.WholeRegex, $regexOptions)) { return $false }
                    if ($Rule.NRegex -and [regex]::IsMatch($leaf, [string]$Rule.NRegex, $regexOptions)) { return $false }
                    if ($Rule.NWholeRegex -and [regex]::IsMatch($full, [string]$Rule.NWholeRegex, $regexOptions)) { return $false }
                }
                catch { return $false }

                return $true
            }

            function Invoke-WorkerRobustScan {
                param($Task)

                $path = [Environment]::ExpandEnvironmentVariables([string]$Task.Path)
                $pathHasWildcard = ($path -match '[\*\?]')
                if (-not $pathHasWildcard -and -not (Test-Path -LiteralPath $path)) { return }

                $patterns = @([string]$Task.Pattern -split ';' | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                if ($patterns.Count -eq 0) { $patterns = @("*") }

                $roots = if ($pathHasWildcard) {
                    @(Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue)
                }
                else {
                    @(Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue)
                }

                foreach ($root in $roots) {
                    if (-not $root) { continue }
                    if (-not $root.PSIsContainer) {
                        foreach ($patternItem in $patterns) {
                            if ($root.Name -like $patternItem) {
                                Add-WorkerTarget -Path $root.FullName -RuleName $Task.RuleName
                                break
                            }
                        }
                    }
                    else {
                        foreach ($patternItem in $patterns) {
                            foreach ($file in @(Get-ChildItem -LiteralPath $root.FullName -Filter $patternItem -File -Recurse:([bool]$Task.Recurse) -Force -ErrorAction SilentlyContinue)) {
                                Add-WorkerTarget -Path $file.FullName -RuleName $Task.RuleName
                            }
                        }
                    }
                }
            }

            function Invoke-WorkerCleanerMlScan {
                param($Task)

                $path = [Environment]::ExpandEnvironmentVariables([string]$Task.Path)
                if ([string]::IsNullOrWhiteSpace($path)) { return }

                $targets = [System.Collections.Generic.List[System.IO.FileSystemInfo]]::new()
                $search = if ($Task.Search) { [string]$Task.Search } else { "file" }

                switch ($search) {
                    "file" {
                        if ($path -match '[\*\?]') {
                            foreach ($target in @(Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue)) {
                                if (Test-WorkerCleanerMlTargetMatch -Item $target -Rule $Task) { [void]$targets.Add($target) }
                            }
                        }
                        elseif (Test-Path -LiteralPath $path) {
                            $target = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
                            if (Test-WorkerCleanerMlTargetMatch -Item $target -Rule $Task) { [void]$targets.Add($target) }
                        }
                    }
                    "glob" {
                        foreach ($target in @(Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue)) {
                            if (Test-WorkerCleanerMlTargetMatch -Item $target -Rule $Task) { [void]$targets.Add($target) }
                        }
                    }
                    "walk.files" {
                        $roots = @(Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue)
                        if ((Test-Path -LiteralPath $path) -and -not ($path -match '[\*\?]')) {
                            $roots = @(Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue)
                        }
                        foreach ($root in $roots) {
                            if (-not $root) { continue }
                            if (-not $root.PSIsContainer) {
                                if (Test-WorkerCleanerMlTargetMatch -Item $root -Rule $Task) { [void]$targets.Add($root) }
                                continue
                            }
                            foreach ($target in @(Get-ChildItem -LiteralPath $root.FullName -File -Recurse -Force -ErrorAction SilentlyContinue)) {
                                if (Test-WorkerCleanerMlTargetMatch -Item $target -Rule $Task) { [void]$targets.Add($target) }
                            }
                        }
                    }
                    "walk.all" {
                        $roots = @(Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue)
                        if ((Test-Path -LiteralPath $path) -and -not ($path -match '[\*\?]')) {
                            $roots = @(Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue)
                        }
                        foreach ($root in $roots) {
                            if (-not $root) { continue }
                            if (Test-WorkerCleanerMlTargetMatch -Item $root -Rule $Task) { [void]$targets.Add($root) }
                            if ($root.PSIsContainer) {
                                foreach ($target in @(Get-ChildItem -LiteralPath $root.FullName -Recurse -Force -ErrorAction SilentlyContinue)) {
                                    if (Test-WorkerCleanerMlTargetMatch -Item $target -Rule $Task) { [void]$targets.Add($target) }
                                }
                            }
                        }
                    }
                    "walk.top" {
                        if (Test-Path -LiteralPath $path) {
                            $root = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
                            if ($root -and (Test-WorkerCleanerMlTargetMatch -Item $root -Rule $Task)) { [void]$targets.Add($root) }
                            if ($root -and $root.PSIsContainer) {
                                foreach ($target in @(Get-ChildItem -LiteralPath $root.FullName -Force -ErrorAction SilentlyContinue)) {
                                    if (Test-WorkerCleanerMlTargetMatch -Item $target -Rule $Task) { [void]$targets.Add($target) }
                                }
                            }
                        }
                    }
                    "deep" {
                        if (Test-Path -LiteralPath $path) {
                            $root = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
                            if ($root -and (Test-WorkerCleanerMlTargetMatch -Item $root -Rule $Task)) { [void]$targets.Add($root) }
                            if ($root -and $root.PSIsContainer) {
                                foreach ($target in @(Get-ChildItem -LiteralPath $root.FullName -Recurse -Force -ErrorAction SilentlyContinue)) {
                                    if (Test-WorkerCleanerMlTargetMatch -Item $target -Rule $Task) { [void]$targets.Add($target) }
                                }
                            }
                        }
                    }
                }

                foreach ($target in @($targets.ToArray() | Sort-Object FullName -Unique)) {
                    Add-WorkerTarget -Path $target.FullName -RuleName $Task.RuleName
                }
            }

            function Invoke-WorkerRecycleBinScan {
                param($Task)

                try {
                    $shell = New-Object -ComObject Shell.Application
                    $bin = $shell.Namespace(0xA)
                    foreach ($f in @($bin.Items())) {
                        try {
                            $path = $f.Path
                            if ($path -and (Test-Path -LiteralPath $path)) {
                                Add-WorkerTarget -Path $path -RuleName $Task.RuleName
                            }
                        }
                        catch {}
                    }
                }
                catch {}
            }

            switch ([string]$Task.Engine) {
                "Robust" { Invoke-WorkerRobustScan -Task $Task }
                "CleanerML" { Invoke-WorkerCleanerMlScan -Task $Task }
                "RecycleBin" { Invoke-WorkerRecycleBinScan -Task $Task }
            }

            return $results.ToArray()
        }

        $maxParallel = [Math]::Max(1, [Math]::Min(4, [Environment]::ProcessorCount))
        $queue = [System.Collections.Generic.Queue[object]]::new()
        foreach ($task in $tasks) { $queue.Enqueue($task) }

        $running = @{}
        $completed = 0
        $total = $tasks.Count
        Write-GuiLog "Analyze scanner: starting $total task(s), up to $maxParallel out-of-process worker(s)."

        while ($queue.Count -gt 0 -or $running.Count -gt 0) {
            while ($queue.Count -gt 0 -and $running.Count -lt $maxParallel) {
                $task = $queue.Dequeue()
                $job = Start-Job -ScriptBlock $jobScript -ArgumentList @($task)
                $running[[int]$job.Id] = [PSCustomObject]@{ Job = $job; Task = $task }
                $pStatus.Text = "Scanning: $($task.RuleName)"
            }

            foreach ($entry in @($running.GetEnumerator())) {
                $job = $entry.Value.Job
                if ($job.State -notin @("Completed", "Failed", "Stopped")) { continue }

                $task = $entry.Value.Task
                $rows = @()
                try { $rows = @(Receive-Job -Job $job -ErrorAction SilentlyContinue) } catch {}
                foreach ($row in $rows) {
                    if (-not $row.FilePath) { continue }
                    $rawBytes = [int64]0
                    try { $rawBytes = [int64]$row.RawBytes } catch {}
                    $previewList.Add([PSCustomObject]@{
                            RuleName         = [string]$row.RuleName
                            FilePath         = [string]$row.FilePath
                            RawBytes         = $rawBytes
                            IsProtected      = [bool]$row.IsProtected
                            ProtectionReason = [string]$row.ProtectionReason
                        })
                    $stats.Deleted++
                    $stats.Bytes += $rawBytes
                }

                try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch {}
                $running.Remove($entry.Key)
                $completed++

                $stats.Progress = (100.0 * $completed / [Math]::Max(1, $total))
                $pBar.Value = [Math]::Min(100, [int]$stats.Progress)
                $mb = [math]::Round($stats.Bytes / 1MB, 2)
                $pLabel.Text = "Found: $($stats.Deleted) | Space: $mb MB"
                $pStatus.Text = "Finished: $($task.RuleName)"
            }

            Invoke-WmtDispatcherPump -Dispatcher $pForm.Dispatcher
            Start-Sleep -Milliseconds 120

            if ($progressState.Closed) {
                foreach ($entry in @($running.GetEnumerator())) {
                    try { Stop-Job -Job $entry.Value.Job -Force -ErrorAction SilentlyContinue } catch {}
                    try { Remove-Job -Job $entry.Value.Job -Force -ErrorAction SilentlyContinue } catch {}
                }
                break
            }
        }
    }

    # 4. MAIN EXECUTION LOOP
    $actionText = if ($isAnalyze) { "Analyzing" } else { "Cleaning" }
    Write-GuiLog "--- Starting $actionText ---"
    $internalRuleDisplayNames = @{
        "TempFiles"  = "Temporary Files"
        "RecycleBin" = "Recycle Bin"
        "WER"        = "Error Logs (WER)"
        "DNS"        = "DNS Cache"
        "Thumbnails" = "Thumbnail / Thumbs Cache"
        "ThumbsDb"   = "Deep Scan: Thumbs.db"
        "Recent"     = "Recent Items"
        "RunMRU"     = "Run History"
        "Edge"       = "Microsoft Edge Cache"
        "Chrome"     = "Google Chrome Cache"
        "Brave"      = "Brave Cache"
        "Firefox"    = "Mozilla Firefox Cache"
        "Opera"      = "Opera Cache"
        "OperaGX"    = "Opera GX Cache"
    }

    $usedOutOfProcessAnalyze = $false
    if ($isAnalyze) {
        try {
            $scanTasks = @(New-WmtAnalyzeScanTasks -Items $selections)
            if ($scanTasks.Count -gt 0) {
                Invoke-WmtOutOfProcessAnalyze -ScanTasks $scanTasks
                $usedOutOfProcessAnalyze = $true
            }
        }
        catch {
            Write-GuiLog "Out-of-process analyzer failed; falling back to in-process scan: $($_.Exception.Message)"
            $usedOutOfProcessAnalyze = $false
        }
    }

    try {
        if (-not $usedOutOfProcessAnalyze) {
            foreach ($item in $selections) {
                if ($progressState.Closed) { break }

                $startBytes = $stats.Bytes

                $stats.Progress += $ruleWeight
                $pBar.Value = [Math]::Min(100, [int]$stats.Progress)

                $itemName = Get-WmtCleanupItemDisplayName -Item $item
                $pLabel.Text = "${actionText}: $itemName"

                $itemPaths = @(Get-WmtCleanupItemPaths -Item $item)

                # --- A. BLEACHBIT CLEANERML RULES ---
                if (Test-WmtCleanupObjectFlag -InputObject $item -Name "IsCleanerML") {
                    foreach ($rule in $itemPaths) {
                        Invoke-CleanerMlClean -Rule $rule -RuleName $itemName
                    }
                }
                # --- B. WINAPP2 RULES ---
                elseif ($itemPaths.Count -gt 0 -and -not ($item -is [string])) {
                    foreach ($rawRule in $itemPaths) {
                        $rule = ConvertTo-WmtWinapp2PathRule -Rule $rawRule
                        if (-not $rule) { continue }
                        Invoke-RobustClean -Path $rule.Path -Pattern $rule.Pattern -Recurse ([bool]$rule.Recurse) -RuleName $itemName
                    }
                }
                # --- C. INTERNAL RULES ---
                else {
                    switch ($item) {
                        "TempFiles" {
                            Invoke-RobustClean $env:TEMP -RuleName $itemName
                            Invoke-RobustClean "$env:SystemRoot\Temp" -RuleName $itemName
                        }
                        "RecycleBin" {
                            try {
                                $shell = New-Object -ComObject Shell.Application
                                $bin = $shell.Namespace(0xA)
                                $items = $bin.Items()
                                $count = $items.Count

                                if ($count -gt 0) {
                                    Write-GuiLog "Recycle Bin: Processing $count items..."
                                    foreach ($f in $items) {
                                        try {
                                            $path = $f.Path
                                            if ($path -and (Test-Path -LiteralPath $path)) {
                                                $size = Measure-WmtPathBytes -Path $path
                                                $stats.Bytes += $size
                                            
                                                if (-not $isAnalyze) {
                                                    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
                                                }
                                                else {
                                                    $protectionInfo = Get-WmtCleanupProtectionInfo -Path $path
                                                    $previewList.Add([PSCustomObject]@{
                                                            RuleName         = "Recycle Bin"
                                                            FilePath         = $path
                                                            RawBytes         = $size
                                                            IsProtected      = [bool]$protectionInfo.IsProtected
                                                            ProtectionReason = [string]$protectionInfo.Reason
                                                        })
                                                }
                                                $stats.Deleted++
                                            }
                                        }
                                        catch {}
                                    }
                                }
                            }
                            catch { Write-GuiLog "Recycle Bin Error: $($_.Exception.Message)" }
                        }
                        "WER" { Invoke-RobustClean "$env:ProgramData\Microsoft\Windows\WER" -RuleName $itemName }
                        "DNS" { if (-not $isAnalyze) { Clear-DnsClientCache -ErrorAction SilentlyContinue } }
                        "Thumbnails" { Invoke-RobustClean "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Pattern "thumbcache_*.db" -Recurse:$false -RuleName $itemName }
                        "ThumbsDb" { Invoke-ThumbsDbDeepScan -RuleName $itemName }
                        "Recent" { Invoke-RobustClean "$env:APPDATA\Microsoft\Windows\Recent" -RuleName $itemName }
                        "RunMRU" { if (-not $isAnalyze) { Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU" -Name * -ErrorAction SilentlyContinue } }
                        "Edge" { Invoke-RobustClean "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache" -RuleName $itemName }
                        "Chrome" { Invoke-RobustClean "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache" -RuleName $itemName }
                        "Brave" { Invoke-RobustClean "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache" -RuleName $itemName }
                        "Firefox" { 
                            if (Test-Path "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles") {
                                try {
                                    foreach ($profilePath in [System.IO.Directory]::EnumerateDirectories("$env:LOCALAPPDATA\Mozilla\Firefox\Profiles")) {
                                        Invoke-RobustClean "$profilePath\cache2\entries" -RuleName $itemName
                                    }
                                }
                                catch {}
                            }
                        }
                        "Opera" { Invoke-RobustClean "$env:APPDATA\Opera Software\Opera Stable\Cache" -RuleName $itemName }
                        "OperaGX" { Invoke-RobustClean "$env:APPDATA\Opera Software\Opera GX Stable\Cache" -RuleName $itemName }
                    }
                }

                $diffBytes = $stats.Bytes - $startBytes
                if ($diffBytes -gt 0) {
                    $itemStr = Format-FileSize $diffBytes
                    $verb = if ($isAnalyze) { "Found" } else { "Cleaned" }
                    Write-GuiLog "$verb $itemName : $itemStr"
                }
            }
        }
    }
    catch {
        Write-GuiLog "Error: $($_.Exception.Message)"
    }
    finally {
        $pForm.Close()
    }

    # 5. FINAL REPORT & PREVIEW
    $finalTotalFormatted = Format-FileSize $stats.Bytes
    
    if ($isAnalyze) {
        Write-GuiLog "Total Found: $finalTotalFormatted"
        
        if ($previewList.Count -gt 0) {
            Show-WmtCleanupPreviewWpf -PreviewList $previewList -FinalTotalFormatted $finalTotalFormatted
            return


        }
        else {
            Show-WmtMessageBox -Message "No files found to clean." -Title "Analysis Results" -Image Information | Out-Null
        }
    }
    else {
        Write-GuiLog "Total Removed: $finalTotalFormatted"
        $msg = "Cleanup Complete.`n`nFiles Removed: $($stats.Deleted)`nSpace Recovered: $finalTotalFormatted"
        Show-WmtMessageBox -Message $msg -Title "Cleanup Results" -Image Information | Out-Null
    }
}

function Expand-ShortcutTarget {
    param([string]$Target)
    if ([string]::IsNullOrWhiteSpace($Target)) { return "" }
    $trimmed = $Target.Trim().Trim('"')
    try { return [System.Environment]::ExpandEnvironmentVariables($trimmed) }
    catch { return $trimmed }
}

function Test-ShortcutTargetIsSpecial {
    param([string]$Target)
    if ([string]::IsNullOrWhiteSpace($Target)) { return $true }
    $trimmed = $Target.Trim().Trim('"')
    if ($trimmed -match '^shell:' -or $trimmed -match '^\s*::{') { return $true }
    if ($trimmed -match '^[a-zA-Z][a-zA-Z0-9+.-]+:' -and $trimmed -notmatch '^[a-zA-Z]:[\\/]') { return $true }
    try {
        if ($trimmed.IndexOfAny([System.IO.Path]::GetInvalidPathChars()) -ge 0) { return $true }
    }
    catch { return $true }
    return $false
}

function Show-BrokenShortcuts {
    $content = @"
    <Grid Margin="16">
        <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <DataGrid Name="dgShortcuts" IsReadOnly="True" SelectionMode="Extended" CanUserAddRows="False" CanUserDeleteRows="False" AlternationCount="2"/>
        <TextBlock Name="lblStatus" Grid.Row="1" Text="Ready." Foreground="{DynamicResource Warning}" Margin="0,10,0,0"/>
        <WrapPanel Grid.Row="2" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button Name="btnDelete" Content="Delete Now" MinWidth="106" Background="{DynamicResource Danger}" Foreground="{DynamicResource DangerText}" Margin="0,0,8,8"/>
            <Button Name="btnBrowse" Content="Browse" MinWidth="92" Margin="0,0,8,8"/>
            <Button Name="btnRescan" Content="Rescan" MinWidth="92" Margin="0,0,8,8"/>
            <Button Name="btnApply" Content="Apply Fixes" MinWidth="112" Background="{DynamicResource Success}" Foreground="{DynamicResource SuccessText}" Margin="0,0,8,8"/>
            <Button Name="btnClose" Content="Close" Width="92" IsCancel="True" Margin="0,0,8,8"/>
        </WrapPanel>
    </Grid>
"@
    $dialog = New-WmtWindowFromXaml -Title "Broken Shortcut Manager" -ContentXaml $content -Width 1220 -Height 720 -MinWidth 940 -MinHeight 560
    $dg = $dialog.FindName("dgShortcuts")
    $lblStatus = $dialog.FindName("lblStatus")
    $btnDelete = $dialog.FindName("btnDelete")
    $btnBrowse = $dialog.FindName("btnBrowse")
    $btnRescan = $dialog.FindName("btnRescan")
    $btnApply = $dialog.FindName("btnApply")
    $btnClose = $dialog.FindName("btnClose")

    $rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $dg.ItemsSource = $rows
    Set-WmtDataGridColumns -DataGrid $dg -Columns @("Shortcut", "Location", "Action", "Details", "BrokenTarget", "NewTarget", "FullPath") -Widths @{ Shortcut = 150; Location = 210; Action = 90; Details = 180; BrokenTarget = "*"; NewTarget = "*" } -Hidden @("FullPath")
    $knownFixes = @{
        "This PC"       = "::{20D04FE0-3AEA-1069-A2D8-08002B30309D}"
        "My Computer"   = "::{20D04FE0-3AEA-1069-A2D8-08002B30309D}"
        "Recycle Bin"   = "::{645FF040-5081-101B-9F08-00AA002F954E}"
        "Control Panel" = "::{21EC2020-3AEA-1069-A2DD-08002B30309D}"
        "Documents"     = "::{450D8FBA-AD25-11D0-98A8-0800361B1103}"
    }

    $getRoots = {
        $roots = [System.Collections.Generic.List[string]]::new()
        $seen = @{}
        $paths = @(
            [Environment]::GetFolderPath('CommonStartMenu'),
            [Environment]::GetFolderPath('StartMenu'),
            [Environment]::GetFolderPath('CommonDesktopDirectory'),
            [Environment]::GetFolderPath('DesktopDirectory'),
            "$env:ProgramData\Microsoft\Windows\Start Menu",
            "$env:APPDATA\Microsoft\Windows\Start Menu",
            "$env:USERPROFILE\Desktop",
            "$env:PUBLIC\Desktop"
        )
        foreach ($pathItem in $paths) {
            if ([string]::IsNullOrWhiteSpace($pathItem) -or -not (Test-Path -LiteralPath $pathItem)) { continue }
            $full = ([System.IO.DirectoryInfo]::new($pathItem)).FullName.TrimEnd("\")
            $key = $full.ToUpperInvariant()
            if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; [void]$roots.Add($full) }
        }
        return @($roots)
    }.GetNewClosure()

    $findAppTarget = {
        param([string]$FileName)
        if ([string]::IsNullOrWhiteSpace($FileName) -or $FileName -notmatch '\.exe$') { return $null }
        foreach ($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryHive]::LocalMachine)) {
            $base = $null
            $key = $null
            try {
                $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, [Microsoft.Win32.RegistryView]::Default)
                $key = $base.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$FileName")
                if ($key) {
                    $candidate = Expand-ShortcutTarget ([string]$key.GetValue(""))
                    if ([System.IO.File]::Exists($candidate)) { return $candidate }
                }
            }
            catch {}
            finally {
                try { if ($key) { $key.Close() } } catch {}
                try { if ($base) { $base.Close() } } catch {}
            }
        }
        foreach ($dir in @(([string]$env:Path).Split(";"))) {
            try {
                $candidate = Join-Path ([Environment]::ExpandEnvironmentVariables($dir.Trim())) $FileName
                if ([System.IO.File]::Exists($candidate)) { return $candidate }
            }
            catch {}
        }
        return $null
    }.GetNewClosure()

    $scan = {
        $rows.Clear()
        $lblStatus.Text = "Scanning shortcuts..."
        Set-WmtBusyCursor -Busy
        $shell = $null
        $scanned = 0
        try {
            $shell = New-Object -ComObject WScript.Shell
            foreach ($root in & $getRoots) {
                $lblStatus.Text = "Scanning $root"
                Invoke-WmtDispatcherPump -Dispatcher $dialog.Dispatcher
                foreach ($lnk in @(Get-ChildItem -LiteralPath $root -Filter *.lnk -Recurse -Force -ErrorAction SilentlyContinue)) {
                    $scanned++
                    try {
                        $sc = $shell.CreateShortcut($lnk.FullName)
                        $target = [string]$sc.TargetPath
                        if (Test-ShortcutTargetIsSpecial $target) { continue }
                        $expanded = Expand-ShortcutTarget $target
                        if ([System.IO.File]::Exists($expanded) -or [System.IO.Directory]::Exists($expanded)) { continue }
                        $action = "None"
                        $details = "Review Needed"
                        $newTarget = ""
                        if ($knownFixes.ContainsKey($lnk.BaseName)) {
                            $action = "Fix"; $details = "Restore System Path"; $newTarget = $knownFixes[$lnk.BaseName]
                        }
                        else {
                            $guess = [System.IO.Path]::GetFileName($expanded)
                            if ([string]::IsNullOrWhiteSpace($guess)) { $guess = "$($lnk.BaseName).exe" }
                            $candidate = & $findAppTarget $guess
                            if ($candidate) { $action = "Fix"; $details = "Located installed app"; $newTarget = $candidate }
                        }
                        [void]$rows.Add([PSCustomObject]@{
                                Shortcut = $lnk.Name; Location = $lnk.DirectoryName; Action = $action; Details = $details
                                BrokenTarget = $target; NewTarget = $newTarget; FullPath = $lnk.FullName
                            })
                    }
                    catch {}
                }
            }
            $lblStatus.Text = "Scan complete. Scanned $scanned shortcut(s); found $($rows.Count)."
            if ($rows.Count -eq 0) { Show-WmtMessageBox -Owner $dialog -Message "Scan complete. No broken shortcuts found." -Title "All Clean" -Image Information | Out-Null }
        }
        catch {
            Show-WmtMessageBox -Owner $dialog -Message "Shortcut scan failed:`n$($_.Exception.Message)" -Title "Scan Failed" -Image Error | Out-Null
        }
        finally {
            try { if ($shell) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) } } catch {}
            Set-WmtBusyCursor
        }
    }.GetNewClosure()

    $selected = { @($dg.SelectedItems | Where-Object { $_ }) }.GetNewClosure()
    $btnBrowse.Add_Click({
            $item = (& $selected | Select-Object -First 1)
            if (-not $item) { return }
            $dlg = [Microsoft.Win32.OpenFileDialog]::new()
            $dlg.Filter = "Programs|*.exe;*.bat;*.cmd;*.lnk|All Files|*.*"
            if ($dlg.ShowDialog() -eq $true) {
                $item.Action = "Fix"
                $item.Details = "Manual Browse"
                $item.NewTarget = $dlg.FileName
                $dg.Items.Refresh()
            }
        }.GetNewClosure())
    $btnDelete.Add_Click({
            $items = & $selected
            if ($items.Count -eq 0) { return }
            if ((Show-WmtMessageBox -Owner $dialog -Message "Permanently delete $($items.Count) selected shortcut(s)?`n`nThis action is immediate." -Title "Confirm Delete" -Button YesNo -Image Warning) -ne [System.Windows.MessageBoxResult]::Yes) { return }
            foreach ($item in $items) {
                try { Remove-Item -LiteralPath ([string]$item.FullPath) -Force -ErrorAction Stop }
                catch { Show-WmtMessageBox -Owner $dialog -Message "Could not delete: $($item.FullPath)`n$($_.Exception.Message)" -Title "Delete Failed" -Image Error | Out-Null }
                [void]$rows.Remove($item)
            }
        }.GetNewClosure())

    $state = @{ Result = $null }
    $btnRescan.Add_Click({ & $scan }.GetNewClosure())
    $btnApply.Add_Click({ $state.Result = @($rows); $dialog.DialogResult = $true }.GetNewClosure())
    $btnClose.Add_Click({ $dialog.Close() }.GetNewClosure())
    $dg.Add_MouseDoubleClick({
            $item = (& $selected | Select-Object -First 1)
            if ($item) {
                Show-TextDialog -Title "Shortcut Details" -Text ("Shortcut: {0}`r`nLocation: {1}`r`nAction: {2}`r`nDetails: {3}`r`nBrokenTarget: {4}`r`nNewTarget: {5}`r`nFullPath: {6}" -f $item.Shortcut, $item.Location, $item.Action, $item.Details, $item.BrokenTarget, $item.NewTarget, $item.FullPath)
            }
        }.GetNewClosure())
    $dialog.Add_ContentRendered({ & $scan }.GetNewClosure())
    $dialog.ShowDialog() | Out-Null
    return $state.Result
}

function Invoke-ShortcutFix {
    $items = Show-BrokenShortcuts
    if (-not $items -or $items.Count -eq 0) { return }

    $toFix = @($items | Where-Object { $_.Action -eq "Fix" -and -not [string]::IsNullOrWhiteSpace([string]$_.FullPath) -and -not [string]::IsNullOrWhiteSpace([string]$_.NewTarget) })

    if ($toFix.Count -eq 0) {
        Show-WmtMessageBox -Message "No fixes were selected.`n`nUse Browse to pick a replacement target, or Delete Now to remove shortcuts immediately." -Title "No Action" -Image Information | Out-Null
        return
    }

    $msg = "You are about to fix $($toFix.Count) shortcut(s)."
    $msg += "`nAre you sure you want to continue?"

    $confirm = Show-WmtMessageBox -Message $msg -Title "Confirm Actions" -Button YesNo -Image Warning
    
    if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

    Invoke-UiCommand {
        param($toFix)
        $shell = $null

        try {
            $shell = New-Object -ComObject WScript.Shell

            foreach ($item in $toFix) {
                try {
                    if (-not [System.IO.File]::Exists([string]$item.FullPath)) { throw "Shortcut file no longer exists." }
                    $newTarget = [string]$item.NewTarget
                    $sc = $shell.CreateShortcut([string]$item.FullPath)
                    $sc.TargetPath = $newTarget

                    if (-not (Test-ShortcutTargetIsSpecial $newTarget)) {
                        $expandedTarget = Expand-ShortcutTarget $newTarget
                        if ([System.IO.File]::Exists($expandedTarget)) {
                            $targetDir = [System.IO.Path]::GetDirectoryName($expandedTarget)
                            if (-not [string]::IsNullOrWhiteSpace($targetDir) -and [System.IO.Directory]::Exists($targetDir)) {
                                $sc.WorkingDirectory = $targetDir
                            }
                        }
                    }

                    $sc.Save()
                    Write-Output "Fixed: $($item.Shortcut) -> $newTarget"
                }
                catch { Write-Output "Failed to fix $($item.Shortcut): $($_.Exception.Message)" }
            }

            Write-Output "Shortcut operation complete."
        }
        finally {
            try { if ($shell) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) } } catch {}
        }

    } "Applying shortcut fixes..." -ArgumentList $toFix
}

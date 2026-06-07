# Functional block generated from WMT-GUI.ps1.
# Dot-source this file; it intentionally shares WMT's script scope.

function Write-GuiLog {
    param($Msg)
    if ($script:LogBox) {
        $script:LogBox.AppendText("[$((Get-Date).ToString('HH:mm'))] $Msg`n")
        try { if ($script:LogBox.LineCount -gt ($script:WmtMaxLogLines + 100)) { Optimize-WmtLogMemory -MaxLines $script:WmtMaxLogLines } } catch {}
        if (-not $script:WmtLogAutoScrollAttached) {
            $script:LogBox.ScrollToEnd()
        }
    }
}

function Write-WmtLastCrash {
    param(
        [string]$Context = "WMT GUI failure",
        [System.Exception]$Exception,
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    try {
        $crashPath = Join-Path (Get-DataPath) "last-crash.txt"
        $exceptionType = if ($Exception) { $Exception.GetType().FullName } else { "Unknown" }
        $message = if ($Exception) { $Exception.Message } else { "No exception details were supplied." }
        $exceptionStackTrace = if ($Exception -and -not [string]::IsNullOrWhiteSpace($Exception.StackTrace)) { $Exception.StackTrace } else { "(not available)" }
        $details = @(
            "Timestamp: $((Get-Date).ToString('o'))"
            "Context: $Context"
            "Exception: $exceptionType"
            "Message: $message"
        )

        if ($ErrorRecord) {
            $details += "PowerShell error ID: $($ErrorRecord.FullyQualifiedErrorId)"
            if (-not [string]::IsNullOrWhiteSpace($ErrorRecord.InvocationInfo.PositionMessage)) {
                $details += "PowerShell position:"
                $details += $ErrorRecord.InvocationInfo.PositionMessage
            }
            if (-not [string]::IsNullOrWhiteSpace($ErrorRecord.ScriptStackTrace)) {
                $details += "PowerShell call stack:"
                $details += $ErrorRecord.ScriptStackTrace
            }
        }

        $details += "Exception stack trace:"
        $details += $exceptionStackTrace

        $inner = if ($Exception) { $Exception.InnerException } else { $null }
        $depth = 1
        while ($inner -and $depth -le 8) {
            $details += ""
            $details += "Inner exception ${depth}: $($inner.GetType().FullName)"
            $details += "Message: $($inner.Message)"
            if (-not [string]::IsNullOrWhiteSpace($inner.StackTrace)) {
                $details += "Stack trace:"
                $details += $inner.StackTrace
            }
            $inner = $inner.InnerException
            $depth++
        }

        [System.IO.File]::WriteAllText($crashPath, ($details -join [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
    }
    catch {}

    try {
        $logMessage = if ($Exception) { $Exception.Message } else { "Unknown error" }
        Write-GuiLog "ERROR: ${Context}: $logMessage"
    }
    catch {}
}

function Optimize-WmtLogMemory {
    param([int]$MaxLines = $script:WmtMaxLogLines)

    try {
        if (-not $script:LogBox) { return }
        if ($MaxLines -lt 50) { $MaxLines = 50 }

        $text = [string]$script:LogBox.Text
        if ([string]::IsNullOrEmpty($text)) { return }
        $lines = $text -split "`r?`n"
        if ($lines.Count -le $MaxLines) { return }

        $keep = $lines | Select-Object -Last $MaxLines
        $script:LogBox.Text = (($keep -join "`r`n").TrimEnd() + "`r`n")
        try { $script:LogBox.ScrollToEnd() } catch {}
    }
    catch {}
}

#requires -Version 5.1
<#
.SYNOPSIS
    Central lifecycle manager for asynchronous WMT PowerShell operations.
.DESCRIPTION
    Dot-source after the application's runspace pool is available. Call
    Update-WmtBackgroundOperations from an existing UI-thread poller. Completion
    callbacks run on the caller's thread. StopAsync is used for cancellation;
    no synchronous worker waits or disposal of active invocations occur.
    The caller owns its polling timer and must continue polling during shutdown.
#>
Set-StrictMode -Version 2.0
if (-not (Get-Variable -Name WmtBackgroundOperationState -Scope Script -ErrorAction SilentlyContinue)) {
    $script:WmtBackgroundOperationState = [hashtable]::Synchronized(@{
        Operations = @{}; NextId = [long]0; ShuttingDown = $false; Log = $null
    })
}
function Initialize-WmtBackgroundOperationManager {
    [CmdletBinding()]
    param([scriptblock]$Log)
    $state = $script:WmtBackgroundOperationState
    [System.Threading.Monitor]::Enter($state.SyncRoot)
    try {
        if ($state.Operations.Count) { throw 'Cannot reinitialize while operations are active.' }
        $state.ShuttingDown = $false; $state.Log = $Log
    } finally { [System.Threading.Monitor]::Exit($state.SyncRoot) }
}
function Write-WmtBackgroundOperationLog {
    param([string]$Message)
    $logger = $script:WmtBackgroundOperationState.Log
    if ($logger -is [scriptblock]) {
        try { & $logger $Message } catch { Write-Verbose "Operation logger failed: $($_.Exception.Message)" }
    } else { Write-Verbose $Message }
}
function Start-WmtBackgroundOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter(Mandatory=$true)][ValidateNotNull()][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [ValidateRange(1,86400)][int]$TimeoutSeconds = 300,
        [System.Management.Automation.Runspaces.RunspacePool]$RunspacePool,
        [scriptblock]$OnCompleted,
        [switch]$AllowDuplicateName
    )
    $state = $script:WmtBackgroundOperationState
    if ($state.ShuttingDown) { throw 'Background-operation manager is shutting down.' }
    $ps = [System.Management.Automation.PowerShell]::Create()
    $async = $null; $id = $null
    try {
        if ($RunspacePool) { $ps.RunspacePool = $RunspacePool }
        [void]$ps.AddScript($ScriptBlock.ToString())
        foreach ($argument in $ArgumentList) { [void]$ps.AddArgument($argument) }
        [System.Threading.Monitor]::Enter($state.SyncRoot)
        try {
            if ($state.ShuttingDown) { throw 'Background-operation manager is shutting down.' }
            if (-not $AllowDuplicateName -and @($state.Operations.Values | Where-Object { $_.Name -eq $Name -and -not $_.CompletionDelivered }).Count) {
                throw "Operation '$Name' is already active."
            }
            $state.NextId = [long]$state.NextId + 1
            $id = 'wmt-op-{0:D8}' -f $state.NextId
        } finally { [System.Threading.Monitor]::Exit($state.SyncRoot) }

        $started = [DateTime]::UtcNow
        $async = $ps.BeginInvoke()
        $record = [pscustomobject]@{
            Id=$id; Name=$Name; PowerShell=$ps; AsyncResult=$async; OnCompleted=$OnCompleted
            StartedUtc=$started; DeadlineUtc=$started.AddSeconds($TimeoutSeconds); TimeoutSeconds=$TimeoutSeconds
            CancelRequested=$false; TimeoutRequested=$false; StopRequestedUtc=$null
            CompletionDelivered=$false; State='Running'; Result=$null; Errors=@(); StopError=$null
        }
        [System.Threading.Monitor]::Enter($state.SyncRoot)
        try {
            if ($state.ShuttingDown) { $record.CancelRequested=$true; $record.State='Cancelling' }
            $state.Operations[$id]=$record
        } finally { [System.Threading.Monitor]::Exit($state.SyncRoot) }
        if ($record.CancelRequested) {
            try { $ps.StopAsync(); $record.StopRequestedUtc=[DateTime]::UtcNow }
            catch { $record.StopError=$_.Exception.Message }
        }
        Write-WmtBackgroundOperationLog ("[{0}/{1}] Started; timeout {2}s." -f $Name,$id,$TimeoutSeconds)
        return $id
    } catch {
        if ($async) {
            # BeginInvoke succeeded; retain ownership until polling observes completion.
            $record = [pscustomobject]@{
                Id=$(if ($id) {$id} else {'wmt-op-unregistered-'+[guid]::NewGuid().ToString('N')})
                Name=$Name; PowerShell=$ps; AsyncResult=$async; OnCompleted=$null
                StartedUtc=[DateTime]::UtcNow; DeadlineUtc=[DateTime]::UtcNow; TimeoutSeconds=$TimeoutSeconds
                CancelRequested=$true; TimeoutRequested=$false; StopRequestedUtc=[DateTime]::UtcNow
                CompletionDelivered=$false; State='Cancelling'; Result=$null; Errors=@(); StopError=$_.Exception.Message
            }
            try { $ps.StopAsync() } catch {}
            [System.Threading.Monitor]::Enter($state.SyncRoot)
            try { $state.Operations[$record.Id]=$record }
            finally { [System.Threading.Monitor]::Exit($state.SyncRoot) }
        } else { try { $ps.Dispose() } catch {} }
        throw
    }
}
function Request-WmtBackgroundOperationCancellation {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Id,[string]$Reason='Cancellation requested')
    $state=$script:WmtBackgroundOperationState
    [System.Threading.Monitor]::Enter($state.SyncRoot)
    try {
        if (-not $state.Operations.ContainsKey($Id)) { return $false }
        $record=$state.Operations[$Id]
        if ($record.CompletionDelivered -or $record.CancelRequested) { return $true }
        $record.CancelRequested=$true; $record.State='Cancelling'
    } finally { [System.Threading.Monitor]::Exit($state.SyncRoot) }
    try {
        $record.PowerShell.StopAsync(); $record.StopRequestedUtc=[DateTime]::UtcNow
        Write-WmtBackgroundOperationLog "[$($record.Name)/$Id] $Reason; async stop requested."
        return $true
    } catch {
        $record.StopError=$_.Exception.Message
        Write-WmtBackgroundOperationLog "[$($record.Name)/$Id] StopAsync failed: $($record.StopError)"
        return $false
    }
}
function Update-WmtBackgroundOperations {
    [CmdletBinding()]
    param()
    $state=$script:WmtBackgroundOperationState; $now=[DateTime]::UtcNow
    [System.Threading.Monitor]::Enter($state.SyncRoot)
    try { $records=@($state.Operations.Values) }
    finally { [System.Threading.Monitor]::Exit($state.SyncRoot) }
    $completed=0
    foreach ($record in $records) {
        if ($record.CompletionDelivered) { continue }
        if (-not $record.CancelRequested -and -not $record.TimeoutRequested -and $now -ge $record.DeadlineUtc) {
            $record.TimeoutRequested=$true; $record.State='TimedOut'
            try {
                $record.PowerShell.StopAsync(); $record.StopRequestedUtc=$now
                Write-WmtBackgroundOperationLog "[$($record.Name)/$($record.Id)] Timed out; async stop requested."
            } catch {
                $record.StopError=$_.Exception.Message
                Write-WmtBackgroundOperationLog "[$($record.Name)/$($record.Id)] Timeout StopAsync failed: $($record.StopError)"
            }
        }
        if (-not $record.AsyncResult.IsCompleted) { continue }
        $result=@(); $errors=@()
        try { $result=@($record.PowerShell.EndInvoke($record.AsyncResult)) } catch { $errors+= $_ }
        try { $errors+= @($record.PowerShell.Streams.Error | ForEach-Object { $_ }) } catch { $errors+= $_ }
        if ($record.TimeoutRequested) { $record.State='TimedOut' }
        elseif ($record.CancelRequested) { $record.State='Cancelled' }
        elseif ($errors.Count -or $record.PowerShell.InvocationStateInfo.State -eq [System.Management.Automation.PSInvocationState]::Failed) { $record.State='Failed' }
        else { $record.State='Completed' }
        $record.Result=$result; $record.Errors=@($errors); $record.CompletionDelivered=$true
        try { $record.PowerShell.Dispose() }
        catch { Write-WmtBackgroundOperationLog "[$($record.Name)/$($record.Id)] Dispose failed: $($_.Exception.Message)" }
        if ($record.OnCompleted -is [scriptblock]) {
            try { & $record.OnCompleted $record }
            catch { Write-WmtBackgroundOperationLog "[$($record.Name)/$($record.Id)] Completion callback failed: $($_.Exception.Message)" }
        }
        [System.Threading.Monitor]::Enter($state.SyncRoot)
        try { [void]$state.Operations.Remove($record.Id) }
        finally { [System.Threading.Monitor]::Exit($state.SyncRoot) }
        Write-WmtBackgroundOperationLog "[$($record.Name)/$($record.Id)] Finished: $($record.State)."
        $completed++
    }
    return $completed
}
function Get-WmtBackgroundOperationSnapshot {
    [CmdletBinding()]
    param()
    $state=$script:WmtBackgroundOperationState
    [System.Threading.Monitor]::Enter($state.SyncRoot)
    try {
        return @($state.Operations.Values | ForEach-Object {
            [pscustomobject]@{
                Id=$_.Id; Name=$_.Name; State=$_.State
                AgeSeconds=[math]::Round(([DateTime]::UtcNow-$_.StartedUtc).TotalSeconds,2)
                TimeoutSeconds=$_.TimeoutSeconds; CancelRequested=$_.CancelRequested
                TimeoutRequested=$_.TimeoutRequested; StopError=$_.StopError
            }
        })
    } finally { [System.Threading.Monitor]::Exit($state.SyncRoot) }
}
function Stop-WmtBackgroundOperationManager {
    [CmdletBinding()]
    param()
    $state=$script:WmtBackgroundOperationState
    [System.Threading.Monitor]::Enter($state.SyncRoot)
    try { $state.ShuttingDown=$true; $ids=@($state.Operations.Keys) }
    finally { [System.Threading.Monitor]::Exit($state.SyncRoot) }
    foreach ($id in $ids) { [void](Request-WmtBackgroundOperationCancellation -Id $id -Reason 'Application shutdown') }
    return $ids.Count
}

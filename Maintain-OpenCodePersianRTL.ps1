param(
    [Parameter(Mandatory)]
    [string]$AppAsar,

    [ValidateRange(5, 3600)]
    [int]$PollSeconds = 15,

    [ValidateRange(0, 300)]
    [int]$StartupDelaySeconds = 30,

    [switch]$Once,

    [switch]$SkipRestart
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$marker = "opencode-persian-rtl"
$installer = Join-Path $PSScriptRoot "Install-OpenCodePersianRTL.ps1"
$logPath = Join-Path $PSScriptRoot "maintenance.log"
$pendingPath = Join-Path $PSScriptRoot "update-pending.json"
$AppAsar = [System.IO.Path]::GetFullPath($AppAsar)
$metadataPath = "$AppAsar.$marker.json"
$appExecutable = Join-Path (Split-Path -Parent (Split-Path -Parent $AppAsar)) "OpenCode.exe"
$pathHasher = [System.Security.Cryptography.SHA256]::Create()
try {
    $pathBytes = [System.Text.Encoding]::UTF8.GetBytes($AppAsar.ToUpperInvariant())
    $installationId = ([System.BitConverter]::ToString($pathHasher.ComputeHash($pathBytes))).Replace("-", "").Substring(0, 12)
}
finally {
    $pathHasher.Dispose()
}
$failedArchiveHash = $null
$preflightFailedHash = $null
$preflightRetryAfter = [datetime]::MinValue

function Write-MaintenanceLog {
    param([Parameter(Mandatory)][string]$Message)

    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message`r`n"
    try {
        if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 1048576) {
            [System.IO.File]::WriteAllText($logPath, "", [System.Text.UTF8Encoding]::new($false))
        }
        [System.IO.File]::AppendAllText($logPath, $line, [System.Text.UTF8Encoding]::new($false))
    }
    catch {
        # Logging must never stop maintenance.
    }
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Test-PatchIsCurrent {
    if (-not (Test-Path -LiteralPath $AppAsar -PathType Leaf) -or
        -not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        return $false
    }

    try {
        $metadata = [System.IO.File]::ReadAllText($metadataPath) | ConvertFrom-Json
        return $metadata.schema -eq 1 -and
            $metadata.state -eq "installed" -and
            $metadata.patchedSha256 -and
            (Get-Sha256 -Path $AppAsar) -eq $metadata.patchedSha256
    }
    catch {
        return $false
    }
}

function Get-StableArchiveHash {
    if (-not (Test-Path -LiteralPath $AppAsar -PathType Leaf)) {
        return $null
    }

    try {
        $observedHash = Get-Sha256 -Path $AppAsar
        for ($sample = 0; $sample -lt 2; $sample++) {
            Start-Sleep -Seconds 5
            if (-not (Test-Path -LiteralPath $AppAsar -PathType Leaf) -or
                (Get-Sha256 -Path $AppAsar) -ne $observedHash) {
                return $null
            }
        }
        return $observedHash
    }
    catch {
        return $null
    }
}

function Get-OpenCodeProcesses {
    return @(Get-Process -Name "OpenCode" -ErrorAction SilentlyContinue | Where-Object {
        try {
            $_.Path -and [System.IO.Path]::GetFullPath($_.Path).Equals(
                [System.IO.Path]::GetFullPath($appExecutable),
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }
        catch {
            $false
        }
    })
}

function Read-PendingUpdate {
    if (-not (Test-Path -LiteralPath $pendingPath -PathType Leaf)) {
        return $null
    }
    try {
        $record = [System.IO.File]::ReadAllText($pendingPath) | ConvertFrom-Json
        if (-not $record.archiveSha256) {
            throw "Missing archive hash."
        }
        return $record
    }
    catch {
        [System.IO.File]::Delete($pendingPath)
        return $null
    }
}

function Write-PendingUpdate {
    param(
        [Parameter(Mandatory)][string]$ArchiveHash,
        [Parameter(Mandatory)][bool]$Restart
    )

    $temporary = "$pendingPath.new"
    $json = @{
        archiveSha256 = $ArchiveHash
        restart = $Restart
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText($temporary, $json, [System.Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $pendingPath) {
        [System.IO.File]::Replace($temporary, $pendingPath, $null, $true)
    }
    else {
        [System.IO.File]::Move($temporary, $pendingPath)
    }
}

function Start-OpenCodeIfRequested {
    param([Parameter(Mandatory)][bool]$Restart)

    if (-not $Restart -or $SkipRestart -or @(Get-OpenCodeProcesses).Count -gt 0) {
        return $true
    }
    if (-not (Test-Path -LiteralPath $appExecutable -PathType Leaf)) {
        Write-MaintenanceLog "The patch succeeded, but the OpenCode executable was not found."
        return $false
    }
    try {
        Start-Process -FilePath $appExecutable
        Write-MaintenanceLog "OpenCode was restarted with the updated Persian RTL patch."
        return $true
    }
    catch {
        Write-MaintenanceLog "The patch succeeded, but OpenCode could not start; restart will be retried: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-Maintenance {
    if (-not (Test-Path -LiteralPath $AppAsar -PathType Leaf)) {
        return
    }

    $pending = Read-PendingUpdate
    if (Test-PatchIsCurrent) {
        $script:failedArchiveHash = $null
        if ($pending -and (Start-OpenCodeIfRequested -Restart ([bool]$pending.restart))) {
            [System.IO.File]::Delete($pendingPath)
        }
        return
    }

    $currentHash = Get-Sha256 -Path $AppAsar
    if ($script:failedArchiveHash -and $currentHash -eq $script:failedArchiveHash) {
        return
    }
    if ($script:failedArchiveHash -and $currentHash -ne $script:failedArchiveHash) {
        $script:failedArchiveHash = $null
    }
    if ($script:preflightFailedHash -and $currentHash -eq $script:preflightFailedHash -and
        (Get-Date) -lt $script:preflightRetryAfter) {
        return
    }
    if ($script:preflightFailedHash -and
        ($currentHash -ne $script:preflightFailedHash -or (Get-Date) -ge $script:preflightRetryAfter)) {
        $script:preflightFailedHash = $null
    }

    $pendingMatches = $pending -and $pending.archiveSha256 -eq $currentHash
    if (-not $pendingMatches) {
        $stableHash = Get-StableArchiveHash
        if (-not $stableHash) {
            Write-MaintenanceLog "The application archive is missing or still changing; retrying later."
            return
        }
        if (-not (Test-Path -LiteralPath $installer -PathType Leaf) -or
            -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "node_modules\.bin\asar.cmd") -PathType Leaf)) {
            $script:failedArchiveHash = $stableHash
            Write-MaintenanceLog "The prepared maintenance runtime is incomplete; automatic retries are paused for this app version."
            return
        }

        try {
            & $installer -Action Preflight -AppAsar $AppAsar | Out-Null
            if (-not $?) {
                throw "Compatibility preflight returned an unsuccessful status."
            }
        }
        catch {
            $script:preflightFailedHash = $stableHash
            $script:preflightRetryAfter = (Get-Date).AddMinutes(10)
            Write-MaintenanceLog "Compatibility preflight failed; retrying in ten minutes: $($_.Exception.Message)"
            return
        }
        if ((Get-Sha256 -Path $AppAsar) -ne $stableHash) {
            Write-MaintenanceLog "The application changed after compatibility preflight; retrying later."
            return
        }

        $restart = @(Get-OpenCodeProcesses).Count -gt 0
        Write-PendingUpdate -ArchiveHash $stableHash -Restart $restart
        $pending = Read-PendingUpdate
        $currentHash = $stableHash
        if ($restart) {
            Write-MaintenanceLog "A compatible OpenCode update is ready. Waiting for OpenCode to close normally before patching."
            return
        }
    }

    if (@(Get-OpenCodeProcesses).Count -gt 0) {
        return
    }

    $restartAfterPatch = $pending -and [bool]$pending.restart
    try {
        Write-MaintenanceLog "Applying the Persian RTL patch while OpenCode is closed."
        # OpenCode may relaunch itself after maintenance observes a clean shutdown.
        # The installer still uses atomic replacement and verifies every hash.
        & $installer -Action Install -AppAsar $AppAsar -SkipFontInstall -SkipProcessCheck
        if (-not $?) {
            throw "The installer returned an unsuccessful status."
        }
        Write-MaintenanceLog "The Persian RTL patch was applied successfully."
        if (Start-OpenCodeIfRequested -Restart $restartAfterPatch) {
            [System.IO.File]::Delete($pendingPath)
        }
    }
    catch {
        $script:failedArchiveHash = if (Test-Path -LiteralPath $AppAsar -PathType Leaf) {
            Get-Sha256 -Path $AppAsar
        } else {
            $currentHash
        }
        Write-MaintenanceLog "Patch failed; automatic retries are paused for this app version: $($_.Exception.Message)"
        if ($restartAfterPatch -and @(Get-OpenCodeProcesses).Count -eq 0 -and
            (Test-Path -LiteralPath $appExecutable -PathType Leaf)) {
            Start-Process -FilePath $appExecutable
            Write-MaintenanceLog "OpenCode was restarted without the patch after maintenance failed."
        }
    }
}

function Invoke-WithMaintenanceLock {
    $mutex = New-Object System.Threading.Mutex($false, "Local\OpenCodePersianRTLMaintenance-$installationId")
    $hasMutex = $false
    try {
        try {
            $hasMutex = $mutex.WaitOne(0)
        }
        catch [System.Threading.AbandonedMutexException] {
            $hasMutex = $true
        }
        if ($hasMutex) {
            Invoke-Maintenance
        }
    }
    finally {
        if ($hasMutex) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

Write-MaintenanceLog "Automatic maintenance started."
if ($StartupDelaySeconds -gt 0) {
    Start-Sleep -Seconds $StartupDelaySeconds
}

do {
    try {
        Invoke-WithMaintenanceLock
    }
    catch {
        Write-MaintenanceLog "Unexpected maintenance error: $($_.Exception.Message)"
    }

    if (-not $Once) {
        Start-Sleep -Seconds $PollSeconds
    }
} while (-not $Once)

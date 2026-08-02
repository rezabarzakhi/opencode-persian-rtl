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
$preparedArchive = "$AppAsar.$marker.prepared"
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

function Get-UnpackedFingerprint {
    $root = "$AppAsar.unpacked"
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        return "none"
    }

    $prefixLength = $root.TrimEnd("\", "/").Length + 1
    $builder = New-Object System.Text.StringBuilder
    foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse | Sort-Object FullName) {
        $relativePath = $file.FullName.Substring($prefixLength).Replace("\", "/")
        [void]$builder.Append($relativePath).Append("|").Append((Get-Sha256 -Path $file.FullName)).Append("`n")
    }

    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
        return ([System.BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace("-", "")
    }
    finally {
        $hasher.Dispose()
    }
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
        if (-not $record.sourceSha256 -or -not $record.patchedSha256 -or
            -not $record.patchVersion -or -not $record.unpackedFingerprint) {
            throw "Missing prepared update data."
        }
        return $record
    }
    catch {
        [System.IO.File]::Delete($pendingPath)
        return $null
    }
}

function Write-PendingUpdate {
    param([Parameter(Mandatory)][hashtable]$Record)

    $temporary = "$pendingPath.new"
    $json = $Record | ConvertTo-Json
    [System.IO.File]::WriteAllText($temporary, $json, [System.Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $pendingPath) {
        $oldPending = "$pendingPath.old"
        if (Test-Path -LiteralPath $oldPending) {
            [System.IO.File]::Delete($oldPending)
        }
        [System.IO.File]::Replace($temporary, $pendingPath, $oldPending, $true)
        [System.IO.File]::Delete($oldPending)
    }
    else {
        [System.IO.File]::Move($temporary, $pendingPath)
    }
}

function Write-AppMetadata {
    param(
        [Parameter(Mandatory)]$Pending,
        [Parameter(Mandatory)][ValidateSet("pending", "installed")][string]$State
    )

    $temporary = "$metadataPath.new"
    $json = @{
        schema = 1
        state = $State
        patchVersion = $Pending.patchVersion
        originalSha256 = $Pending.sourceSha256
        patchedSha256 = $Pending.patchedSha256
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText($temporary, $json, [System.Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $metadataPath) {
        $oldMetadata = "$metadataPath.old"
        if (Test-Path -LiteralPath $oldMetadata) {
            [System.IO.File]::Delete($oldMetadata)
        }
        [System.IO.File]::Replace($temporary, $metadataPath, $oldMetadata, $true)
        [System.IO.File]::Delete($oldMetadata)
    }
    else {
        [System.IO.File]::Move($temporary, $metadataPath)
    }
}

function Prepare-PatchedArchive {
    param(
        [Parameter(Mandatory)][string]$SourceHash,
        [Parameter(Mandatory)][string]$UnpackedFingerprint,
        [Parameter(Mandatory)][bool]$Restart
    )

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("$marker-prepare-" + [guid]::NewGuid())
    $tempArchive = Join-Path $tempRoot "app.asar"
    [System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
    try {
        [System.IO.File]::Copy($AppAsar, $tempArchive, $true)
        if (Test-Path -LiteralPath "$AppAsar.unpacked" -PathType Container) {
            Copy-Item -LiteralPath "$AppAsar.unpacked" -Destination "$tempArchive.unpacked" -Recurse
        }

        & $installer -Action Install -AppAsar $tempArchive -SkipFontInstall
        if (-not $?) {
            throw "The preparation installer returned an unsuccessful status."
        }
        if ((Get-Sha256 -Path $AppAsar) -ne $SourceHash) {
            throw "OpenCode changed while the patched archive was being prepared."
        }
        if ((Get-UnpackedFingerprint) -ne $UnpackedFingerprint) {
            throw "OpenCode's unpacked files changed while the patched archive was being prepared."
        }

        $tempMetadataPath = "$tempArchive.$marker.json"
        $tempMetadata = [System.IO.File]::ReadAllText($tempMetadataPath) | ConvertFrom-Json
        $patchedHash = Get-Sha256 -Path $tempArchive
        if ($tempMetadata.state -ne "installed" -or $tempMetadata.patchedSha256 -ne $patchedHash -or
            $tempMetadata.originalSha256 -ne $SourceHash) {
            throw "The prepared archive failed metadata verification."
        }

        [System.IO.File]::Copy($tempArchive, $preparedArchive, $true)
        if ((Get-Sha256 -Path $preparedArchive) -ne $patchedHash) {
            throw "The staged prepared archive failed hash verification."
        }
        Write-PendingUpdate -Record @{
            sourceSha256 = $SourceHash
            patchedSha256 = $patchedHash
            patchVersion = $tempMetadata.patchVersion
            unpackedFingerprint = $UnpackedFingerprint
            restart = $Restart
        }
        return Read-PendingUpdate
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

function Commit-PreparedArchive {
    param([Parameter(Mandatory)]$Pending)

    $currentHash = Get-Sha256 -Path $AppAsar
    $backupPath = "$AppAsar.$marker.backup"
    if ($currentHash -eq $Pending.patchedSha256) {
        if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf) -or
            (Get-Sha256 -Path $backupPath) -ne $Pending.sourceSha256) {
            throw "The prepared patch was committed without a valid backup. Manual repair is required."
        }
        if ((Get-UnpackedFingerprint) -ne $Pending.unpackedFingerprint) {
            throw "The unpacked files changed during prepared patch recovery."
        }
        Write-AppMetadata -Pending $Pending -State "installed"
        return
    }
    if ($currentHash -ne $Pending.sourceSha256) {
        throw "OpenCode changed after the patched archive was prepared."
    }
    if (-not (Test-Path -LiteralPath $preparedArchive -PathType Leaf) -or
        (Get-Sha256 -Path $preparedArchive) -ne $Pending.patchedSha256) {
        throw "The prepared archive is missing or invalid."
    }

    Write-AppMetadata -Pending $Pending -State "pending"
    if (Test-Path -LiteralPath $backupPath) {
        [System.IO.File]::Delete($backupPath)
    }
    if (@(Get-OpenCodeProcesses).Count -gt 0) {
        throw "OpenCode restarted before the prepared patch could be committed."
    }
    if ((Get-Sha256 -Path $AppAsar) -ne $Pending.sourceSha256) {
        throw "OpenCode changed immediately before the prepared patch commit."
    }
    if ((Get-UnpackedFingerprint) -ne $Pending.unpackedFingerprint) {
        throw "OpenCode's unpacked files changed before the prepared patch commit."
    }
    [System.IO.File]::Replace($preparedArchive, $AppAsar, $backupPath, $true)
    if ((Get-Sha256 -Path $AppAsar) -ne $Pending.patchedSha256 -or
        (Get-Sha256 -Path $backupPath) -ne $Pending.sourceSha256) {
        throw "The prepared archive failed post-commit verification."
    }
    Write-AppMetadata -Pending $Pending -State "installed"
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

    $pendingMatches = $pending -and (
        $pending.sourceSha256 -eq $currentHash -or $pending.patchedSha256 -eq $currentHash
    )
    if ($pendingMatches -and $pending.sourceSha256 -eq $currentHash -and
        (-not (Test-Path -LiteralPath $preparedArchive -PathType Leaf) -or
            (Get-Sha256 -Path $preparedArchive) -ne $pending.patchedSha256)) {
        [System.IO.File]::Delete($pendingPath)
        $pending = $null
        $pendingMatches = $false
    }
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
        try {
            Write-MaintenanceLog "Preparing the Persian RTL patch in the background."
            $unpackedFingerprint = Get-UnpackedFingerprint
            $pending = Prepare-PatchedArchive `
                -SourceHash $stableHash `
                -UnpackedFingerprint $unpackedFingerprint `
                -Restart $restart
            Write-MaintenanceLog "The patched archive is prepared and verified."
        }
        catch {
            $script:failedArchiveHash = $stableHash
            Write-MaintenanceLog "Patch preparation failed; automatic retries are paused for this app version: $($_.Exception.Message)"
            return
        }
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
        Write-MaintenanceLog "Committing the prepared Persian RTL patch while OpenCode is closed."
        Commit-PreparedArchive -Pending $pending
        Write-MaintenanceLog "The Persian RTL patch was applied successfully."
        if (Start-OpenCodeIfRequested -Restart $restartAfterPatch) {
            [System.IO.File]::Delete($pendingPath)
        }
    }
    catch {
        Write-MaintenanceLog "Prepared patch commit was deferred and will be retried: $($_.Exception.Message)"
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

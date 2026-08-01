param(
    [ValidateSet("Install", "Restore", "Preflight", "EnableAutoMaintenance", "DisableAutoMaintenance")]
    [string]$Action = "Install",

    [string]$AppAsar,

    [switch]$SkipFontInstall,

    [switch]$SkipProcessCheck
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion -lt [version]"5.1") {
    throw "PowerShell 5.1 or newer is required."
}
if ($env:OS -ne "Windows_NT") {
    throw "This installer currently supports Windows only."
}

$marker = "opencode-persian-rtl"
$patchVersion = "1.1.0"
$fontHash = "696249A2C74B39FFDEF55DE4DF2809C5B639D3FF80D618D8160A095D2FD49DCA"
$fontUrl = "https://raw.githubusercontent.com/google/fonts/6f9713a50c628d79f60259319d05fa0a239a9a7f/ofl/vazirmatn/Vazirmatn%5Bwght%5D.ttf"
$asarCommand = Join-Path $PSScriptRoot "node_modules\.bin\asar.cmd"

function Resolve-AppAsar {
    if ($AppAsar) {
        $fullPath = [System.IO.Path]::GetFullPath($AppAsar)
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            return (Get-Item -LiteralPath $fullPath).FullName
        }
        return $fullPath
    }

    $candidates = @(@(
        (Join-Path $env:LOCALAPPDATA "Programs\@opencode-aidesktop\resources\app.asar"),
        (Join-Path $env:LOCALAPPDATA "Programs\OpenCode\resources\app.asar"),
        (Join-Path $env:LOCALAPPDATA "Programs\opencode\resources\app.asar")
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })

    if ($candidates.Count -eq 1) {
        return $candidates[0]
    }

    if ($candidates.Count -gt 1) {
        throw "Multiple OpenCode installations were found. Pass the intended app.asar path with -AppAsar."
    }

    throw "OpenCode app.asar was not found in a known installation directory. Pass its path with -AppAsar."
}

$AppAsar = Resolve-AppAsar
$backup = "$AppAsar.$marker.backup"
$metadataPath = "$AppAsar.$marker.json"
$pathHasher = [System.Security.Cryptography.SHA256]::Create()
try {
    $pathBytes = [System.Text.Encoding]::UTF8.GetBytes($AppAsar.ToUpperInvariant())
    $installationId = ([System.BitConverter]::ToString($pathHasher.ComputeHash($pathBytes))).Replace("-", "").Substring(0, 12)
}
finally {
    $pathHasher.Dispose()
}
$maintenanceTaskPath = "\OpenCodePersianRTL\"
$maintenanceTaskName = "Maintenance-$installationId"
$maintenanceRoot = Join-Path $env:LOCALAPPDATA "OpenCodePersianRTL\$installationId"
$expectedOpenCodeExecutable = Join-Path (Split-Path -Parent (Split-Path -Parent $AppAsar)) "OpenCode.exe"

function Assert-OpenCodeIsClosed {
    if ($SkipProcessCheck) {
        return
    }

    $matchingProcesses = @(Get-Process -Name "OpenCode" -ErrorAction SilentlyContinue | Where-Object {
        try {
            $_.Path -and [System.IO.Path]::GetFullPath($_.Path).Equals(
                [System.IO.Path]::GetFullPath($expectedOpenCodeExecutable),
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }
        catch {
            $false
        }
    })
    if ($matchingProcesses.Count -gt 0) {
        throw "Close OpenCode completely, then run this installer again."
    }
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Install-Vazirmatn {
    if ($SkipFontInstall) {
        return
    }

    $fontDirectory = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    [System.IO.Directory]::CreateDirectory($fontDirectory) | Out-Null

    $fontPath = Join-Path $fontDirectory "OpenCodePersianRTL-Vazirmatn.ttf"
    if (Test-Path -LiteralPath $fontPath -PathType Leaf) {
        if ((Get-Sha256 -Path $fontPath) -ne $fontHash) {
            throw "A different file already uses the patch's font filename. It was not overwritten."
        }
    }
    else {
        $fontTemp = "$fontPath.download"
        if (Test-Path -LiteralPath $fontTemp) {
            [System.IO.File]::Delete($fontTemp)
        }

        $previousProtocol = [System.Net.ServicePointManager]::SecurityProtocol
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = $previousProtocol -bor [System.Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $fontUrl -OutFile $fontTemp -UseBasicParsing
        }
        finally {
            [System.Net.ServicePointManager]::SecurityProtocol = $previousProtocol
        }

        if ((Get-Sha256 -Path $fontTemp) -ne $fontHash) {
            [System.IO.File]::Delete($fontTemp)
            throw "The Vazirmatn download failed integrity verification."
        }

        [System.IO.File]::Move($fontTemp, $fontPath)
    }

    $fontRegistry = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
    $fontRegistryName = "Vazirmatn OpenCode Persian RTL (TrueType)"
    $existingRegistration = Get-ItemProperty -LiteralPath $fontRegistry -Name $fontRegistryName -ErrorAction SilentlyContinue
    if ($existingRegistration -and $existingRegistration.$fontRegistryName -ne $fontPath) {
        throw "A different font registration already uses the patch's registry name. It was not overwritten."
    }
    New-ItemProperty `
        -Path $fontRegistry `
        -Name $fontRegistryName `
        -Value $fontPath `
        -PropertyType String `
        -Force | Out-Null
}

function Initialize-Asar {
    if (Test-Path -LiteralPath $asarCommand -PathType Leaf) {
        return
    }

    $packageJson = Join-Path $PSScriptRoot "package.json"
    $packageLock = Join-Path $PSScriptRoot "package-lock.json"
    if (-not (Test-Path -LiteralPath $packageJson -PathType Leaf) -or
        -not (Test-Path -LiteralPath $packageLock -PathType Leaf)) {
        throw "The required package.json and package-lock.json files are missing."
    }

    $npm = Get-Command "npm.cmd" -ErrorAction SilentlyContinue
    $node = Get-Command "node.exe" -ErrorAction SilentlyContinue
    if (-not $npm -or -not $node) {
        throw "Node.js 22.12 or newer with npm is required."
    }
    $nodeVersion = [version](& $node.Source -p "process.versions.node")
    if ($nodeVersion -lt [version]"22.12.0") {
        throw "Node.js 22.12 or newer is required. The installed version is $nodeVersion."
    }

    & $npm.Source ci --ignore-scripts --no-audit --no-fund --prefix $PSScriptRoot | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $asarCommand -PathType Leaf)) {
        throw "The locked Electron ASAR dependency could not be installed."
    }
}

function Invoke-Asar {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    Initialize-Asar
    $output = & $asarCommand $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "asar $Command failed with exit code $LASTEXITCODE."
    }

    return $output
}

function Get-UnpackedEntries {
    param([Parameter(Mandatory)][string]$Archive)

    $paths = foreach ($line in @(Invoke-Asar -Command "list" -Arguments @("--is-pack", $Archive))) {
        if ($line -match '^unpack\s*:\s*[\\/](.+)$') {
            $Matches[1].Replace("\", "/")
        }
    }

    return @($paths | Sort-Object -Unique)
}

function Get-UnpackedFileHashes {
    param(
        [Parameter(Mandatory)][string]$Archive,
        [Parameter(Mandatory)][string[]]$Entries
    )

    $result = @{}
    $unpackedRoot = "$Archive.unpacked"
    foreach ($entry in $Entries) {
        $path = Join-Path $unpackedRoot ($entry.Replace("/", "\"))
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $result[$entry] = Get-Sha256 -Path $path
        }
    }
    return $result
}

function Assert-HashMapMatches {
    param(
        [Parameter(Mandatory)][hashtable]$Expected,
        [Parameter(Mandatory)][hashtable]$Actual,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Expected.Count -ne $Actual.Count) {
        throw $Message
    }
    foreach ($key in $Expected.Keys) {
        if (-not $Actual.ContainsKey($key) -or $Actual[$key] -ne $Expected[$key]) {
            throw $Message
        }
    }
}

function Get-UnpackExpression {
    param([Parameter(Mandatory)][string[]]$Paths)

    if ($Paths.Count -eq 0) {
        return $null
    }

    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($path in $Paths | Sort-Object Length) {
        $covered = $false
        foreach ($root in $roots) {
            if ($path -eq $root -or $path.StartsWith("$root/", [System.StringComparison]::Ordinal)) {
                $covered = $true
                break
            }
        }

        if (-not $covered) {
            $roots.Add($path)
        }
    }

    $patterns = @($roots | ForEach-Object { "**/$_/**" })
    if ($patterns.Count -eq 1) {
        return $patterns[0]
    }

    return "{" + ($patterns -join ",") + "}"
}

function Find-RendererIndex {
    param([Parameter(Mandatory)][string]$Root)

    $indexPath = Join-Path $Root "out\renderer\index.html"
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        throw "The expected OpenCode renderer index was not found. This app version is not supported."
    }

    $packagePath = Join-Path $Root "package.json"
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
        throw "The OpenCode package manifest was not found."
    }
    $package = [System.IO.File]::ReadAllText($packagePath) | ConvertFrom-Json
    if ($package.name -ne "@opencode-ai/desktop" -or -not $package.version) {
        throw "The selected archive is not a supported OpenCode Desktop package."
    }

    $html = [System.IO.File]::ReadAllText($indexPath)
    $bodyClosings = [regex]::Matches($html, "</body>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $html.Contains('id="root"') -or $bodyClosings.Count -ne 1) {
        throw "The OpenCode renderer structure is not supported by this patch version."
    }

    $rendererRoot = Split-Path -Parent $indexPath
    $hasMarkdownSelector = $false
    $hasUserMessageSelector = $false
    foreach ($asset in Get-ChildItem -LiteralPath $rendererRoot -File -Recurse -Include "*.css", "*.js") {
        $content = [System.IO.File]::ReadAllText($asset.FullName)
        $hasMarkdownSelector = $hasMarkdownSelector -or $content.Contains('data-component="markdown"')
        $hasUserMessageSelector = $hasUserMessageSelector -or $content.Contains('data-slot="user-message-text"')
        if ($hasMarkdownSelector -and $hasUserMessageSelector) {
            break
        }
    }
    if (-not $hasMarkdownSelector -or -not $hasUserMessageSelector) {
        throw "The required OpenCode chat renderer selectors were not found."
    }

    return $indexPath
}

function Read-InstallMetadata {
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw "The patch metadata file is missing. Restore or repair OpenCode before continuing."
    }
    $metadata = [System.IO.File]::ReadAllText($metadataPath) | ConvertFrom-Json
    if ($metadata.schema -ne 1 -or -not $metadata.state -or
        -not $metadata.originalSha256 -or -not $metadata.patchedSha256) {
        throw "The patch metadata is invalid. Restore or repair OpenCode before continuing."
    }
    return $metadata
}

function Get-Injection {
    return @'
    <!-- opencode-persian-rtl -->
    <style id="opencode-persian-rtl-style">
      :root {
        --font-family-sans: "Vazirmatn", ui-sans-serif, system-ui, sans-serif !important;
        --font-family-text: "Vazirmatn", "Inter", sans-serif !important;
        --v2-font-family-sans: "Vazirmatn", "Inter", sans-serif !important;
      }
      [data-oc-auto-direction="rtl"] {
        direction: rtl;
        text-align: right;
        unicode-bidi: plaintext;
      }
      [data-oc-auto-direction="ltr"] {
        direction: ltr;
        text-align: left;
        unicode-bidi: plaintext;
      }
      [data-component="markdown"] pre,
      [data-component="markdown"] code {
        direction: ltr;
        text-align: left;
        unicode-bidi: isolate;
      }
    </style>
    <script id="opencode-persian-rtl-script">
      (() => {
        const persian = /[\u0600-\u06ff\u0750-\u077f\u0870-\u089f\u08a0-\u08ff\ufb50-\ufdff\ufe70-\ufefc\u{1ee00}-\u{1eeff}]/u;
        const blocks = [
          '[data-component="markdown"] p',
          '[data-component="markdown"] h1',
          '[data-component="markdown"] h2',
          '[data-component="markdown"] h3',
          '[data-component="markdown"] h4',
          '[data-component="markdown"] h5',
          '[data-component="markdown"] h6',
          '[data-component="markdown"] li',
          '[data-component="markdown"] blockquote',
          '[data-component="markdown"] td',
          '[data-component="markdown"] th',
          '[data-slot="user-message-text"]'
        ].join(',');
        let queued = false;
        const updateDirections = () => {
          queued = false;
          document.querySelectorAll(blocks).forEach((element) => {
            if (element.closest('pre, [data-component="markdown-code"]')) return;
            const direction = persian.test(element.textContent || '') ? 'rtl' : 'ltr';
            if (element.dataset.ocAutoDirection === direction) return;
            element.dataset.ocAutoDirection = direction;
            element.dir = direction;
          });
        };
        const scheduleUpdate = () => {
          if (queued) return;
          queued = true;
          requestAnimationFrame(updateDirections);
        };
        new MutationObserver(scheduleUpdate).observe(document.body, {
          childList: true,
          characterData: true,
          subtree: true
        });
        scheduleUpdate();
      })();
    </script>
'@
}

function Write-Metadata {
    param([Parameter(Mandatory)][hashtable]$Metadata)

    $temporaryMetadata = "$metadataPath.new"
    $json = $Metadata | ConvertTo-Json
    [System.IO.File]::WriteAllText($temporaryMetadata, $json, [System.Text.UTF8Encoding]::new($false))

    if (Test-Path -LiteralPath $metadataPath) {
        $oldMetadata = "$metadataPath.old"
        if (Test-Path -LiteralPath $oldMetadata) {
            [System.IO.File]::Delete($oldMetadata)
        }
        [System.IO.File]::Replace($temporaryMetadata, $metadataPath, $oldMetadata, $true)
        [System.IO.File]::Delete($oldMetadata)
    }
    else {
        [System.IO.File]::Move($temporaryMetadata, $metadataPath)
    }
}

function Invoke-WithMaintenanceLock {
    param([Parameter(Mandatory)][scriptblock]$Operation)

    $mutex = New-Object System.Threading.Mutex($false, "Local\OpenCodePersianRTLMaintenance-$installationId")
    $hasMutex = $false
    try {
        try {
            $hasMutex = $mutex.WaitOne([TimeSpan]::FromMinutes(2))
        }
        catch [System.Threading.AbandonedMutexException] {
            $hasMutex = $true
        }
        if (-not $hasMutex) {
            throw "Automatic maintenance is busy. Try again after the current operation finishes."
        }
        & $Operation
    }
    finally {
        if ($hasMutex) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

function Get-MaintenanceTask {
    Import-Module ScheduledTasks -ErrorAction Stop
    return Get-ScheduledTask -TaskPath $maintenanceTaskPath -TaskName $maintenanceTaskName -ErrorAction SilentlyContinue
}

function Get-MaintenanceCommand {
    $monitor = Join-Path $maintenanceRoot "Maintain-OpenCodePersianRTL.ps1"
    $powershell = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    $arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$monitor`" -AppAsar `"$AppAsar`""
    return @{
        Execute = $powershell
        Arguments = $arguments
    }
}

function Assert-MaintenanceTaskOwned {
    param([Parameter(Mandatory)]$Task)

    $expected = Get-MaintenanceCommand
    $actions = @($Task.Actions)
    if ($actions.Count -ne 1 -or
        -not [System.IO.Path]::GetFullPath($actions[0].Execute).Equals(
            [System.IO.Path]::GetFullPath($expected.Execute),
            [System.StringComparison]::OrdinalIgnoreCase
        ) -or
        -not $actions[0].Arguments.Equals($expected.Arguments, [System.StringComparison]::Ordinal)) {
        throw "The scheduled task with this installation ID is not owned by this patch and was left unchanged."
    }
}

function Stop-MaintenanceTask {
    param([Parameter(Mandatory)]$Task)

    Assert-MaintenanceTaskOwned -Task $Task
    Stop-ScheduledTask -TaskPath $maintenanceTaskPath -TaskName $maintenanceTaskName -ErrorAction Stop
    $deadline = (Get-Date).AddSeconds(30)
    do {
        $current = Get-ScheduledTask -TaskPath $maintenanceTaskPath -TaskName $maintenanceTaskName -ErrorAction Stop
        if ($current.State -ne "Running") {
            return
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw "The existing maintenance task did not stop safely."
}

function Disable-AutoMaintenance {
    Invoke-WithMaintenanceLock {
        $existingTask = Get-MaintenanceTask
        if (-not $existingTask) {
            Write-Host "Automatic Persian RTL maintenance is already disabled."
            return
        }

        Stop-MaintenanceTask -Task $existingTask
        Unregister-ScheduledTask -TaskPath $maintenanceTaskPath -TaskName $maintenanceTaskName -Confirm:$false -ErrorAction Stop
        Write-Host "Automatic Persian RTL maintenance was disabled."
    }
}

function Enable-AutoMaintenance {
    Invoke-WithMaintenanceLock {
        Import-Module ScheduledTasks -ErrorAction Stop
        $sourceFiles = @(
            "Install-OpenCodePersianRTL.ps1",
            "Maintain-OpenCodePersianRTL.ps1",
            "package.json",
            "package-lock.json"
        )
        foreach ($file in $sourceFiles) {
            $source = Join-Path $PSScriptRoot $file
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
                throw "Automatic maintenance requires the missing file: $file"
            }
        }

        $stageRoot = "$maintenanceRoot.stage-$([guid]::NewGuid())"
        $oldRoot = "$maintenanceRoot.old-$([guid]::NewGuid())"
        $existingTask = $null
        $taskRegistrationAttempted = $false
        [System.IO.Directory]::CreateDirectory($stageRoot) | Out-Null
        try {
            foreach ($file in $sourceFiles) {
                [System.IO.File]::Copy((Join-Path $PSScriptRoot $file), (Join-Path $stageRoot $file), $true)
            }

            $npm = Get-Command "npm.cmd" -ErrorAction SilentlyContinue
            $node = Get-Command "node.exe" -ErrorAction SilentlyContinue
            if (-not $npm -or -not $node -or [version](& $node.Source -p "process.versions.node") -lt [version]"22.12.0") {
                throw "Node.js 22.12 or newer with npm is required before automatic maintenance can be enabled."
            }
            & $npm.Source ci --ignore-scripts --no-audit --no-fund --prefix $stageRoot | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $stageRoot "node_modules\.bin\asar.cmd") -PathType Leaf)) {
                throw "The locked maintenance runtime could not be prepared."
            }

            $existingTask = Get-MaintenanceTask
            if ($existingTask) {
                Stop-MaintenanceTask -Task $existingTask
            }

            if (Test-Path -LiteralPath $maintenanceRoot) {
                [System.IO.Directory]::Move($maintenanceRoot, $oldRoot)
            }
            [System.IO.Directory]::Move($stageRoot, $maintenanceRoot)

            $command = Get-MaintenanceCommand
            $action = New-ScheduledTaskAction -Execute $command.Execute -Argument $command.Arguments
            $userId = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
            $principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
            $settings = New-ScheduledTaskSettingsSet `
                -AllowStartIfOnBatteries `
                -DontStopIfGoingOnBatteries `
                -StartWhenAvailable `
                -MultipleInstances IgnoreNew `
                -RestartCount 3 `
                -RestartInterval (New-TimeSpan -Minutes 1) `
                -ExecutionTimeLimit ([TimeSpan]::Zero)

            $taskRegistrationAttempted = $true
            Register-ScheduledTask `
                -TaskPath $maintenanceTaskPath `
                -TaskName $maintenanceTaskName `
                -Action $action `
                -Trigger $trigger `
                -Principal $principal `
                -Settings $settings `
                -Description "Reapplies Persian RTL support after OpenCode Desktop updates." `
                -Force | Out-Null
            Start-ScheduledTask -TaskPath $maintenanceTaskPath -TaskName $maintenanceTaskName

            if (Test-Path -LiteralPath $oldRoot) {
                [System.IO.Directory]::Delete($oldRoot, $true)
            }
            Write-Host "Automatic Persian RTL maintenance was enabled."
            Write-Host "OpenCode will be patched and restarted automatically after compatible updates."
        }
        catch {
            if (-not $existingTask -and $taskRegistrationAttempted) {
                Unregister-ScheduledTask -TaskPath $maintenanceTaskPath -TaskName $maintenanceTaskName -Confirm:$false -ErrorAction SilentlyContinue
            }
            if (Test-Path -LiteralPath $oldRoot) {
                if (Test-Path -LiteralPath $maintenanceRoot) {
                    [System.IO.Directory]::Delete($maintenanceRoot, $true)
                }
                [System.IO.Directory]::Move($oldRoot, $maintenanceRoot)
            }
            elseif ($taskRegistrationAttempted -and (Test-Path -LiteralPath $maintenanceRoot)) {
                [System.IO.Directory]::Delete($maintenanceRoot, $true)
            }
            if ($existingTask) {
                Start-ScheduledTask -TaskPath $maintenanceTaskPath -TaskName $maintenanceTaskName -ErrorAction SilentlyContinue
            }
            throw
        }
        finally {
            if (Test-Path -LiteralPath $stageRoot) {
                [System.IO.Directory]::Delete($stageRoot, $true)
            }
        }
    }
}

function Test-PatchPreflight {
    if (-not (Test-Path -LiteralPath $AppAsar -PathType Leaf)) {
        throw "OpenCode app.asar was not found at: $AppAsar"
    }

    $unpackedEntries = @(Get-UnpackedEntries -Archive $AppAsar)
    if ($unpackedEntries.Count -gt 0 -and -not (Test-Path -LiteralPath "$AppAsar.unpacked" -PathType Container)) {
        throw "OpenCode's app.asar.unpacked directory is missing. Repair the OpenCode installation first."
    }

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("$marker-preflight-" + [guid]::NewGuid())
    $extracted = Join-Path $tempRoot "extracted"
    [System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
    try {
        Invoke-Asar -Command "extract" -Arguments @($AppAsar, $extracted) | Out-Null
        $indexPath = Find-RendererIndex -Root $extracted
        $html = [System.IO.File]::ReadAllText($indexPath)
        if ($html.Contains('id="opencode-persian-rtl-style"') -or
            $html.Contains('id="opencode-persian-rtl-script"') -or
            $html.Contains("<!-- $marker -->")) {
            throw "The renderer already contains a complete or partial Persian RTL patch with invalid restore state."
        }
        Write-Host "OpenCode passed the Persian RTL compatibility preflight."
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

function Install-Patch {
    if (-not (Test-Path -LiteralPath $AppAsar -PathType Leaf)) {
        throw "OpenCode app.asar was not found at: $AppAsar"
    }

    $unpackedDirectory = "$AppAsar.unpacked"
    $originalHash = Get-Sha256 -Path $AppAsar
    $originalUnpackedEntries = @(Get-UnpackedEntries -Archive $AppAsar)
    if ($originalUnpackedEntries.Count -gt 0 -and -not (Test-Path -LiteralPath $unpackedDirectory -PathType Container)) {
        throw "OpenCode's app.asar.unpacked directory is missing. Repair the OpenCode installation first."
    }
    $originalUnpackedHashes = Get-UnpackedFileHashes -Archive $AppAsar -Entries $originalUnpackedEntries

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("$marker-" + [guid]::NewGuid())
    $extracted = Join-Path $tempRoot "extracted"
    $validation = Join-Path $tempRoot "validation"
    $patchedArchive = Join-Path $tempRoot "app.asar"
    $stagedArchive = "$AppAsar.$marker.new"
    [System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null

    try {
        Invoke-Asar -Command "extract" -Arguments @($AppAsar, $extracted) | Out-Null
        $indexPath = Find-RendererIndex -Root $extracted
        $html = [System.IO.File]::ReadAllText($indexPath)
        $hasStyle = $html.Contains('id="opencode-persian-rtl-style"')
        $hasScript = $html.Contains('id="opencode-persian-rtl-script"')

        if ($hasStyle -and $hasScript) {
            if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
                throw "The patch is installed, but its backup is missing. Repair OpenCode before continuing."
            }
            $metadata = Read-InstallMetadata
            if ($metadata.state -ne "installed" -or
                (Get-Sha256 -Path $AppAsar) -ne $metadata.patchedSha256 -or
                (Get-Sha256 -Path $backup) -ne $metadata.originalSha256) {
                throw "The installed patch or its restore data failed integrity verification."
            }
            Write-Host "OpenCode Persian RTL is already installed."
            return
        }

        if ($hasStyle -or $hasScript -or $html.Contains("<!-- $marker -->")) {
            throw "A partial or unsupported Persian RTL patch was found. Restore or repair OpenCode before continuing."
        }

        $closingBody = [regex]::Match($html, "</body>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $patchedHtml = $html.Insert($closingBody.Index, "$(Get-Injection)`r`n  ")
        [System.IO.File]::WriteAllText($indexPath, $patchedHtml, [System.Text.UTF8Encoding]::new($false))

        $packArguments = New-Object System.Collections.Generic.List[string]
        $unpackExpression = $null
        if ($originalUnpackedEntries.Count -gt 0) {
            $unpackExpression = Get-UnpackExpression -Paths $originalUnpackedEntries
            $packArguments.Add("--unpack")
            $packArguments.Add($unpackExpression)
        }
        $packArguments.Add($extracted)
        $packArguments.Add($patchedArchive)

        Invoke-Asar -Command "pack" -Arguments $packArguments.ToArray() | Out-Null
        $patchedUnpackedHashes = Get-UnpackedFileHashes -Archive $patchedArchive -Entries $originalUnpackedEntries
        Assert-HashMapMatches `
            -Expected $originalUnpackedHashes `
            -Actual $patchedUnpackedHashes `
            -Message "The patched archive did not preserve OpenCode's unpacked-file contents."
        Invoke-Asar -Command "extract" -Arguments @($patchedArchive, $validation) | Out-Null

        $validationIndex = Find-RendererIndex -Root $validation
        $validatedHtml = [System.IO.File]::ReadAllText($validationIndex)
        if (-not $validatedHtml.Contains('id="opencode-persian-rtl-style"') -or
            -not $validatedHtml.Contains('id="opencode-persian-rtl-script"')) {
            throw "The patched archive failed renderer validation. The installed app was not changed."
        }

        $patchedHash = Get-Sha256 -Path $patchedArchive
        [System.IO.File]::Copy($patchedArchive, $stagedArchive, $true)
        if ((Get-Sha256 -Path $stagedArchive) -ne $patchedHash) {
            throw "The staged archive failed integrity verification."
        }

        Assert-OpenCodeIsClosed
        if ((Get-Sha256 -Path $AppAsar) -ne $originalHash) {
            throw "OpenCode changed while the patch was being prepared. Nothing was installed; run the installer again."
        }
        $currentUnpackedHashes = Get-UnpackedFileHashes -Archive $AppAsar -Entries $originalUnpackedEntries
        Assert-HashMapMatches `
            -Expected $originalUnpackedHashes `
            -Actual $currentUnpackedHashes `
            -Message "OpenCode's unpacked files changed while the patch was being prepared. Nothing was installed."

        try {
            Install-Vazirmatn
        }
        catch {
            Write-Warning "Vazirmatn could not be installed without overwriting an existing file: $($_.Exception.Message)"
        }

        Assert-OpenCodeIsClosed
        if ((Get-Sha256 -Path $AppAsar) -ne $originalHash) {
            throw "OpenCode changed before the final replacement. Nothing was installed; run the installer again."
        }

        if (Test-Path -LiteralPath $backup) {
            [System.IO.File]::Delete($backup)
        }

        Write-Metadata -Metadata @{
            schema = 1
            state = "pending"
            patchVersion = $patchVersion
            originalSha256 = $originalHash
            patchedSha256 = $patchedHash
        }

        [System.IO.File]::Replace($stagedArchive, $AppAsar, $backup, $true)
        if ((Get-Sha256 -Path $AppAsar) -ne $patchedHash -or (Get-Sha256 -Path $backup) -ne $originalHash) {
            throw "Post-install integrity verification failed. Use -Action Restore before opening OpenCode."
        }

        Write-Metadata -Metadata @{
            schema = 1
            state = "installed"
            patchVersion = $patchVersion
            originalSha256 = $originalHash
            patchedSha256 = $patchedHash
        }

        Write-Host "OpenCode Persian RTL was installed successfully."
        Write-Host "Restart OpenCode to apply the changes."
    }
    finally {
        if (Test-Path -LiteralPath $stagedArchive) {
            [System.IO.File]::Delete($stagedArchive)
        }
        if (Test-Path -LiteralPath $tempRoot) {
            [System.IO.Directory]::Delete($tempRoot, $true)
        }
    }
}

function Get-ValidatedRestoreMetadata {
    if (-not (Test-Path -LiteralPath $backup -PathType Leaf) -or
        -not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw "A complete backup and metadata pair was not found. Repair or reinstall OpenCode instead."
    }

    $metadata = Read-InstallMetadata
    if ($metadata.state -ne "installed" -and $metadata.state -ne "pending") {
        throw "The backup metadata has an unsupported transaction state."
    }

    $currentHash = Get-Sha256 -Path $AppAsar
    if ($currentHash -ne $metadata.patchedSha256) {
        throw "OpenCode changed after this patch was installed. Restore was stopped to avoid downgrading or corrupting the app."
    }

    if ((Get-Sha256 -Path $backup) -ne $metadata.originalSha256) {
        throw "The OpenCode backup failed integrity verification."
    }

    return $metadata
}

function Restore-Original {
    $metadata = Get-ValidatedRestoreMetadata

    $stagedRestore = "$AppAsar.$marker.restore"
    $discardedPatch = "$AppAsar.$marker.patched"
    try {
        [System.IO.File]::Copy($backup, $stagedRestore, $true)
        if (Test-Path -LiteralPath $discardedPatch) {
            [System.IO.File]::Delete($discardedPatch)
        }
        [System.IO.File]::Replace($stagedRestore, $AppAsar, $discardedPatch, $true)
        if ((Get-Sha256 -Path $AppAsar) -ne $metadata.originalSha256) {
            throw "Restore integrity verification failed."
        }

        [System.IO.File]::Delete($backup)
        [System.IO.File]::Delete($metadataPath)
        [System.IO.File]::Delete($discardedPatch)
        Write-Host "The original OpenCode interface was restored."
        Write-Host "Vazirmatn remains installed for the current Windows user."
        Write-Host "Restart OpenCode to apply the changes."
    }
    finally {
        if (Test-Path -LiteralPath $stagedRestore) {
            [System.IO.File]::Delete($stagedRestore)
        }
    }
}

function Invoke-WithInstallerLock {
    param([Parameter(Mandatory)][scriptblock]$Operation)

    $mutex = New-Object System.Threading.Mutex($false, "Local\OpenCodePersianRTLInstaller")
    $hasMutex = $false
    try {
        try {
            $hasMutex = $mutex.WaitOne(0)
        }
        catch [System.Threading.AbandonedMutexException] {
            $hasMutex = $true
        }
        if (-not $hasMutex) {
            throw "Another OpenCode Persian RTL installer is already running."
        }
        & $Operation
    }
    finally {
        if ($hasMutex) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

switch ($Action) {
    "Install" {
        Invoke-WithInstallerLock {
            Assert-OpenCodeIsClosed
            Install-Patch
        }
    }
    "Preflight" {
        Invoke-WithInstallerLock {
            Test-PatchPreflight
        }
    }
    "Restore" {
        Invoke-WithMaintenanceLock {
            Assert-OpenCodeIsClosed
            [void](Get-ValidatedRestoreMetadata)
            $task = Get-MaintenanceTask
            $taskXml = $null
            if ($task) {
                Assert-MaintenanceTaskOwned -Task $task
                $taskXml = Export-ScheduledTask -TaskPath $maintenanceTaskPath -TaskName $maintenanceTaskName -ErrorAction Stop
                Stop-MaintenanceTask -Task $task
                Unregister-ScheduledTask -TaskPath $maintenanceTaskPath -TaskName $maintenanceTaskName -Confirm:$false -ErrorAction Stop
            }
            try {
                Invoke-WithInstallerLock {
                    Restore-Original
                }
            }
            catch {
                if ($taskXml) {
                    Register-ScheduledTask -TaskPath $maintenanceTaskPath -TaskName $maintenanceTaskName -Xml $taskXml -Force | Out-Null
                    Start-ScheduledTask -TaskPath $maintenanceTaskPath -TaskName $maintenanceTaskName -ErrorAction SilentlyContinue
                }
                throw
            }
            if ($taskXml) {
                Write-Host "Automatic Persian RTL maintenance was disabled."
            }
        }
    }
    "EnableAutoMaintenance" {
        Enable-AutoMaintenance
    }
    "DisableAutoMaintenance" {
        Disable-AutoMaintenance
    }
}

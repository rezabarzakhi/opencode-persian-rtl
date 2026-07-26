$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $projectRoot "Install-OpenCodePersianRTL.ps1"
$asarCommand = Join-Path $projectRoot "node_modules\.bin\asar.cmd"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("opencode-persian-rtl-test-" + [guid]::NewGuid())
$source = Join-Path $testRoot "source"
$renderer = Join-Path $source "out\renderer"
$nativeDirectory = Join-Path $source "node_modules\native"
$archive = Join-Path $testRoot "app.asar"
$originalLocalAppData = $env:LOCALAPPDATA

function Invoke-TestAsar {
    param([string[]]$Arguments)

    & $asarCommand @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Test ASAR command failed: $($Arguments -join ' ')"
    }
}

try {
    [System.IO.Directory]::CreateDirectory($renderer) | Out-Null
    [System.IO.Directory]::CreateDirectory($nativeDirectory) | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $source "package.json"),
        '{"name":"@opencode-ai/desktop","version":"1.18.5"}'
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $renderer "index.html"),
        '<!doctype html><html><body><div id="root"></div></body></html>'
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $renderer "fixture.css"),
        '[data-component="markdown"] {} [data-slot="user-message-text"] {}'
    )
    [System.IO.File]::WriteAllText((Join-Path $nativeDirectory "fixture.node"), "native fixture")

    Invoke-TestAsar -Arguments @(
        "pack",
        "--unpack-dir",
        "node_modules/native",
        $source,
        $archive
    )

    $originalListing = & $asarCommand list --is-pack $archive
    if (-not ($originalListing -match 'unpack\s*:\s*[\\/]node_modules[\\/]native[\\/]fixture\.node')) {
        throw "The test fixture did not create an unpacked native file."
    }

    $originalHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    $env:LOCALAPPDATA = Join-Path $testRoot "local-app-data"
    $fontDirectory = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    [System.IO.Directory]::CreateDirectory($fontDirectory) | Out-Null
    $fontCollision = Join-Path $fontDirectory "OpenCodePersianRTL-Vazirmatn.ttf"
    [System.IO.File]::WriteAllText($fontCollision, "do not overwrite")

    & $installer -AppAsar $archive -SkipProcessCheck
    if (-not $?) {
        throw "Installer test failed."
    }
    if ([System.IO.File]::ReadAllText($fontCollision) -ne "do not overwrite") {
        throw "The installer overwrote an existing font collision."
    }

    $listing = & $asarCommand list --is-pack $archive
    if (-not ($listing -match 'unpack\s*:\s*[\\/]node_modules[\\/]native[\\/]fixture\.node')) {
        throw "The unpacked native fixture was not preserved."
    }

    $validation = Join-Path $testRoot "validation"
    Invoke-TestAsar -Arguments @("extract", $archive, $validation)
    $patchedHtml = [System.IO.File]::ReadAllText((Join-Path $validation "out\renderer\index.html"))
    if (-not $patchedHtml.Contains('id="opencode-persian-rtl-style"') -or
        -not $patchedHtml.Contains('id="opencode-persian-rtl-script"')) {
        throw "The renderer injection was not found."
    }

    & $installer -AppAsar $archive -SkipFontInstall -SkipProcessCheck
    if (-not $?) {
        throw "Idempotency test failed."
    }

    $metadata = "$archive.opencode-persian-rtl.json"
    $metadataHold = "$metadata.test-hold"
    [System.IO.File]::Move($metadata, $metadataHold)
    $missingMetadataWasBlocked = $false
    try {
        & $installer -AppAsar $archive -SkipFontInstall -SkipProcessCheck
    }
    catch {
        $missingMetadataWasBlocked = $_.Exception.Message.Contains("metadata file is missing")
    }
    finally {
        [System.IO.File]::Move($metadataHold, $metadata)
    }
    if (-not $missingMetadataWasBlocked) {
        throw "Idempotency did not reject missing restore metadata."
    }

    $patchedCopy = Join-Path $testRoot "patched.asar"
    [System.IO.File]::Copy($archive, $patchedCopy)
    $stream = [System.IO.File]::Open($archive, [System.IO.FileMode]::Append)
    try {
        $stream.WriteByte(0)
    }
    finally {
        $stream.Dispose()
    }

    $unsafeRestoreWasBlocked = $false
    try {
        & $installer -Action Restore -AppAsar $archive -SkipFontInstall -SkipProcessCheck
    }
    catch {
        $unsafeRestoreWasBlocked = $_.Exception.Message.Contains("changed after this patch")
    }
    if (-not $unsafeRestoreWasBlocked) {
        throw "Restore did not block a changed application archive."
    }
    [System.IO.File]::Copy($patchedCopy, $archive, $true)

    & $installer -Action Restore -AppAsar $archive -SkipFontInstall -SkipProcessCheck
    if (-not $?) {
        throw "Restore test failed."
    }

    $restoredHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    if ($restoredHash -ne $originalHash) {
        throw "The restored archive does not match the original SHA-256 hash."
    }

    Write-Host "PASS: install, unpacked content, renderer, font collision, idempotency, restore-data guard, stale-restore guard, restore, and SHA-256 checks."
}
finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    if (Test-Path -LiteralPath $testRoot) {
        [System.IO.Directory]::Delete($testRoot, $true)
    }
}

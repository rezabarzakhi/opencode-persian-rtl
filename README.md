<p align="center">
  <img src="assets/banner.svg" alt="OpenCode Persian RTL" width="900">
</p>

<h1 align="center">OpenCode Persian RTL</h1>

<p align="center">
  Per-block bidirectional chat layout and a polished Persian font for OpenCode Desktop.
</p>

<p align="center">
  <a href="README.fa.md">فارسی</a>
  ·
  <a href="#install">Install</a>
  ·
  <a href="#safety">Safety</a>
  ·
  <a href="#restore">Restore</a>
</p>

[![Platform](https://img.shields.io/badge/platform-Windows-0078D4?logo=windows)](https://www.microsoft.com/windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell)](https://learn.microsoft.com/powershell/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Checks](https://github.com/rezabarzakhi/opencode-persian-rtl/actions/workflows/check.yml/badge.svg)](https://github.com/rezabarzakhi/opencode-persian-rtl/actions/workflows/check.yml)
[![Release](https://img.shields.io/github/v/release/rezabarzakhi/opencode-persian-rtl?color=7C3AED)](https://github.com/rezabarzakhi/opencode-persian-rtl/releases/latest)

Automatic Persian and Arabic-script direction detection plus the Vazirmatn font for [OpenCode Desktop](https://opencode.ai/) on Windows.

> [!IMPORTANT]
> This is an unofficial renderer patch. It is not affiliated with OpenCode. Optional automatic maintenance can reapply it after compatible OpenCode updates.

## Why

Mixed Persian and Latin chat text can be difficult to read when the entire chat surface uses one fixed direction. This patch evaluates each supported text block independently:

| Content | Result |
| --- | --- |
| Contains Persian or Arabic-script characters | Right-to-left, right-aligned |
| Latin-only text | Left-to-right, left-aligned |
| Markdown code | Always left-to-right |

It also installs [Vazirmatn](https://github.com/rastikerdar/vazirmatn) for the current Windows user and uses it for the OpenCode interface.

## Safety

The installer is intentionally defensive:

- Preserves and verifies Electron ASAR unpacked-file content.
- Validates the rebuilt renderer before changing OpenCode.
- Replaces the application archive atomically.
- Records SHA-256 hashes for both the original and patched archives.
- Refuses unsafe restore attempts after OpenCode has changed or updated.
- Pins and verifies the downloaded Vazirmatn font.
- Installs dependencies from an exact npm lockfile with lifecycle scripts disabled.
- Rechecks the application immediately before replacement to detect concurrent updates.
- Avoids duplicate or partial patch installation.

## Compatibility

| Component | Supported |
| --- | --- |
| Operating system | Windows 10 and Windows 11 |
| OpenCode | Desktop app using the current Electron renderer layout |
| Tested OpenCode version | 1.18.10 |
| PowerShell | Windows PowerShell 5.1 or newer |
| Node.js | 22.12 or newer with npm |

The patch uses private renderer selectors. A future OpenCode release can change them. Unsupported renderer layouts fail safely before the installed application is modified.

## Install

1. Download this repository and extract it.
2. Close every OpenCode window.
3. Open PowerShell in the extracted directory.
4. Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-OpenCodePersianRTL.ps1
```

5. Start OpenCode again.

The installer checks these common per-user installation paths automatically:

```text
%LOCALAPPDATA%\Programs\@opencode-aidesktop\resources\app.asar
%LOCALAPPDATA%\Programs\OpenCode\resources\app.asar
%LOCALAPPDATA%\Programs\opencode\resources\app.asar
```

For a different location:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-OpenCodePersianRTL.ps1 -AppAsar "C:\path\to\resources\app.asar"
```

To keep the current interface font:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-OpenCodePersianRTL.ps1 -SkipFontInstall
```

## Automatic Update Maintenance

Enable the optional background maintenance task:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-OpenCodePersianRTL.ps1 -Action EnableAutoMaintenance
```

The task runs only for the current Windows user. When an OpenCode update replaces the patched archive, it waits for the new archive to become stable, asks OpenCode to close normally, reapplies the patch, and restarts the app. It never force-terminates OpenCode; if the app does not close normally, maintenance retries later.

Disable automatic maintenance without changing the current patch:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-OpenCodePersianRTL.ps1 -Action DisableAutoMaintenance
```

## Restore

Close OpenCode, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-OpenCodePersianRTL.ps1 -Action Restore
```

Restore only proceeds when the installed archive and backup match their recorded hashes. It disables automatic maintenance first so the patch is not reapplied. Vazirmatn remains installed because other applications may be using it.

## Updates

OpenCode updates normally replace the patched archive. Enable automatic maintenance to reapply it, or close OpenCode and run the installer manually. Do not restore a backup created for an older OpenCode version; the installer blocks this automatically.

## What It Changes

The installer modifies:

```text
<OpenCode resources>\app.asar
%LOCALAPPDATA%\Microsoft\Windows\Fonts\OpenCodePersianRTL-Vazirmatn.ttf
HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts
```

It creates these files next to the application archive:

```text
app.asar.opencode-persian-rtl.backup
app.asar.opencode-persian-rtl.json
```

Automatic maintenance also creates a scheduled task and stores its runtime here:

```text
%LOCALAPPDATA%\OpenCodePersianRTL
Task Scheduler\OpenCode Persian RTL Maintenance
```

## Troubleshooting

### OpenCode is running

Close all OpenCode windows and check Task Manager for any remaining OpenCode process.

### OpenCode was not found

Locate the application's `resources\app.asar` file and pass it with `-AppAsar`.

### Restore was stopped

OpenCode changed after the patch was installed. Reinstall or repair OpenCode instead of forcing an old backup over a newer version.

### The patch disappeared after an update

Enable automatic maintenance or run the installer again. The installer treats the updated archive as a new clean version and creates a matching backup. Maintenance details are written to:

```text
%LOCALAPPDATA%\OpenCodePersianRTL\maintenance.log
```

## Development

Install the exact locked dependencies and run the fixture-based integration test:

```powershell
npm ci --ignore-scripts --no-audit --no-fund
npm test
```

The test builds a mock Electron archive with an unpacked native file, validates installation and restore safeguards, simulates an app update, verifies automatic patch reapplication, and compares SHA-256 hashes.

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), [CHANGELOG.md](CHANGELOG.md), and [third-party notices](THIRD_PARTY_NOTICES.md).

## License

Project code is available under the [MIT License](LICENSE). Third-party components retain their own licenses.

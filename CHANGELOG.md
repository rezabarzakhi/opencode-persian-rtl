# Changelog

All notable changes to this project are documented here.

## 1.1.1 - 2026-08-02

### Fixed

- Maintenance now waits for the user to close OpenCode normally before patching.
- OpenCode is reopened automatically after a pending update is patched.
- A crash-safe pending marker preserves update and restart intent across task restarts.
- The monitor no longer attempts to close OpenCode before the patch can be applied.
- Empty process results are handled correctly under PowerShell strict mode.

## 1.1.0 - 2026-07-31

### Added

- Optional scheduled maintenance that detects OpenCode updates and reapplies the patch.
- Graceful OpenCode close and automatic restart after a compatible update is patched.
- Persistent per-user maintenance runtime with bounded logging.
- One-shot maintenance mode for integration testing.

### Changed

- Process checks now target only the selected OpenCode installation.
- Restoring the original interface automatically disables scheduled maintenance.
- Compatibility was verified against OpenCode Desktop 1.18.10.

## 1.0.0 - 2026-07-26

### Added

- Automatic right-to-left direction for Persian and Arabic-script chat blocks.
- Left-to-right isolation for Latin-only text and Markdown code.
- Optional per-user Vazirmatn installation with pinned source and SHA-256 verification.
- Atomic OpenCode archive replacement with a verified backup and restore metadata.
- Preservation and content verification for Electron ASAR unpacked files.
- Guards against duplicate installs, stale restores, concurrent installers, and concurrent app updates.
- Locked Electron ASAR dependency installation with lifecycle scripts disabled.
- English and Persian documentation plus fixture-based integration tests.

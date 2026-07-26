# Contributing

Contributions that improve compatibility, safety, tests, documentation, or bidirectional text handling are welcome.

## Development

Requirements:

- Windows
- PowerShell 5.1 or newer
- Node.js 22.12 or newer with npm

Run the integration test before opening a pull request:

```powershell
npm ci --ignore-scripts --no-audit --no-fund
npm test
```

## Pull Requests

- Keep the patch narrowly scoped to the OpenCode chat renderer.
- Preserve safe failure behavior for unknown OpenCode layouts.
- Add or update tests for installer changes.
- Update the compatibility table when testing a new OpenCode release.
- Do not commit application archives, fonts, generated backups, or user-specific paths.

## Bug Reports

Use the bug report template and remove personal information from logs and paths before posting.

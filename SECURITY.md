# Security Policy

## Supported Versions

Only the latest tagged release is supported. Compatibility is tested against the OpenCode Desktop version listed in the README.

## Reporting a Vulnerability

Do not include credentials, private paths, or sensitive logs in a public issue. Report vulnerabilities through [GitHub private vulnerability reporting](https://github.com/rezabarzakhi/opencode-persian-rtl/security/advisories/new).

Include:

- OpenCode Desktop version
- Windows version
- PowerShell version
- Node.js version
- The command that was run
- Sanitized error output

## Security Model

This project modifies OpenCode Desktop's packaged renderer. The installer validates hashes, preserves ASAR unpack metadata, and blocks stale restores, but it cannot provide an official OpenCode code signature. Review the script before running it and download releases only from this repository.

# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in time.md, please report it responsibly.

### How to Report

1. **Do not** open a public GitHub issue for security vulnerabilities
2. Email security concerns to: [your-email@example.com]
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

### What to Expect

- **Response time**: We'll acknowledge receipt within 48 hours
- **Updates**: We'll provide status updates as we investigate
- **Resolution**: We aim to resolve critical issues within 7 days
- **Credit**: We'll credit reporters in release notes (unless you prefer anonymity)

## Security Considerations

### Data Privacy

time.md is designed with privacy as a core principle:

- **Local-first**: All raw Screen Time data stays on your device
- **No analytics**: We don't collect usage data
- **No network requests**: Except for optional iCloud sync
- **Open source**: Audit the code yourself

### iCloud Sync

When iCloud sync is enabled:

- Only aggregated daily summaries are synced
- Data is encrypted in transit and at rest by Apple
- No third-party servers are involved
- You can disable sync at any time

### Permissions

| Permission | macOS | iOS | Purpose |
|------------|-------|-----|---------|
| Full Disk Access | Required | N/A | Read knowledgeC.db |
| iCloud | Optional | Optional | Cross-device sync |
| Screen Time | N/A | Required | Read iOS usage data |

### Best Practices

- Keep your OS updated
- Review app permissions periodically
- Use strong iCloud credentials with 2FA
- Report suspicious behavior

## Security Updates

Security fixes will be released as patch versions (e.g., 1.0.1) and documented in the CHANGELOG.

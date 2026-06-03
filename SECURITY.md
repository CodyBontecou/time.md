# Security Policy

## Supported Versions

Security updates are provided for the latest direct-distribution release of time.md.

## Reporting a Vulnerability

If you discover a security vulnerability in time.md, please report it responsibly.

### How to Report

1. **Do not** open a public GitHub issue for security vulnerabilities.
2. Email security concerns to: security@codybontecou.com.
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix, if any

### What to Expect

- **Response time**: We'll acknowledge receipt within 48 hours.
- **Updates**: We'll provide status updates as we investigate.
- **Resolution**: We aim to resolve critical issues within 7 days.
- **Credit**: We'll credit reporters in release notes unless you prefer anonymity.

## Security Considerations

### Data Privacy

time.md is designed with privacy as a core principle:

- **Local-first**: Raw Screen Time, browser history, and optional input tracking data stay on your Mac.
- **No analytics**: We don't collect usage data.
- **No account**: There is no backend account system.
- **Open source**: Audit the code yourself.

### Network Access

time.md does not upload your screen time data. Network access is used for direct-distribution app updates through Sparkle and for opening user-requested links.

### Permissions

| Permission | Required | Purpose |
|------------|----------|---------|
| Full Disk Access | Required for Screen Time and browser history | Read local macOS databases |
| Accessibility | Optional | Enable input tracking when you opt in |
| Input Monitoring | Optional | Enable keyboard/mouse input analytics when you opt in |
| User-selected file access | Optional | Write exports to directories you choose |

### Best Practices

- Keep macOS updated.
- Install time.md from the official GitHub Releases page or isolated.tech.
- Review app permissions periodically in System Settings → Privacy & Security.
- Report suspicious behavior privately via the security contact above.

## Security Updates

Security fixes will be released as patch versions and documented in `CHANGELOG.md`.

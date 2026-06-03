# Privacy Policy

**time.md**  
*Last updated: May 2026*

## Overview

time.md is a privacy-first macOS screen time analytics app. It is distributed directly and runs locally on your Mac. We do not operate a backend for your screen time data.

## Data We Collect

**We do not collect any personal data.**

time.md has no analytics service, no advertising SDK, and no account system. Your usage data stays on your Mac unless you explicitly export it yourself.

## How time.md Works on macOS

- Reads Apple's local Screen Time database (`knowledgeC.db`) after you grant Full Disk Access.
- Reads local browser history databases for the Web History view.
- Can optionally persist browser visit rows in its own local database so they remain visible after a browser clears history.
- Can optionally track keyboard/mouse activity for input analytics after you enable Input Tracking and grant Accessibility/Input Monitoring permissions.
- Stores local app data under `~/Library/Application Support/time.md/`.
- Can write formatted exports to a directory you choose.

No screen time, browser history, or input tracking data is sent to us.

## Data Storage

| Data Type | Where Stored | Who Can Access |
|-----------|--------------|----------------|
| Raw screen time sessions (`screentime.db`) | Your Mac only | Only you |
| Readable screen time snapshot (`screen-time-snapshot.json`) | Your Mac only | Only you |
| Formatted auto-export (`screen-time-auto.<ext>`) | Your chosen export directory | Only you |
| Opt-in web history archive | Your Mac only | Only you |
| Opt-in input tracking data | Your Mac only | Only you |
| Category mappings and app preferences | Your Mac only | Only you |

## Third-Party Services

time.md uses Apple's local macOS services and databases, including Screen Time and privacy permissions. It does not use third-party analytics, advertising, or tracking services.

Sparkle may contact the configured appcast URL to check for app updates. This check does not include your screen time data.

## Data Deletion

You can delete your time.md data at any time:

1. **Delete app data**: Remove `~/Library/Application Support/time.md/`.
2. **Delete persisted web history**: Use Settings → Web Browsers → Delete persisted web history.
3. **Delete input tracking data**: Disable Input Tracking and remove the local input-tracking database in the app support folder if desired.
4. **Delete exports**: Remove any `screen-time-auto.*` or manual export files in your chosen export destination.

## Children's Privacy

time.md does not knowingly collect data from children under 13. The app displays data that Apple's Screen Time has already collected locally on macOS.

## Changes to This Policy

We may update this privacy policy from time to time. We will notify you of any changes by posting the new policy on this page and updating the "Last updated" date.

## Contact

If you have questions about this privacy policy, please contact:

**Email**: privacy@codybontecou.com  
**Website**: https://codybontecou.com

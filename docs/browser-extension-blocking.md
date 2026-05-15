# Optional browser extension blocking bridge

`time.md` can detect website access from local browser history. The optional browser-extension bridge adds lower-latency URL events for users who want enhanced detection.

## Status

- First supported family: Chromium-based browsers.
- Extension folder: `browser-extension/chromium/`.
- Native messaging host manifest template: `browser-extension/native-host/chromium/com.bontecou.time_md.blocking.json`.
- The bridge is optional. If the extension or native host is missing, history polling and app/category blocking continue to work.
- Live enforcement remains gated by `FeatureFlags.blockingInterventionsEnabledKey` until the QA checklist in `docs/blocking-qa.md` is complete.

## Native message protocol

The extension sends JSON framed by the standard Chrome/Firefox native-messaging protocol (little-endian `UInt32` byte length followed by UTF-8 JSON):

```json
{
  "type": "urlAccess",
  "url": "https://www.reddit.com/r/swift",
  "title": "optional page title",
  "browser": "Chromium",
  "profile": "optional profile name",
  "tabId": 42,
  "frameId": 0,
  "occurredAt": 1778848800.0
}
```

Only `http` and `https` URLs are accepted. `file:`, `javascript:`, extension pages, and malformed payloads are rejected safely.

The app/native host responds with:

```json
{
  "version": 1,
  "action": "allow | block | ignored | invalid",
  "targetDomain": "reddit.com",
  "blockedUntil": 1778848860.0,
  "remainingSeconds": 60,
  "reason": "Access allowed; cooldown scheduled."
}
```

`block` means the domain is already in an active cooldown. The Chromium extension redirects the tab to its local `blocked.html` page and uses `remainingSeconds` to render a countdown.

## Deduplication

Extension URL events share a short local deduplication window with browser-history polling. If both sources report the same normalized domain/URL within the window, only the first event mutates strike state. This prevents an extension event followed by a history row from double-counting.

## Chromium development install

1. Open `chrome://extensions`.
2. Enable Developer Mode.
3. Load unpacked extension from `browser-extension/chromium`.
4. Copy the native host manifest template to Chrome's NativeMessagingHosts directory and replace `REPLACE_WITH_EXTENSION_ID` with the loaded extension ID.
5. Update `path` to the packaged native messaging host binary when one is bundled.

Typical macOS per-user host location:

```bash
mkdir -p "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
cp browser-extension/native-host/chromium/com.bontecou.time_md.blocking.json \
  "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/"
```

For Arc, Brave, and Edge, use the browser-specific NativeMessagingHosts application-support directory.

## Privacy notes

- Events are processed locally.
- No URL data is sent to a cloud service by this bridge.
- Incognito/private access requires explicit browser extension permission and may still be unavailable depending on browser settings.
- Users can remove the extension at any time; time.md continues with history-based detection.

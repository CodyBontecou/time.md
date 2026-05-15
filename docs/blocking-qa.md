# time.md blocking QA checklist

Blocking interventions are guarded by `FeatureFlags.blockingInterventionsEnabledKey` (`feature.blockingInterventions.enabled`) until the recovery paths below have been verified on target Macs.

## Preflight

- Confirm existing analytics still record app sessions with blocking disabled.
- Confirm the Blocking screen opens, diagnostics run, and **Remove all managed blocks** is visible.
- Export or back up `~/Library/Application Support/time.md/blocking-rules.db` before destructive manual tests.

## Policy and app/category enforcement

- Create a domain rule (`reddit.com`, 1m ×2, max 4h), an app rule, and a category rule.
- Trigger app/category rules and verify countdown UI, menu bar active-block status, and audit entries.
- Verify protected apps (Finder, System Settings, Terminal, time.md) are not hidden/terminated by default.
- Disable the feature flag and relaunch; verify analytics continue while browser polling and app/category blocking watchers do not start.

## Browser history and Full Disk Access

- Safari, Chrome, Firefox, Arc/Brave/Edge: verify history polling can observe a visit when permissions allow it.
- Revoke Full Disk Access and verify diagnostics/UX report degraded browser access without crashing or blocking analytics.
- Clear browser history while time.md is running and verify future visits still process once.

## Privileged helper / domain enforcement

- Install/upgrade helper with the consent copy visible to the user.
- Verify `/etc/hosts` preserves user content and contains at most one `time.md` marker block.
- Verify `/etc/pf.anchors/com.bontecou.time-md` is owned by time.md and unrelated pf/VPN/firewall rules remain untouched.
- Run Repair helper with active domain blocks and verify helper active domains match policy state.
- Run Remove all managed blocks and verify active cooldown timestamps are cleared, the owned hosts block is removed, and the owned pf anchor no longer blocks domains.
- Uninstall helper, relaunch, and verify diagnostics report domain helper as not installed rather than broken.

## Recovery edge cases

- Simulate partial hosts marker (begin marker without footer); diagnostics must report **broken** and Repair/Remove all must restore a safe state.
- Kill the app after a cooldown is scheduled; relaunch and verify expired blocks clear on startup/diagnostics.
- Sleep/wake during an active block; verify remaining countdown is based on wall-clock time and expired blocks clear.
- Reboot during an active domain block; verify helper reconnect/repair reconciles desired domains.
- Manually edit/remove the owned pf anchor; diagnostics should report degraded and Repair should recreate it.
- Simulate helper apply failure; audit log should include the recovery/enforcement failure and UI should expose a repair action.

## Release gate

Do not enable `feature.blockingInterventions.enabled` by default until:

- Full `xcodebuild -scheme time.md -destination 'platform=macOS' test` passes.
- Full `xcodebuild -scheme time.md -destination 'platform=macOS' build` passes.
- Manual QA above is completed on the current and minimum supported macOS versions.
- A tester verifies Remove all managed blocks from the UI restores browsing/app access without deleting analytics.

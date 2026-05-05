import AppKit
import IOKit.hid
import SwiftUI

/// Settings panel for the opt-in keystroke + cursor tracker. Slots into the
/// existing Settings scaffold view in `RootSplitView.swift`. Two independent
/// sensitivity pickers (keystrokes / cursor) drive what gets captured. Master
/// toggle is a quick kill switch — when off, the tracker doesn't run regardless
/// of the picker selections.
struct InputTrackingSettingsSection: View {
    @AppStorage(InputEventTracker.enabledKey) private var inputTrackingEnabled: Bool = false
    @AppStorage(InputEventTracker.keystrokeLevelKey) private var keystrokeLevelRaw: String = ""
    @AppStorage(InputEventTracker.cursorLevelKey) private var cursorLevelRaw: String = ""
    @AppStorage(InputDataPruner.retentionDaysKey) private var retentionDays: Int = InputDataPruner.defaultRetentionDays
    @AppStorage(InputEventTracker.pausedUntilKey) private var pausedUntilTimestamp: Double = 0

    @State private var inputMonitoringGranted: Bool = false
    @State private var statusRefreshTimer: Timer?
    @State private var deleteConfirmation: Bool = false
    @State private var contentEnableConfirmation: Bool = false
    @State private var pendingFullContentSelection: Bool = false

    private var keystrokeLevel: KeystrokeTrackingLevel {
        if let level = KeystrokeTrackingLevel(rawValue: keystrokeLevelRaw) {
            return level
        }
        return InputEventTracker.resolveKeystrokeLevel()
    }

    private var cursorLevel: CursorTrackingLevel {
        if let level = CursorTrackingLevel(rawValue: cursorLevelRaw) {
            return level
        }
        return InputEventTracker.resolveCursorLevel()
    }

    private var pausedUntil: Date? {
        guard pausedUntilTimestamp > Date().timeIntervalSince1970 else { return nil }
        return Date(timeIntervalSince1970: pausedUntilTimestamp)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(BrutalTheme.sectionLabel(10, "INPUT TRACKING (BETA)"))
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1.5)

                Text("Optional capture of keystrokes and cursor events while time.md is running. Configure each stream independently. All data stays on this Mac.")
                    .font(BrutalTheme.bodyMono)
                    .foregroundColor(BrutalTheme.textPrimary)
                    .lineSpacing(3)

                masterToggleRow

                if inputTrackingEnabled {
                    Divider()
                    permissionStatusRow
                    Divider()
                    streamConfigSection
                    Divider()
                    retentionSlider
                    pauseRow
                    Divider()
                    destructiveActions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            refreshPermissions()
            statusRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                refreshPermissions()
            }
        }
        .onDisappear {
            statusRefreshTimer?.invalidate()
            statusRefreshTimer = nil
        }
        .onChange(of: inputTrackingEnabled) { _, newValue in
            handleMasterToggleChange(newValue: newValue)
        }
        .onChange(of: keystrokeLevelRaw) { _, _ in
            InputEventTracker.shared.reloadSettings()
        }
        .onChange(of: cursorLevelRaw) { _, _ in
            InputEventTracker.shared.reloadSettings()
        }
        .alert("Record actual keystrokes?", isPresented: $contentEnableConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingFullContentSelection = false
            }
            Button("Enable Full Content", role: .destructive) {
                if pendingFullContentSelection {
                    keystrokeLevelRaw = KeystrokeTrackingLevel.fullContent.rawValue
                }
                pendingFullContentSelection = false
            }
        } message: {
            Text("Stores every character you type while time.md is running. Treat the database like a password vault. macOS Secure Input mode and the exclusion list redact some fields, but not all. You can change this at any time.")
        }
    }

    // MARK: - Master toggle

    private var masterToggleRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Run input tracker")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BrutalTheme.textPrimary)
                Text(masterStatusText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(inputTrackingEnabled ? .green : BrutalTheme.textTertiary)
            }
            Spacer()
            Toggle("", isOn: $inputTrackingEnabled)
                .toggleStyle(.switch)
                .tint(.green)
                .labelsHidden()
        }
    }

    private var masterStatusText: String {
        if !inputTrackingEnabled {
            return "Disabled — no events captured."
        }
        let parts: [String] = [
            "Keystrokes: \(keystrokeLevel.displayName)",
            "Cursor: \(cursorLevel.displayName)"
        ]
        return parts.joined(separator: " · ")
    }

    // MARK: - Permission status

    private var permissionStatusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PERMISSION")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(BrutalTheme.textTertiary)

            HStack(spacing: 10) {
                Image(systemName: inputMonitoringGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(inputMonitoringGranted ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Input Monitoring")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BrutalTheme.textPrimary)
                    Text(inputMonitoringGranted ? "Granted — events flowing." : "Required to listen for keyboard and mouse events.")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(inputMonitoringGranted ? BrutalTheme.textTertiary : .orange)
                }

                Spacer()

                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(BrutalTheme.surface.opacity(0.5))
            )

            Text("If macOS doesn't list time.md after first toggling on, restart the app — the system registers the request when capture is first attempted.")
                .font(BrutalTheme.captionMono)
                .foregroundColor(BrutalTheme.textTertiary)
        }
    }

    // MARK: - Stream config

    private var streamConfigSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            keystrokeLevelPicker
            cursorLevelPicker
        }
    }

    private var keystrokeLevelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Keystrokes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BrutalTheme.textPrimary)
                Spacer()
                Picker("", selection: Binding(
                    get: { keystrokeLevel },
                    set: { newValue in
                        if newValue == .fullContent && keystrokeLevel != .fullContent {
                            // Don't write the value yet — force the user to confirm.
                            pendingFullContentSelection = true
                            contentEnableConfirmation = true
                        } else {
                            keystrokeLevelRaw = newValue.rawValue
                        }
                    }
                )) {
                    ForEach(KeystrokeTrackingLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }
            Text(keystrokeLevel.summary)
                .font(BrutalTheme.captionMono)
                .foregroundColor(keystrokeLevel == .fullContent ? .orange : BrutalTheme.textTertiary)
                .lineSpacing(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(BrutalTheme.surface.opacity(0.5))
        )
    }

    private var cursorLevelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Cursor")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BrutalTheme.textPrimary)
                Spacer()
                Picker("", selection: Binding(
                    get: { cursorLevel },
                    set: { newValue in
                        cursorLevelRaw = newValue.rawValue
                    }
                )) {
                    ForEach(CursorTrackingLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }
            Text(cursorLevel.summary)
                .font(BrutalTheme.captionMono)
                .foregroundColor(BrutalTheme.textTertiary)
                .lineSpacing(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(BrutalTheme.surface.opacity(0.5))
        )
    }

    // MARK: - Retention / pause / destructive

    private var retentionSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Keep raw events for")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BrutalTheme.textPrimary)
                Spacer()
                Text("\(retentionDays) days")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(BrutalTheme.accent)
            }
            Slider(
                value: Binding(
                    get: { Double(retentionDays) },
                    set: { retentionDays = Int($0) }
                ),
                in: 1...30,
                step: 1
            )
            Text("Aggregates (top words, heatmap bins) are kept indefinitely. Raw mouse events use half this retention since they grow fastest.")
                .font(BrutalTheme.captionMono)
                .foregroundColor(BrutalTheme.textTertiary)
        }
    }

    private var pauseRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hotkey: ⌥⌘P pauses for 30 minutes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BrutalTheme.textPrimary)
                if let pausedUntil {
                    let remaining = Int(pausedUntil.timeIntervalSinceNow / 60)
                    Text("⏸ Paused — resumes in \(max(0, remaining)) min")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.orange)
                } else {
                    Text("Press anywhere on macOS to pause capture")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary)
                }
            }
            Spacer()
            if pausedUntil != nil {
                Button("Resume Now") {
                    InputEventTracker.shared.resume()
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .buttonStyle(.bordered)
                .tint(.green)
            } else {
                Button("Pause Now") {
                    InputEventTracker.shared.pause()
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .buttonStyle(.bordered)
            }
        }
    }

    private var destructiveActions: some View {
        HStack(spacing: 10) {
            Button {
                deleteConfirmation = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                    Text("Delete all input data")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)
            Spacer()
        }
        .alert("Delete all keystroke + mouse data?", isPresented: $deleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                InputEventTracker.deleteAllData()
            }
        } message: {
            Text("Removes every row from keystroke_events, mouse_events, typed_words, and cursor_heatmap_bins. Cannot be undone.")
        }
    }

    // MARK: - State helpers

    private func refreshPermissions() {
        inputMonitoringGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    private func handleMasterToggleChange(newValue: Bool) {
        if newValue {
            // Trigger the system permission request. The first call registers
            // time.md in System Settings → Privacy & Security → Input Monitoring.
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)

            // If the user just turned it on for the first time, seed levels
            // from the resolved defaults so the pickers show meaningful values.
            if keystrokeLevelRaw.isEmpty {
                keystrokeLevelRaw = InputEventTracker.resolveKeystrokeLevel().rawValue
            }
            if cursorLevelRaw.isEmpty {
                cursorLevelRaw = InputEventTracker.resolveCursorLevel().rawValue
            }
            // If both levels are off but master toggled on, default to sane levels.
            if keystrokeLevel == .off && cursorLevel == .off {
                keystrokeLevelRaw = KeystrokeTrackingLevel.perKey.rawValue
                cursorLevelRaw = CursorTrackingLevel.heatmap.rawValue
            }

            InputEventTracker.shared.start()
            InputAggregator.shared.start()
            InputDataPruner.shared.start()
        } else {
            InputEventTracker.shared.stop()
            InputAggregator.shared.stop()
            InputDataPruner.shared.stop()
        }

        refreshPermissions()
    }
}
